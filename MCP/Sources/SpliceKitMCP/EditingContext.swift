import Foundation
import MCP

let editingInstructions = """
Use bridge_status to check the Final Cut Pro connection, open_project to load a project, and get_timeline_clips to inspect it. Seek to an exact time with seek_to_time. Select a clip before applying effects or retiming. Use blade_at_times and add_markers_at_times for batches. Verify the result with verify_action, capture_timeline, or capture_viewer. The bridge uses Final Cut Pro's own editing methods.
"""

extension EditingWorkflows {
    func resource(_ uri: String) async throws -> String {
        switch uri {
        case "splicekit://project/info":
            let version = (try? await rpc("system.version")) ?? [:]
            let timeline = (try? await rpc("timeline.getState")) ?? [:]
            let playhead = (try? await rpc("playback.getPosition")) ?? [:]
            let libraries = (try? await rpc("system.callMethodWithArgs", ["target": "FFLibraryDocument",
                "selector": "copyActiveLibraries", "args": [], "classMethod": true, "returnHandle": true])) ?? [:]
            let updating = (try? await rpc("system.callMethod", ["className": "FFLibraryDocument",
                "selector": "isAnyLibraryUpdating", "classMethod": true])) ?? [:]
            return try Value.object(["splicekit": version, "timeline": timeline, "playhead": playhead,
                                     "libraries": libraries, "isLibraryUpdating": updating]).json()
        case "splicekit://timeline/clips": return try await rpc("timeline.getDetailedState").json()
        case "splicekit://timeline/markers":
            let markers = try await rpc("timeline.getState")["markers"].list
            return try Value.object(["markers": .array(markers), "count": .int(markers.count)]).json()
        case "splicekit://timeline/selected-clips":
            return try await selectedClips(rpc("timeline.getDetailedState")).json()
        case "splicekit://timeline/analysis":
            return try await timelineAnalysis(rpc("timeline.getDetailedState")).json()
        case "splicekit://effects/available": return try await rpc("effects.listAvailable", ["type": "all"]).json()
        case "splicekit://transitions/available": return try await rpc("transitions.list").json()
        case "splicekit://clips/applied-effects": return try await rpc("effects.getClipEffects").json()
        case "splicekit://browser/clips": return try await rpc("browser.listClips").json()
        case "splicekit://config/instructions": return editingInstructions
        default: throw ToolFailure("Unknown SpliceKit resource: \(uri)")
        }
    }

    func aiCommand(_ query: String) async throws -> String {
        let plan = try await rpc("command.ai", ["query": .string(query)])
        if let summary = plan["summary"].stringValue, !summary.isEmpty { return summary }
        let actions = plan["actions"].list
        guard !actions.isEmpty else { return "No actions determined from query." }
        func perform(_ action: Value) async throws -> [String] {
            try Task.checkCancellation()
            let type = action["type"].stringValue ?? "timeline"
            let name = action["action"].text
            switch type {
            case "seek":
                _ = try await rpc("playback.seekToTime", ["seconds": action["seconds"]])
            case "effect":
                _ = try await rpc("timeline.action", ["action": "selectClipAtPlayhead"])
                _ = try await rpc("effects.apply", ["name": action["name"]])
            case "transition":
                _ = try await rpc("transitions.apply", ["name": action["name"], "freezeExtend": true])
            case "scene_detect", "scene_markers":
                _ = try await rpc("scene.detect", ["threshold": 0.35, "sampleInterval": 0.1,
                                                   "action": type == "scene_detect" ? "detect" : "markers"])
            case "repeat_pattern":
                var messages: [String] = []
                for _ in 0..<max(0, action["count"].intValue ?? 1) {
                    for sub in action["actions"].list { messages += try await perform(sub) }
                }
                return messages
            case "timeline", "playback":
                try await performAction(type: type, name: name, count: action["repeat"].intValue ?? 1)
            default: throw ToolFailure("Unknown editing action type '\(type)'.")
            }
            return ["\(type)\(name.isEmpty ? "" : ".\(name)") -> ok"]
        }
        var messages: [String] = []
        for action in actions { messages += try await perform(action) }
        return (["AI executed \(actions.count) action(s):"] + messages).joined(separator: "\n")
    }
}

func selectedClips(_ state: Value) -> Value {
    let clips = state["items"].list.filter { $0["selected"].truthy }
    return ["selectedCount": .int(clips.count), "items": .array(clips)]
}

func timelineAnalysis(_ state: Value) -> Value {
    let items = state["items"].list
    let clips = items.filter { !$0["class"].text.contains("Transition") }
    let durations = clips.map { $0["duration"]["seconds"].number }
    let fourth = durations.count / 4
    var pacing = "unknown"
    if fourth > 0 {
        let start = durations.prefix(fourth).reduce(0, +), end = durations.suffix(fourth).reduce(0, +)
        pacing = end < start * 0.7 ? "accelerating" : end > start * 1.3 ? "decelerating" : "steady"
    }
    let short = durations.filter { $0 < 0.5 }.count, long = durations.filter { $0 > 30 }.count
    var issues: [Value] = []
    if short > 0 { issues.append(.string("\(short) flash frames (< 0.5s)")) }
    if long > 0 { issues.append(.string("\(long) long clips (> 30s)")) }
    return ["sequenceName": state["sequenceName"], "durationSeconds": state["duration"]["seconds"],
            "playheadSeconds": state["playheadTime"]["seconds"], "clipCount": .int(clips.count),
            "transitionCount": .int(items.count - clips.count), "avgClipDuration": .double(durations.reduce(0, +) / Double(max(1, durations.count))),
            "minClipDuration": .double(durations.min() ?? 0), "maxClipDuration": .double(durations.max() ?? 0),
            "pacing": .string(pacing), "issues": .array(issues)]
}

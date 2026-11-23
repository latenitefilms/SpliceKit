import Foundation
import MCP

struct EditingWorkflows {
    let bridge: Bridge

    func call(_ name: String, _ a: Arguments) async throws -> String {
        if let request = try editingRequest(name, a) {
            let result = try await bridge.call(request)
            return try formatEditingResult(name, result, a)
        }
        switch name {
        case "set_playback_speed":
            if !a["rate"].isNull, a["action"].isNull {
                return try await rpc("playback.setRate", ["rate": a["rate"]]).json()
            }
            guard a["rate"].isNull, ["faster", "slower", "stop"].contains(a["action"].text) else {
                throw ToolFailure("Provide either a playback rate or a shuttle action (faster, slower, stop).")
            }
            return try await rpc("playback.shuttle", ["direction": a["action"]]).json()
        case "verify_action":
            let state: Value
            do { state = try await rpc("timeline.getDetailedState") }
            catch { state = try await rpc("timeline.getState") }
            let result: Value = ["playhead_seconds": state["playheadTime"]["seconds"],
                                 "item_count": state["itemCount"], "selected_count": state["selectedCount"],
                                 "sequence_name": state["sequenceName"], "description": a["description"],
                                 "timestamp": .double(Date().timeIntervalSince1970)]
            return try result.json()
        case "list_handles", "manage_handles", "inspect_handle", "release_handle", "release_all_handles":
            let action = ["list_handles": "list", "inspect_handle": "inspect", "release_handle": "release",
                          "release_all_handles": "release_all"][name] ?? a["action"].text
            switch action {
            case "list": return try await rpc("object.list").json()
            case "release_all": return try await rpc("object.release", ["all": true]).json()
            case "inspect", "release":
                guard a["handle"].truthy else { throw ToolFailure("A handle is required.") }
                return try await rpc(action == "inspect" ? "object.get" : "object.release", ["handle": a["handle"]]).json()
            default: throw ToolFailure("Expected list, inspect, release, or release_all.")
            }
        case "generate_fcpxml": return try TimelineXML.generate(a)
        case "export_otio", "import_otio": return try await TimelineExchange(bridge: bridge).run(name, a)
        case "batch_timeline_actions": return try await batchActions(a)
        case "batch_apply_effect", "batch_color_correct": return try await batchEffects(name, a)
        case "trim_clips_to_beats", "sync_clips_to_song_beats", "build_song_cut", "assemble_random_clips_to_song_beats":
            return try await songEdit(name, a)
        case "import_srt_as_markers":
            let markers = TimelineXML.subtitleMarkers(a["srt_content"].text)
            guard !markers.isEmpty else { return "No valid SRT entries found" }
            let result = try await rpc("timeline.addMarkers", ["markers": .array(markers)])
            return "Imported \(result["applied"].intValue ?? 0)/\(markers.count) markers from SRT"
        case "ai_command": return try await aiCommand(a["query"].text)
        case "detect_beats", "analyze_song_structure", "beat_sync_blade", "song_structure_blocks", "song_structure_sections":
            return try await AudioWorkflows(bridge: bridge).run(name, a)
        case "debug_set_config":
            let text = a["value"].text
            let value: Value
            switch text.lowercased() {
            case "true", "yes", "1": value = true
            case "false", "no", "0": value = false
            default: value = Int(text).map(Value.int) ?? .string(text)
            }
            return try await rpc("debug.setConfig", ["key": a["key"], "value": value]).json()
        case "import_media":
            var paths = a["paths"].list.filter(\.truthy)
            if a["path"].truthy { paths.append(a["path"]) }
            guard !paths.isEmpty else { throw ToolFailure("Provide paths or a path to import.") }
            var p: [String: Value] = ["paths": .array(paths), "manageFileType": a["manage_file_type"]]
            for key in ["library", "event"] where a[key].truthy { p[key] = a[key] }
            return try await rpc("media.importFile", p).json()
        default: throw ToolFailure("Unknown editing tool '\(name)'.")
        }
    }

    func rpc(_ method: String, _ params: [String: Value] = [:]) async throws -> Value {
        try await bridge.call(BridgeRequest(method, params))
    }

    func performAction(type: String, name: String, count: Int) async throws {
        guard count >= 0 else { throw ToolFailure("Negative repeat count.") }
        let frameSteps = ["nextFrame": 1, "prevFrame": -1, "nextFrame10": 10, "prevFrame10": -10]
        if type == "playback", count > 1, let step = frameSteps[name] {
            let position = try await rpc("playback.getPosition")
            let frameRate = position["frameRate"].number
            guard let seconds = position.fields["seconds"], !seconds.isNull, frameRate > 0 else {
                throw ToolFailure("Cannot seek by frames without the timeline's playhead position and frame rate.")
            }
            var target = max(0, seconds.number + Double(step) * Double(count) / frameRate)
            if let duration = position["duration"].fields["seconds"], duration.number > 0 {
                target = min(target, duration.number)
            }
            _ = try await rpc("playback.seekToTime", ["seconds": .double(target)])
            return
        }
        for _ in 0..<count {
            try Task.checkCancellation()
            _ = try await rpc(type == "playback" ? "playback.action" : "timeline.action", ["action": .string(name)])
        }
    }

    private func batchActions(_ a: Arguments) async throws -> String {
        guard let actions = try a["actions"].decodedJSON().arrayValue else { throw ToolFailure("Expected an array of actions.") }
        var lines: [String] = []
        var failures = 0
        for (index, entry) in actions.enumerated() {
            try Task.checkCancellation()
            let type = entry["type"].stringValue ?? "timeline"
            let action = entry["action"].text
            let count = entry["repeat"].intValue ?? 1
            let label = "[\(index)] \(type).\(action)" + (count > 1 ? " x\(count)" : "")
            do {
                switch type {
                case "wait":
                    let seconds = entry.fields["seconds"]?.number ?? 0.5
                    guard seconds >= 0 else { throw ToolFailure("Negative wait duration.") }
                    try await Task.sleep(for: .seconds(seconds))
                case "timeline", "playback":
                    try await performAction(type: type, name: action, count: count)
                default: throw ToolFailure("Unknown action type '\(type)'.")
                }
                lines.append("\(label) -> OK")
            } catch is CancellationError { throw CancellationError() }
            catch { failures += 1; lines.append("\(label) -> FAILED: \(error.localizedDescription)") }
        }
        let failed = failures == 0 ? "" : " (\(failures) failed)"
        return (["Executed \(actions.count) actions\(failed):"] + lines).joined(separator: "\n")
    }

    private func batchEffects(_ name: String, _ a: Arguments) async throws -> String {
        let correction = name == "batch_color_correct"
        var p: [String: Value] = [:]
        if correction {
            let allowed = ["addColorBoard", "addColorWheels", "addColorCurves", "addColorAdjustment",
                           "addHueSaturation", "addEnhanceLightAndColor", "balanceColor", "matchColor"]
            guard allowed.contains(a["correction"].text) else { throw ToolFailure("Unknown color correction.") }
            p["action"] = a["correction"]
        } else {
            for key in ["name", "effectID"] where a[key].truthy { p[key] = a[key] }
            guard !p.isEmpty else { throw ToolFailure("Provide an effect name or effectID.") }
        }
        let count = a["clip_count"].intValue ?? 0
        guard count >= 0 else { throw ToolFailure("clip_count must be zero or positive.") }
        _ = try await rpc("timeline.action", ["action": "selectClipAtPlayhead"])
        var summary: [Value] = []
        var applied = 0
        var previousPosition: Value?
        while count == 0 || summary.count < count {
            try Task.checkCancellation()
            if count == 0 {
                let current = try await rpc("playback.getPosition")
                guard let position = current.fields["seconds"] ?? current.fields["playheadTime"] ?? current.fields["currentTime"],
                      !position.isNull else { throw ToolFailure("Cannot advance effects without a playhead position.") }
                if position == previousPosition { break }
                previousPosition = position
            }
            var entry: [String: Value] = ["clip": .int(summary.count)]
            do {
                let response = try await rpc(correction ? "timeline.action" : "effects.apply", p)
                entry["success"] = true
                entry[correction ? "correction" : "effect"] = correction ? a["correction"] : response["effect"]
                applied += 1
            } catch { entry["success"] = false; entry["error"] = .string(error.localizedDescription) }
            summary.append(.object(entry))
            if count > 0 && summary.count >= count { break }
            do {
                _ = try await rpc("timeline.action", ["action": "nextEdit"])
                _ = try await rpc("timeline.action", ["action": "selectClipAtPlayhead"])
            } catch { break }
        }
        var result: [String: Value] = ["applied": .int(applied), "errors": .int(summary.count - applied),
                                       "total": .int(summary.count), "results": .array(summary)]
        if correction { result["correction"] = a["correction"] }
        return try Value.object(result).json()
    }

    private func songEdit(_ name: String, _ a: Arguments) async throws -> String {
        var p: [String: Value] = ["dryRun": a["dry_run"], "randomSeed": a["random_seed"]]
        func copy(_ fields: [(String, String)], optional: Bool = false) {
            for (input, rpc) in fields where !optional || a[input].truthy { p[rpc] = a[input] }
        }
        func json(_ key: String, as field: String, array: Bool) throws {
            guard a[key].truthy else { return }
            let value = try a[key].decodedJSON()
            guard array ? value.arrayValue != nil : value.objectValue != nil else { throw ToolFailure("Invalid JSON type for \(key).") }
            if value.truthy { p[field] = value }
        }
        if name == "trim_clips_to_beats" || name == "sync_clips_to_song_beats" {
            copy([("random_min_step", "randomMinStep"), ("random_max_step", "randomMaxStep")])
            copy([("source_handle", "sourceHandle"), ("target_mode", "targetMode")], optional: true)
            for (key, target) in [("min_trim_seconds", "minTrimSeconds"), ("min_result_duration", "minResultDuration")]
            where a[key].number > 0 { p[target] = a[key] }
            if name == "trim_clips_to_beats" {
                p["grid"] = a["grid"]; p["randomize"] = a["randomize"]
                try json("target_handles", as: "targetHandles", array: true)
            } else {
                p["grid"] = a["mode"]
                p["randomize"] = .bool(["random", "random_half", "random_half_beat", "random_quarter", "random_quarter_beat"].contains(a["mode"].text))
                if a["overlay_only"].truthy { p["targetMode"] = "overlay" }
            }
            return try await rpc("timeline.trimClipsToBeats", p).json()
        }
        copy([("project_name", "projectName"), ("allow_clip_reuse", "allowClipReuse"), ("include_audio", "includeAudio"),
              ("build_mode", "buildMode"), ("target_current_timeline", "targetCurrentTimeline")])
        copy([("event_name", "eventName"), ("source_handle", "sourceHandle"), ("source_project_name", "sourceProjectName"),
              ("clip_source_project_name", "clipSourceProjectName")], optional: true)
        if a["max_segments"].number > 0 { p["maxSegments"] = a["max_segments"] }
        try json("clip_handles", as: "clipHandles", array: true)
        if name == "build_song_cut" {
            p["grid"] = "half_beat"; p["segmentMinStep"] = 1; p["segmentMaxStep"] = 4
            switch a["pace"].text.lowercased() {
            case "natural": p["stepWeights"] = ["1": 1, "2": 8, "4": 3]
            case "medium": p["segmentMinStep"] = 2
            case "fast": p["segmentMaxStep"] = 2; p["stepWeights"] = ["1": 1, "2": 4]
            case "aggressive": p["grid"] = "quarter_beat"
            default: throw ToolFailure("Expected natural, medium, fast, or aggressive pacing.")
            }
        } else {
            copy([("grid", "grid"), ("segment_min_step", "segmentMinStep"), ("segment_max_step", "segmentMaxStep")])
            try json("step_weights", as: "stepWeights", array: false)
        }
        return try await rpc("timeline.assembleRandomClipsToBeats", p).json()
    }
}

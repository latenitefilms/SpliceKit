import Foundation
import MCP

func formatEditingResult(_ name: String, _ result: Value, _ args: Arguments) throws -> String {
    func summary(_ title: String, entries: [Value], fields: [String]) -> String {
        let rows = entries.map { row in
            fields.compactMap { key in row.fields[key].map { "\(key)=\($0)" } }.joined(separator: "  ")
        }
        return ([title] + rows).joined(separator: "\n")
    }
    switch name {
    case "get_selected_clips":
        let selected = selectedClips(result)
        return selected["items"].list.isEmpty ? "No clips selected" : try selected.json()
    case "get_timeline_clips":
        let title = "Sequence: \(result["sequenceName"])\nPlayhead: \(result["playheadTime"]["seconds"])s\nDuration: \(result["duration"]["seconds"])s\nItems: \(result["itemCount"])\nSelected: \(result["selectedCount"])"
        return summary(title, entries: result["items"].list, fields: ["index", "class", "name", "startTime", "endTime", "duration", "lane", "selected", "handle"])
    case "analyze_timeline":
        return try timelineAnalysis(result).json()
    case "get_clip_effects":
        let title = "Clip: \(result["clipName"]) (\(result["clipClass"]))\nEffects: \(result["effectCount"])"
        let list = summary(title, entries: result["effects"].list, fields: ["name", "class", "effectID", "handle"])
        return result["effectStackHandle"].truthy ? list + "\nEffect stack handle: \(result["effectStackHandle"])" : list
    case "list_effects":
        return summary("Available \(args["type"]) effects: \(result["count"])", entries: result["effects"].list,
                       fields: ["name", "category", "type", "effectID"])
    case "list_transitions":
        return summary("Available transitions: \(result["count"])", entries: result["transitions"].list,
                       fields: ["name", "category", "effectID"])
    case "detect_scene_changes":
        return summary("Scene changes: \(result["count"]) (threshold=\(result["threshold"]), file=\(result["mediaFile"]))",
                       entries: result["sceneChanges"].list, fields: ["time", "score"])
    case "apply_effect": return "Applied effect: \(result["effect"]) (\(result["effectID"]))"
    case "close_transcript": return "Transcript panel closed."
    case "show_command_palette": return "Command palette opened."
    case "hide_command_palette": return "Command palette closed."
    case "ai_command_gemma": return result["summary"].stringValue ?? "Done."
    case "mixer_volume_begin": return "Undo transaction opened for volume adjustment"
    case "mixer_volume_end": return "Undo transaction closed"
    case "hide_sections": return "Sections bar hidden"
    case "close_captions": return "Captions panel closed."
    case "lua_reset": return "Lua VM reset"
    case "capture_viewer", "capture_timeline", "capture_inspector":
        guard result["status"].text == "ok" else { return try result.json() }
        let label = String(name.dropFirst("capture_".count)).capitalized
        return "\(label) captured: \(result["path"])\nSize: \(result["width"])x\(result["height"]) (\(result["bytes"]) bytes)"
    case "get_transcript":
        var lines = ["Status: \(result["status"])", "Words: \(result["wordCount"])", "Silences: \(result["silenceCount"])",
                     "Silence threshold: \(result["silenceThreshold"])s"]
        for key in ["gapBuckets", "progress", "text"] where result[key].truthy {
            let value = try result[key].stringValue ?? result[key].json()
            lines.append("\(key): \(value)")
        }
        lines.append(summary("Silences:", entries: result["silences"].list, fields: ["startTimecode", "endTimecode", "duration", "afterWordIndex"]))
        lines.append(summary("Word list:", entries: result["words"].list, fields: ["index", "startTime", "endTime", "confidence", "speaker", "text"]))
        return lines.joined(separator: "\n")
    case "search_transcript":
        return summary("Query: \(result["query"])\nResults: \(result["resultCount"])", entries: result["results"].list,
                       fields: ["type", "index", "startTime", "endTime", "confidence", "text", "duration"])
    case "set_timeline_range":
        return String(format: "Range set: %.3fs - %.3fs\nMark in: %@  Mark out: %@",
                      result["startSeconds"].number, result["endSeconds"].number,
                      result["rangeStartSet"].truthy ? "OK" : "failed", result["rangeEndSet"].truthy ? "OK" : "failed")
    default: return try result.json()
    }
}

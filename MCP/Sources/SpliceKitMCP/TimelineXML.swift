import Foundation
import MCP

enum TimelineXML {
    static func generate(_ a: Arguments) throws -> String {
        let rates = ["23.976": (1001, 24000), "24": (100, 2400), "25": (100, 2500),
                     "29.97": (1001, 30000), "30": (100, 3000), "48": (100, 4800),
                     "50": (100, 5000), "59.94": (1001, 60000), "60": (100, 6000)]
        let (numerator, scale) = rates[a["frame_rate"].text] ?? (100, 2400)
        func time(_ seconds: Double) throws -> String {
            let frames = (seconds * Double(scale) / Double(numerator)).rounded(.toNearestOrEven)
            guard frames.isFinite, frames >= 0, frames < Double(Int64.max / Int64(numerator)) else {
                throw ToolFailure("Time is outside the supported FCPXML range.")
            }
            return "\(Int64(frames) * Int64(numerator))/\(scale)s"
        }
        func element(_ name: String, _ attributes: [String: String] = [:], parent: XMLElement? = nil) -> XMLElement {
            let node = XMLElement(name: name)
            for (key, value) in attributes.sorted(by: { $0.key < $1.key }) {
                node.addAttribute(XMLNode.attribute(withName: key, stringValue: value) as! XMLNode)
            }
            parent?.addChild(node)
            return node
        }
        guard let items = try a["items"].decodedJSON().arrayValue else { throw ToolFailure("Expected an array of timeline items.") }
        let root = element("fcpxml", ["version": "1.14"])
        let resources = element("resources", parent: root)
        let rate = a["frame_rate"].text, width = a["width"].description, height = a["height"].description
        _ = element("format", ["id": "r1", "name": "FFVideoFormat\(width)x\(height)p\(rate)",
                               "frameDuration": "\(numerator)/\(scale)s", "width": width, "height": height], parent: resources)
        if items.contains(where: { $0["type"].text == "title" }) {
            _ = element("effect", ["id": "title", "name": "Basic Title",
                "uid": ".../Titles.localized/Bumper:Opener.localized/Basic Title.localized/Basic Title.moti"], parent: resources)
        }
        if items.contains(where: { $0["type"].text == "transition" }) {
            _ = element("effect", ["id": "dissolve", "name": "Cross Dissolve",
                                   "uid": "FxPlug:4731E73A-8DAC-4113-9A30-AE85B1761265"], parent: resources)
        }
        let library = element("library", parent: root)
        let event = element("event", ["name": a["event_name"].text], parent: library)
        let project = element("project", ["name": a["project_name"].text], parent: event)
        let sequence = element("sequence", ["format": "r1", "tcStart": "0s", "tcFormat": "NDF"], parent: project)
        let spine = element("spine", parent: sequence)
        var content = items.filter { ["gap", "title", "transition"].contains($0["type"].stringValue ?? "gap") }
        if content.isEmpty { content = [["type": "gap", "duration": 10]] }
        var offset = 0.0
        var anchors: [(offset: Double, end: Double, node: XMLElement)] = []
        for (index, item) in content.enumerated() {
            let duration = item.fields["duration"]?.number ?? 5
            var attrs = ["offset": try time(offset), "duration": try time(duration), "start": "3600s"]
            switch item["type"].text {
            case "transition":
                attrs.removeValue(forKey: "start")
                attrs["name"] = "Cross Dissolve"
                let transition = element("transition", attrs, parent: spine)
                _ = element("filter-video", ["ref": "dissolve"], parent: transition)
            case "title":
                let title = item["text"].stringValue ?? "Title"
                attrs["name"] = item["name"].stringValue ?? title
                attrs["ref"] = "title"
                let node = element("title", attrs, parent: spine)
                let styleID = "ts\(index + 1)"
                let text = element("text", parent: node)
                element("text-style", ["ref": styleID], parent: text).stringValue = title
                let style = element("text-style-def", ["id": styleID], parent: node)
                _ = element("text-style", ["font": "Helvetica", "fontColor": "1 1 1 1",
                                           "fontSize": item["position"].text == "lower-third" ? "42" : "63"], parent: style)
                anchors.append((offset, offset + duration, node))
            default:
                attrs["name"] = item["name"].stringValue ?? "Gap"
                anchors.append((offset, offset + duration, element("gap", attrs, parent: spine)))
            }
            offset += duration
        }
        sequence.addAttribute(XMLNode.attribute(withName: "duration", stringValue: try time(offset)) as! XMLNode)
        for marker in items where marker["type"].text == "marker" {
            let start = marker["time"].number
            guard let anchor = anchors.first(where: { $0.offset <= start && start < $0.end }) else {
                throw ToolFailure("The marker at \(start)s is outside a clip or gap.")
            }
            let duration = marker["duration"].number > 0 ? marker["duration"].number : Double(numerator) / Double(scale)
            var attrs = ["start": try time(3600 + start - anchor.offset), "duration": try time(duration),
                         "value": marker["name"].stringValue ?? "Marker"]
            if marker["kind"].text == "todo" { attrs["completed"] = "0" }
            let chapter = marker["kind"].text == "chapter"
            if chapter { attrs["posterOffset"] = "0s" }
            _ = element(chapter ? "chapter-marker" : "marker", attrs, parent: anchor.node)
        }
        return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE fcpxml>\n" + root.xmlString(options: .nodePrettyPrint)
    }

    static func subtitleMarkers(_ text: String) -> [Value] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        return normalized.components(separatedBy: "\n\n").compactMap { block in
            let lines = block.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")
            guard let index = lines.firstIndex(where: { $0.contains("-->") }), index + 1 < lines.count,
                  let start = lines[index].components(separatedBy: "-->").first else { return nil }
            let fields = start.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".").components(separatedBy: ":")
            guard fields.count == 3, let h = Int(fields[0]), let m = Int(fields[1]), let s = Double(fields[2]) else { return nil }
            return ["time": .double(Double(h) * 3600 + Double(m) * 60 + s),
                    "name": .string(lines[(index + 1)...].joined(separator: " ")), "kind": "standard"]
        }
    }
}

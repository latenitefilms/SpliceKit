import Foundation
import MCP

struct TimelineExchange {
    let bridge: Bridge

    private func convert(_ input: [String: Value]) async throws -> Value {
        let files = FileManager.default
        let candidates: [URL]
        if let override = ProcessInfo.processInfo.environment["SPLICEKIT_OTIO_ADAPTER"], !override.isEmpty {
            guard (override as NSString).isAbsolutePath else {
                throw ToolFailure("SPLICEKIT_OTIO_ADAPTER must be an absolute executable path.")
            }
            candidates = [URL(fileURLWithPath: override)]
        } else {
            candidates = [CompanionTools.checkout?.appendingPathComponent("MCP/otio-adapter"),
                          files.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/splicekit-otio-adapter")]
                .compactMap { $0 }
        }
        guard let adapter = candidates.first(where: { files.isExecutableFile(atPath: $0.path) }) else {
            throw ToolFailure("This format needs an external OpenTimelineIO adapter. Set SPLICEKIT_OTIO_ADAPTER to the absolute path of MCP/otio-adapter in your checkout.")
        }
        let data = try await CompanionTools.run(adapter, arguments: [], input: JSONEncoder().encode(input), timeout: 300)
        return try JSONDecoder().decode(Value.self, from: data)
    }

    func run(_ name: String, _ a: Arguments) async throws -> String {
        let path = a["path"].text
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()
        let nativeXML = ["fcpxml", "fcpxmld"].contains(ext)
        let xmlURL = ext == "fcpxmld" ? url.appendingPathComponent("Info.fcpxml") : url
        if name == "export_otio" {
            guard !path.isEmpty else { throw ToolFailure("An output path is required.") }
            if nativeXML {
                if ext == "fcpxmld" { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
                _ = try await bridge.call(BridgeRequest("fcpxml.export", ["path": .string(xmlURL.path)]))
                let data = try Data(contentsOf: xmlURL)
                var summary = (try? metadata(data).first?.fields) ?? [:]
                summary.merge(["status": "ok", "path": .string(path), "format": .string(ext), "bytes": .int(data.count)]) { _, new in new }
                return try Value.object(summary).json()
            }
            let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("fcpxml")
            defer { try? FileManager.default.removeItem(at: source) }
            _ = try await bridge.call(BridgeRequest("fcpxml.export", ["path": .string(source.path)]))
            return try await convert(["operation": "export", "source": .string(source.path), "path": a["path"], "rate": a["rate"]]).json()
        }
        guard !path.isEmpty || a["otio_json"].truthy else { throw ToolFailure("Provide a path or raw otio_json.") }
        if nativeXML {
            let data = try Data(contentsOf: xmlURL)
            guard let xml = String(data: data, encoding: .utf8) else { throw ToolFailure("FCPXML must be UTF-8.") }
            _ = try await insert(xml)
            let details = (try? metadata(data)) ?? []
            return try Value.object(["status": "ok", "format": .string(ext), "timelines_total": .int(details.count), "details": .array(details)]).json()
        }
        if ext == "otio" || path.isEmpty {
            var input: [String: Value] = ["path": path.isEmpty ? "/dev/null" : a["path"]]
            if path.isEmpty { input["otio_json"] = a["otio_json"] }
            // Only the conversion is retriable. Never import a timeline twice after an ambiguous reply.
            if let converted = try? await bridge.call(BridgeRequest("otio.toFCPXML", input)),
               let xml = converted["fcpxml"].stringValue, !xml.isEmpty {
                let document = try XMLDocument(xmlString: xml, options: [.nodeLoadExternalEntitiesNever])
                let details = (try? metadata(Data(xml.utf8))) ?? []
                for node in try document.nodes(forXPath: "/fcpxml/library/event/asset-clip | /fcpxml/event/asset-clip") { node.detach() }
                if let library = try document.nodes(forXPath: "/fcpxml/library").first, let root = document.rootElement() {
                    for node in library.children ?? [] { node.detach(); root.addChild(node) }
                    library.detach()
                }
                _ = try await insert(document.xmlString)
                return try Value.object(["status": "ok", "format": .string(path.isEmpty ? "otio_json" : ext),
                                         "converter": "native", "timelines_total": .int(details.count), "details": .array(details)]).json()
            }
        }
        let documents = try await convert(["operation": "import", "path": a["path"], "rate": a["rate"], "otio_json": a["otio_json"]])
        var entries: [Value] = []
        var imported = 0
        for doc in documents.list {
            var summary = doc["summary"].fields
            if let xml = doc["xml"].stringValue {
                summary["converter"] = summary["converter"] ?? "external_adapter"
                do {
                    _ = try await insert(xml)
                    imported += 1
                    summary["status"] = "ok"
                } catch { summary["error"] = .string(error.localizedDescription) }
            } else { summary["error"] = doc["error"] }
            entries.append(.object(summary))
        }
        return try Value.object(["status": imported > 0 ? "ok" : "error", "format": .string(path.isEmpty ? "otio_json" : ext),
                                 "timelines_imported": .int(imported), "timelines_total": .int(entries.count), "details": .array(entries)]).json()
    }

    private func insert(_ xml: String) async throws -> Value {
        try await bridge.call(BridgeRequest("fcpxml.import", ["xml": .string(xml), "internal": true]))
    }

    private func metadata(_ data: Data) throws -> [Value] {
        let document = try XMLDocument(data: data, options: [.nodeLoadExternalEntitiesNever])
        let clipElements: Set<String> = ["asset-clip", "clip", "ref-clip", "sync-clip", "mc-clip", "video", "audio", "title", "audition"]
        return try document.nodes(forXPath: "//project").compactMap { node in
            guard let project = node as? XMLElement else { return nil }
            let duration = (try? project.nodes(forXPath: "sequence/@duration").first?.stringValue) ?? ""
            let parts = duration.trimmingCharacters(in: CharacterSet(charactersIn: "s")).split(separator: "/").compactMap { Double($0) }
            var info: [String: Value] = ["name": .string(project.attribute(forName: "name")?.stringValue ?? "unknown")]
            if let numerator = parts.first, parts.count == 1 || parts[1] > 0 {
                info["duration_seconds"] = .double(numerator / (parts.count > 1 ? parts[1] : 1))
            }
            // A clip's own audio and video elements are media components. Count
            // storyline items and connected clips, which carry a lane attribute.
            if let spine = try project.nodes(forXPath: "sequence/spine").first {
                let items = try spine.nodes(forXPath: "./* | .//spine/* | .//*[@lane]").compactMap { $0 as? XMLElement }
                info["clips"] = .int(items.filter { clipElements.contains($0.name ?? "") }.count)
                let connectedLanes = items.compactMap { $0.attribute(forName: "lane")?.stringValue }.compactMap(Int.init)
                info["tracks"] = .int(Set(connectedLanes).union([0]).count)
            }
            return .object(info)
        }
    }
}

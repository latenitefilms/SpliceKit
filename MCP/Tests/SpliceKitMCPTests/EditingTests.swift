import Darwin
import Foundation
import MCP
import Testing
@testable import SpliceKitMCP

private func arguments(_ name: String, _ values: [String: Value] = [:]) throws -> Arguments {
    let catalog = try ToolCatalog.load()
    let tool = try #require(catalog.tools.first { $0.name == name })
    return try Arguments(values, for: tool)
}

private func reply(_ id: Int, _ result: Value) -> Value {
    ["jsonrpc": "2.0", "id": .int(id), "result": result]
}

/// Supply a finite stream of replies and record every request without touching Final Cut Pro.
private func recordedRequests(replies: [Value], operation: (Bridge) async throws -> Void) async throws -> [Value] {
    var sockets = [Int32](repeating: -1, count: 2)
    guard socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets) == 0 else { throw POSIXError(.ENOTCONN) }
    let client = FileHandle(fileDescriptor: sockets[0], closeOnDealloc: true)
    let peer = FileHandle(fileDescriptor: sockets[1], closeOnDealloc: true)
    // The bridge may close its descriptor during the lost-reply test.
    let bridgeSocket = dup(client.fileDescriptor)
    guard bridgeSocket >= 0 else { throw POSIXError(.EMFILE) }
    let bridge = Bridge(connectedSocket: bridgeSocket)
    let encoder = JSONEncoder()
    for reply in replies {
        var data = try encoder.encode(reply)
        data.append(10)
        try peer.write(contentsOf: data)
    }
    shutdown(peer.fileDescriptor, SHUT_WR)
    try await operation(bridge)
    shutdown(client.fileDescriptor, SHUT_WR)
    let recorded = try peer.readToEnd() ?? Data()
    return try recorded.split(separator: 10).map { try JSONDecoder().decode(Value.self, from: $0) }
}

@Test func catalogHasUniqueEditingToolsResourcesAndPrompts() throws {
    let catalog = try ToolCatalog.load()
    #expect(catalog.tools.count == Set(catalog.tools.map(\.name)).count)
    #expect(catalog.resources.count == 10)
    #expect(catalog.prompts.count == 7)
    for name in ["open_project", "generate_captions", "get_timeline_clips", "export_otio", "detect_beats"] {
        #expect(catalog.tools.contains { $0.name == name })
    }
    for prompt in catalog.prompts {
        #expect(try !editingPrompt(prompt.name, arguments: [:]).isEmpty)
    }
}

@Test func toolArgumentsPreserveDefaultsAndValidateTypes() throws {
    let timeline = try arguments("get_timeline_clips")
    #expect(try editingRequest("get_timeline_clips", timeline)?.parameters["limit"] == .int(100))
    #expect(throws: ToolFailure.self) { try arguments("get_timeline_clips", ["limit": "100"]) }
    #expect(throws: ToolFailure.self) { try arguments("seek_to_time") }
    let edit = try arguments("timeline_navigation_action", ["action": "delete"])
    #expect(throws: ToolFailure.self) { try editingRequest("timeline_navigation_action", edit) }
}

@Test func generatedXMLPreservesProjectNamesAndClipRelativeMarkerTimes() throws {
    let items: Value = [["type": "gap", "duration": 3], ["type": "title", "duration": 5, "text": "A < B"],
                        ["type": "marker", "time": 5, "kind": "chapter", "name": "Act & Two"]]
    let args = try arguments("generate_fcpxml", ["project_name": "Act \"A\" & B", "items": .string(try items.json())])
    let xml = try XMLDocument(xmlString: TimelineXML.generate(args), options: [.nodeLoadExternalEntitiesNever])
    #expect(try xml.nodes(forXPath: "//project/@name").first?.stringValue == "Act \"A\" & B")
    #expect(try xml.nodes(forXPath: "//title/text/text-style").first?.stringValue == "A < B")
    #expect(try xml.nodes(forXPath: "//title/chapter-marker/@value").first?.stringValue == "Act & Two")
    #expect(try xml.nodes(forXPath: "//title/chapter-marker/@start").first?.stringValue == "8644800/2400s")
    #expect(try xml.nodes(forXPath: "//sequence/@duration").first?.stringValue == "19200/2400s")
}

@Test func subtitlesKeepMultilineTextAndFractionalSeconds() {
    let markers = TimelineXML.subtitleMarkers("1\r\n00:00:01,125 --> 00:00:03,000\r\nWord\r\nwrap\r\n\r\ninvalid")
    #expect(markers == [["time": 1.125, "kind": "standard", "name": "Word wrap"]])
}

@Test func bridgeMatchesReplyIDsAndKeepsConnectionAfterRPCError() async throws {
    let replies: [Value] = [
        ["method": "events.notification", "params": [:]], reply(98, ["stale": true]),
        ["jsonrpc": "2.0", "id": 1, "error": ["message": "Detailed state unavailable"]],
        reply(2, ["itemCount": 4, "selectedCount": 1, "sequenceName": "Test",
                  "playheadTime": ["seconds": 2.5]])
    ]
    let requests = try await recordedRequests(replies: replies) { bridge in
        let text = try await EditingWorkflows(bridge: bridge).call("verify_action", arguments("verify_action"))
        let result = try Value.string(text).decodedJSON()
        #expect(result["item_count"] == 4)
        #expect(result["playhead_seconds"] == 2.5)
    }
    #expect(requests.map { $0["method"].text } == ["timeline.getDetailedState", "timeline.getState"])
    #expect(requests.map { $0["id"].intValue } == [1, 2])
}

@Test func lostReplyDoesNotReplayAnEditingRequest() async throws {
    let requests = try await recordedRequests(replies: []) { bridge in
        await #expect(throws: ToolFailure.self) { try await bridge.call(BridgeRequest("timeline.action", ["action": "blade"])) }
    }
    #expect(requests.count == 1)
}

@Test func fcpxmlPackageImportsAllProjectsWithoutAnAdapter() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".fcpxmld")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let xml = """
    <fcpxml version="1.14"><library><event name="Test">
      <project name="First"><sequence duration="100/25s"><spine>
        <clip><video ref="r1"/><title lane="1"/></clip>
      </spine></sequence></project>
      <project name="Second"><sequence duration="8s"><spine/></sequence></project>
    </event></library></fcpxml>
    """
    try Data(xml.utf8).write(to: directory.appendingPathComponent("Info.fcpxml"))
    let requests = try await recordedRequests(replies: [reply(1, ["status": "ok"])]) { bridge in
        let args = try arguments("import_otio", ["path": .string(directory.path)])
        let text = try await TimelineExchange(bridge: bridge).run("import_otio", args)
        let imported = try Value.string(text).decodedJSON()
        #expect(imported["timelines_total"] == 2)
        #expect(imported["details"].list.map { $0["duration_seconds"].number } == [4, 8])
        #expect(imported["details"].list.first?["clips"] == 2)
        #expect(imported["details"].list.first?["tracks"] == 2)
    }
    #expect(requests.map { $0["method"].text } == ["fcpxml.import"])
    #expect(requests.first?["params"]["xml"].stringValue == xml)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["SPLICEKIT_OTIO_PYTHON"] != nil))
func optionalOTIOAdapterImportsTransitionsThroughTheEditingBridge() async throws {
    let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    let fixture = package.deletingLastPathComponent()
        .appendingPathComponent("Tests/fixtures/upstream_otio_fcpxml/fcpx_transitions.fcpxml")
    let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".otio")
    defer { try? FileManager.default.removeItem(at: output) }
    let export: Value = ["operation": "export", "source": .string(fixture.path), "path": .string(output.path)]
    _ = try await CompanionTools.run(package.appendingPathComponent("otio-adapter"), arguments: [],
                                     input: JSONEncoder().encode(export))
    let replies = [reply(1, ["error": "Native converter unavailable"]), reply(2, ["status": "ok"])]
    let requests = try await recordedRequests(replies: replies) { bridge in
        let args = try arguments("import_otio", ["path": .string(output.path)])
        let result = try await TimelineExchange(bridge: bridge).run("import_otio", args)
        let summary = try Value.string(result).decodedJSON()
        #expect(summary["timelines_imported"] == 1)
        #expect(summary["details"].list.first?["clips"] == 3)
        #expect(summary["details"].list.first?["converter"] == "python_adapter")
    }
    #expect(requests.map { $0["method"].text } == ["otio.toFCPXML", "fcpxml.import"])
    let xml = try #require(requests.last?["params"]["xml"].stringValue)
    let document = try XMLDocument(xmlString: xml, options: [.nodeLoadExternalEntitiesNever])
    #expect(try document.nodes(forXPath: "//transition").count == 2)
}

@Test func repeatedFrameActionsSeekOnceAtProjectFrameRate() async throws {
    let actions: Value = [["type": "playback", "action": "nextFrame", "repeat": 30],
                          ["type": "playback", "action": "prevFrame10", "repeat": 100]]
    let state: Value = ["seconds": 4, "frameRate": .double(30000.0 / 1001), "duration": ["seconds": 20]]
    let requests = try await recordedRequests(replies: [reply(1, state), reply(2, [:]), reply(3, state), reply(4, [:])]) { bridge in
        let args = try arguments("batch_timeline_actions", ["actions": .string(try actions.json())])
        let summary = try await EditingWorkflows(bridge: bridge).call("batch_timeline_actions", args)
        #expect(!summary.contains("FAILED"))
    }
    #expect(requests.map { $0["method"].text } == ["playback.getPosition", "playback.seekToTime", "playback.getPosition", "playback.seekToTime"])
    #expect(abs(requests[1]["params"]["seconds"].number - 5.001) < 0.000001)
    #expect(requests[3]["params"]["seconds"].number == 0)
}

@Test func dynamicToolsBelongToRegisteredPluginNamespaces() async throws {
    let methods: Value = ["methods": [["name": "org.example.colors.grade", "pluginId": "org.example.colors", "readOnly": true],
                                     ["name": "org.example.audio.meters"], ["name": "unowned.method"]]]
    let manifests: Value = ["plugins": ["org.example.audio": ["name": "Meters"]]]
    let requests = try await recordedRequests(replies: [reply(1, methods), reply(2, manifests), reply(3, ["methods": []])]) { bridge in
        let registry = PluginTools()
        let tools = await registry.discover(from: bridge)
        #expect(tools.map(\.name) == ["plugin_org_example_audio_meters", "plugin_org_example_colors_grade"])
        #expect(await registry.method(named: "plugin_org_example_audio_meters") == "org.example.audio.meters")
        let refreshedCount = try await registry.reload(from: bridge)
        #expect(refreshedCount == 0)
        #expect(await registry.method(named: "plugin_org_example_audio_meters") == nil)
    }
    #expect(requests.map { $0["method"].text } == ["plugin.listMethods", "plugin.list", "plugin.listMethods"])
}

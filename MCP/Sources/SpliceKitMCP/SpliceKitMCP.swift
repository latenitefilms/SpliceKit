import Darwin
import Foundation
import MCP

/// Only methods declared by installed plug-ins are added to this registry.
actor PluginTools {
    private var entries: [String: (method: String, tool: Tool)] = [:]
    private var initialDiscovery: Task<Int, Error>?

    func discover(from bridge: Bridge) async -> [Tool] {
        if initialDiscovery == nil {
            initialDiscovery = Task { try await reload(from: bridge) }
        }
        _ = try? await initialDiscovery?.value
        return entries.values.map(\.tool).sorted { $0.name < $1.name }
    }

    func reload(from bridge: Bridge) async throws -> Int {
        let result = try await bridge.call(BridgeRequest("plugin.listMethods"))
        let methods = result["methods"].list
        var installedIDs: [String] = []
        if methods.contains(where: { $0["pluginId"].text.isEmpty }) {
            let manifests = try? await bridge.call(BridgeRequest("plugin.list"))
            installedIDs = manifests?["plugins"].fields.keys.sorted() ?? []
        }
        var updated: [String: (String, Tool)] = [:]
        for entry in methods {
            let method = entry["name"].text
            let plugin = entry["pluginId"].stringValue ?? installedIDs.first { method.hasPrefix($0 + ".") }
            guard let plugin, plugin.contains("."), method.hasPrefix(plugin + ".") else { continue }
            let name = "plugin_" + method.replacingOccurrences(of: ".", with: "_")
            let readOnly = entry["readOnly"].truthy
            let tool = Tool(name: name, description: entry["description"].stringValue ?? method,
                            inputSchema: ["type": "object", "properties": ["params": ["type": "string", "default": "{}"]]],
                            annotations: .init(title: plugin + ": " + (entry["shortName"].stringValue ?? method),
                                               readOnlyHint: readOnly, destructiveHint: false, idempotentHint: readOnly, openWorldHint: false))
            updated[name] = (method, tool)
        }
        entries = updated
        return updated.count
    }

    func method(named name: String) -> String? { entries[name]?.method }
}

@main
struct SpliceKitMCP {
    static func main() async {
        do { try await run() }
        catch {
            FileHandle.standardError.write(Data("SpliceKit MCP: \(error.localizedDescription)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    private static func run() async throws {
        let catalog = try ToolCatalog.load()
        if CommandLine.arguments.dropFirst().elementsEqual(["--check"]) {
            print("SpliceKit MCP: \(catalog.tools.count) tools, \(catalog.resources.count) resources, \(catalog.prompts.count) prompts.")
            return
        }
        let bridge = Bridge()
        let workflows = EditingWorkflows(bridge: bridge)
        let plugins = PluginTools()
        let builtins = Dictionary(uniqueKeysWithValues: catalog.tools.map { ($0.name, $0) })
        let bundle = ToolCatalog.executableDirectory.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let version = Bundle(url: bundle)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        let server = Server(name: "splicekit", version: version, instructions: editingInstructions,
                            capabilities: .init(prompts: .init(), resources: .init(), tools: .init(listChanged: true)))
        await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: catalog.tools + (await plugins.discover(from: bridge)))
        }
        await server.withMethodHandler(CallTool.self) { request in
            do {
                let text: String
                if request.name == "reload_plugin_tools" {
                    let count = try await plugins.reload(from: bridge)
                    try? await server.notify(ToolListChangedNotification.message())
                    text = try Value.object(["registered": .int(count), "status": "ok"]).json()
                } else if let tool = builtins[request.name] {
                    text = try await workflows.call(tool.name, Arguments(request.arguments ?? [:], for: tool))
                } else if let method = await plugins.method(named: request.name) {
                    let params = try (request.arguments?["params"] ?? "{}").decodedJSON()
                    guard let object = params.objectValue else { throw ToolFailure("Plugin params must be a JSON object.") }
                    text = try await bridge.call(BridgeRequest(method, object)).json()
                } else { throw ToolFailure("Unknown SpliceKit tool '\(request.name)'.") }
                return .init(content: [.text(text: text, annotations: nil, _meta: nil)], structuredContent: .object(["result": .string(text)]))
            } catch {
                return .init(content: [.text(text: "Error: \(error.localizedDescription)", annotations: nil, _meta: nil)], isError: true)
            }
        }
        await server.withMethodHandler(ListResources.self) { _ in .init(resources: catalog.resources) }
        await server.withMethodHandler(ReadResource.self) { request in
            guard let resource = catalog.resources.first(where: { $0.uri == request.uri }) else {
                throw MCPError.invalidParams("Unknown resource '\(request.uri)'.")
            }
            let text = try await workflows.resource(request.uri)
            return .init(contents: [.text(text, uri: resource.uri, mimeType: resource.mimeType)])
        }
        await server.withMethodHandler(ListPrompts.self) { _ in .init(prompts: catalog.prompts) }
        await server.withMethodHandler(GetPrompt.self) { request in
            let text = try editingPrompt(request.name, arguments: request.arguments ?? [:])
            return .init(messages: [.user(.text(text: text))])
        }
        try await server.start(transport: StdioTransport())
        await server.waitUntilCompleted()
    }
}

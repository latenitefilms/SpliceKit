import Darwin
import Foundation
import MCP

struct ToolCatalog: Decodable {
    let tools: [Tool]
    let resources: [Resource]
    let prompts: [Prompt]

    static let executableDirectory: URL = {
        var length: UInt32 = 0
        _NSGetExecutablePath(nil, &length)
        var path = [CChar](repeating: 0, count: Int(length))
        _NSGetExecutablePath(&path, &length)
        return URL(fileURLWithFileSystemRepresentation: path, isDirectory: false, relativeTo: nil)
            .resolvingSymlinksInPath().deletingLastPathComponent()
    }()

    static func load() throws -> ToolCatalog {
        let adjacent = executableDirectory.appendingPathComponent("Catalog.json")
        let url: URL
        if FileManager.default.fileExists(atPath: adjacent.path) {
            url = adjacent
        } else if let packaged = packageCatalog {
            url = packaged
        } else {
            throw ToolFailure("SpliceKit MCP tool catalog is missing.")
        }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }

    private final class BundleAnchor {}

    static var productDirectories: [URL] {
        [executableDirectory, Bundle(for: BundleAnchor.self).bundleURL.deletingLastPathComponent()]
    }

    private static var packageCatalog: URL? {
        // SwiftPM places its resource bundle beside the program or the test bundle.
        for directory in productDirectories {
            let bundle = Bundle(url: directory.appendingPathComponent("SpliceKitMCP_SpliceKitMCP.bundle"))
            if let url = bundle?.url(forResource: "Catalog", withExtension: "json") { return url }
        }
        return nil
    }
}

extension Value {
    var text: String { stringValue ?? "" }
    var number: Double { doubleValue ?? intValue.map(Double.init) ?? 0 }
    var list: [Value] { arrayValue ?? [] }
    var fields: [String: Value] { objectValue ?? [:] }
    subscript(_ key: String) -> Value { fields[key] ?? .null }

    var truthy: Bool {
        switch self {
        case .null: false
        case .bool(let b): b
        case .int(let i): i != 0
        case .double(let d): d != 0
        case .string(let s): !s.isEmpty
        case .array(let a): !a.isEmpty
        case .object(let o): !o.isEmpty
        case .data(_, let data): !data.isEmpty
        }
    }

    func decodedJSON() throws -> Value {
        guard let stringValue else { return self }
        do { return try JSONDecoder().decode(Value.self, from: Data(stringValue.utf8)) }
        catch { throw ToolFailure("Invalid JSON: \(error.localizedDescription)") }
    }

    func json() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }
}

struct Arguments {
    var values: [String: Value]
    subscript(_ key: String) -> Value { values[key] ?? .null }

    init(_ given: [String: Value], for tool: Tool) throws {
        let schema = tool.inputSchema
        var result = given
        for key in schema["required"].list.compactMap(\.stringValue) where given[key] == nil {
            throw ToolFailure("Missing required argument '\(key)' for \(tool.name).")
        }
        for (key, property) in schema["properties"].fields {
            if let value = given[key] {
                guard Self.matches(value, property) else { throw ToolFailure("Invalid value for '\(key)' in \(tool.name).") }
            } else if let defaultValue = property.fields["default"] {
                result[key] = defaultValue
            }
        }
        values = result
    }

    private static func matches(_ value: Value, _ schema: Value) -> Bool {
        if let choices = schema["anyOf"].arrayValue {
            return choices.contains { matches(value, $0) }
        }
        switch schema["type"].text {
        case "string": return value.stringValue != nil
        case "integer": return value.intValue != nil
        case "number": return value.intValue != nil || value.doubleValue != nil
        case "boolean": return value.boolValue != nil
        case "object": return value.objectValue != nil
        case "null": return value.isNull
        case "array": return value.arrayValue?.allSatisfy { matches($0, schema["items"]) } == true
        default: return true
        }
    }
}

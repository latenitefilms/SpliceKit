import Darwin
import Foundation
import MCP

enum CompanionTools {
    static var checkout: URL? {
        for productDirectory in ToolCatalog.productDirectories {
            var directory = productDirectory
            while directory.path != "/" {
                if FileManager.default.fileExists(atPath: directory.appendingPathComponent("MCP/Package.swift").path) {
                    return directory
                }
                directory.deleteLastPathComponent()
            }
        }
        return nil
    }

    static func audio(_ name: String) throws -> URL {
        let directory = ToolCatalog.executableDirectory
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [directory.deletingLastPathComponent().appendingPathComponent("tools/\(name)"),
                          checkout?.appendingPathComponent("build/\(name)"),
                          home.appendingPathComponent("Applications/SpliceKit/tools/\(name)"),
                          home.appendingPathComponent("Library/Application Support/SpliceKit/tools/\(name)")]
        guard let executable = candidates.compactMap({ $0 }).first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
            throw ToolFailure("Missing \(name). Rebuild the SpliceKit patcher or run make -f Scripts/Makefile tools in the source checkout.")
        }
        return executable
    }

    /// Files keep large adapter output independent of the pipe buffer size.
    static func run(_ executable: URL, arguments: [String], input: Data? = nil, timeout: TimeInterval = 60) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result { try runBlocking(executable, arguments: arguments, input: input, timeout: timeout) })
            }
        }
    }

    private static func runBlocking(_ executable: URL, arguments: [String], input: Data?, timeout: TimeInterval) throws -> Data {
        let files = FileManager.default
        let directory = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try files.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? files.removeItem(at: directory) }
        let output = directory.appendingPathComponent("output"), errors = directory.appendingPathComponent("errors")
        try Data().write(to: output)
        try Data().write(to: errors)
        let stdout = try FileHandle(forWritingTo: output), stderr = try FileHandle(forWritingTo: errors)
        defer { try? stdout.close(); try? stderr.close() }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr
        let stdin: FileHandle
        if let input {
            let url = directory.appendingPathComponent("input")
            try input.write(to: url)
            stdin = try FileHandle(forReadingFrom: url)
        } else { stdin = FileHandle.nullDevice }
        defer { if input != nil { try? stdin.close() } }
        process.standardInput = stdin
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        try process.run()
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            if process.isRunning { process.terminate() }
            if finished.wait(timeout: .now() + 1) == .timedOut, process.isRunning {
                Darwin.kill(process.processIdentifier, SIGKILL)
                process.waitUntilExit()
            }
            throw ToolFailure("\(executable.lastPathComponent) timed out.")
        }
        guard process.terminationStatus == 0 else {
            let detail = (try? String(contentsOf: errors, encoding: .utf8)) ?? ""
            throw ToolFailure("\(executable.lastPathComponent): \(detail.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return try Data(contentsOf: output)
    }
}

struct AudioWorkflows {
    let bridge: Bridge

    func run(_ name: String, _ a: Arguments) async throws -> String {
        let detector = name == "detect_beats"
        let executable = try CompanionTools.audio(detector ? "beat-detector" : "structure-analyzer")
        let file = a["file_path"].text
        let data = try await CompanionTools.run(executable, arguments: [file, a["sensitivity"].description,
                                                                          a["min_bpm"].description, a["max_bpm"].description])
        let result = try JSONDecoder().decode(Value.self, from: data)
        if let error = result["error"].stringValue { throw ToolFailure(error) }
        if detector { return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) }
        let sections = result["structure"].list
        let song = URL(fileURLWithPath: file).lastPathComponent
        let bpm = result["bpm"].description
        if name == "analyze_song_structure" {
            var lines = ["Song Structure Analysis: \(song)", "Duration: \(result["duration"])s  BPM: \(bpm)  Bars: \(result["barCount"])  Beats: \(result["beatCount"])", "", "Structure:"]
            lines += sections.map { "  \($0["label"])  \($0["start"])s – \($0["end"])s  (\($0["bars"]) bars, energy=\($0["energy"]), \($0["duration"])s)" }
            if !result["drops"].list.isEmpty { lines.append("Drops: " + result["drops"].list.map(\.description).joined(separator: ", ")) }
            lines.append("Beat interval: \(result["beatInterval"])s")
            return lines.joined(separator: "\n")
        }
        if name == "beat_sync_blade" { return try await blade(a, result, song) }
        guard !sections.isEmpty else { throw ToolFailure("No song structure detected.") }
        let blocks = name == "song_structure_blocks"
        let reply = try await bridge.call(BridgeRequest(blocks ? "structure.generateCaptions" : "sections.show",
                                                        ["sections": .array(sections)]))
        let count = blocks ? reply["captionCount"].intValue : reply["sectionCount"].intValue
        var lines = ["\(blocks ? "Structure Blocks" : "Sections Bar"): \(song)", "BPM: \(bpm)  Sections: \(count ?? sections.count)"]
        lines += sections.map { "\($0["label"])  \($0["start"])s – \($0["end"])s" }
        return lines.joined(separator: "\n")
    }

    private func blade(_ a: Arguments, _ analysis: Value, _ song: String) async throws -> String {
        let level = a["cut_on"].text
        var beats: [Value]
        switch level {
        case "beat": beats = analysis["beats"].list
        case "bar", "downbeat": beats = analysis["bars"].list
        case "half_bar": beats = analysis["beats"].list.enumerated().compactMap { $0.offset.isMultiple(of: 2) ? $0.element : nil }
        case "section": beats = analysis["structure"].list.map { $0["start"] }
        case "drop": beats = analysis["drops"].list
        default: throw ToolFailure("Unknown cut_on value '\(level)'.")
        }
        guard !beats.isEmpty else { throw ToolFailure("No \(level) timestamps found in audio analysis.") }
        let offset = a["offset_frames"].number / 24
        var times: [Double] = []
        for beat in beats.map(\.number) {
            if a["range_start"].number >= 0 && beat < a["range_start"].number { continue }
            if a["range_end"].number >= 0 && beat > a["range_end"].number { continue }
            let time = beat + offset
            if let last = times.last, time - last < a["min_clip_duration"].number { continue }
            times.append(time)
        }
        times.removeAll { $0 <= 0.05 }
        guard !times.isEmpty else { return "No cut points remain after filtering" }
        var lines = ["Beat Sync Blade: \(song)", "BPM: \(analysis["bpm"])  Cut on: \(level)  Cuts: \(times.count)"]
        if a["dry_run"].truthy {
            lines.append("Planned cuts:")
            lines += times.enumerated().map { String(format: "%d. %.2fs", $0.offset + 1, $0.element) }
        } else {
            let result = try await bridge.call(BridgeRequest("timeline.bladeAtTimes", ["times": .array(times.map(Value.double))]))
            lines.append("Applied \(result["applied"])/\(times.count) cuts")
            lines += result["cuts"].list.filter { !$0["success"].truthy }.map { "\($0["time"])s: \($0["error"])" }
        }
        return lines.joined(separator: "\n")
    }
}

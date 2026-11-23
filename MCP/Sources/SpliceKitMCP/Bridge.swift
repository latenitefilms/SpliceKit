import Darwin
import Foundation
import MCP

struct ToolFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct BridgeRequest {
    let method: String
    let parameters: [String: Value]

    init(_ method: String, _ parameters: [String: Value] = [:]) {
        self.method = method
        self.parameters = parameters
    }
}

/// The bridge owns connection-scoped subscriptions and object handles. Serialize
/// requests so simultaneous MCP calls cannot consume one another's replies.
actor Bridge {
    private var socket: Int32 = -1
    private var sequence = 0
    private var buffered = Data()

    init(connectedSocket: Int32 = -1) { socket = connectedSocket }

    deinit { if socket >= 0 { Darwin.close(socket) } }

    private func connect() throws {
        guard socket == -1 else { return }
        socket = Darwin.socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard socket >= 0 else { throw ToolFailure(String(cString: strerror(errno))) }
        var yes: Int32 = 1
        var timeout = timeval(tv_sec: 30, tv_usec: 0)
        guard setsockopt(socket, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout.size(ofValue: yes))) == 0,
              setsockopt(socket, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout))) == 0,
              setsockopt(socket, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout))) == 0
        else { throw ToolFailure(String(cString: strerror(errno))) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(9876).bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let length = socklen_t(MemoryLayout.size(ofValue: address))
        let status = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(socket, $0, length) }
        }
        guard status == 0 else {
            throw ToolFailure("Cannot connect to SpliceKit on 127.0.0.1:9876. Open the patched Final Cut Pro and try again.")
        }
    }

    func call(_ request: BridgeRequest) throws -> Value {
        do {
            try connect()
            sequence += 1
            let envelope: Value = ["jsonrpc": "2.0", "id": .int(sequence),
                                   "method": .string(request.method), "params": .object(request.parameters)]
            var bytes = try JSONEncoder().encode(envelope)
            bytes.append(10)
            try bytes.withUnsafeBytes { buffer in
                var sent = 0
                while sent < buffer.count {
                    let count = Darwin.send(socket, buffer.baseAddress!.advanced(by: sent), buffer.count - sent, 0)
                    if count == -1 && errno == EINTR { continue }
                    guard count > 0 else { throw ToolFailure("The bridge connection closed while sending the request.") }
                    sent += count
                }
            }
            var searchStart = buffered.startIndex
            var chunk = [UInt8](repeating: 0, count: 64 * 1024)
            while true {
                if let newline = buffered[searchStart...].firstIndex(of: 10) {
                    let line = buffered[..<newline]
                    buffered.removeSubrange(...newline)
                    searchStart = buffered.startIndex
                    let message = try JSONDecoder().decode(Value.self, from: line)
                    guard message.objectValue?["id"]?.intValue == sequence else { continue }
                    if let error = message.objectValue?["error"] {
                        throw RPCFailure(message: error.objectValue?["message"]?.stringValue ?? error.description)
                    }
                    guard let result = message.objectValue?["result"] else { throw ToolFailure("Missing bridge result.") }
                    if let error = result.objectValue?["error"]?.stringValue { throw RPCFailure(message: error) }
                    return result
                }
                searchStart = buffered.endIndex
                let count = chunk.withUnsafeMutableBytes { Darwin.recv(socket, $0.baseAddress, $0.count, 0) }
                if count == -1 && errno == EINTR { continue }
                guard count > 0 else { throw ToolFailure("The bridge connection closed or timed out before replying.") }
                buffered.append(contentsOf: chunk.prefix(count))
            }
        } catch let error as RPCFailure {
            throw ToolFailure(error.message)
        } catch {
            if socket >= 0 { Darwin.close(socket) }
            socket = -1
            buffered.removeAll()
            // A write may already have taken effect. Reconnect on the next call.
            throw error
        }
    }

    private struct RPCFailure: Error { let message: String }
}

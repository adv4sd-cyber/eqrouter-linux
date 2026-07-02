#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Musl)
import Musl
#endif

import Foundation

/// A tiny blocking HTTP/1.1 server built directly on BSD sockets, so it
/// needs no networking library and cross-compiles with the static-Linux
/// SDK. One thread per connection; ample for a single-user local control
/// panel. Not exposed beyond localhost by default.
public final class HTTPServer {
    public struct Request {
        public let method: String
        public let path: String
        public let query: [String: String]
        public let headers: [String: String]
        public let body: Data
    }

    public struct Response {
        public var status: Int
        public var headers: [String: String]
        public var body: Data

        public init(status: Int = 200, contentType: String = "text/plain; charset=utf-8", body: Data = Data()) {
            self.status = status
            self.headers = ["Content-Type": contentType]
            self.body = body
        }

        public static func json(_ data: Data, status: Int = 200) -> Response {
            Response(status: status, contentType: "application/json; charset=utf-8", body: data)
        }
        public static func html(_ string: String) -> Response {
            Response(contentType: "text/html; charset=utf-8", body: Data(string.utf8))
        }
        public static func text(_ string: String, status: Int = 200) -> Response {
            Response(status: status, body: Data(string.utf8))
        }
    }

    public typealias Handler = (Request) -> Response

    private let port: UInt16
    private let host: String
    private var listenFD: Int32 = -1
    private var handler: Handler = { _ in Response(status: 404, body: Data("not found".utf8)) }
    private var running = false

    public init(host: String = "127.0.0.1", port: UInt16 = 8080) {
        self.host = host
        self.port = port
    }

    public func setHandler(_ handler: @escaping Handler) { self.handler = handler }

    private static let statusText: [Int: String] = [
        200: "OK", 201: "Created", 204: "No Content", 400: "Bad Request",
        404: "Not Found", 405: "Method Not Allowed", 500: "Internal Server Error",
    ]

    public enum ServerError: Error, CustomStringConvertible {
        case socketFailed(String)
        public var description: String {
            switch self { case .socketFailed(let s): return "HTTP server: \(s)" }
        }
    }

    /// Binds and serves forever on the calling thread.
    public func run() throws {
        listenFD = socket(AF_INET, sockStreamType, 0)
        guard listenFD >= 0 else { throw ServerError.socketFailed("socket() failed (errno \(errno))") }

        var yes: Int32 = 1
        setsockopt(listenFD, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr(host)

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(listenFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            close(listenFD)
            throw ServerError.socketFailed("bind() to \(host):\(port) failed (errno \(errno)) — is the port already in use?")
        }
        guard listen(listenFD, 32) == 0 else {
            close(listenFD)
            throw ServerError.socketFailed("listen() failed (errno \(errno))")
        }

        running = true
        while running {
            let clientFD = accept(listenFD, nil, nil)
            if clientFD < 0 {
                if errno == EINTR { continue }
                break
            }
            // One detached thread per connection.
            let fd = clientFD
            let thread = Thread { [weak self] in self?.serveConnection(fd) }
            thread.stackSize = 1 << 19
            thread.start()
        }
        close(listenFD)
    }

    public func stop() {
        running = false
        if listenFD >= 0 { close(listenFD) }
    }

    private func serveConnection(_ fd: Int32) {
        defer { close(fd) }
        guard let request = readRequest(fd) else {
            sendResponse(fd, Response(status: 400, body: Data("bad request".utf8)))
            return
        }
        let response = handler(request)
        sendResponse(fd, response)
    }

    // MARK: - Parsing

    private func readRequest(_ fd: Int32) -> Request? {
        var buffer = [UInt8]()
        var chunk = [UInt8](repeating: 0, count: 4096)
        var headerEnd: Int? = nil

        // Read until we have the full header block.
        while headerEnd == nil {
            let n = recv(fd, &chunk, chunk.count, 0)
            if n <= 0 { return nil }
            buffer.append(contentsOf: chunk[0..<n])
            headerEnd = findHeaderEnd(buffer)
            if buffer.count > 1 << 20 { return nil } // 1 MB header cap
        }
        guard let hEnd = headerEnd else { return nil }

        let headerData = Array(buffer[0..<hEnd])
        guard let headerText = String(bytes: headerData, encoding: .utf8) else { return nil }
        let lines = headerText.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        let method = String(parts[0])
        let rawTarget = String(parts[1])

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        // Body (respecting Content-Length).
        var body = Data(buffer[(hEnd + 4)...])
        if let lenStr = headers["content-length"], let len = Int(lenStr) {
            while body.count < len {
                let n = recv(fd, &chunk, chunk.count, 0)
                if n <= 0 { break }
                body.append(contentsOf: chunk[0..<n])
            }
            if body.count > len { body = body.prefix(len) }
        }

        let (path, query) = Self.splitTarget(rawTarget)
        return Request(method: method, path: path, query: query, headers: headers, body: body)
    }

    private func findHeaderEnd(_ buffer: [UInt8]) -> Int? {
        guard buffer.count >= 4 else { return nil }
        for i in 0...(buffer.count - 4) {
            if buffer[i] == 0x0D, buffer[i+1] == 0x0A, buffer[i+2] == 0x0D, buffer[i+3] == 0x0A {
                return i
            }
        }
        return nil
    }

    static func splitTarget(_ target: String) -> (path: String, query: [String: String]) {
        guard let q = target.firstIndex(of: "?") else {
            return (percentDecode(target), [:])
        }
        let path = percentDecode(String(target[..<q]))
        var query: [String: String] = [:]
        let queryString = target[target.index(after: q)...]
        for pair in queryString.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            let key = percentDecode(String(kv[0]))
            let value = kv.count > 1 ? percentDecode(String(kv[1])) : ""
            query[key] = value
        }
        return (path, query)
    }

    static func percentDecode(_ s: String) -> String {
        s.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? s
    }

    // MARK: - Writing

    private func sendResponse(_ fd: Int32, _ response: Response) {
        var head = "HTTP/1.1 \(response.status) \(Self.statusText[response.status] ?? "OK")\r\n"
        var headers = response.headers
        headers["Content-Length"] = String(response.body.count)
        headers["Connection"] = "close"
        for (k, v) in headers { head += "\(k): \(v)\r\n" }
        head += "\r\n"

        var out = Data(head.utf8)
        out.append(response.body)
        out.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var sent = 0
            while sent < raw.count {
                let n = send(fd, base.advanced(by: sent), raw.count - sent, sendNoSignalFlags)
                if n <= 0 { break }
                sent += n
            }
        }
    }
}

// `SOCK_STREAM` is imported differently per libc: a plain `Int32` on Musl
// and Darwin, but an enum case on Glibc (needs `.rawValue`). `MSG_NOSIGNAL`
// exists on Linux but not Darwin, where `signal(SIGPIPE, SIG_IGN)` covers us.
#if canImport(Musl)
private let sockStreamType = SOCK_STREAM
private let sendNoSignalFlags = Int32(MSG_NOSIGNAL)
#elseif canImport(Glibc)
private let sockStreamType = Int32(SOCK_STREAM.rawValue)
private let sendNoSignalFlags = Int32(MSG_NOSIGNAL)
#else
private let sockStreamType = SOCK_STREAM
private let sendNoSignalFlags: Int32 = 0
#endif

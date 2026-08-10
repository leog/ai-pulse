import Foundation

/// Minimal HTTP/1.1 request representation for the loopback service.
public struct HTTPRequest: Sendable, Equatable {
    public var method: String
    public var path: String
    /// Header names lowercased.
    public var headers: [String: String]
    public var body: Data
}

public enum HTTPParseOutcome: Sendable, Equatable {
    /// Need more bytes.
    case incomplete
    /// Malformed or over limits; the connection should be rejected.
    case invalid
    case request(HTTPRequest)
}

/// Tiny, allocation-light HTTP/1.1 parser. One request per connection
/// (the server always responds `Connection: close`).
public enum HTTPMessageParser {
    public static let maxHeaderBytes = 8_192

    public static func parse(_ buffer: Data, maxBodyBytes: Int) -> HTTPParseOutcome {
        guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else {
            return buffer.count > maxHeaderBytes ? .invalid : .incomplete
        }
        guard headerEnd.lowerBound <= maxHeaderBytes else { return .invalid }

        guard let head = String(data: buffer[..<headerEnd.lowerBound], encoding: .utf8) else {
            return .invalid
        }
        var lines = head.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return .invalid }

        let requestLine = lines.removeFirst().components(separatedBy: " ")
        guard requestLine.count == 3, requestLine[2].hasPrefix("HTTP/1.") else { return .invalid }
        let method = requestLine[0]
        let path = requestLine[1]

        var headers: [String: String] = [:]
        for line in lines where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { return .invalid }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        let contentLength = Int(headers["content-length"] ?? "0") ?? -1
        guard contentLength >= 0 else { return .invalid }
        guard contentLength <= maxBodyBytes else { return .invalid }

        let bodyStart = headerEnd.upperBound
        let available = buffer.count - bodyStart
        if available < contentLength { return .incomplete }

        let body = buffer.subdata(in: bodyStart..<(bodyStart + contentLength))
        return .request(HTTPRequest(method: method, path: path, headers: headers, body: body))
    }
}

/// Serialized HTTP response.
public enum HTTPResponseBuilder {
    public static func response(status: Int, reason: String, jsonBody: Data?) -> Data {
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        head += "Connection: close\r\n"
        if let jsonBody {
            head += "Content-Type: application/json\r\n"
            head += "Content-Length: \(jsonBody.count)\r\n"
        } else {
            head += "Content-Length: 0\r\n"
        }
        head += "\r\n"
        var data = Data(head.utf8)
        if let jsonBody {
            data.append(jsonBody)
        }
        return data
    }
}

import Foundation
import AIPulseKit

struct CLIError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

/// "--key value" flag parser; rejects unknown dangling values.
struct Flags {
    private var values: [String: String] = [:]

    init(_ arguments: [String]) throws {
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            guard argument.hasPrefix("--") else {
                throw CLIError("unexpected argument '\(argument)'")
            }
            let key = String(argument.dropFirst(2))
            guard index + 1 < arguments.count else {
                throw CLIError("missing value for --\(key)")
            }
            values[key] = arguments[index + 1]
            index += 2
        }
    }

    func value(_ key: String) -> String? { values[key] }

    func require(_ key: String) throws -> String {
        guard let value = values[key], !value.isEmpty else {
            throw CLIError("missing required --\(key)")
        }
        return value
    }
}

struct HTTPClient {
    let port: Int
    let token: String?

    func get(_ path: String) async throws -> (status: Int, body: String) {
        try await request("GET", path, body: nil)
    }

    func post(_ path: String, body: Data) async throws -> (status: Int, body: String) {
        try await request("POST", path, body: body)
    }

    func delete(_ path: String) async throws -> (status: Int, body: String) {
        try await request("DELETE", path, body: nil)
    }

    private func request(_ method: String, _ path: String, body: Data?) async throws -> (status: Int, body: String) {
        guard let url = URL(string: "http://127.0.0.1:\(port)\(path)") else {
            throw CLIError("invalid path")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 5
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return (status, String(data: data, encoding: .utf8) ?? "")
        } catch {
            throw CLIError("could not reach AI Pulse on 127.0.0.1:\(port) — is it running? (\(error.localizedDescription))")
        }
    }
}

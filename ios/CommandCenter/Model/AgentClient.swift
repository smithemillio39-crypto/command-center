import Foundation

struct AgentStatus: Decodable {
    let ok: Bool
    let host: String?
    let platform: String?
    let agentVersion: String?
    let volume: Int?
    let muted: Bool?
}

struct AgentReply: Decodable {
    let ok: Bool
    let result: String?
    let error: String?
}

enum AgentError: LocalizedError {
    case notConfigured
    case badAddress
    case http(Int, String?)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Add your PC's address and pairing token in Settings."
        case .badAddress:
            return "That address doesn't look valid."
        case let .http(code, message):
            if code == 401 { return "The pairing token was rejected." }
            return message ?? "The agent replied with HTTP \(code)."
        case let .transport(message):
            return message
        }
    }
}

/// Minimal HTTP client for the agent running on the PC.
struct AgentClient {
    var host: String
    var port: Int
    var token: String

    var isConfigured: Bool {
        baseURL != nil && !token.isEmpty
    }

    private var baseURL: URL? {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, port > 0, port < 65_536 else { return nil }
        var components = URLComponents()
        components.scheme = "http"
        components.host = trimmed
        components.port = port
        return components.url
    }

    func status() async throws -> AgentStatus {
        let data = try await call(path: "status", method: "GET", body: nil)
        return try JSONDecoder().decode(AgentStatus.self, from: data)
    }

    @discardableResult
    func send(_ action: String, value: String? = nil) async throws -> AgentReply {
        var payload: [String: Any] = ["action": action]
        if let value { payload["value"] = value }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let data = try await call(path: "command", method: "POST", body: body)
        let reply = try JSONDecoder().decode(AgentReply.self, from: data)
        if reply.ok == false {
            throw AgentError.transport(reply.error ?? "The PC rejected that command.")
        }
        return reply
    }

    private func call(path: String, method: String, body: Data?) async throws -> Data {
        guard let baseURL else { throw AgentError.badAddress }
        guard !token.isEmpty else { throw AgentError.notConfigured }

        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = 6
        request.setValue(token, forHTTPHeaderField: "X-Agent-Token")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw AgentError.transport("Unexpected response from the agent.")
            }
            guard (200..<300).contains(http.statusCode) else {
                throw AgentError.http(http.statusCode, String(data: data, encoding: .utf8))
            }
            return data
        } catch let error as AgentError {
            throw error
        } catch {
            throw AgentError.transport(error.localizedDescription)
        }
    }
}

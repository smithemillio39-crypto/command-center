import Foundation

struct FileEntry: Identifiable, Decodable, Hashable {
    let name: String
    let directory: Bool
    let size: Int
    let modified: String?

    var id: String { name }

    var sizeLabel: String {
        guard !directory else { return "folder" }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}

private struct Listing: Decodable {
    let root: String
    let path: String
    let entries: [FileEntry]
}

private struct SimpleReply: Decodable {
    let ok: Bool
    let error: String?
    let name: String?
    let size: Int?
}

enum FileError: LocalizedError {
    case notConfigured
    case http(Int, String?)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Add your PC's address and pairing token in Settings."
        case let .http(code, message):
            if code == 401 { return "The pairing token was rejected." }
            return message ?? "The PC replied with HTTP \(code)."
        }
    }
}

/// Talks to the agent's `/files` endpoints. Only the shared roots are visible.
@MainActor
final class FileBrowser: ObservableObject {
    @Published private(set) var entries: [FileEntry] = []
    @Published private(set) var path: String = ""
    @Published private(set) var rootLabel: String = "share"
    @Published private(set) var isLoading = false
    @Published private(set) var isUploading = false
    @Published var errorMessage: String?

    private let host: String
    private let port: Int
    private let token: String
    private let session: URLSession

    init(host: String, port: Int, token: String) {
        self.host = host
        self.port = port
        self.token = token
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        session = URLSession(configuration: configuration)
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

    private func url(_ endpoint: String, query: [String: String]) -> URL? {
        guard let baseURL, !token.isEmpty,
              var components = URLComponents(
                url: baseURL.appendingPathComponent(endpoint),
                resolvingAgainstBaseURL: false
              ) else { return nil }
        var items = [URLQueryItem(name: "token", value: token)]
        items.append(contentsOf: query.map { URLQueryItem(name: $0.key, value: $0.value) })
        components.queryItems = items
        return components.url
    }

    /// Public URL for a file, used by the share sheet (the token is in the query).
    func link(for entry: FileEntry) -> URL? {
        url("files/raw", query: ["root": rootLabel, "path": joined(entry.name)])
    }

    private func joined(_ name: String) -> String {
        path.isEmpty ? name : "\(path)/\(name)"
    }

    func load(_ target: String? = nil) async {
        isLoading = true
        defer { isLoading = false }
        guard let endpoint = url("files", query: ["root": rootLabel, "path": target ?? path]) else {
            errorMessage = FileError.notConfigured.errorDescription
            return
        }
        do {
            let (data, response) = try await session.data(from: endpoint)
            guard let http = response as? HTTPURLResponse else { return }
            guard http.statusCode == 200 else {
                throw FileError.http(http.statusCode, Self.message(from: data))
            }
            let listing = try JSONDecoder().decode(Listing.self, from: data)
            entries = listing.entries
            path = listing.path
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func open(_ entry: FileEntry) async {
        if entry.directory {
            await load(joined(entry.name))
        }
    }

    func goUp() async {
        guard !path.isEmpty else { return }
        var parts = path.split(separator: "/").map(String.init)
        parts.removeLast()
        await load(parts.joined(separator: "/"))
    }

    func upload(_ data: Data, name: String) async -> Bool {
        guard let endpoint = url("files/upload", query: ["root": rootLabel, "path": path, "name": name]) else {
            errorMessage = FileError.notConfigured.errorDescription
            return false
        }
        isUploading = true
        defer { isUploading = false }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        do {
            let (body, response) = try await session.upload(for: request, from: data)
            guard let http = response as? HTTPURLResponse else { return false }
            guard http.statusCode == 200 else {
                throw FileError.http(http.statusCode, Self.message(from: body))
            }
            await load()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func newFolder(_ name: String) async {
        guard let endpoint = url("files/folder", query: ["root": rootLabel, "path": joined(name)]) else { return }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw FileError.http((response as? HTTPURLResponse)?.statusCode ?? 0, Self.message(from: data))
            }
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Moves the file into the PC's `_trash` folder - nothing is destroyed.
    func trash(_ entry: FileEntry) async {
        guard let endpoint = url("files/trash", query: ["root": rootLabel, "path": joined(entry.name)]) else { return }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw FileError.http((response as? HTTPURLResponse)?.statusCode ?? 0, Self.message(from: data))
            }
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func message(from data: Data) -> String? {
        struct Failure: Decodable { let error: String? }
        return (try? JSONDecoder().decode(Failure.self, from: data))?.error
    }
}

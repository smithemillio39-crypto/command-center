import Foundation
import UIKit

/// Receives the agent's length-prefixed JPEG stream.
///
/// The agent frames every image as a 4-byte big-endian length followed by one
/// JPEG, so no container parser or video player is involved. Frames are decoded
/// off the main thread and published one at a time.
final class PaddleReader: NSObject, URLSessionDataDelegate {
    var onFrame: ((UIImage) -> Void)?
    var onFailure: ((String) -> Void)?

    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var buffer = Data()
    private let limit = 8_000_000

    func start(url: URL) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = .greatestFiniteMagnitude
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        task = session?.dataTask(with: url)
        task?.resume()
    }

    func stop() {
        task?.cancel()
        session?.invalidateAndCancel()
        task = nil
        session = nil
        buffer.removeAll()
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let message = http.statusCode == 401
                ? "The pairing token was rejected."
                : "The PC refused the stream (HTTP \(http.statusCode))."
            onFailure?(message)
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        buffer.append(data)
        drain()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error, (error as NSError).code != NSURLErrorCancelled {
            onFailure?(error.localizedDescription)
        }
    }

    private func drain() {
        while buffer.count >= 4 {
            let length = buffer.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
            guard length > 3, length < limit else {
                buffer.removeAll()
                onFailure?("The stream sent an impossible frame.")
                return
            }
            guard buffer.count >= 4 + length else { return }

            let start = buffer.index(buffer.startIndex, offsetBy: 4)
            let end = buffer.index(start, offsetBy: length)
            let jpeg = buffer.subdata(in: start..<end)
            buffer.removeSubrange(buffer.startIndex..<end)

            guard let image = UIImage(data: jpeg) else { continue }
            onFrame?(image)
        }
    }
}

@MainActor
final class PaddleClient: ObservableObject {
    @Published private(set) var frame: UIImage?
    @Published private(set) var framesPerSecond: Double = 0
    @Published private(set) var isStreaming = false
    @Published private(set) var errorMessage: String?

    private let host: String
    private let port: Int
    private let token: String
    private var reader: PaddleReader?
    private var received = 0
    private var windowStart = Date()

    init(host: String, port: Int, token: String) {
        self.host = host
        self.port = port
        self.token = token
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

    func start() {
        guard reader == nil else { return }
        guard let baseURL, !token.isEmpty else {
            errorMessage = "Add your PC's address and pairing token in Settings."
            return
        }
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent("paddle"),
            resolvingAgainstBaseURL: false
        ) else { return }

        components.queryItems = [
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "width", value: "1280"),
            URLQueryItem(name: "fps", value: "20"),
            URLQueryItem(name: "q", value: "10")
        ]
        guard let url = components.url else { return }

        let reader = PaddleReader()
        reader.onFrame = { [weak self] image in
            Task { @MainActor in self?.accept(image) }
        }
        reader.onFailure = { [weak self] message in
            Task { @MainActor in self?.fail(message) }
        }
        reader.start(url: url)
        self.reader = reader
        isStreaming = true
        errorMessage = nil
        windowStart = Date()
        received = 0
    }

    func stop() {
        reader?.stop()
        reader = nil
        isStreaming = false
        frame = nil
        framesPerSecond = 0
    }

    /// Fire-and-forget input. Gestures already arrive at touch rate.
    func send(_ payload: [String: Any]) {
        guard let baseURL, !token.isEmpty else { return }
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent("input"),
            resolvingAgainstBaseURL: false
        ) else { return }
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        guard let url = components.url else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 4
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        URLSession.shared.dataTask(with: request).resume()
    }

    private func accept(_ image: UIImage) {
        frame = image
        received += 1
        let elapsed = Date().timeIntervalSince(windowStart)
        if elapsed >= 1 {
            framesPerSecond = Double(received) / elapsed
            received = 0
            windowStart = Date()
        }
    }

    private func fail(_ message: String) {
        errorMessage = message
        isStreaming = false
    }
}

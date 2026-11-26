import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    private enum Key {
        static let host = "cc.host"
        static let port = "cc.port"
        static let token = "cc.token"
        static let launchers = "cc.launchers"
    }

    private let defaults = UserDefaults.standard
    private let monitor = ControllerMonitor()
    private var pollTask: Task<Void, Never>?
    private var clearErrorTask: Task<Void, Never>?
    private var suppressVolumeUntil = Date.distantPast

    @Published var host: String { didSet { defaults.set(host, forKey: Key.host) } }
    @Published var port: Int { didSet { defaults.set(port, forKey: Key.port) } }
    @Published var token: String { didSet { defaults.set(token, forKey: Key.token) } }
    @Published var launchers: [Launcher] {
        didSet {
            if let data = try? JSONEncoder().encode(launchers) {
                defaults.set(data, forKey: Key.launchers)
            }
        }
    }

    @Published private(set) var isOnline = false
    @Published private(set) var pcName = "Your PC"
    @Published var volume: Double = 50
    @Published private(set) var muted = false
    @Published private(set) var windows: [PCWindow] = []
    @Published private(set) var windowsLoading = false
    @Published private(set) var controllerName: String?
    @Published var errorMessage: String?
    @Published private(set) var testResult: String?

    /// Lets a view report its own outcome (a bad scanned code, say) through the
    /// same line the settings form already shows.
    func noteTest(_ text: String) {
        testResult = text
    }

    /// Applies a pairing link from an in-app scan or a commandcenter:// open.
    @discardableResult
    func applyPairing(_ code: String) -> Bool {
        guard let link = PairingLink(code) else {
            noteTest("That QR is not a Command Center pairing code.")
            return false
        }
        host = link.host
        port = link.port
        token = link.token
        Task { await testConnection() }
        return true
    }

    init() {
        host = defaults.string(forKey: Key.host) ?? ""
        port = defaults.object(forKey: Key.port) as? Int ?? 8765
        token = defaults.string(forKey: Key.token) ?? ""

        if let data = defaults.data(forKey: Key.launchers),
           let saved = try? JSONDecoder().decode([Launcher].self, from: data),
           !saved.isEmpty {
            launchers = saved
        } else {
            launchers = Self.defaultLaunchers
        }

        monitor.onCommand = { [weak self] command in
            Task { @MainActor in self?.send(command) }
        }
        monitor.onChange = { [weak self] name in
            Task { @MainActor in self?.controllerName = name }
        }
        monitor.start()
    }

    static let defaultLaunchers: [Launcher] = [
        Launcher(title: "Steam", symbol: "gamecontroller.fill", target: "steam-bigpicture"),
        Launcher(title: "LYRA", symbol: "sparkles", target: "lyra"),
        Launcher(title: "Chrome", symbol: "globe", target: "chrome"),
        Launcher(title: "Discord", symbol: "bubble.left.and.bubble.right.fill", target: "discord"),
        Launcher(title: "Spotify", symbol: "music.note", target: "spotify"),
        Launcher(title: "Files", symbol: "folder.fill", target: "explorer"),
        Launcher(title: "Task mgr", symbol: "chart.bar.xaxis", target: "taskmgr"),
        Launcher(title: "Settings", symbol: "gearshape.fill", target: "settings"),
        Launcher(title: "Terminal", symbol: "terminal", target: "terminal")
    ]

    private var client: AgentClient {
        AgentClient(host: host, port: port, token: token)
    }

    var isConfigured: Bool { client.isConfigured }

    // MARK: - Polling

    func start() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh() async {
        guard client.isConfigured else {
            isOnline = false
            return
        }

        do {
            let status = try await client.status()
            isOnline = status.ok
            if let name = status.host, !name.isEmpty { pcName = name }
            if let level = status.volume, Date() > suppressVolumeUntil {
                volume = Double(level)
            }
            if let flag = status.muted { muted = flag }
        } catch {
            isOnline = false
        }
    }

    // MARK: - Commands

    func send(_ command: Command, value: String? = nil) {
        Haptics.tap()
        applyOptimisticState(for: command, value: value)
        Task { await deliver(command, value: value) }
    }

    private func deliver(_ command: Command, value: String?) async {
        guard client.isConfigured else {
            show(error: "Add your PC's address and pairing token in Settings.")
            return
        }

        do {
            try await client.send(command.rawValue, value: value)
            isOnline = true
            errorMessage = nil
        } catch {
            isOnline = false
            show(error: error.localizedDescription)
        }
    }

    private func applyOptimisticState(for command: Command, value: String?) {
        switch command {
        case .volumeUp:
            volume = min(100, volume + 4)
            muted = false
        case .volumeDown:
            volume = max(0, volume - 4)
        case .volumeMute:
            muted.toggle()
        case .volumeSet:
            if let value, let level = Double(value) { volume = level }
            muted = false
            suppressVolumeUntil = Date().addingTimeInterval(2.5)
        default:
            break
        }
    }

    /// Called when the volume dial drag ends, so one command is sent per gesture.
    func commitVolume() {
        suppressVolumeUntil = Date().addingTimeInterval(2.5)
        send(.volumeSet, value: String(Int(volume.rounded())))
    }

    func launch(_ launcher: Launcher) {
        send(.launch, value: launcher.target)
    }

    func launch(target: String) {
        send(.launch, value: target)
    }

    /// Reloads the PC's open windows. A failure keeps the last list, since the
    /// status dot already reports whether the agent is reachable.
    func loadWindows() async {
        guard client.isConfigured else { return }
        windowsLoading = true
        defer { windowsLoading = false }
        do {
            windows = try await client.windows()
            isOnline = true
        } catch {
            // Leave the previous list in place.
        }
    }

    /// Brings a window on the PC to the front, restoring it if it was minimised.
    func activate(_ window: PCWindow) {
        Haptics.tap()
        Task {
            do {
                try await client.activate(hwnd: window.hwnd)
                Haptics.success()
                errorMessage = nil
                try? await Task.sleep(nanoseconds: 400_000_000)
                await loadWindows()
            } catch {
                show(error: error.localizedDescription)
            }
        }
    }

    // MARK: - Settings

    func testConnection() async {
        testResult = "Checking..."
        do {
            let status = try await client.status()
            isOnline = status.ok
            if let name = status.host { pcName = name }
            testResult = "Connected to \(status.host ?? "the PC") - agent \(status.agentVersion ?? "?")"
            Haptics.success()
        } catch {
            isOnline = false
            testResult = error.localizedDescription
            Haptics.failure()
        }
    }

    func addLauncher() {
        launchers.append(Launcher(title: "New app", symbol: "app.fill", target: "notepad.exe"))
    }

    func removeLaunchers(at offsets: IndexSet) {
        launchers.remove(atOffsets: offsets)
    }

    func resetLaunchers() {
        launchers = Self.defaultLaunchers
    }

    private func show(error message: String) {
        errorMessage = message
        clearErrorTask?.cancel()
        clearErrorTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            self?.errorMessage = nil
        }
    }
}

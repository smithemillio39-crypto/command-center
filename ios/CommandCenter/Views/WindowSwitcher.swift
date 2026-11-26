import SwiftUI

/// The PC's open windows as a scrollable list. One tap raises the window on the
/// PC, so you never have to drag a pointer across a mirrored screen to get to it.
struct WindowSwitcherCard: View {
    @ObservedObject var model: AppModel
    @State private var showAll = false

    private var visible: [PCWindow] {
        guard !showAll, model.windows.count > collapsedCount else { return model.windows }
        return Array(model.windows.prefix(collapsedCount))
    }

    private let collapsedCount = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("ON THE PC")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.55))
                Spacer()
                if model.windowsLoading {
                    ProgressView().scaleEffect(0.6)
                }
                Text("\(model.windows.count)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
                Button {
                    Task { await model.loadWindows() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(.white.opacity(0.10)))
                }
                .buttonStyle(.plain)
            }

            if model.windows.isEmpty {
                Text(model.isOnline ? "No open windows on the PC." : "Not connected to the PC.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 6) {
                    ForEach(visible) { window in
                        Button {
                            model.activate(window)
                        } label: {
                            row(for: window)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if model.windows.count > collapsedCount {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showAll.toggle() }
                    } label: {
                        Text(showAll ? "Show fewer" : "Show all \(model.windows.count)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.ccViolet)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: .ccViolet, strength: 0.10)
        .task { await model.loadWindows() }
    }

    private func row(for window: PCWindow) -> some View {
        HStack(spacing: 11) {
            Image(systemName: symbol(for: window.process))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.ccViolet)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(window.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.94))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitle(for: window))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Image(systemName: "arrow.up.forward.app")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.28))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(0.05))
        )
        .contentShape(Rectangle())
    }

    private func subtitle(for window: PCWindow) -> String {
        let name = window.process.isEmpty ? "app" : window.process
        return window.minimized == true ? "\(name) · minimized" : name
    }

    private func symbol(for process: String) -> String {
        switch process.lowercased() {
        case "chrome", "msedge", "firefox", "brave", "opera", "vivaldi", "arc":
            return "globe"
        case "explorer":
            return "folder.fill"
        case "steam", "steamwebhelper":
            return "gamecontroller.fill"
        case "discord":
            return "bubble.left.and.bubble.right.fill"
        case "spotify":
            return "music.note"
        case "code", "cursor", "devenv":
            return "chevron.left.forwardslash.chevron.right"
        case "windowsterminal", "wt", "powershell", "cmd", "conhost":
            return "terminal"
        case "notepad", "notepad++":
            return "doc.text"
        case "photos", "mspaint", "paint":
            return "photo"
        case "pythonw", "python", "lyra":
            return "sparkles"
        case "taskmgr":
            return "chart.bar.xaxis"
        case "sideloadly":
            return "arrow.down.app"
        case "vlc", "mpc-hc64":
            return "play.rectangle.fill"
        case "winword", "excel", "powerpnt":
            return "doc.richtext"
        default:
            return "macwindow"
        }
    }
}

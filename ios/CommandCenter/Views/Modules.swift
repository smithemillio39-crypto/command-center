import SwiftUI

// MARK: - Header

struct HeaderBar: View {
    @ObservedObject var model: AppModel
    var onSettings: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Command Center")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                    .textCase(.uppercase)
                Text(model.pcName)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            StatusPill(isOnline: model.isOnline, hasController: model.controllerName != nil)

            Button(action: onSettings) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .glassSurface(Circle(), strength: 0.12, gloss: 0.20)
            }
            .buttonStyle(.plain)
        }
    }
}

struct StatusPill: View {
    let isOnline: Bool
    let hasController: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isOnline ? Color.ccMint : Color.white.opacity(0.30))
                .frame(width: 7, height: 7)
            Text(isOnline ? "Online" : "Offline")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            if hasController {
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.ccAmber)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .glassSurface(Capsule(), strength: 0.10, gloss: 0.18)
    }
}

struct ErrorBanner: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color.ccAmber)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(
            RoundedRectangle(cornerRadius: 18, style: .continuous),
            tint: .ccAmber,
            strength: 0.10,
            gloss: 0.14
        )
    }
}

// MARK: - Media

struct MediaDeck: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Media")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .textCase(.uppercase)

            Spacer(minLength: 8)

            HStack(spacing: 10) {
                RoundButton(symbol: "backward.fill", size: 44) { model.send(.prevTrack) }
                RoundButton(symbol: "playpause.fill", size: 60, prominent: true) { model.send(.playPause) }
                RoundButton(symbol: "forward.fill", size: 44) { model.send(.nextTrack) }
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 8)

            Text("Plays whatever is active on the PC")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.35))
                .lineLimit(1)
        }
        .padding(15)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .glassCard()
    }
}

struct RoundButton: View {
    let symbol: String
    var size: CGFloat = 44
    var prominent: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.34, weight: .semibold))
                .foregroundStyle(prominent ? Color.black.opacity(0.85) : Color.white)
                .frame(width: size, height: size)
                .glassSurface(
                    Circle(),
                    strength: prominent ? 0.90 : 0.14,
                    gloss: prominent ? 0.40 : 0.24
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Volume

struct VolumeDial: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(.white.opacity(0.10))

                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.ccMint, Color.ccBlue],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(height: max(12, geo.size.height * CGFloat(model.volume / 100)))
                        .opacity(model.muted ? 0.35 : 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let height = max(geo.size.height, 1)
                            let fraction = 1 - (value.location.y / height)
                            model.volume = min(100, max(0, Double(fraction) * 100))
                        }
                        .onEnded { _ in
                            model.commitVolume()
                        }
                )
            }

            HStack(spacing: 4) {
                Image(systemName: model.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text("\(Int(model.volume.rounded()))")
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(.white.opacity(0.75))
        }
        .padding(10)
        .frame(maxHeight: .infinity)
        .glassCard()
    }
}

// MARK: - Power grid

struct PowerGrid: View {
    @ObservedObject var model: AppModel

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            CircleAction(symbol: "lock.fill", label: "Lock", tint: .ccBlue) {
                model.send(.lock)
            }
            CircleAction(symbol: "moon.zzz.fill", label: "Sleep", tint: .ccViolet) {
                model.send(.sleep)
            }
            CircleAction(symbol: "display", label: "Screen off", tint: .ccAmber) {
                model.send(.displayOff)
            }
            CircleAction(
                symbol: model.muted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                label: model.muted ? "Unmute" : "Mute",
                tint: .ccPink,
                isOn: model.muted
            ) {
                model.send(.volumeMute)
            }
        }
        .padding(16)
        .glassCard()
    }
}

struct CircleAction: View {
    let symbol: String
    let label: String
    let tint: Color
    var isOn: Bool = false
    var action: () -> Void

    var body: some View {
        VStack(spacing: 7) {
            Button(action: action) {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(isOn ? Color.black.opacity(0.85) : Color.white)
                    .frame(width: 54, height: 54)
                    .glassSurface(
                        Circle(),
                        tint: isOn ? tint : .white,
                        strength: isOn ? 0.55 : 0.14,
                        gloss: 0.24
                    )
            }
            .buttonStyle(.plain)

            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Launchers

struct LauncherGrid: View {
    @ObservedObject var model: AppModel

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Launch")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .textCase(.uppercase)

            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(model.launchers) { launcher in
                    LauncherButton(launcher: launcher) {
                        model.launch(launcher)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

struct LauncherButton: View {
    let launcher: Launcher
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: launcher.symbol)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .glassSurface(Circle(), strength: 0.12, gloss: 0.22)
                Text(launcher.title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Game streaming

struct PaddleCard: View {
    @ObservedObject var model: AppModel
    @State private var showStream = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.ccAmber)
                Text("Paddle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }

            Text("Your own stream from this PC - no Sunshine, no Moonlight. Tap to click, drag to drag, hold for a right click. Best on the same Wi-Fi.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 9) {
                Button {
                    model.launch(target: "steam-bigpicture")
                } label: {
                    Label("Big Picture", systemImage: "play.rectangle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.vertical, 9)
                        .padding(.horizontal, 14)
                        .glassSurface(Capsule(), strength: 0.14, gloss: 0.20)
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Button {
                    showStream = true
                } label: {
                    Label("Open Paddle", systemImage: "play.tv.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.vertical, 9)
                        .padding(.horizontal, 14)
                        .glassSurface(Capsule(), tint: .ccBlue, strength: 0.28, gloss: 0.22)
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: .ccAmber, strength: 0.05)
        .fullScreenCover(isPresented: $showStream) {
            PaddleView(model: model)
        }
    }
}

// MARK: - Power row

struct PowerRow: View {
    var onPower: (Command) -> Void

    var body: some View {
        HStack(spacing: 10) {
            PowerButton(symbol: "arrow.clockwise", label: "Restart") { onPower(.restart) }
            PowerButton(symbol: "power", label: "Shut down", destructive: true) { onPower(.shutdown) }
            PowerButton(symbol: "xmark.circle", label: "Cancel") { onPower(.cancelShutdown) }
        }
    }
}

struct PowerButton: View {
    let symbol: String
    let label: String
    var destructive: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(destructive ? Color.ccPink : Color.white.opacity(0.85))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .glassSurface(
                RoundedRectangle(cornerRadius: 18, style: .continuous),
                tint: destructive ? .ccPink : .white,
                strength: 0.10,
                gloss: 0.16
            )
        }
        .buttonStyle(.plain)
    }
}

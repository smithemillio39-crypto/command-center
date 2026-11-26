import SwiftUI

/// Full-screen view of the PC, with touch driving the real pointer.
///
/// One finger: tap is a click, drag is a drag (press, move, release). A long
/// press is a right click. Everything is sent to the agent's `/input` endpoint.
struct PaddleView: View {
    @ObservedObject var model: AppModel
    @StateObject private var client: PaddleClient
    @Environment(\.dismiss) private var dismiss

    @State private var pointerDown = false
    @State private var travelled: CGFloat = 0

    init(model: AppModel) {
        self.model = model
        _client = StateObject(
            wrappedValue: PaddleClient(host: model.host, port: model.port, token: model.token)
        )
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { proxy in
                if let frame = client.frame {
                    Image(uiImage: frame)
                        .resizable()
                        .scaledToFit()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .contentShape(Rectangle())
                        .gesture(pointer(in: proxy.size, image: frame.size))
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: 0.55)
                                .onEnded { _ in
                                    Haptics.tap()
                                    client.send(["t": "click", "b": 2])
                                }
                        )
                } else {
                    VStack(spacing: 14) {
                        ProgressView().tint(.white)
                        Text(client.errorMessage ?? "Connecting to \(model.pcName)…")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }

            chrome
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear { client.start() }
        .onDisappear { client.stop() }
    }

    private var chrome: some View {
        VStack {
            HStack(spacing: 10) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(.black.opacity(0.55)))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Text(client.isStreaming ? "paddle · \(Int(client.framesPerSecond.rounded())) fps" : "paddle · offline")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.black.opacity(0.55)))

                Spacer()

                ForEach(keyRows, id: \.label) { key in
                    Button {
                        Haptics.tap()
                        client.send(["t": "key", "vk": key.code])
                    } label: {
                        Text(key.label)
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(.black.opacity(0.55)))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)

            Spacer()

            Text("tap = click · drag = drag · hold = right click")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(.black.opacity(0.5)))
                .padding(.bottom, 14)
        }
    }

    private struct KeyTap {
        let label: String
        let code: Int
    }

    private var keyRows: [KeyTap] {
        [
            KeyTap(label: "esc", code: 27),
            KeyTap(label: "tab", code: 9),
            KeyTap(label: "enter", code: 13),
            KeyTap(label: "⌫", code: 8),
            KeyTap(label: "⊞", code: 91)
        ]
    }

    private func pointer(in size: CGSize, image: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let point = normalise(value.location, in: size, image: image)
                if !pointerDown {
                    pointerDown = true
                    travelled = 0
                    Haptics.tap()
                    client.send(["t": "move", "x": point.x, "y": point.y])
                    client.send(["t": "down", "b": 1])
                    return
                }
                travelled = max(
                    travelled,
                    abs(value.translation.width) + abs(value.translation.height)
                )
                client.send(["t": "move", "x": point.x, "y": point.y])
            }
            .onEnded { value in
                let point = normalise(value.location, in: size, image: image)
                client.send(["t": "move", "x": point.x, "y": point.y])
                client.send(["t": "up", "b": 1])
                pointerDown = false
                travelled = 0
            }
    }

    /// Maps a touch inside the letterboxed image to 0…1 over the PC desktop.
    private func normalise(_ location: CGPoint, in size: CGSize, image: CGSize) -> CGPoint {
        guard image.width > 0, image.height > 0 else { return .zero }
        let scale = min(size.width / image.width, size.height / image.height)
        let drawn = CGSize(width: image.width * scale, height: image.height * scale)
        let origin = CGPoint(
            x: (size.width - drawn.width) / 2,
            y: (size.height - drawn.height) / 2
        )
        let x = (location.x - origin.x) / drawn.width
        let y = (location.y - origin.y) / drawn.height
        return CGPoint(x: min(max(x, 0), 1), y: min(max(y, 0), 1))
    }
}

import SwiftUI

@MainActor
struct ContentView: View {
    @StateObject private var model = AppModel()
    @State private var showSettings = false
    @State private var pendingPower: Command?

    var body: some View {
        ZStack {
            background

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    HeaderBar(model: model) { showSettings = true }

                    if let message = model.errorMessage {
                        ErrorBanner(text: message)
                    }

                    WindowSwitcherCard(model: model)

                    HStack(alignment: .top, spacing: 14) {
                        MediaDeck(model: model)
                        VolumeDial(model: model)
                            .frame(width: 96)
                    }
                    .frame(height: 188)

                    PowerGrid(model: model)
                    LauncherGrid(model: model)
                    PaddleCard(model: model)
                    FilesCard(model: model)
                    PowerRow { command in pendingPower = command }
                }
                .padding(.horizontal, 18)
                .padding(.top, 6)
                .padding(.bottom, 40)
            }
            .refreshable { await model.refresh() }
        }
        .preferredColorScheme(.dark)
        .task { model.start() }
        .onDisappear { model.stop() }
        .onOpenURL { url in
            // Scanning the pairing QR with the Camera app lands here.
            model.applyPairing(url.absoluteString)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(model: model)
        }
        .confirmationDialog(
            powerTitle,
            isPresented: Binding(
                get: { pendingPower != nil },
                set: { if !$0 { pendingPower = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let command = pendingPower {
                Button(command == .restart ? "Restart in 60s" : "Shut down in 60s", role: .destructive) {
                    model.send(command)
                    pendingPower = nil
                }
                Button("Cancel", role: .cancel) { pendingPower = nil }
            }
        } message: {
            Text("You have 60 seconds to cancel from this app before the PC goes down.")
        }
    }

    private var powerTitle: String {
        pendingPower == .restart ? "Restart the PC?" : "Shut down the PC?"
    }

    private var background: some View {
        LyraBackdrop()
    }
}

#Preview {
    ContentView()
}

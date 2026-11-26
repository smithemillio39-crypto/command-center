import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var scanning = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("PC address (192.168.1.20)", text: $model.host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.numbersAndPunctuation)

                    TextField("Port", value: $model.port, format: .number)
                        .keyboardType(.numberPad)

                    TextField("Pairing token", text: $model.token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Button {
                        scanning = true
                    } label: {
                        Label("Scan pairing QR", systemImage: "qrcode.viewfinder")
                    }

                    Button("Test connection") {
                        Task { await model.testConnection() }
                    }

                    if let result = model.testResult {
                        Text(result)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Computer")
                } footer: {
                    Text("Run pc-agent/start-agent.bat on the PC. It prints the address and the pairing token.")
                }

                Section {
                    ForEach($model.launchers) { $launcher in
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("Name", text: $launcher.title)
                            TextField("Target", text: $launcher.target)
                                .font(.footnote)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            TextField("SF Symbol name", text: $launcher.symbol)
                                .font(.footnote)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                    }
                    .onDelete { model.removeLaunchers(at: $0) }

                    Button("Add launcher") { model.addLauncher() }
                    Button("Reset to defaults") { model.resetLaunchers() }
                } header: {
                    Text("Launchers")
                } footer: {
                    Text("Targets can be aliases (steam-bigpicture, chrome, discord, spotify, explorer, taskmgr, settings, terminal), a URI such as steam://open/main, or a full path.")
                }

                Section {
                    LabeledContent("Connected", value: model.controllerName ?? "None")
                    Text("A play/pause - B mute - X previous - Y next - D-pad up/down volume - bumpers skip")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Controller")
                }

                Section("About") {
                    LabeledContent("App", value: "Command Center 1.0")
                    Text("Native SwiftUI, compiled on a cloud macOS runner and installed with Sideloadly. No web wrapper.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .sheet(isPresented: $scanning) {
                NavigationStack {
                    PairingScanner { code in
                        scanning = false
                        apply(code)
                    }
                    .ignoresSafeArea()
                    .navigationTitle("Scan pairing QR")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { scanning = false }
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    /// Fill the computer fields from a scanned QR, then test straight away.
    private func apply(_ code: String) {
        guard let link = PairingLink(code) else {
            model.noteTest("That QR is not a Command Center pairing code.")
            return
        }
        model.host = link.host
        model.port = link.port
        model.token = link.token
        Task { await model.testConnection() }
    }
}

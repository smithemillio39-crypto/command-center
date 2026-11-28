import SwiftUI

struct CartridgeDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let info: CartridgeInfo
    let onDelete: () -> Result<Void, Error>

    @State private var verification: AX1VDVerify?
    @State private var confirmDelete = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                AetherStyle.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        titleBlock
                        metrics
                        if let problem = info.problem {
                            warning(problem)
                        }
                        if let verification {
                            verificationBlock(verification)
                        }
                        actions
                        Text("This sheet exposes the AX1VD enclosure only. It does not mount or browse an internal file catalog.")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(AetherStyle.muted)
                    }
                    .padding(18)
                }
            }
            .navigationTitle(info.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Delete cartridge?", isPresented: $confirmDelete,
                                titleVisibility: .visible) {
                Button("Delete \(info.url.lastPathComponent)", role: .destructive) {
                    switch onDelete() {
                    case .success:
                        dismiss()
                    case .failure(let error):
                        errorMessage = error.localizedDescription
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Permanently remove this copy from the Studio library? The original file outside the app is not touched. This cannot be undone.")
            }
            .alert("AETHER Studio", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var titleBlock: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: info.header == nil ? "exclamationmark.triangle.fill" : "sdcard.fill")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(info.header == nil ? AetherStyle.amber : AetherStyle.accent)
            VStack(alignment: .leading, spacing: 5) {
                Text(info.displayName)
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                    .foregroundStyle(AetherStyle.text)
                    .lineLimit(2)
                Text(info.header == nil ? "UNREADABLE ENCLOSURE" : "AX1VD-01 · READY")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(info.header == nil ? AetherStyle.amber : AetherStyle.mint)
            }
        }
    }

    private var metrics: some View {
        VStack(spacing: 1) {
            metric("LOGICAL CAPACITY", capacityText(info.header?.capacity))
            metric("PHYSICAL ALLOCATED", byteText(info.allocatedBytes ?? info.fileBytes))
            metric("SECTOR SIZE", info.header.map { "\($0.sectorSize) bytes" } ?? "-")
            metric("GENERATION", info.header.map { "\($0.generation)" } ?? "-")
            metric("MODIFIED", dateText(info.modified))
        }
        .background(AetherStyle.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AetherStyle.edge.opacity(0.8)))
    }

    private func metric(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(AetherStyle.muted)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(AetherStyle.text)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func verificationBlock(_ report: AX1VDVerify) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("STRUCTURE VERIFIED", systemImage: "checkmark.seal.fill")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(AetherStyle.mint)
            Text(report.summary)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(AetherStyle.text)
            Text("Checked \(dateText(report.verifiedAt))")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(AetherStyle.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AetherStyle.glass, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AetherStyle.mint.opacity(0.35)))
    }

    private func warning(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AetherStyle.amber)
            Text(text)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(AetherStyle.text)
        }
        .padding(12)
        .background(AetherStyle.glass, in: RoundedRectangle(cornerRadius: 14))
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                do {
                    verification = try AX1VD.verify(at: info.url)
                } catch {
                    errorMessage = "Verify failed: \(error.localizedDescription)"
                }
            } label: {
                Label("Verify structure", systemImage: "checkmark.shield")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(AetherStyle.accent.opacity(0.18), in: Capsule())
                    .overlay(Capsule().stroke(AetherStyle.accent.opacity(0.7)))
            }
            .buttonStyle(.plain)
            .foregroundStyle(AetherStyle.text)

            ShareLink(item: info.url) {
                Label("Export / Share", systemImage: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(AetherStyle.glass, in: Capsule())
                    .overlay(Capsule().stroke(AetherStyle.edge))
            }
            .buttonStyle(.plain)
            .foregroundStyle(AetherStyle.text)

            Button(role: .destructive) {
                confirmDelete = true
            } label: {
                Label("Delete cartridge", systemImage: "trash")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color.red.opacity(0.14), in: Capsule())
                    .overlay(Capsule().stroke(Color.red.opacity(0.45)))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.red)
        }
    }
}

import SwiftUI

struct CartridgeDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let info: CartridgeInfo
    let onDelete: () -> Result<Void, Error>

    @State private var verification: AX1VDVerify?
    @State private var integrity: VolumeIntegrity?
    @State private var confirmDelete = false
    @State private var errorMessage: String?
    @State private var working: String?

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
                        if let integrity {
                            volumeBlock(integrity)
                        }
                        if let verification {
                            verificationBlock(verification)
                        }
                        actions
                        Text("The cartridge is an AX1VD enclosure around a FAT32 volume. A computer can open it as a drive; this build checks the volume but does not browse files yet.")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(AetherStyle.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(18)
                }
                if let working {
                    AetherWorkingOverlay(title: working)
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
                Button("Delete " + info.url.lastPathComponent, role: .destructive) {
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
                Text(info.header == nil ? "UNREADABLE ENCLOSURE" : "AX1VD-01 · FAT32")
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
            metric("SECTOR SIZE", info.header.map { String($0.sectorSize) + " bytes" } ?? "-")
            metric("VOLUME", integrity.map { "FAT32 · " + String($0.clusterBytes / 1024) + " KiB clusters" } ?? "not checked")
            metric("GENERATION", info.header.map { String($0.generation) } ?? "-")
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

    private func volumeBlock(_ report: VolumeIntegrity) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(report.isHealthy ? "VOLUME VALID" : "VOLUME HAS PROBLEMS",
                  systemImage: report.isHealthy ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(report.isHealthy ? AetherStyle.mint : AetherStyle.amber)
            HStack(spacing: 18) {
                volumeMetric("FREE", byteText(Int64(clamping: report.freeBytes)))
                volumeMetric("USED", byteText(Int64(clamping: report.usedBytes)))
                volumeMetric("CLUSTER", String(report.clusterBytes / 1024) + " KiB")
            }
            Text(report.summary)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(AetherStyle.text)
                .fixedSize(horizontal: false, vertical: true)
            Text("Volume " + report.label + " · checked " + dateText(report.checkedAt))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(AetherStyle.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AetherStyle.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AetherStyle.mint.opacity(0.35)))
    }

    private func volumeMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(AetherStyle.muted)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(AetherStyle.text)
        }
    }

    private func verificationBlock(_ report: AX1VDVerify) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("STRUCTURE VERIFIED", systemImage: "checkmark.seal.fill")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(AetherStyle.mint)
            Text(report.summary)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(AetherStyle.text)
                .fixedSize(horizontal: false, vertical: true)
            Text("Checked " + dateText(report.verifiedAt))
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
                checkVolume()
            } label: {
                Label("Check volume", systemImage: "externaldrive.badge.checkmark")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(AetherStyle.accent.opacity(0.18), in: Capsule())
                    .overlay(Capsule().stroke(AetherStyle.accent.opacity(0.7)))
            }
            .buttonStyle(.plain)
            .foregroundStyle(AetherStyle.text)
            .disabled(working != nil)

            Button {
                verifyStructure()
            } label: {
                Label("Verify structure", systemImage: "checkmark.shield")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(AetherStyle.glass, in: Capsule())
                    .overlay(Capsule().stroke(AetherStyle.edge))
            }
            .buttonStyle(.plain)
            .foregroundStyle(AetherStyle.text)
            .disabled(working != nil)

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
            .disabled(working != nil)
        }
    }

    private func checkVolume() {
        working = "CHECKING VOLUME"
        let url = info.url
        Task.detached(priority: .userInitiated) {
            do {
                let report = try AX1VDVolume.integrityCheck(at: url)
                let structure = try AX1VD.verify(at: url)
                await MainActor.run {
                    integrity = report
                    verification = structure
                    working = nil
                }
            } catch {
                let text = error.localizedDescription
                await MainActor.run {
                    working = nil
                    errorMessage = text
                }
            }
        }
    }

    private func verifyStructure() {
        working = "VERIFYING STRUCTURE"
        let url = info.url
        Task.detached(priority: .userInitiated) {
            do {
                let report = try AX1VD.verify(at: url)
                await MainActor.run {
                    verification = report
                    working = nil
                }
            } catch {
                let text = error.localizedDescription
                await MainActor.run {
                    working = nil
                    errorMessage = text
                }
            }
        }
    }
}

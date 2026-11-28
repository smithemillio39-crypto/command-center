import SwiftUI
import UniformTypeIdentifiers

enum AetherStyle {
    static let background = Color(red: 0.07, green: 0.06, blue: 0.09)
    static let panel = Color(red: 0.11, green: 0.10, blue: 0.14)
    static let glass = Color(red: 0.14, green: 0.12, blue: 0.20)
    static let edge = Color(red: 0.29, green: 0.24, blue: 0.42)
    static let accent = Color(red: 0.73, green: 0.58, blue: 0.99)
    static let mint = Color(red: 0.36, green: 0.86, blue: 0.72)
    static let amber = Color(red: 1.00, green: 0.81, blue: 0.52)
    static let text = Color(red: 0.93, green: 0.91, blue: 0.96)
    static let muted = Color(red: 0.62, green: 0.58, blue: 0.70)
}

func byteText(_ value: Int64?) -> String {
    guard let value else { return "-" }
    return ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
}

func capacityText(_ value: UInt64?) -> String {
    guard let value else { return "-" }
    return ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file)
}

func dateText(_ value: Date?) -> String {
    guard let value else { return "unknown" }
    return value.formatted(date: .abbreviated, time: .shortened)
}

struct StudioView: View {
    @StateObject private var library = CartridgeLibrary()
    @State private var showCreate = false
    @State private var showImporter = false
    @State private var selected: CartridgeInfo?
    @State private var deleteCandidate: CartridgeInfo?
    @State private var message: String?

    private var cartridgeType: UTType {
        UTType(filenameExtension: "vdrive") ?? .data
    }

    private var deleteDialog: Binding<Bool> {
        Binding(get: { deleteCandidate != nil },
                set: { if !$0 { deleteCandidate = nil } })
    }

    private var alertBinding: Binding<Bool> {
        Binding(get: { message != nil },
                set: { if !$0 { message = nil } })
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AetherStyle.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        summary
                        actions
                        cartridgeList
                        footnote
                    }
                    .padding(18)
                }
            }
            .navigationTitle("Studio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showImporter = true } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .accessibilityLabel("Import cartridge")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showCreate = true } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New cartridge")
                }
            }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [cartridgeType],
                          allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    guard let source = urls.first else { return }
                    do {
                        selected = try library.importFile(source)
                    } catch {
                        message = "Import failed: \(error.localizedDescription)"
                    }
                case .failure(let error):
                    message = "Import failed: \(error.localizedDescription)"
                }
            }
            .sheet(isPresented: $showCreate) {
                CreateCartridgeView { name, sizeMB in
                    do {
                        selected = try library.create(name: name, sizeMB: sizeMB)
                        return nil
                    } catch {
                        return error.localizedDescription
                    }
                }
            }
            .sheet(item: $selected) { info in
                CartridgeDetailView(info: info) {
                    do {
                        try library.delete(info)
                        selected = nil
                        return .success(())
                    } catch {
                        return .failure(error)
                    }
                }
            }
            .confirmationDialog("Delete cartridge?",
                                isPresented: deleteDialog,
                                titleVisibility: .visible,
                                presenting: deleteCandidate) { info in
                Button("Delete \(info.displayName)", role: .destructive) {
                    delete(info)
                }
                Button("Cancel", role: .cancel) {}
            } message: { info in
                Text("Permanently remove \(info.url.lastPathComponent) from this iPhone's Studio library? The original file outside the app is not touched. This cannot be undone.")
            }
            .alert("AETHER Studio", isPresented: alertBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(message ?? "")
            }
            .onAppear { library.refresh() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text("AETHER")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .tracking(5)
                    .foregroundStyle(AetherStyle.accent)
                Spacer()
                Image(systemName: "externaldrive.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(AetherStyle.mint)
            }
            Text("PORTABLE DRIVE STUDIO")
                .font(.system(size: 25, weight: .bold, design: .rounded))
                .foregroundStyle(AetherStyle.text)
            Text("Local AX1VD cartridges on your iPhone")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(AetherStyle.muted)
        }
    }

    private var summary: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("CARTRIDGES")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(AetherStyle.muted)
                Text("\(library.cartridges.count)")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(AetherStyle.text)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text("STORAGE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(AetherStyle.muted)
                Text("On-device")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(AetherStyle.mint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(AetherStyle.panel, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(AetherStyle.edge.opacity(0.8)))
    }

    private var actions: some View {
        HStack(spacing: 10) {
            actionButton("New cartridge", systemImage: "plus") { showCreate = true }
            actionButton("Import .vdrive", systemImage: "square.and.arrow.down") {
                showImporter = true
            }
        }
    }

    private func actionButton(_ title: String, systemImage: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(AetherStyle.glass, in: Capsule())
                .overlay(Capsule().stroke(AetherStyle.edge))
        }
        .buttonStyle(.plain)
        .foregroundStyle(AetherStyle.text)
    }

    private var cartridgeList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LIBRARY")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(AetherStyle.muted)
            if library.cartridges.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No cartridges yet")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(AetherStyle.text)
                    Text("Create a sparse cartridge here, or import a .vdrive copy from Files.")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(AetherStyle.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(AetherStyle.panel, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(AetherStyle.edge.opacity(0.8)))
            } else {
                ForEach(library.cartridges) { info in
                    cartridgeRow(info)
                }
            }
        }
    }

    private func cartridgeRow(_ info: CartridgeInfo) -> some View {
        Button { selected = info } label: {
            HStack(spacing: 12) {
                Image(systemName: info.header == nil ? "exclamationmark.triangle.fill" : "sdcard.fill")
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(info.header == nil ? AetherStyle.amber : AetherStyle.accent)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 4) {
                    Text(info.displayName)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(AetherStyle.text)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        Text(capacityText(info.header?.capacity) + " logical")
                        Text("·")
                        Text(byteText(info.allocatedBytes ?? info.fileBytes) + " physical")
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(AetherStyle.muted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AetherStyle.muted)
            }
            .padding(14)
            .background(AetherStyle.panel, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AetherStyle.edge.opacity(0.7)))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                deleteCandidate = info
            } label: {
                Label("Delete cartridge", systemImage: "trash")
            }
        }
    }

    private var footnote: some View {
        Text("Import copies a cartridge into this app. Deleting removes that copy and its metadata; an original selected in Files is never deleted. This build verifies raw AX1VD enclosures and does not expose an AXFS file browser.")
            .font(.system(size: 11, design: .rounded))
            .foregroundStyle(AetherStyle.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func delete(_ info: CartridgeInfo) {
        do {
            try library.delete(info)
            deleteCandidate = nil
        } catch {
            message = "Delete failed: \(error.localizedDescription)"
        }
    }
}

struct CreateCartridgeView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = "FIELD-CARTRIDGE"
    @State private var sizeMB = 64
    @State private var error: String?

    let onCreate: (String, Int) -> String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Cartridge name") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }
                Section("Logical capacity") {
                    Picker("Capacity", selection: $sizeMB) {
                        Text("64 MiB").tag(64)
                        Text("256 MiB").tag(256)
                        Text("1 GiB").tag(1024)
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Text("Only the logical size is declared. The file stays sparse until data is written.")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(AetherStyle.muted)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AetherStyle.background)
            .navigationTitle("New cartridge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        if let failure = onCreate(name, sizeMB) {
                            error = failure
                        } else {
                            dismiss()
                        }
                    }
                }
            }
            .alert("Create failed", isPresented: Binding(
                get: { error != nil },
                set: { if !$0 { error = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
        }
    }
}

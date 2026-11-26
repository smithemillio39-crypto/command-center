import PhotosUI
import SwiftUI

/// Card on the main screen that opens the shared-folder browser.
struct FilesCard: View {
    @ObservedObject var model: AppModel
    @State private var showFiles = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.ccMint)
                Text("Move things off this phone")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }

            Text("Send photos and videos straight to your PC over Wi-Fi, or pull files back. Nothing is deleted - removed files go to the PC's _trash folder.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)

            Button {
                showFiles = true
            } label: {
                Label("Open files", systemImage: "folder.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.vertical, 9)
                    .padding(.horizontal, 14)
                    .background(Capsule().fill(Color.ccMint.opacity(0.24)))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: .ccMint, strength: 0.05)
        .fullScreenCover(isPresented: $showFiles) {
            FilesView(model: model)
        }
    }
}

/// Browses the agent's shared roots; uploads from the photo library.
struct FilesView: View {
    @ObservedObject var model: AppModel
    @StateObject private var browser: FileBrowser
    @Environment(\.dismiss) private var dismiss

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var newFolder = ""
    @State private var showNewFolder = false

    init(model: AppModel) {
        self.model = model
        _browser = StateObject(
            wrappedValue: FileBrowser(host: model.host, port: model.port, token: model.token)
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LyraBackdrop()

                List {
                    if let message = browser.errorMessage {
                        Text(message)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.ccPink)
                            .listRowBackground(Color.clear)
                    }

                    if browser.entries.isEmpty && !browser.isLoading {
                        Text(browser.path.isEmpty ? "This shared folder is empty." : "Nothing here.")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.45))
                            .listRowBackground(Color.clear)
                    }

                    ForEach(browser.entries) { entry in
                        row(entry)
                    }
                }
                .scrollContentBackground(.hidden)
                .listStyle(.plain)
                .refreshable { await browser.load() }

                if browser.isLoading || browser.isUploading {
                    ProgressView()
                        .tint(.white)
                        .padding(18)
                        .background(Circle().fill(.black.opacity(0.6)))
                }
            }
            .navigationTitle(browser.path.isEmpty ? "Shared files" : "/" + browser.path)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if !browser.path.isEmpty {
                        Button {
                            Task { await browser.goUp() }
                        } label: {
                            Image(systemName: "arrow.up")
                        }
                    }
                    PhotosPicker(selection: $pickerItems, maxSelectionCount: 12, matching: .any(of: [.images, .videos])) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    Button {
                        showNewFolder = true
                    } label: {
                        Image(systemName: "folder.badge.plus")
                    }
                }
            }
            .alert("New folder", isPresented: $showNewFolder) {
                TextField("Name", text: $newFolder)
                Button("Create") {
                    let name = newFolder.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    newFolder = ""
                    Task { await browser.newFolder(name) }
                }
                Button("Cancel", role: .cancel) { newFolder = "" }
            }
            .task { await browser.load() }
            .onChange(of: pickerItems) { _, items in
                guard !items.isEmpty else { return }
                Task {
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            await browser.upload(data, name: Self.fileName(for: item))
                        }
                    }
                    pickerItems = []
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func row(_ entry: FileEntry) -> some View {
        HStack(spacing: 10) {
            Image(systemName: entry.directory ? "folder.fill" : icon(for: entry.name))
                .foregroundStyle(entry.directory ? Color.ccAmber : Color.ccBlue)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(entry.sizeLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.45))
            }

            Spacer()

            if !entry.directory, let link = browser.link(for: entry) {
                ShareLink(item: link) {
                    Image(systemName: "arrow.down.circle")
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard entry.directory else { return }
            Task { await browser.open(entry) }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task { await browser.trash(entry) }
            } label: {
                Label("Trash", systemImage: "trash")
            }
        }
        .listRowBackground(Color.white.opacity(0.04))
    }

    private func icon(for name: String) -> String {
        let lowered = name.lowercased()
        if lowered.hasSuffix(".jpg") || lowered.hasSuffix(".jpeg") || lowered.hasSuffix(".png")
            || lowered.hasSuffix(".heic") {
            return "photo.fill"
        }
        if lowered.hasSuffix(".mp4") || lowered.hasSuffix(".mov") {
            return "video.fill"
        }
        return "doc.fill"
    }

    private static func fileName(for item: PhotosPickerItem) -> String {
        let extensionName = item.supportedContentTypes.first?.preferredFilenameExtension ?? "bin"
        let stamp = ISO8601DateFormatter()
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        return "phone-\(stamp).\(extensionName)"
    }
}

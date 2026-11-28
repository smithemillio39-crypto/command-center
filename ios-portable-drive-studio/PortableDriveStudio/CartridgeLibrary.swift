import Foundation
import Combine

struct CartridgeInfo: Identifiable {
    let url: URL
    let header: AX1VDHeader?
    let fileBytes: Int64?
    let allocatedBytes: Int64?
    let modified: Date?
    let problem: String?

    var id: String { url.path }
    var displayName: String { url.deletingPathExtension().lastPathComponent }
}

/// The app owns a single Documents/Cartridges folder. Importing copies a file
/// into that folder; deleting removes only that copy. The original picked from
/// Files is never touched.
final class CartridgeLibrary: ObservableObject {
    @Published private(set) var cartridges: [CartridgeInfo] = []
    @Published var notice: String?

    let root: URL

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory,
                                                  in: .userDomainMask)[0]
        root = documents.appendingPathComponent("Cartridges", isDirectory: true)
        try? FileManager.default.createDirectory(at: root,
                                                 withIntermediateDirectories: true)
    }

    func refresh() {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        cartridges = urls
            .filter { $0.pathExtension.lowercased() == "vdrive" }
            .map(inspect)
            .sorted { left, right in
                (left.modified ?? .distantPast) > (right.modified ?? .distantPast)
            }
    }

    func create(name: String, sizeMB: Int) throws -> CartridgeInfo {
        let capacity = UInt64(max(1, sizeMB)) << 20
        let url = uniqueURL(for: sanitized(name))
        try AX1VD.create(at: url, capacity: capacity)
        writeMetadata(for: url, capacity: capacity)
        refresh()
        guard let info = cartridges.first(where: { $0.url == url }) else {
            throw AX1VDError.createFailed
        }
        return info
    }

    func importFile(_ source: URL) throws -> CartridgeInfo {
        let scoped = source.startAccessingSecurityScopedResource()
        defer {
            if scoped { source.stopAccessingSecurityScopedResource() }
        }
        let target = uniqueURL(for: sanitized(source.lastPathComponent))
        try FileManager.default.copyItem(at: source, to: target)
        do {
            _ = try AX1VD.header(at: target)
        } catch {
            try? FileManager.default.removeItem(at: target)
            throw error
        }
        refresh()
        guard let info = cartridges.first(where: { $0.url == target }) else {
            throw AX1VDError.createFailed
        }
        return info
    }

    /// Deletes only a cartridge that lives directly in this app's library.
    /// Imported copies can be removed without touching the original file.
    func delete(_ info: CartridgeInfo) throws {
        let target = info.url.standardizedFileURL
        let library = root.standardizedFileURL
        guard target.deletingLastPathComponent() == library else {
            throw AX1VDError.notInLibrary
        }
        guard target.pathExtension.lowercased() == "vdrive" else {
            throw AX1VDError.notInLibrary
        }
        try FileManager.default.removeItem(at: target)
        try? FileManager.default.removeItem(at: target.appendingPathExtension("cart.json"))
        refresh()
    }

    private func inspect(_ url: URL) -> CartridgeInfo {
        var header: AX1VDHeader?
        var problem: String?
        do {
            header = try AX1VD.header(at: url)
        } catch {
            problem = error.localizedDescription
        }
        let values = try? url.resourceValues(forKeys: [
            .fileSizeKey, .totalFileAllocatedSizeKey, .contentModificationDateKey
        ])
        let fileBytes = values?.fileSize.map { Int64($0) }
        let allocated = (values?.totalFileAllocatedSize ?? values?.fileSize).map { Int64($0) }
        return CartridgeInfo(url: url, header: header, fileBytes: fileBytes,
                             allocatedBytes: allocated,
                             modified: values?.contentModificationDate,
                             problem: problem)
    }

    private func sanitized(_ raw: String) -> String {
        let leaf = raw.replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/").last.map(String.init) ?? raw
        var candidate = leaf.trimmingCharacters(in: .whitespacesAndNewlines)
        if !candidate.lowercased().hasSuffix(".vdrive") {
            candidate += ".vdrive"
        }
        candidate = String(candidate.map { character in
            character.isLetter || character.isNumber || "._- ".contains(character)
                ? character : "-"
        })
        if candidate.isEmpty || candidate == ".vdrive" {
            candidate = "CARTRIDGE.vdrive"
        }
        if candidate.count > 80 {
            candidate = String(candidate.prefix(76)) + ".vdrive"
        }
        return candidate
    }

    private func uniqueURL(for name: String) -> URL {
        var candidate = root.appendingPathComponent(name)
        let stem = candidate.deletingPathExtension().lastPathComponent
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = root.appendingPathComponent("\(stem)-\(suffix).vdrive")
            suffix += 1
        }
        return candidate
    }

    private func writeMetadata(for url: URL, capacity: UInt64) {
        let metadata: [String: Any] = [
            "format": "aether-cartridge/1",
            "label": url.deletingPathExtension().lastPathComponent,
            "created": ISO8601DateFormatter().string(from: Date()),
            "logical_capacity": Double(capacity)
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: metadata,
                                                      options: [.prettyPrinted]) else {
            return
        }
        try? data.write(to: url.appendingPathExtension("cart.json"), options: .atomic)
    }
}

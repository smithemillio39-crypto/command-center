import Foundation

struct VolumeDescriptor {
    let header: AX1VDHeader
    let geometry: FAT32Geometry
    let label: String

    var dataOffset: UInt64 { UInt64(AX1VD.dataOffset) }
    var capacityBytes: UInt64 { header.capacity }
}

struct VolumeIntegrity {
    let label: String
    let clusterBytes: Int
    let totalClusters: UInt64
    let usedClusters: UInt64
    let freeClusters: UInt64
    let headerValid: Bool
    let geometryValid: Bool
    let fatCopiesMatch: Bool
    let bootBackupMatches: Bool
    let fsinfoMatches: Bool
    let crossLinkedClusters: Int
    let journalState: AX1VDJournalState
    let checkedAt: Date

    var freeBytes: UInt64 { freeClusters * UInt64(clusterBytes) }
    var usedBytes: UInt64 { usedClusters * UInt64(clusterBytes) }

    var isHealthy: Bool {
        headerValid && geometryValid && fatCopiesMatch && bootBackupMatches && fsinfoMatches
            && crossLinkedClusters == 0
    }

    var summary: String {
        var parts: [String] = []
        parts.append(isHealthy ? "FAT32 volume valid." : "FAT32 volume has problems.")
        parts.append(fatCopiesMatch ? "Both FAT copies match." : "The FAT copies differ.")
        parts.append(bootBackupMatches ? "Backup boot sector matches." : "The backup boot sector differs.")
        parts.append(fsinfoMatches
                     ? "FSInfo free count matches the cluster sweep."
                     : "FSInfo free count is wrong.")
        parts.append(crossLinkedClusters == 0
                     ? "No cluster is in two chains."
                     : String(crossLinkedClusters) + " clusters are in two chains.")
        return parts.joined(separator: " ")
    }
}

enum VolumeError: LocalizedError {
    case sizeMismatch(expected: UInt64, actual: UInt64)
    case emptyLabel

    var errorDescription: String? {
        switch self {
        case .sizeMismatch(let expected, let actual):
            let want = ByteCountFormatter.string(fromByteCount: Int64(clamping: expected), countStyle: .file)
            let have = ByteCountFormatter.string(fromByteCount: Int64(clamping: actual), countStyle: .file)
            return "The header declares " + want + " but the file holds " + have + ". Format the cartridge to create the volume."
        case .emptyLabel:
            return "The volume label cannot be empty."
        }
    }
}

final class AX1VDVolume {
    let url: URL
    let header: AX1VDHeader
    let geometry: FAT32Geometry
    let label: String

    private let handle: FileHandle
    private let filesystem: FAT32Volume
    private var ejected = false

    private init(url: URL,
                 header: AX1VDHeader,
                 geometry: FAT32Geometry,
                 label: String,
                 handle: FileHandle,
                 filesystem: FAT32Volume) {
        self.url = url
        self.header = header
        self.geometry = geometry
        self.label = label
        self.handle = handle
        self.filesystem = filesystem
    }

    // MARK: Format and mount

    static func format(cartridgeAt url: URL, label: String, clusterSize: Int? = nil) throws -> VolumeDescriptor {
        let header = try AX1VD.header(at: url)
        let normalized = FAT32Name.volumeLabel(label)
        if normalized.isEmpty { throw VolumeError.emptyLabel }
        let geometry = try FAT32Geometry.make(capacity: header.capacity, clusterSize: clusterSize)
        let required = UInt64(AX1VD.dataOffset) + header.capacity
        let handle = try FileHandle(forUpdating: url)
        defer { try? handle.close() }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        let current = values?.fileSize.map { UInt64(clamping: $0) } ?? 0
        if current < required {
            try handle.truncate(atOffset: required)
        }
        let volumeID = FAT32Name.volumeID(label: normalized, capacity: header.capacity)
        try FAT32Volume.format(handle: handle,
                               baseOffset: UInt64(AX1VD.dataOffset),
                               geometry: geometry,
                               label: normalized,
                               volumeID: volumeID)
        try AX1VDJournal.setDirty(false, at: url)
        return VolumeDescriptor(header: header, geometry: geometry, label: normalized)
    }

    static func mount(at url: URL) throws -> AX1VDVolume {
        let header = try AX1VD.header(at: url)
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        let actual = values?.fileSize.map { UInt64(clamping: $0) } ?? 0
        let required = UInt64(AX1VD.dataOffset) + header.capacity
        guard actual >= required else {
            throw VolumeError.sizeMismatch(expected: required, actual: actual)
        }
        let handle = try FileHandle(forUpdating: url)
        do {
            let geometry = try FAT32Volume.validate(handle: handle,
                                                   baseOffset: UInt64(AX1VD.dataOffset),
                                                   expectedCapacity: header.capacity)
            let filesystem = try FAT32Volume(handle: handle,
                                             baseOffset: UInt64(AX1VD.dataOffset),
                                             geometry: geometry)
            let boot = try FAT32Volume.load(handle: handle, at: UInt64(AX1VD.dataOffset), count: 512)
            let label = FAT32Name.label(fromBootSector: boot)
            try AX1VDJournal.setDirty(true, at: url)
            return AX1VDVolume(url: url,
                               header: header,
                               geometry: geometry,
                               label: label,
                               handle: handle,
                               filesystem: filesystem)
        } catch {
            try? handle.close()
            throw error
        }
    }

    func eject() throws {
        if ejected { return }
        try filesystem.flush()
        try handle.synchronize()
        try? handle.close()
        try AX1VDJournal.setDirty(false, at: url)
        ejected = true
    }

    // MARK: Space

    var totalBytes: UInt64 { header.capacity }
    var freeBytes: UInt64 { filesystem.freeBytes }
    var usedBytes: UInt64 { filesystem.usedBytes }
    var freeClusterCount: UInt32 { filesystem.freeClusterCount }

    // MARK: Files and folders

    func list(_ path: [String] = []) throws -> [FAT32Entry] {
        let directory = try filesystem.resolve(directory: path)
        return try filesystem.list(directory: directory)
    }

    func writeFile(_ name: String, in path: [String] = [], data: Data) throws {
        let directory = try filesystem.resolve(directory: path)
        _ = try filesystem.createFile(in: directory, name: name, data: data)
        try filesystem.flush()
    }

    func readFile(_ name: String, in path: [String] = []) throws -> Data {
        let directory = try filesystem.resolve(directory: path)
        return try filesystem.readFile(in: directory, name: name)
    }

    func deleteFile(_ name: String, in path: [String] = []) throws {
        let directory = try filesystem.resolve(directory: path)
        try filesystem.deleteFile(in: directory, name: name)
        try filesystem.flush()
    }

    // MARK: Integrity

    static func integrityCheck(at url: URL) throws -> VolumeIntegrity {
        let header = try AX1VD.header(at: url)
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        let actual = values?.fileSize.map { UInt64(clamping: $0) } ?? 0
        let required = UInt64(AX1VD.dataOffset) + header.capacity
        guard actual >= required else {
            throw VolumeError.sizeMismatch(expected: required, actual: actual)
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let offset = UInt64(AX1VD.dataOffset)
        let geometry = try FAT32Volume.validate(handle: handle,
                                               baseOffset: offset,
                                               expectedCapacity: header.capacity)
        let filesystem = try FAT32Volume(handle: handle, baseOffset: offset, geometry: geometry)
        let snapshot = try filesystem.integritySnapshot()
        let boot = try FAT32Volume.load(handle: handle, at: offset, count: 512)
        let backup = try FAT32Volume.load(handle: handle,
                                          at: offset + UInt64(FAT32Geometry.backupBootSector) * 512,
                                          count: 512)
        return VolumeIntegrity(label: FAT32Name.label(fromBootSector: boot),
                               clusterBytes: snapshot.clusterBytes,
                               totalClusters: snapshot.totalClusters,
                               usedClusters: snapshot.usedClusters,
                               freeClusters: snapshot.freeClusters,
                               headerValid: true,
                               geometryValid: true,
                               fatCopiesMatch: snapshot.fatCopiesMatch,
                               bootBackupMatches: boot == backup,
                               fsinfoMatches: snapshot.freeCountMatches,
                               crossLinkedClusters: snapshot.crossLinkedClusters,
                               journalState: AX1VDJournal.state(at: url),
                               checkedAt: Date())
    }
}

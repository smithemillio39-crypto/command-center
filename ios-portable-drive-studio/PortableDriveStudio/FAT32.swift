import Foundation

// MARK: - Errors

enum FAT32Error: LocalizedError {
    case capacityTooSmall(minimum: UInt64)
    case capacityTooLarge(maximum: UInt64)
    case badClusterSize
    case bootSectorInvalid(String)
    case ioFailed(String)
    case shortIO
    case alreadyExists(String)
    case notFound(String)
    case notAFile(String)
    case notADirectory(String)
    case noFreeClusters
    case corruptChain(String)

    var errorDescription: String? {
        switch self {
        case .capacityTooSmall(let minimum):
            let text = ByteCountFormatter.string(fromByteCount: Int64(clamping: minimum), countStyle: .file)
            return "A FAT32 volume needs at least \(text)."
        case .capacityTooLarge(let maximum):
            let text = ByteCountFormatter.string(fromByteCount: Int64(clamping: maximum), countStyle: .file)
            return "A FAT32 volume cannot exceed \(text)."
        case .badClusterSize:
            return "The cluster size must be a power of two between 512 bytes and 64 KiB."
        case .bootSectorInvalid(let reason):
            return "FAT32 boot sector invalid: \(reason)."
        case .ioFailed(let reason):
            return "Volume access failed: \(reason)."
        case .shortIO:
            return "The volume ended before the expected bytes were read."
        case .alreadyExists(let name):
            return "\(name) already exists in that folder."
        case .notFound(let name):
            return "\(name) was not found in that folder."
        case .notAFile(let name):
            return "\(name) is a folder, not a file."
        case .notADirectory(let name):
            return "\(name) is not a folder."
        case .noFreeClusters:
            return "The volume has no free clusters."
        case .corruptChain(let reason):
            return "Corrupt cluster chain: \(reason)."
        }
    }
}

// MARK: - Geometry

struct FAT32Geometry: Equatable {
    static let bytesPerSector = 512
    static let reservedSectors = 32
    static let numberOfFATs = 2
    static let rootCluster: UInt32 = 2
    static let minimumClusters: UInt64 = 65525
    static let maximumClusters: UInt64 = 268_435_445
    static let minimumCapacity: UInt64 = 300 * 1024 * 1024
    static let maximumCapacity: UInt64 = 2 * 1024 * 1024 * 1024 * 1024
    static let fsInfoSector = 1
    static let backupBootSector = 6
    static let mediaByte: UInt8 = 0xF8

    let sectorsPerCluster: Int
    let totalSectors: UInt64
    let fatSectors: UInt32
    let totalClusters: UInt64

    var clusterBytes: Int { sectorsPerCluster * FAT32Geometry.bytesPerSector }
    var totalBytes: UInt64 { totalSectors * UInt64(FAT32Geometry.bytesPerSector) }
    var fatOffset: UInt64 { UInt64(FAT32Geometry.reservedSectors) * UInt64(FAT32Geometry.bytesPerSector) }
    var clusterLimit: UInt64 { totalClusters + 2 }

    var dataStartSector: UInt64 {
        UInt64(FAT32Geometry.reservedSectors) + UInt64(FAT32Geometry.numberOfFATs) * UInt64(fatSectors)
    }

    func sector(of cluster: UInt32) -> UInt64 {
        dataStartSector + UInt64(cluster - 2) * UInt64(sectorsPerCluster)
    }

    func offset(of cluster: UInt32) -> UInt64 {
        sector(of: cluster) * UInt64(FAT32Geometry.bytesPerSector)
    }

    static func make(capacity: UInt64, clusterSize: Int?) throws -> FAT32Geometry {
        guard capacity >= minimumCapacity else { throw FAT32Error.capacityTooSmall(minimum: minimumCapacity) }
        guard capacity <= maximumCapacity else { throw FAT32Error.capacityTooLarge(maximum: maximumCapacity) }
        guard capacity % UInt64(bytesPerSector) == 0 else {
            throw FAT32Error.bootSectorInvalid("the capacity is not a multiple of 512 bytes")
        }
        let totalSectors = capacity / UInt64(bytesPerSector)
        var candidates: [Int]
        if let clusterSize {
            guard clusterSize >= 512, clusterSize <= 65536,
                  clusterSize % bytesPerSector == 0,
                  clusterSize & (clusterSize - 1) == 0 else {
                throw FAT32Error.badClusterSize
            }
            candidates = [clusterSize / bytesPerSector]
        } else {
            candidates = [8, 16, 32, 64, 128]
        }
        var failure = FAT32Error.capacityTooSmall(minimum: minimumCapacity)
        for spc in candidates {
            guard let layout = solve(totalSectors: totalSectors, sectorsPerCluster: spc) else { continue }
            if layout.clusters < minimumClusters { continue }
            if layout.clusters > maximumClusters {
                failure = FAT32Error.capacityTooLarge(maximum: maximumCapacity)
                continue
            }
            return FAT32Geometry(sectorsPerCluster: spc,
                                 totalSectors: totalSectors,
                                 fatSectors: layout.fatSectors,
                                 totalClusters: layout.clusters)
        }
        throw failure
    }

    private static func solve(totalSectors: UInt64, sectorsPerCluster: Int) -> (fatSectors: UInt32, clusters: UInt64)? {
        var fatSectors: UInt64 = 1
        var clusters: UInt64 = 0
        var round = 0
        while round < 16 {
            let overhead = UInt64(reservedSectors) + UInt64(numberOfFATs) * fatSectors
            guard totalSectors > overhead else { return nil }
            clusters = (totalSectors - overhead) / UInt64(sectorsPerCluster)
            guard clusters > 0 else { return nil }
            let needed = ((clusters + 2) * 4 + UInt64(bytesPerSector) - 1) / UInt64(bytesPerSector)
            if needed <= fatSectors { return (UInt32(fatSectors), clusters) }
            fatSectors = needed
            round += 1
        }
        return (UInt32(fatSectors), clusters)
    }
}

// MARK: - Names

enum FAT32Name {
    static let allowedShortCharacters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789$%'-_@~`!(){}^#&")

    static func checksum(_ shortName: [UInt8]) -> UInt8 {
        var sum: UInt8 = 0
        for byte in shortName {
            let carry: UInt8 = (sum & 1) == 1 ? 0x80 : 0x00
            sum = carry &+ (sum >> 1) &+ byte
        }
        return sum
    }

    static func units(_ name: String) -> [UInt16] {
        Array(name.utf16)
    }

    static func string(units: [UInt16]) -> String {
        var trimmed = units
        while let last = trimmed.last, last == 0x0000 || last == 0xFFFF {
            trimmed.removeLast()
        }
        return String(decoding: trimmed, as: UTF16.self)
    }

    static func longNameSlots(name: String) -> Int {
        let count = units(name).count
        return count == 0 ? 0 : (count + 12) / 13
    }

    static func filtered(_ text: String) -> String {
        var result = ""
        for character in text.uppercased() {
            if allowedShortCharacters.contains(character) {
                result.append(character)
            } else if character == " " || character == "." {
                continue
            } else {
                result.append("_")
            }
        }
        return result
    }

    static func padded(base: String, ext: String) -> [UInt8] {
        var bytes = Array(base.prefix(8).utf8)
        while bytes.count < 8 { bytes.append(0x20) }
        var tail = Array(ext.prefix(3).utf8)
        while tail.count < 3 { tail.append(0x20) }
        return bytes + tail
    }

    static func display(shortName: [UInt8]) -> String {
        let base = String(bytes: shortName[0..<8], encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? ""
        let ext = String(bytes: shortName[8..<11], encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? ""
        let safeBase = base.isEmpty ? "FILE" : base
        return ext.isEmpty ? safeBase : safeBase + "." + ext
    }

    static func shortName(for name: String, taken: Set<String>) -> [UInt8] {
        let parts = name.uppercased().split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        var base = filtered(parts.first ?? "")
        var ext = parts.count > 1 ? filtered(parts.last ?? "") : ""
        if base.isEmpty { base = "FILE" }
        if ext.count > 3 { ext = String(ext.prefix(3)) }
        if parts.count <= 2, base.count <= 8, !taken.contains(display(shortName: padded(base: base, ext: ext))) {
            return padded(base: base, ext: ext)
        }
        let stem = String(base.prefix(6))
        var counter = 1
        while counter < 100000 {
            let tail = "~" + String(counter)
            let head = String(stem.prefix(8 - tail.count))
            let candidate = (head.isEmpty ? "FILE" : head) + tail
            let bytes = padded(base: candidate, ext: ext)
            if !taken.contains(display(shortName: bytes)) { return bytes }
            counter += 1
        }
        return padded(base: "FILE~999", ext: "")
    }

    static func needsLongName(name: String, shortName: [UInt8]) -> Bool {
        display(shortName: shortName) != name
    }

    static func stamp(_ date: Date) -> (date: UInt16, time: UInt16) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone.current
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = max(1980, parts.year ?? 1980) - 1980
        let month = min(12, max(1, parts.month ?? 1))
        let day = min(31, max(1, parts.day ?? 1))
        let hour = min(23, max(0, parts.hour ?? 0))
        let minute = min(59, max(0, parts.minute ?? 0))
        let second = min(59, max(0, parts.second ?? 0))
        let dateWord = UInt16((year << 9) | (month << 5) | day)
        let timeWord = UInt16((hour << 11) | (minute << 5) | (second / 2))
        return (dateWord, timeWord)
    }

    static func date(date: UInt16, time: UInt16) -> Date? {
        guard date != 0 else { return nil }
        var components = DateComponents()
        components.year = 1980 + Int((date >> 9) & 0x7F)
        components.month = Int((date >> 5) & 0x0F)
        components.day = Int(date & 0x1F)
        components.hour = Int((time >> 11) & 0x1F)
        components.minute = Int((time >> 5) & 0x3F)
        components.second = Int(time & 0x1F) * 2
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone.current
        return calendar.date(from: components)
    }

    static func volumeLabel(_ label: String) -> String {
        var base = filtered(label)
        if base.isEmpty { base = "NO NAME" }
        if base.count > 11 { base = String(base.prefix(11)) }
        return base
    }

    static func volumeLabelBytes(_ label: String) -> [UInt8] {
        var bytes = Array(volumeLabel(label).utf8)
        if bytes.count > 11 { bytes = Array(bytes.prefix(11)) }
        while bytes.count < 11 { bytes.append(0x20) }
        return bytes
    }

    static func volumeID(label: String, capacity: UInt64) -> UInt32 {
        var hash: UInt32 = 2166136261
        for byte in Array(label.utf8) {
            hash = (hash ^ UInt32(byte)) &* 16777619
        }
        var remaining = capacity
        var index = 0
        while index < 8 {
            hash = (hash ^ UInt32(truncatingIfNeeded: remaining)) &* 16777619
            remaining >>= 8
            index += 1
        }
        return hash
    }

    static func label(fromBootSector boot: Data) -> String {
        guard boot.count >= 90 else { return "" }
        let raw = Array(boot[71..<82])
        let text = String(bytes: raw, encoding: .ascii) ?? ""
        return text.trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Little-endian helpers

private func le16(_ data: Data, _ offset: Int) -> UInt16 {
    UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
}

private func le32(_ data: Data, _ offset: Int) -> UInt32 {
    UInt32(data[offset])
        | (UInt32(data[offset + 1]) << 8)
        | (UInt32(data[offset + 2]) << 16)
        | (UInt32(data[offset + 3]) << 24)
}

private func putLE16(_ value: UInt16, _ data: inout Data, _ offset: Int) {
    data[offset] = UInt8(value & 0xFF)
    data[offset + 1] = UInt8((value >> 8) & 0xFF)
}

private func putLE32(_ value: UInt32, _ data: inout Data, _ offset: Int) {
    data[offset] = UInt8(value & 0xFF)
    data[offset + 1] = UInt8((value >> 8) & 0xFF)
    data[offset + 2] = UInt8((value >> 16) & 0xFF)
    data[offset + 3] = UInt8((value >> 24) & 0xFF)
}

private func appendLE32(_ value: UInt32, to data: inout Data) {
    data.append(UInt8(value & 0xFF))
    data.append(UInt8((value >> 8) & 0xFF))
    data.append(UInt8((value >> 16) & 0xFF))
    data.append(UInt8((value >> 24) & 0xFF))
}

// MARK: - Entries

struct FAT32Entry: Identifiable, Equatable {
    let name: String
    let shortName: String
    let isDirectory: Bool
    let size: UInt32
    let firstCluster: UInt32
    let modified: Date?

    var id: String { name + "-" + String(firstCluster) }
}

struct FAT32Integrity {
    let clusterBytes: Int
    let totalClusters: UInt64
    let usedClusters: UInt64
    let freeClusters: UInt64
    let freeCountMatches: Bool
    let fatCopiesMatch: Bool
    let crossLinkedClusters: Int
}

// MARK: - Volume

final class FAT32Volume {
    static let eoc: UInt32 = 0x0FFFFFFF
    static let badCluster: UInt32 = 0x0FFFFFF7

    let geometry: FAT32Geometry
    let baseOffset: UInt64

    private let handle: FileHandle
    private var fatTable: [UInt32]
    private var dirtySectors: Set<Int>
    private var freeClusters: UInt32
    private var nextFree: UInt32

    struct ScannedEntry {
        let entry: FAT32Entry
        let slot: Int
        let longNameSlots: Int
    }

    init(handle: FileHandle, baseOffset: UInt64, geometry: FAT32Geometry) throws {
        self.handle = handle
        self.baseOffset = baseOffset
        self.geometry = geometry
        self.dirtySectors = []
        let fatBytes = Int(geometry.fatSectors) * FAT32Geometry.bytesPerSector
        let raw = try FAT32Volume.load(handle: handle, at: baseOffset + geometry.fatOffset, count: fatBytes)
        var table = [UInt32](repeating: 0, count: fatBytes / 4)
        var index = 0
        while index < table.count {
            table[index] = le32(raw, index * 4)
            index += 1
        }
        self.fatTable = table
        let info = try FAT32Volume.load(handle: handle,
                                        at: baseOffset + UInt64(FAT32Geometry.fsInfoSector) * 512,
                                        count: 512)
        let reportedFree = le32(info, 488)
        let reportedNext = le32(info, 492)
        if reportedFree == 0xFFFFFFFF || UInt64(reportedFree) > geometry.totalClusters {
            self.freeClusters = FAT32Volume.countFree(table: table, geometry: geometry)
        } else {
            self.freeClusters = reportedFree
        }
        if reportedNext >= 3 && UInt64(reportedNext) < geometry.clusterLimit {
            self.nextFree = reportedNext
        } else {
            self.nextFree = 3
        }
    }

    // MARK: Accessors

    var freeClusterCount: UInt32 { freeClusters }

    var freeBytes: UInt64 {
        UInt64(freeClusters) * UInt64(geometry.clusterBytes)
    }

    var usedBytes: UInt64 {
        let free = UInt64(min(UInt64(freeClusters), geometry.totalClusters))
        return (geometry.totalClusters - free) * UInt64(geometry.clusterBytes)
    }

    // MARK: Raw I/O

    static func load(handle: FileHandle, at offset: UInt64, count: Int) throws -> Data {
        do {
            try handle.seek(toOffset: offset)
            let data = try handle.read(upToCount: count) ?? Data()
            guard data.count == count else { throw FAT32Error.shortIO }
            return data
        } catch let error as FAT32Error {
            throw error
        } catch {
            throw FAT32Error.ioFailed(error.localizedDescription)
        }
    }

    static func store(handle: FileHandle, at offset: UInt64, data: Data) throws {
        do {
            try handle.seek(toOffset: offset)
            try handle.write(contentsOf: data)
        } catch {
            throw FAT32Error.ioFailed(error.localizedDescription)
        }
    }

    // MARK: Format

    static func format(handle: FileHandle,
                       baseOffset: UInt64,
                       geometry: FAT32Geometry,
                       label: String,
                       volumeID: UInt32) throws {
        let labelBytes = FAT32Name.volumeLabelBytes(label)
        let boot = bootSector(geometry: geometry, labelBytes: labelBytes, volumeID: volumeID)
        let info = fsInfoSector(free: UInt32(geometry.totalClusters - 1), next: 3)
        try store(handle: handle, at: baseOffset, data: boot)
        try store(handle: handle, at: baseOffset + UInt64(FAT32Geometry.fsInfoSector) * 512, data: info)
        try store(handle: handle, at: baseOffset + UInt64(FAT32Geometry.backupBootSector) * 512, data: boot)
        try store(handle: handle, at: baseOffset + UInt64(FAT32Geometry.backupBootSector + 1) * 512, data: info)

        var table = [UInt32](repeating: 0, count: Int(geometry.fatSectors) * 128)
        table[0] = 0x0FFFFFF8
        table[1] = 0x0FFFFFFF
        table[2] = 0x0FFFFFFF
        var fat = Data()
        fat.reserveCapacity(table.count * 4)
        for value in table { appendLE32(value, to: &fat) }
        let firstFAT = baseOffset + geometry.fatOffset
        let fatBytes = UInt64(Int(geometry.fatSectors) * FAT32Geometry.bytesPerSector)
        try store(handle: handle, at: firstFAT, data: fat)
        try store(handle: handle, at: firstFAT + fatBytes, data: fat)

        var root = Data(count: geometry.clusterBytes)
        let labelEntry = volumeLabelEntry(labelBytes: labelBytes)
        root.replaceSubrange(0..<32, with: labelEntry)
        try store(handle: handle, at: baseOffset + geometry.offset(of: FAT32Geometry.rootCluster), data: root)
        try handle.synchronize()
    }

    static func bootSector(geometry: FAT32Geometry, labelBytes: [UInt8], volumeID: UInt32) -> Data {
        var boot = Data(count: 512)
        boot[0] = 0xEB
        boot[1] = 0x58
        boot[2] = 0x90
        boot.replaceSubrange(3..<11, with: Array("MSWIN4.1".utf8))
        putLE16(512, &boot, 11)
        boot[13] = UInt8(geometry.sectorsPerCluster)
        putLE16(UInt16(FAT32Geometry.reservedSectors), &boot, 14)
        boot[16] = UInt8(FAT32Geometry.numberOfFATs)
        putLE16(0, &boot, 17)
        putLE16(0, &boot, 19)
        boot[21] = FAT32Geometry.mediaByte
        putLE16(0, &boot, 22)
        putLE16(63, &boot, 24)
        putLE16(255, &boot, 26)
        putLE32(0, &boot, 28)
        putLE32(UInt32(geometry.totalSectors), &boot, 32)
        putLE32(geometry.fatSectors, &boot, 36)
        putLE16(0, &boot, 40)
        putLE16(0, &boot, 42)
        putLE32(FAT32Geometry.rootCluster, &boot, 44)
        putLE16(UInt16(FAT32Geometry.fsInfoSector), &boot, 48)
        putLE16(UInt16(FAT32Geometry.backupBootSector), &boot, 50)
        boot[64] = 0x80
        boot[66] = 0x29
        putLE32(volumeID, &boot, 67)
        boot.replaceSubrange(71..<82, with: labelBytes)
        boot.replaceSubrange(82..<90, with: Array("FAT32   ".utf8))
        boot[510] = 0x55
        boot[511] = 0xAA
        return boot
    }

    static func fsInfoSector(free: UInt32, next: UInt32) -> Data {
        var sector = Data(count: 512)
        putLE32(0x41615252, &sector, 0)
        putLE32(0x61417272, &sector, 484)
        putLE32(free, &sector, 488)
        putLE32(next, &sector, 492)
        putLE32(0xAA550000, &sector, 508)
        return sector
    }

    static func volumeLabelEntry(labelBytes: [UInt8]) -> Data {
        var entry = Data(count: 32)
        entry[0] = labelBytes.first == 0xE5 ? 0x05 : (labelBytes.first ?? 0x20)
        var index = 1
        while index < 11 {
            entry[index] = labelBytes[index]
            index += 1
        }
        entry[11] = 0x08
        putLE16(0, &entry, 12)
        putLE16(0, &entry, 20)
        putLE16(0, &entry, 22)
        putLE16(0, &entry, 24)
        putLE16(0, &entry, 26)
        putLE32(0, &entry, 28)
        return entry
    }

    static func validate(handle: FileHandle, baseOffset: UInt64, expectedCapacity: UInt64) throws -> FAT32Geometry {
        let boot = try load(handle: handle, at: baseOffset, count: 512)
        guard boot[510] == 0x55, boot[511] == 0xAA else {
            throw FAT32Error.bootSectorInvalid("missing the 0x55AA signature")
        }
        let sectorSize = Int(le16(boot, 11))
        guard sectorSize == FAT32Geometry.bytesPerSector else {
            throw FAT32Error.bootSectorInvalid("logical sector size is " + String(sectorSize))
        }
        let spc = Int(boot[13])
        guard spc > 0, spc & (spc - 1) == 0, spc * 512 <= 65536 else {
            throw FAT32Error.bootSectorInvalid("the cluster size is unsupported")
        }
        let reserved = Int(le16(boot, 14))
        guard reserved >= 1 else { throw FAT32Error.bootSectorInvalid("there are no reserved sectors") }
        let fats = Int(boot[16])
        guard fats >= 1, fats <= 2 else {
            throw FAT32Error.bootSectorInvalid("the FAT count is " + String(fats))
        }
        guard le16(boot, 17) == 0 else {
            throw FAT32Error.bootSectorInvalid("the root entry count is set on a FAT32 volume")
        }
        guard le16(boot, 22) == 0 else {
            throw FAT32Error.bootSectorInvalid("the 16-bit FAT size is set on a FAT32 volume")
        }
        let fatSectors = le32(boot, 36)
        guard fatSectors > 0 else { throw FAT32Error.bootSectorInvalid("the FAT size is zero") }
        let totalSectors = UInt64(le32(boot, 32))
        guard totalSectors > 0 else { throw FAT32Error.bootSectorInvalid("the total sector count is zero") }
        guard le32(boot, 44) == FAT32Geometry.rootCluster else {
            throw FAT32Error.bootSectorInvalid("the root cluster is not 2")
        }
        guard boot[21] == FAT32Geometry.mediaByte else {
            throw FAT32Error.bootSectorInvalid("the media byte is not 0xF8")
        }
        let infoSector = Int(le16(boot, 48))
        guard infoSector > 0, infoSector < reserved else {
            throw FAT32Error.bootSectorInvalid("the FSInfo sector is outside the reserved area")
        }
        guard totalSectors * 512 == expectedCapacity else {
            throw FAT32Error.bootSectorInvalid("the volume size does not match the AX1VD capacity")
        }
        let dataStart = UInt64(reserved) + UInt64(fats) * UInt64(fatSectors)
        guard dataStart < totalSectors else { throw FAT32Error.bootSectorInvalid("the data region is empty") }
        let clusters = (totalSectors - dataStart) / UInt64(spc)
        guard clusters >= FAT32Geometry.minimumClusters else {
            throw FAT32Error.bootSectorInvalid("only " + String(clusters) + " clusters")
        }
        guard clusters <= FAT32Geometry.maximumClusters else {
            throw FAT32Error.bootSectorInvalid("too many clusters for FAT32")
        }
        return FAT32Geometry(sectorsPerCluster: spc,
                             totalSectors: totalSectors,
                             fatSectors: fatSectors,
                             totalClusters: clusters)
    }

    static func countFree(table: [UInt32], geometry: FAT32Geometry) -> UInt32 {
        var free: UInt32 = 0
        var index: UInt64 = 2
        while index < geometry.clusterLimit {
            if index < UInt64(table.count), table[Int(index)] & 0x0FFFFFFF == 0 {
                free += 1
            }
            index += 1
        }
        return free
    }

    // MARK: Clusters

    func readCluster(_ cluster: UInt32) throws -> Data {
        try FAT32Volume.load(handle: handle,
                             at: baseOffset + geometry.offset(of: cluster),
                             count: geometry.clusterBytes)
    }

    func writeCluster(_ cluster: UInt32, _ data: Data) throws {
        var payload = data
        if payload.count < geometry.clusterBytes {
            payload.append(Data(repeating: 0, count: geometry.clusterBytes - payload.count))
        }
        if payload.count > geometry.clusterBytes {
            payload = Data(payload.prefix(geometry.clusterBytes))
        }
        try FAT32Volume.store(handle: handle, at: baseOffset + geometry.offset(of: cluster), data: payload)
    }

    func fatValue(_ cluster: UInt32) -> UInt32 {
        let index = Int(cluster)
        guard index >= 0, index < fatTable.count else { return FAT32Volume.badCluster }
        return fatTable[index] & 0x0FFFFFFF
    }

    func setFAT(_ cluster: UInt32, _ value: UInt32) {
        let index = Int(cluster)
        guard index >= 0, index < fatTable.count else { return }
        fatTable[index] = (fatTable[index] & 0xF0000000) | (value & 0x0FFFFFFF)
        dirtySectors.insert(index / 128)
    }

    func isFree(_ cluster: UInt32) -> Bool {
        guard cluster >= 2, UInt64(cluster) < geometry.clusterLimit else { return false }
        return fatValue(cluster) == 0
    }

    func chain(start: UInt32) throws -> [UInt32] {
        guard start != 0 else { return [] }
        var clusters: [UInt32] = []
        var seen = Set<UInt32>()
        var current = start
        while true {
            guard UInt64(current) >= 2, UInt64(current) < geometry.clusterLimit else {
                throw FAT32Error.corruptChain("cluster " + String(current) + " is outside the data region")
            }
            guard seen.insert(current).inserted else {
                throw FAT32Error.corruptChain("cluster " + String(current) + " appears twice in one chain")
            }
            clusters.append(current)
            let next = fatValue(current)
            if next >= 0x0FFFFFF8 { break }
            if next == 0 { throw FAT32Error.corruptChain("cluster " + String(current) + " points at a free cluster") }
            if next == FAT32Volume.badCluster { throw FAT32Error.corruptChain("cluster " + String(current) + " points at a bad cluster") }
            current = next
        }
        return clusters
    }

    func allocate(count: Int) throws -> [UInt32] {
        guard count > 0 else { return [] }
        var result: [UInt32] = []
        var candidate = nextFree < 3 ? UInt32(3) : nextFree
        if UInt64(candidate) >= geometry.clusterLimit { candidate = 3 }
        var probes: UInt64 = 0
        let limit = geometry.clusterLimit + 4
        while result.count < count {
            probes += 1
            if probes > limit { throw FAT32Error.noFreeClusters }
            if isFree(candidate) {
                result.append(candidate)
            }
            candidate += 1
            if UInt64(candidate) >= geometry.clusterLimit { candidate = 3 }
        }
        var index = 0
        while index < result.count {
            let next = index + 1 < result.count ? result[index + 1] : FAT32Volume.eoc
            setFAT(result[index], next)
            index += 1
        }
        if freeClusters >= UInt32(result.count) {
            freeClusters -= UInt32(result.count)
        } else {
            freeClusters = 0
        }
        nextFree = candidate
        return result
    }

    func release(_ clusters: [UInt32]) {
        if clusters.isEmpty { return }
        for cluster in clusters {
            setFAT(cluster, 0)
        }
        let total = UInt64(freeClusters) + UInt64(clusters.count)
        freeClusters = UInt32(min(total, geometry.totalClusters))
        if let lowest = clusters.min(), lowest < nextFree || nextFree < 3 {
            nextFree = lowest
        }
    }

    func flush() throws {
        let entriesPerSector = FAT32Geometry.bytesPerSector / 4
        let sectors = Int(geometry.fatSectors)
        for sectorIndex in dirtySectors.sorted() {
            guard sectorIndex >= 0, sectorIndex < sectors else { continue }
            var sector = Data(count: FAT32Geometry.bytesPerSector)
            var offset = 0
            while offset < entriesPerSector {
                let entryIndex = sectorIndex * entriesPerSector + offset
                let value = entryIndex < fatTable.count ? fatTable[entryIndex] : 0
                putLE32(value, &sector, offset * 4)
                offset += 1
            }
            let firstFAT = baseOffset + geometry.fatOffset + UInt64(sectorIndex * FAT32Geometry.bytesPerSector)
            try FAT32Volume.store(handle: handle, at: firstFAT, data: sector)
            let secondFAT = firstFAT + UInt64(sectors * FAT32Geometry.bytesPerSector)
            try FAT32Volume.store(handle: handle, at: secondFAT, data: sector)
        }
        dirtySectors.removeAll()
        let info = FAT32Volume.fsInfoSector(free: freeClusters, next: nextFree)
        let infoOffset = baseOffset + UInt64(FAT32Geometry.fsInfoSector) * 512
        try FAT32Volume.store(handle: handle, at: infoOffset, data: info)
        try FAT32Volume.store(handle: handle,
                              at: baseOffset + UInt64(FAT32Geometry.backupBootSector + 1) * 512,
                              data: info)
        try handle.synchronize()
    }

    // MARK: Directories

    func directoryData(start: UInt32) throws -> (data: Data, clusters: [UInt32]) {
        let clusters = try chain(start: start)
        var data = Data()
        data.reserveCapacity(clusters.count * geometry.clusterBytes)
        for cluster in clusters {
            data.append(try readCluster(cluster))
        }
        return (data, clusters)
    }

    func scannedEntries(in data: Data) -> [ScannedEntry] {
        var results: [ScannedEntry] = []
        var longParts: [Int: [UInt16]] = [:]
        var longChecksums: [Int: UInt8] = [:]
        var longCount = 0
        var slot = 0
        while (slot + 1) * 32 <= data.count {
            let offset = slot * 32
            let first = data[offset]
            if first == 0x00 { break }
            if first == 0xE5 {
                longParts.removeAll()
                longChecksums.removeAll()
                longCount = 0
                slot += 1
                continue
            }
            let attributes = data[offset + 11]
            if attributes & 0x3F == 0x0F {
                let sequence = Int(first & 0x1F)
                var units: [UInt16] = []
                var index = 0
                while index < 5 {
                    units.append(le16(data, offset + 1 + index * 2))
                    index += 1
                }
                index = 0
                while index < 6 {
                    units.append(le16(data, offset + 14 + index * 2))
                    index += 1
                }
                index = 0
                while index < 2 {
                    units.append(le16(data, offset + 28 + index * 2))
                    index += 1
                }
                longParts[sequence] = units
                longChecksums[sequence] = data[offset + 13]
                longCount += 1
                slot += 1
                continue
            }
            let shortBytes = Array(data[offset..<(offset + 11)])
            let shortDisplay = FAT32Name.display(shortName: shortBytes)
            var displayName = shortDisplay
            if let highest = longParts.keys.max(), highest > 0 {
                let expected = FAT32Name.checksum(shortBytes)
                var complete = true
                var sequence = 1
                while sequence <= highest {
                    if longParts[sequence] == nil { complete = false }
                    if longChecksums[sequence] != expected { complete = false }
                    sequence += 1
                }
                if complete {
                    var collected: [UInt16] = []
                    sequence = 1
                    while sequence <= highest {
                        collected.append(contentsOf: longParts[sequence] ?? [])
                        sequence += 1
                    }
                    let candidate = FAT32Name.string(units: collected)
                    if !candidate.isEmpty { displayName = candidate }
                }
            }
            let firstCluster = (UInt32(le16(data, offset + 20)) << 16) | UInt32(le16(data, offset + 26))
            let entry = FAT32Entry(name: displayName,
                                   shortName: shortDisplay,
                                   isDirectory: attributes & 0x10 != 0,
                                   size: le32(data, offset + 28),
                                   firstCluster: firstCluster,
                                   modified: FAT32Name.date(date: le16(data, offset + 24),
                                                            time: le16(data, offset + 22)))
            let isLabel = attributes & 0x08 != 0
            if !isLabel && shortDisplay != "." && shortDisplay != ".." {
                results.append(ScannedEntry(entry: entry, slot: slot, longNameSlots: longCount))
            }
            longParts.removeAll()
            longChecksums.removeAll()
            longCount = 0
            slot += 1
        }
        return results
    }

    func usedSlots(in data: Data) -> Int {
        var slot = 0
        while (slot + 1) * 32 <= data.count {
            if data[slot * 32] == 0x00 { break }
            slot += 1
        }
        return slot
    }

    func list(directory: UInt32 = FAT32Geometry.rootCluster) throws -> [FAT32Entry] {
        let (data, _) = try directoryData(start: directory)
        return scannedEntries(in: data).map { $0.entry }
    }

    func resolve(directory: [String]) throws -> UInt32 {
        var cluster = FAT32Geometry.rootCluster
        for component in directory {
            if component.isEmpty { continue }
            let (data, _) = try directoryData(start: cluster)
            let match = scannedEntries(in: data).first {
                $0.entry.name.caseInsensitiveCompare(component) == .orderedSame
            }
            guard let found = match else { throw FAT32Error.notFound(component) }
            guard found.entry.isDirectory else { throw FAT32Error.notADirectory(component) }
            cluster = found.entry.firstCluster
        }
        return cluster
    }

    // MARK: Files

    @discardableResult
    func createFile(in directory: UInt32 = FAT32Geometry.rootCluster,
                    name: String,
                    data: Data) throws -> FAT32Entry {
        let (existingData, clusters) = try directoryData(start: directory)
        let scanned = scannedEntries(in: existingData)
        if scanned.contains(where: { $0.entry.name.caseInsensitiveCompare(name) == .orderedSame }) {
            throw FAT32Error.alreadyExists(name)
        }
        let taken = Set(scanned.map { $0.entry.shortName.uppercased() })
        let short = FAT32Name.shortName(for: name, taken: taken)
        let longSlots = FAT32Name.needsLongName(name: name, shortName: short)
            ? FAT32Name.longNameSlots(name: name)
            : 0
        let perCluster = geometry.clusterBytes
        let neededClusters = data.isEmpty ? 0 : (data.count + perCluster - 1) / perCluster
        var fileClusters: [UInt32] = []
        if neededClusters > 0 {
            fileClusters = try allocate(count: neededClusters)
            var offset = 0
            for cluster in fileClusters {
                let end = min(offset + perCluster, data.count)
                try writeCluster(cluster, data.subdata(in: offset..<end))
                offset = end
            }
        }
        let stamp = FAT32Name.stamp(Date())
        let first = fileClusters.first ?? 0
        var entry = Data(count: 32)
        entry.replaceSubrange(0..<11, with: Data(short))
        entry[11] = 0x20
        putLE16(stamp.time, &entry, 14)
        putLE16(stamp.date, &entry, 16)
        putLE16(stamp.date, &entry, 18)
        putLE16(UInt16(first >> 16), &entry, 20)
        putLE16(stamp.time, &entry, 22)
        putLE16(stamp.date, &entry, 24)
        putLE16(UInt16(first & 0xFFFF), &entry, 26)
        putLE32(UInt32(data.count), &entry, 28)

        var mutableDirectory = existingData
        var allClusters = clusters
        let used = usedSlots(in: existingData)
        let neededSlots = longSlots + 1
        while (used + neededSlots) * 32 > mutableDirectory.count {
            let extra = try allocate(count: 1)
            guard let newCluster = extra.first else { throw FAT32Error.noFreeClusters }
            if let previous = allClusters.last {
                setFAT(previous, newCluster)
            }
            mutableDirectory.append(Data(count: perCluster))
            allClusters.append(newCluster)
        }
        if longSlots > 0 {
            let units = FAT32Name.units(name)
            let check = FAT32Name.checksum(short)
            var sequence = longSlots
            while sequence >= 1 {
                var slotData = Data(count: 32)
                slotData[0] = UInt8(sequence) | (sequence == longSlots ? 0x40 : 0x00)
                var position = 0
                while position < 13 {
                    let unitIndex = (sequence - 1) * 13 + position
                    var value: UInt16 = 0xFFFF
                    if unitIndex < units.count {
                        value = units[unitIndex]
                    } else if unitIndex == units.count {
                        value = 0x0000
                    }
                    var target = 28 + (position - 11) * 2
                    if position < 5 {
                        target = 1 + position * 2
                    } else if position < 11 {
                        target = 14 + (position - 5) * 2
                    }
                    putLE16(value, &slotData, target)
                    position += 1
                }
                slotData[11] = 0x0F
                slotData[13] = check
                let start = (used + (longSlots - sequence)) * 32
                mutableDirectory.replaceSubrange(start..<(start + 32), with: slotData)
                sequence -= 1
            }
        }
        let entryStart = (used + longSlots) * 32
        mutableDirectory.replaceSubrange(entryStart..<(entryStart + 32), with: entry)
        var offset = 0
        for cluster in allClusters {
            let end = offset + perCluster
            try writeCluster(cluster, mutableDirectory.subdata(in: offset..<end))
            offset = end
        }
        return FAT32Entry(name: name,
                          shortName: FAT32Name.display(shortName: short),
                          isDirectory: false,
                          size: UInt32(data.count),
                          firstCluster: first,
                          modified: Date())
    }

    func readFile(in directory: UInt32 = FAT32Geometry.rootCluster, name: String) throws -> Data {
        let (dirData, _) = try directoryData(start: directory)
        let match = scannedEntries(in: dirData).first {
            $0.entry.name.caseInsensitiveCompare(name) == .orderedSame
        }
        guard let found = match else { throw FAT32Error.notFound(name) }
        guard !found.entry.isDirectory else { throw FAT32Error.notAFile(name) }
        let size = Int(found.entry.size)
        if size == 0 { return Data() }
        guard found.entry.firstCluster != 0 else {
            throw FAT32Error.corruptChain("a non-empty file starts at cluster 0")
        }
        let clusters = try chain(start: found.entry.firstCluster)
        let needed = (size + geometry.clusterBytes - 1) / geometry.clusterBytes
        guard clusters.count >= needed else {
            throw FAT32Error.corruptChain("the file is shorter than its directory entry says")
        }
        var data = Data()
        data.reserveCapacity(size)
        for cluster in clusters.prefix(needed) {
            data.append(try readCluster(cluster))
        }
        return data.prefix(size)
    }

    func deleteFile(in directory: UInt32 = FAT32Geometry.rootCluster, name: String) throws {
        let (dirData, clusters) = try directoryData(start: directory)
        let match = scannedEntries(in: dirData).first {
            $0.entry.name.caseInsensitiveCompare(name) == .orderedSame
        }
        guard let found = match else { throw FAT32Error.notFound(name) }
        guard !found.entry.isDirectory else { throw FAT32Error.notAFile(name) }
        if found.entry.firstCluster != 0 {
            let fileClusters = try chain(start: found.entry.firstCluster)
            release(fileClusters)
        }
        var mutableDirectory = dirData
        let firstSlot = found.slot - found.longNameSlots
        var index = 0
        while index < found.longNameSlots + 1 {
            let offset = (firstSlot + index) * 32
            if offset >= 0, offset + 32 <= mutableDirectory.count {
                mutableDirectory[offset] = 0xE5
            }
            index += 1
        }
        var offset = 0
        for cluster in clusters {
            let end = offset + geometry.clusterBytes
            try writeCluster(cluster, mutableDirectory.subdata(in: offset..<end))
            offset = end
        }
    }

    // MARK: Integrity

    func integritySnapshot() throws -> FAT32Integrity {
        let fatBytes = Int(geometry.fatSectors) * FAT32Geometry.bytesPerSector
        let first = try FAT32Volume.load(handle: handle, at: baseOffset + geometry.fatOffset, count: fatBytes)
        let second = try FAT32Volume.load(handle: handle,
                                          at: baseOffset + geometry.fatOffset + UInt64(fatBytes),
                                          count: fatBytes)
        var owners: [UInt32: String] = [:]
        var crossLinked = 0
        var directories: [(cluster: UInt32, path: String)] = [(FAT32Geometry.rootCluster, "/")]
        var visited = Set<UInt32>()
        while let item = directories.popLast() {
            if !visited.insert(item.cluster).inserted { continue }
            let directoryChain = try chain(start: item.cluster)
            for cluster in directoryChain {
                if owners[cluster] != nil {
                    crossLinked += 1
                } else {
                    owners[cluster] = item.path
                }
            }
            let (data, _) = try directoryData(start: item.cluster)
            for scanned in scannedEntries(in: data) {
                if scanned.entry.firstCluster == 0 { continue }
                if scanned.entry.isDirectory {
                    directories.append((scanned.entry.firstCluster, item.path + scanned.entry.name + "/"))
                } else {
                    let fileChain = try chain(start: scanned.entry.firstCluster)
                    for cluster in fileChain {
                        if owners[cluster] != nil {
                            crossLinked += 1
                        } else {
                            owners[cluster] = item.path + scanned.entry.name
                        }
                    }
                }
            }
        }
        let used = UInt64(owners.count)
        let info = try FAT32Volume.load(handle: handle,
                                        at: baseOffset + UInt64(FAT32Geometry.fsInfoSector) * 512,
                                        count: 512)
        let reportedFree = le32(info, 488)
        let expected = geometry.totalClusters > used ? geometry.totalClusters - used : 0
        let matches = reportedFree != 0xFFFFFFFF && UInt64(reportedFree) == expected
        let free = matches ? UInt64(reportedFree) : expected
        return FAT32Integrity(clusterBytes: geometry.clusterBytes,
                              totalClusters: geometry.totalClusters,
                              usedClusters: used,
                              freeClusters: free,
                              freeCountMatches: matches,
                              fatCopiesMatch: first == second,
                              crossLinkedClusters: crossLinked)
    }
}

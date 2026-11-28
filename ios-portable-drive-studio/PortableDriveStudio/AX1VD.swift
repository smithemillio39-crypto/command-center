import Foundation

/// The public AX1VD enclosure header. The logical capacity is declared by the
/// header and the file is truncated to hold it; the data region holds a FAT32
/// volume.
struct AX1VDHeader: Equatable {
    let sectorSize: UInt32
    let blockSize: UInt32
    let sectors: UInt64
    let generation: UInt64
    let capacity: UInt64
}

enum AX1VDJournalState: Equatable {
    case clean
    case open
    case unknown

    var text: String {
        switch self {
        case .clean: return "Journal clean."
        case .open: return "Journal marks a volume that was not ejected."
        case .unknown: return "Journal unreadable."
        }
    }
}

/// Result of a structural check. It checks the enclosure and a bounded sample
/// of the data region, not a full filesystem pass.
struct AX1VDVerify {
    let header: AX1VDHeader
    let journalState: AX1VDJournalState
    let bootSectorPresent: Bool
    let sampledBytes: Int
    let expectedBytes: Int64?
    let fileBytes: Int64?
    let allocatedBytes: Int64?
    let verifiedAt: Date

    var sizeComplete: Bool {
        guard let fileBytes, let expectedBytes else { return false }
        return fileBytes >= expectedBytes
    }

    var summary: String {
        var parts: [String] = []
        parts.append("Header and CRC valid.")
        parts.append(journalState.text)
        parts.append(bootSectorPresent
                     ? "FAT32 boot sector present."
                     : "No FAT32 boot sector in the data region.")
        parts.append("Sampled " + String(sampledBytes) + " bytes.")
        if let fileBytes, let expectedBytes, fileBytes < expectedBytes {
            parts.append(String(expectedBytes - fileBytes) + " bytes are missing from the declared size.")
        }
        return parts.joined(separator: " ")
    }
}

enum AX1VDError: LocalizedError {
    case unreadable
    case shortHeader
    case badMagic
    case badCRC
    case badGeometry
    case exists
    case createFailed
    case notInLibrary

    var errorDescription: String? {
        switch self {
        case .unreadable: return "The cartridge could not be read."
        case .shortHeader: return "The file is shorter than an AX1VD header."
        case .badMagic: return "This is not an AX1VD-01 cartridge."
        case .badCRC: return "The AX1VD header checksum does not match."
        case .badGeometry: return "The AX1VD geometry is invalid."
        case .exists: return "A cartridge with that name already exists."
        case .createFailed: return "The cartridge file could not be created."
        case .notInLibrary: return "Only cartridges in the AETHER library can be deleted."
        }
    }
}

/// The first four journal bytes are a mount flag: all zero means clean, 0x01
/// means a volume was mounted and not ejected.
enum AX1VDJournal {
    static func state(at url: URL) -> AX1VDJournalState {
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            try handle.seek(toOffset: UInt64(AX1VD.journalOffset))
            guard let data = try handle.read(upToCount: 4), data.count == 4 else { return .unknown }
            if data.allSatisfy({ $0 == 0 }) { return .clean }
            if data[0] == 0x01, data[1] == 0, data[2] == 0, data[3] == 0 { return .open }
            return .unknown
        } catch {
            return .unknown
        }
    }

    static func setDirty(_ dirty: Bool, at url: URL) throws {
        let handle = try FileHandle(forUpdating: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(AX1VD.journalOffset))
        try handle.write(contentsOf: Data([dirty ? 0x01 : 0x00, 0x00, 0x00, 0x00]))
        try handle.synchronize()
    }
}

enum AX1VD {
    static let magic = Array("AX1VD-01".utf8)
    static let headerSize = 4096
    static let journalOffset = 4096
    static let journalSize = 65536
    static let dataOffset = 4096 + 65536
    static let defaultSector = 4096
    static let defaultBlock = 60 << 10

    private static let maxSample = 1 << 20

    static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in bytes {
            crc ^= UInt32(byte)
            var bit = 0
            while bit < 8 {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xedb88320 : crc >> 1
                bit += 1
            }
        }
        return crc ^ 0xffffffff
    }

    static func header(at url: URL) throws -> AX1VDHeader {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let raw = try handle.read(upToCount: headerSize) ?? Data()
        guard raw.count >= 36 else { throw AX1VDError.shortHeader }
        guard Array(raw.prefix(8)) == magic else { throw AX1VDError.badMagic }

        let sector = readU32(raw, 8)
        let block = readU32(raw, 12)
        let sectors = readU64(raw, 16)
        let generation = readU64(raw, 24)
        let checksum = readU32(raw, 32)
        guard sector >= 512, sector % 512 == 0 else { throw AX1VDError.badGeometry }
        guard block >= sector, block % sector == 0 else { throw AX1VDError.badGeometry }
        guard sectors >= 1 else { throw AX1VDError.badGeometry }
        guard crc32(Array(raw.prefix(32))) == checksum else { throw AX1VDError.badCRC }
        let (capacity, overflow) = sectors.multipliedReportingOverflow(by: UInt64(sector))
        guard !overflow else { throw AX1VDError.badGeometry }
        return AX1VDHeader(sectorSize: sector,
                           blockSize: block,
                           sectors: sectors,
                           generation: generation,
                           capacity: capacity)
    }

    /// Writes the header, clears the journal and extends the file to hold the
    /// declared capacity so the data region exists on disk.
    static func create(at url: URL, capacity: UInt64) throws {
        let sectorSize = UInt64(defaultSector)
        let blockSize = UInt64(defaultBlock)
        guard sectorSize >= 512, sectorSize % 512 == 0 else { throw AX1VDError.badGeometry }
        guard blockSize >= sectorSize, blockSize % sectorSize == 0 else { throw AX1VDError.badGeometry }
        let sectors = capacity / sectorSize
        guard sectors >= 1 else { throw AX1VDError.badGeometry }
        let declared = sectors * sectorSize
        let total = UInt64(dataOffset).addingReportingOverflow(declared)
        guard !total.overflow else { throw AX1VDError.badGeometry }
        guard !FileManager.default.fileExists(atPath: url.path) else { throw AX1VDError.exists }
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw AX1VDError.createFailed
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        var header = Data(count: headerSize)
        header.replaceSubrange(0..<8, with: Data(magic))
        writeU32(UInt32(defaultSector), at: 8, into: &header)
        writeU32(UInt32(defaultBlock), at: 12, into: &header)
        writeU64(sectors, at: 16, into: &header)
        writeU64(0, at: 24, into: &header)
        writeU32(crc32(Array(header.prefix(32))), at: 32, into: &header)
        try handle.write(contentsOf: header)
        try handle.seek(toOffset: UInt64(journalOffset))
        try handle.write(contentsOf: Data(repeating: 0, count: 4))
        try handle.truncate(atOffset: total.partialValue)
        try handle.synchronize()
    }

    static func verify(at url: URL) throws -> AX1VDVerify {
        let header = try self.header(at: url)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey])
        let fileBytes = values?.fileSize.map { Int64($0) }
        let allocated = (values?.totalFileAllocatedSize ?? values?.fileSize).map { Int64($0) }
        let declared = UInt64(dataOffset).addingReportingOverflow(header.capacity)
        let expected = declared.overflow ? Int64.max : Int64(clamping: declared.partialValue)
        let available = max(0, (fileBytes ?? 0) - Int64(dataOffset))
        let sampleLength = Int(min(header.capacity,
                                   UInt64(maxSample),
                                   UInt64(clamping: available)))
        try handle.seek(toOffset: UInt64(dataOffset))
        let sample = try handle.read(upToCount: sampleLength) ?? Data()
        let bytes = [UInt8](sample)
        let bootPresent = bytes.count >= 512
            && bytes[510] == 0x55
            && bytes[511] == 0xAA
            && bytes[82] == 0x46
            && bytes[83] == 0x41
            && bytes[84] == 0x54
            && bytes[85] == 0x33
            && bytes[86] == 0x32
        return AX1VDVerify(header: header,
                           journalState: AX1VDJournal.state(at: url),
                           bootSectorPresent: bootPresent,
                           sampledBytes: bytes.count,
                           expectedBytes: expected,
                           fileBytes: fileBytes,
                           allocatedBytes: allocated,
                           verifiedAt: Date())
    }

    private static func readU32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    private static func readU64(_ data: Data, _ offset: Int) -> UInt64 {
        var value: UInt64 = 0
        var index = 0
        while index < 8 {
            value |= UInt64(data[offset + index]) << UInt64(index * 8)
            index += 1
        }
        return value
    }

    private static func writeU32(_ value: UInt32, at offset: Int, into data: inout Data) {
        data[offset] = UInt8(value & 0xFF)
        data[offset + 1] = UInt8((value >> 8) & 0xFF)
        data[offset + 2] = UInt8((value >> 16) & 0xFF)
        data[offset + 3] = UInt8((value >> 24) & 0xFF)
    }

    private static func writeU64(_ value: UInt64, at offset: Int, into data: inout Data) {
        var index = 0
        while index < 8 {
            data[offset + index] = UInt8((value >> UInt64(index * 8)) & 0xFF)
            index += 1
        }
    }
}

import Foundation

/// The public AX1VD enclosure header. The logical capacity is declared by the
/// header; the file itself stays sparse until data is written.
struct AX1VDHeader: Equatable {
    let sectorSize: UInt32
    let blockSize: UInt32
    let sectors: UInt64
    let generation: UInt64
    let capacity: UInt64
}

/// Result of a structural check. This intentionally checks the enclosure and
/// a bounded sample, not an invented full-filesystem result.
struct AX1VDVerify {
    let header: AX1VDHeader
    let journalEmpty: Bool
    let sampledBytes: Int
    let fileBytes: Int64?
    let allocatedBytes: Int64?
    let verifiedAt: Date

    var summary: String {
        "Header and CRC valid; journal \(journalEmpty ? "empty" : "not empty"); "
            + "sampled \(sampledBytes) bytes."
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

enum AX1VD {
    static let magic = Array("AX1VD-01".utf8)
    static let headerSize = 4096
    static let journalOffset = 4096
    static let journalSize = 65536
    static let dataOffset = 4096 + 65536
    static let defaultSector = 4096
    private static let maxSample = 1 << 20

    static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xedb88320 : crc >> 1
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
        guard sector >= 512, sectors >= 1 else { throw AX1VDError.badGeometry }
        guard crc32(Array(raw.prefix(32))) == checksum else { throw AX1VDError.badCRC }
        let (capacity, overflow) = sectors.multipliedReportingOverflow(by: UInt64(sector))
        guard !overflow else { throw AX1VDError.badGeometry }
        return AX1VDHeader(sectorSize: sector, blockSize: block,
                           sectors: sectors, generation: generation,
                           capacity: capacity)
    }

    static func create(at url: URL, capacity: UInt64) throws {
        let sector = UInt64(defaultSector)
        guard capacity >= sector else { throw AX1VDError.badGeometry }
        let sectors = capacity / sector
        guard sectors >= 1 else { throw AX1VDError.badGeometry }
        guard !FileManager.default.fileExists(atPath: url.path) else { throw AX1VDError.exists }
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw AX1VDError.createFailed
        }

        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        var header = Data(repeating: 0, count: headerSize)
        header.replaceSubrange(0..<8, with: Data(magic))
        writeU32(UInt32(defaultSector), at: 8, into: &header)
        writeU32(UInt32(60 << 10), at: 12, into: &header)
        writeU64(sectors, at: 16, into: &header)
        writeU64(0, at: 24, into: &header)
        writeU32(crc32(Array(header.prefix(32))), at: 32, into: &header)
        try handle.write(contentsOf: header)
        try handle.seek(toOffset: UInt64(journalOffset))
        try handle.write(contentsOf: Data(repeating: 0, count: 4))
        try handle.synchronize()
    }

    static func verify(at url: URL) throws -> AX1VDVerify {
        let header = try self.header(at: url)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(journalOffset))
        let journal = try handle.read(upToCount: 4) ?? Data()
        let journalEmpty = journal.count == 4 && journal.allSatisfy { $0 == 0 }
        let sampleLength = Int(min(header.capacity, UInt64(maxSample)))
        try handle.seek(toOffset: UInt64(dataOffset))
        let sample = try handle.read(upToCount: sampleLength) ?? Data()
        let values = try? url.resourceValues(forKeys: [
            .fileSizeKey, .totalFileAllocatedSizeKey, .contentModificationDateKey
        ])
        let fileBytes = values?.fileSize.map { Int64($0) }
        let allocated = (values?.totalFileAllocatedSize ?? values?.fileSize).map { Int64($0) }
        return AX1VDVerify(header: header, journalEmpty: journalEmpty,
                           sampledBytes: sample.count, fileBytes: fileBytes,
                           allocatedBytes: allocated, verifiedAt: Date())
    }

    private static func readU32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    private static func readU64(_ data: Data, _ offset: Int) -> UInt64 {
        var value: UInt64 = 0
        for index in 0..<8 {
            value |= UInt64(data[offset + index]) << UInt64(index * 8)
        }
        return value
    }

    private static func writeU32(_ value: UInt32, at offset: Int, into data: inout Data) {
        var little = value.littleEndian
        let bytes = withUnsafeBytes(of: &little) { Data($0) }
        data.replaceSubrange(offset..<(offset + 4), with: bytes)
    }

    private static func writeU64(_ value: UInt64, at offset: Int, into data: inout Data) {
        var little = value.littleEndian
        let bytes = withUnsafeBytes(of: &little) { Data($0) }
        data.replaceSubrange(offset..<(offset + 8), with: bytes)
    }
}

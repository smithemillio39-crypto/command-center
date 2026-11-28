import Foundation

enum FixtureError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        }
    }
}

func note(_ text: String) {
    print("fixture: " + text)
}

func stop(_ text: String) -> Never {
    FileHandle.standardError.write(Data(("fixture: " + text + "\n").utf8))
    exit(1)
}

func makeImage(at root: URL) throws {
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let capacity: UInt64 = 320 * 1024 * 1024
    let image = root.appendingPathComponent("plain.img")
    try? FileManager.default.removeItem(at: image)
    guard FileManager.default.createFile(atPath: image.path, contents: nil) else {
        throw FixtureError.message("could not create the image")
    }
    let handle = try FileHandle(forUpdating: image)
    defer { try? handle.close() }
    try handle.truncate(atOffset: capacity)
    let geometry = try FAT32Geometry.make(capacity: capacity, clusterSize: nil)
    note("geometry: " + String(geometry.totalClusters) + " clusters of " + String(geometry.clusterBytes) + " bytes")
    try FAT32Volume.format(handle: handle,
                           baseOffset: 0,
                           geometry: geometry,
                           label: "AETHER TEST",
                           volumeID: 0x41455448)
    let filesystem = try FAT32Volume(handle: handle, baseOffset: 0, geometry: geometry)
    let greeting = Data("AX1VD fixture volume\n".utf8)
    _ = try filesystem.createFile(in: FAT32Geometry.rootCluster, name: "readme.txt", data: greeting)
    let longName = "field notes and a long file name.txt"
    var payload = Data()
    var index = 0
    while index < 180 * 1024 {
        payload.append(UInt8((index * 31 + 7) % 251))
        index += 1
    }
    _ = try filesystem.createFile(in: FAT32Geometry.rootCluster, name: longName, data: payload)
    _ = try filesystem.createFile(in: FAT32Geometry.rootCluster, name: "SHORT.TXT", data: Data("short name\n".utf8))
    _ = try filesystem.createFile(in: FAT32Geometry.rootCluster, name: "delete-me.txt", data: Data("temporary\n".utf8))
    try filesystem.deleteFile(in: FAT32Geometry.rootCluster, name: "delete-me.txt")
    try filesystem.flush()

    // Re-open so every check below reads the volume that is really on disk.
    let onDisk = try FAT32Volume(handle: handle, baseOffset: 0, geometry: geometry)
    let listing = try onDisk.list(directory: FAT32Geometry.rootCluster)
    for entry in listing {
        note("entry: " + entry.name + " " + String(entry.size) + " bytes")
    }
    guard listing.count == 3 else { throw FixtureError.message("expected 3 files, found " + String(listing.count)) }
    let readBack = try onDisk.readFile(in: FAT32Geometry.rootCluster, name: longName)
    guard readBack == payload else { throw FixtureError.message("the long-name file did not round-trip") }
    let readme = try onDisk.readFile(in: FAT32Geometry.rootCluster, name: "readme.txt")
    guard readme == greeting else { throw FixtureError.message("readme.txt did not round-trip") }
    let short = try onDisk.readFile(in: FAT32Geometry.rootCluster, name: "SHORT.TXT")
    guard short == Data("short name\n".utf8) else { throw FixtureError.message("SHORT.TXT did not round-trip") }
    let snapshot = try onDisk.integritySnapshot()
    guard snapshot.fatCopiesMatch else { throw FixtureError.message("the FAT copies differ") }
    guard snapshot.crossLinkedClusters == 0 else {
        throw FixtureError.message(String(snapshot.crossLinkedClusters) + " cross-linked clusters")
    }
    guard snapshot.freeCountMatches else { throw FixtureError.message("the FSInfo free count is wrong") }
    note("free " + String(snapshot.freeClusters) + " of " + String(snapshot.totalClusters) + " clusters")
    note("wrote " + image.path)
}

func makeCartridge(at root: URL) throws {
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let url = root.appendingPathComponent("cartridge.vdrive")
    try? FileManager.default.removeItem(at: url)
    let capacity: UInt64 = 320 * 1024 * 1024
    try AX1VD.create(at: url, capacity: capacity)
    let descriptor = try AX1VDVolume.format(cartridgeAt: url, label: "AETHER CART", clusterSize: nil)
    note("cartridge geometry: " + String(descriptor.geometry.totalClusters) + " clusters")
    let body = Data("written through AX1VDVolume\n".utf8)
    let volume = try AX1VDVolume.mount(at: url)
    try volume.writeFile("cartridge note.txt", in: [], data: body)
    let readBack = try volume.readFile("cartridge note.txt", in: [])
    guard readBack == body else { throw FixtureError.message("the cartridge file did not round-trip") }
    note("cartridge free bytes: " + String(volume.freeBytes))
    try volume.eject()
    let verify = try AX1VD.verify(at: url)
    note(verify.summary)
    guard verify.journalState == .clean else { throw FixtureError.message("the journal was not clean after eject") }
    guard verify.bootSectorPresent else { throw FixtureError.message("no FAT32 boot sector in the data region") }
    guard verify.sizeComplete else { throw FixtureError.message("the cartridge is shorter than its declared capacity") }
    let integrity = try AX1VDVolume.integrityCheck(at: url)
    guard integrity.isHealthy else { throw FixtureError.message(integrity.summary) }
    note(integrity.summary)
    note("wrote " + url.path)
}

func openImage(_ path: String) throws -> (handle: FileHandle, geometry: FAT32Geometry) {
    let url = URL(fileURLWithPath: path)
    let handle = try FileHandle(forReadingFrom: url)
    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { UInt64(clamping: $0) } ?? 0
    let geometry = try FAT32Volume.validate(handle: handle, baseOffset: 0, expectedCapacity: size)
    return (handle, geometry)
}

func catalogue(imagePath: String) throws {
    let opened = try openImage(imagePath)
    defer { try? opened.handle.close() }
    let filesystem = try FAT32Volume(handle: opened.handle, baseOffset: 0, geometry: opened.geometry)
    let entries = try filesystem.list(directory: FAT32Geometry.rootCluster)
    for entry in entries {
        print(entry.name + "\t" + String(entry.size))
    }
}

func cat(imagePath: String, name: String) throws {
    let opened = try openImage(imagePath)
    defer { try? opened.handle.close() }
    let filesystem = try FAT32Volume(handle: opened.handle, baseOffset: 0, geometry: opened.geometry)
    let data = try filesystem.readFile(in: FAT32Geometry.rootCluster, name: name)
    try FileHandle.standardOutput.write(contentsOf: data)
}

let arguments = CommandLine.arguments
if arguments.count < 3 {
    stop("usage: fat32fixture build|cartridge|catalogue|cat <path> [name]")
}
let command = arguments[1]
let target = arguments[2]

do {
    switch command {
    case "build":
        try makeImage(at: URL(fileURLWithPath: target, isDirectory: true))
    case "cartridge":
        try makeCartridge(at: URL(fileURLWithPath: target, isDirectory: true))
    case "catalogue":
        try catalogue(imagePath: target)
    case "cat":
        if arguments.count < 4 { stop("cat needs a file name") }
        try cat(imagePath: target, name: arguments[3])
    default:
        stop("unknown command " + command)
    }
} catch {
    stop(error.localizedDescription)
}

import Foundation

/// One app tile on the Launch grid. `target` is an agent alias, a URI or a full
/// path - the PC agent resolves it.
struct Launcher: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var symbol: String
    var target: String

    init(id: UUID = UUID(), title: String, symbol: String, target: String) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.target = target
    }
}

/// Actions the PC agent understands. Raw values are the wire protocol.
enum Command: String, Hashable {
    case volumeUp = "volume.up"
    case volumeDown = "volume.down"
    case volumeMute = "volume.mute"
    case volumeSet = "volume.set"
    case playPause = "media.playpause"
    case nextTrack = "media.next"
    case prevTrack = "media.prev"
    case lock = "system.lock"
    case sleep = "system.sleep"
    case displayOff = "system.displayOff"
    case shutdown = "system.shutdown"
    case restart = "system.restart"
    case cancelShutdown = "system.cancelShutdown"
    case launch = "app.launch"
}

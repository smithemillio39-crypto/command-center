import Foundation
import GameController

/// Maps a connected Bluetooth/USB-C controller straight onto PC commands, so the
/// controller is useful without looking at the screen.
@MainActor
final class ControllerMonitor {
    var onCommand: ((Command) -> Void)?
    var onChange: ((String?) -> Void)?

    private var observers: [NSObjectProtocol] = []
    private var attached: [GCController] = []

    func start() {
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        )
        observers.append(
            center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        )
        refresh()
    }

    deinit {
        let center = NotificationCenter.default
        for observer in observers { center.removeObserver(observer) }
    }

    private func refresh() {
        for controller in attached { clear(controller) }
        attached = GCController.controllers()
        for controller in attached {
            bind(controller)
            controller.playerIndex = .index1
        }
        onChange?(attached.first?.vendorName)
    }

    private func bind(_ controller: GCController) {
        if let pad = controller.extendedGamepad {
            press(pad.buttonA) { .playPause }
            press(pad.buttonB) { .volumeMute }
            press(pad.buttonX) { .prevTrack }
            press(pad.buttonY) { .nextTrack }
            press(pad.dpad.up) { .volumeUp }
            press(pad.dpad.down) { .volumeDown }
            press(pad.leftShoulder) { .prevTrack }
            press(pad.rightShoulder) { .nextTrack }
        } else if let pad = controller.microGamepad {
            press(pad.buttonA) { .playPause }
            press(pad.buttonX) { .volumeMute }
            press(pad.dpad.up) { .volumeUp }
            press(pad.dpad.down) { .volumeDown }
        }
    }

    private func clear(_ controller: GCController) {
        if let pad = controller.extendedGamepad {
            pad.buttonA.pressedChangedHandler = nil
            pad.buttonB.pressedChangedHandler = nil
            pad.buttonX.pressedChangedHandler = nil
            pad.buttonY.pressedChangedHandler = nil
            pad.dpad.up.pressedChangedHandler = nil
            pad.dpad.down.pressedChangedHandler = nil
            pad.leftShoulder.pressedChangedHandler = nil
            pad.rightShoulder.pressedChangedHandler = nil
        }
        if let pad = controller.microGamepad {
            pad.buttonA.pressedChangedHandler = nil
            pad.buttonX.pressedChangedHandler = nil
            pad.dpad.up.pressedChangedHandler = nil
            pad.dpad.down.pressedChangedHandler = nil
        }
    }

    private func press(_ button: GCControllerButtonInput, command: @escaping () -> Command) {
        button.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            let resolved = command()
            Task { @MainActor in self?.onCommand?(resolved) }
        }
    }
}

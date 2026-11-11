import GameController
import SimCore

/// Game controllers (Xbox, PlayStation, MFi) and Bluetooth keyboards.
///
/// Keyboard: Up / W accelerate, Down / S brake, Left / A and Right / D steer,
/// [ and ] turn signals, Backspace cancel signal, I dashboard, G GPS, N engine, H horn, Escape pause,
/// R radio on/off, comma and period previous/next song.
///
/// Controller: right trigger accelerate, left trigger brake, left stick steer,
/// L1 / R1 turn signals, A dashboard, X GPS, Y engine, B horn, Menu pause,
/// D-pad up radio on/off, D-pad left/right previous/next song.
final class HardwareInput {
    var onAction: ((DrivingAction) -> Void)?
    private var observers: [NSObjectProtocol] = []

    func start() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .GCKeyboardDidConnect, object: nil, queue: .main) { [weak self] _ in
            self?.attachKeyboard()
        })
        observers.append(center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] note in
            if let controller = note.object as? GCController { self?.attach(controller) }
        })
        attachKeyboard()
        GCController.controllers().forEach { attach($0) }
    }

    func stop() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        GCKeyboard.coalesced?.keyboardInput?.keyChangedHandler = nil
    }

    private func attachKeyboard() {
        GCKeyboard.coalesced?.keyboardInput?.keyChangedHandler = { [weak self] _, _, key, pressed in
            guard pressed, let action = HardwareInput.action(for: key) else { return }
            DispatchQueue.main.async { self?.onAction?(action) }
        }
    }

    private static func action(for key: GCKeyCode) -> DrivingAction? {
        switch key {
        case .openBracket: return .signal(.left)
        case .closeBracket: return .signal(.right)
        case .deleteOrBackspace: return .cancelSignal
        case .keyI: return .speakDashboard
        case .keyG: return .speakRoadAhead
        case .keyE: return .speakAroundMe
        case .keyN: return .toggleEngine
        case .keyH: return .horn
        case .escape: return .pause
        case .keyR: return .toggleRadio
        case .period: return .nextSong
        case .comma: return .previousSong
        default: return nil
        }
    }

    private func attach(_ controller: GCController) {
        guard let pad = controller.extendedGamepad else { return }
        func bind(_ button: GCControllerButtonInput, _ action: DrivingAction) {
            button.pressedChangedHandler = { [weak self] _, _, pressed in
                if pressed { self?.onAction?(action) }
            }
        }
        bind(pad.leftShoulder, .signal(.left))
        bind(pad.rightShoulder, .signal(.right))
        bind(pad.buttonA, .speakDashboard)
        bind(pad.buttonX, .speakRoadAhead)
        bind(pad.buttonY, .toggleEngine)
        bind(pad.buttonB, .horn)
        bind(pad.buttonMenu, .pause)
        bind(pad.dpad.up, .toggleRadio)
        bind(pad.dpad.right, .nextSong)
        bind(pad.dpad.left, .previousSong)
        bind(pad.dpad.down, .speakAroundMe)
    }

    /// Continuous controls, polled every frame.
    func poll() -> DrivingInput {
        var input = DrivingInput()
        if let kb = GCKeyboard.coalesced?.keyboardInput {
            func down(_ keys: GCKeyCode...) -> Bool { keys.contains { kb.button(forKeyCode: $0)?.isPressed == true } }
            if down(.upArrow, .keyW) { input.throttle = 1 }
            if down(.downArrow, .keyS) { input.brake = 1 }
            if down(.leftArrow, .keyA) { input.steer -= 1 }
            if down(.rightArrow, .keyD) { input.steer += 1 }
        }
        for controller in GCController.controllers() {
            guard let pad = controller.extendedGamepad else { continue }
            input.throttle = max(input.throttle, Double(pad.rightTrigger.value))
            input.brake = max(input.brake, Double(pad.leftTrigger.value))
            let x = Double(pad.leftThumbstick.xAxis.value)
            if abs(x) > 0.08 { input.steer += x }
        }
        input.steer = min(1, max(-1, input.steer))
        return input
    }
}

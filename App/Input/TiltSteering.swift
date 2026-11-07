import CoreMotion
import UIKit

/// Steering by tilting the phone (held sideways): lower the right end to steer right, the left end to steer left.
///
/// It measures how high one end of the phone is compared to the other, so it works however the phone is held:
/// upright like a steering wheel, tilted back, or flat like a tray. The position you hold the phone in when
/// driving starts (or resumes) counts as "straight".
final class TiltSteering {
    private let manager = CMMotionManager()
    private var neutral: Double?

    /// Degrees of tilt for full steering lock.
    var rangeDegrees: Double = 25
    var invert = false

    var isAvailable: Bool { manager.isDeviceMotionAvailable }

    func start() {
        guard isAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60
        manager.startDeviceMotionUpdates()
        neutral = nil
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }

    /// Treat the current phone position as straight ahead.
    func recenter() {
        neutral = nil
    }

    /// -1 (full left) ... 1 (full right)
    func steer(orientation: UIInterfaceOrientation) -> Double {
        guard let g = manager.deviceMotion?.gravity else { return 0 }
        // Device +y runs along the phone's long side, toward the top of the phone (away from the charging port).
        // Held sideways, that axis points left or right, so gravity along it tells how far one end is lowered,
        // whether the screen faces you or the ceiling.
        //   Port on the right (landscape right): top of the phone is on the left; lowering the right end
        //   (the port end) makes g.y negative.
        //   Port on the left (landscape left): top of the phone is on the right; lowering the right end makes g.y positive.
        let alongLongSide = orientation == .landscapeLeft ? g.y : -g.y
        let angle = asin(max(-1, min(1, alongLongSide)))
        if neutral == nil { neutral = angle }
        let delta = angle - (neutral ?? angle)

        let deadZone = 1.5 * Double.pi / 180
        let range = max(5, rangeDegrees) * Double.pi / 180
        guard abs(delta) > deadZone else { return 0 }
        let magnitude = min(1, (abs(delta) - deadZone) / (range - deadZone))
        let value = delta > 0 ? magnitude : -magnitude
        return invert ? -value : value
    }
}

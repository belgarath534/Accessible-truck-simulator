import CoreMotion
import UIKit

/// Steering by rotating the phone like a steering wheel (landscape, screen facing you).
/// The position you hold the phone in when driving starts (or resumes) counts as "straight".
final class TiltSteering {
    private let manager = CMMotionManager()
    private var neutral: Double?

    /// Degrees of rotation for full steering lock.
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
        // Rotation of gravity within the screen plane. Device +y points to the top of the phone.
        // In landscape-right the top of the phone is on your left; in landscape-left it's on your right.
        let angle: Double
        switch orientation {
        case .landscapeLeft: angle = atan2(g.y, g.x)
        default: angle = atan2(-g.y, -g.x)
        }
        if neutral == nil { neutral = angle }
        var delta = angle - (neutral ?? angle)
        if delta > .pi { delta -= 2 * .pi }
        if delta < -.pi { delta += 2 * .pi }

        let deadZone = 1.5 * Double.pi / 180
        let range = max(5, rangeDegrees) * Double.pi / 180
        guard abs(delta) > deadZone else { return 0 }
        let magnitude = min(1, (abs(delta) - deadZone) / (range - deadZone))
        let value = delta > 0 ? magnitude : -magnitude
        return invert ? -value : value
    }
}

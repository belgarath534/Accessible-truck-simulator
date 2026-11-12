import CoreMotion
import UIKit

/// The phone as a yoke, held sideways. Turn it like a wheel to bank (lower the right end to bank right).
/// Tilt the top edge back toward you to raise the nose, forward to lower it.
/// The way you hold the phone when the flight starts (or when you recenter) counts as level.
final class YokeInput {
    private let manager = CMMotionManager()
    private var neutral: (roll: Double, pitch: Double)?
    private var samples: [(roll: Double, pitch: Double)] = []

    var rangeDegrees = 22.0
    var invertPitch = false

    var isAvailable: Bool { manager.isDeviceMotionAvailable }

    func start() {
        guard isAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60
        manager.startDeviceMotionUpdates()
        recenter()
    }

    func stop() { manager.stopDeviceMotionUpdates() }

    func recenter() {
        neutral = nil
        samples = []
    }

    /// pitch: -1 nose down ... 1 nose up; roll: -1 left ... 1 right.
    func read(orientation: UIInterfaceOrientation) -> (pitch: Double, roll: Double) {
        guard let g = manager.deviceMotion?.gravity else { return (0, 0) }
        // Along the long side (device y), as in the truck sim: how much lower one end is.
        let along = orientation == .landscapeLeft ? g.y : -g.y
        let roll = asin(max(-1, min(1, along)))
        // Screen facing up more (top edge tilted back toward you) makes gravity point out of the back: -z.
        let pitch = asin(max(-1, min(1, -g.z)))
        guard let n = neutral else {
            samples.append((roll, pitch))
            if samples.count >= 30 {
                neutral = (samples.map(\.roll).reduce(0, +) / 30, samples.map(\.pitch).reduce(0, +) / 30)
            }
            return (0, 0)
        }
        let p = shape(pitch - n.pitch)
        return (invertPitch ? -p : p, shape(roll - n.roll))
    }

    private func shape(_ delta: Double) -> Double {
        let degree = Double.pi / 180
        let dead = 3 * degree, range = max(8, rangeDegrees) * degree
        guard abs(delta) > dead else { return 0 }
        let v = pow(min(1, (abs(delta) - dead) / (range - dead)), 1.4)
        return delta > 0 ? v : -v
    }
}

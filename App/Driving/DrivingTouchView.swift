import SimCore
import SwiftUI
import UIKit

/// The full-screen driving surface.
///
/// Accessibility: it is a single element with the "allows direct interaction" trait, so with VoiceOver on,
/// touches pass straight through to the game instead of being VoiceOver gestures. The game speaks for itself.
/// The drawing is a simple top-down view for sighted players and is never needed to play.
final class DrivingTouchView: UIView {
    weak var controller: DrivingController?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        isOpaque = true
        backgroundColor = UIColor(red: 0.13, green: 0.22, blue: 0.13, alpha: 1)
        contentMode = .redraw
        isAccessibilityElement = true
        accessibilityLabel = "Driving area"
        accessibilityHint = "Touches go directly to the game. Two-finger swipe down for the pause menu."
        accessibilityTraits = .allowsDirectInteraction
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            UIAccessibility.post(notification: .screenChanged, argument: self)
        }
    }

    // MARK: Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        controller?.touchesChanged(.began, touches, in: self)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        controller?.touchesChanged(.moved, touches, in: self)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        controller?.touchesChanged(.ended, touches, in: self)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        controller?.touchesChanged(.cancelled, touches, in: self)
    }

    // VoiceOver's own gestures, in case they reach us.
    override func accessibilityPerformMagicTap() -> Bool {
        controller?.perform(.speakDashboard)
        return true
    }

    override func accessibilityPerformEscape() -> Bool {
        controller?.perform(.pause)
        return true
    }

    // MARK: Drawing (for sighted players)

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), let controller else { return }
        let truck = controller.session.truck
        let road = controller.session.road
        let w = bounds.width, h = bounds.height
        let ppm = w / 22 // pixels per metre
        let laneCenterX = w / 2

        // Road: our lane is centred; the oncoming lane is to the left.
        let laneW = road.laneWidth * ppm
        let roadLeft = laneCenterX - laneW * 1.5
        let roadRight = laneCenterX + laneW * 0.5
        ctx.setFillColor(UIColor(white: 0.25, alpha: 1).cgColor)
        ctx.fill(CGRect(x: roadLeft, y: 0, width: roadRight - roadLeft, height: h))

        // Rumble strips.
        ctx.setFillColor(UIColor(white: 0.4, alpha: 1).cgColor)
        ctx.fill(CGRect(x: roadRight, y: 0, width: 0.4 * ppm, height: h))

        // Lane markings scroll with distance travelled.
        let dash = 4 * ppm, gap = 8 * ppm
        let offset = CGFloat(truck.position.truncatingRemainder(dividingBy: 12)) * ppm
        ctx.setFillColor(UIColor.white.cgColor)
        var y = -dash - gap + offset
        while y < h {
            ctx.fill(CGRect(x: laneCenterX - laneW / 2 - 2, y: y, width: 4, height: dash))
            y += dash + gap
        }
        ctx.fill(CGRect(x: roadLeft, y: 0, width: 3, height: h))
        ctx.fill(CGRect(x: roadRight - 3, y: 0, width: 3, height: h))

        // Curve indicator at the top: an arrow when the road bends.
        let k = road.curvature(at: truck.position + 60)
        if abs(k) > 0.0005 {
            let arrow = k > 0 ? "Curve right ➡︎" : "⬅︎ Curve left"
            drawText(arrow, at: CGPoint(x: laneCenterX, y: 20), size: 22, color: .yellow, centered: true)
        }

        // Other vehicles: oncoming in the left lane, slower ones ahead.
        for v in controller.session.traffic {
            let rel = CGFloat(v.position - truck.position)
            let carY = h * 0.7 - rel * ppm
            guard carY > -100 && carY < h + 100 else { continue }
            let carX = laneCenterX + CGFloat(v.lane) * ppm
            let carW = CGFloat(v.halfWidth * 2) * ppm, carL = CGFloat(v.length) * ppm
            ctx.setFillColor((v.oncoming ? UIColor.systemBlue : UIColor.systemOrange).cgColor)
            ctx.fill(CGRect(x: carX - carW / 2, y: carY - carL / 2, width: carW, height: carL))
        }

        // Truck.
        ctx.saveGState()
        let truckX = laneCenterX + CGFloat(truck.lateralOffset) * ppm
        let truckY = h * 0.7
        ctx.translateBy(x: truckX, y: truckY)
        ctx.rotate(by: CGFloat(truck.headingError))
        let truckW = 2.5 * ppm, truckL = 7 * ppm
        ctx.setFillColor(UIColor.systemRed.cgColor)
        ctx.fill(CGRect(x: -truckW / 2, y: -truckL / 2, width: truckW, height: truckL * 0.3))
        ctx.setFillColor(UIColor(white: 0.85, alpha: 1).cgColor)
        ctx.fill(CGRect(x: -truckW / 2, y: -truckL / 2 + truckL * 0.33, width: truckW, height: truckL * 0.67))
        ctx.restoreGState()

        // Dashboard text.
        let units = controller.settings.units
        let speed = units.speed(truck.speed)
        let unit = units == .metric ? "km/h" : "mph"
        drawText("\(speed) \(unit)", at: CGPoint(x: 20, y: 20), size: 34, color: .white, centered: false)
        var status: [String] = []
        switch truck.engine {
        case .off: status.append("Engine off")
        case .starting: status.append("Starting…")
        case .running: status.append("Gear \(truck.gearIndex + 1)  \(Int(truck.rpm)) rpm")
        }
        if case let .on(side) = truck.signal { status.append(side == .left ? "◀︎ signal" : "signal ▶︎") }
        status.append("Fuel \(Int(truck.fuelLiters / controller.session.spec.fuelCapacityLiters * 100))%")
        if let remaining = controller.session.remaining {
            status.append("Drop-off: \(units.distance(max(0, remaining)))")
        }
        drawText(status.joined(separator: "   "), at: CGPoint(x: 20, y: 64), size: 17, color: .white, centered: false)
    }

    private func drawText(_ text: String, at point: CGPoint, size: CGFloat, color: UIColor, centered: Bool) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: size, weight: .semibold),
            .foregroundColor: color,
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let s = str.size()
        str.draw(at: CGPoint(x: centered ? point.x - s.width / 2 : point.x, y: point.y))
    }
}

/// SwiftUI wrapper.
struct DrivingSurface: UIViewRepresentable {
    let controller: DrivingController
    let isPaused: Bool

    func makeUIView(context: Context) -> DrivingTouchView {
        let view = DrivingTouchView(frame: .zero)
        view.controller = controller
        controller.view = view
        return view
    }

    func updateUIView(_ view: DrivingTouchView, context: Context) {
        view.accessibilityElementsHidden = isPaused
        view.isUserInteractionEnabled = !isPaused
    }
}

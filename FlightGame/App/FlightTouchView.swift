import FlightCore
import SwiftUI
import UIKit

/// The flying surface. One VoiceOver element with "allows direct interaction", so touches go straight to the
/// game with VoiceOver on, and the game speaks for itself.
final class FlightTouchView: UIView {
    weak var controller: FlightController?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        isAccessibilityElement = true
        // Short on purpose: VoiceOver reads this when the flight starts, right before the instructor speaks.
        accessibilityLabel = "Cockpit"
        accessibilityTraits = .allowsDirectInteraction
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            UIAccessibility.post(notification: .screenChanged, argument: self)
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { controller?.touches(.began, touches, in: self) }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { controller?.touches(.moved, touches, in: self) }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { controller?.touches(.ended, touches, in: self) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { controller?.touches(.cancelled, touches, in: self) }

    override func accessibilityPerformMagicTap() -> Bool { controller?.perform(.speakInstruments); return true }
    override func accessibilityPerformEscape() -> Bool { controller?.pause(); return true }
}

struct FlightSurface: UIViewRepresentable {
    let controller: FlightController

    func makeUIView(context: Context) -> FlightTouchView {
        let v = FlightTouchView()
        v.controller = controller
        controller.view = v
        return v
    }

    func updateUIView(_ view: FlightTouchView, context: Context) {}
}

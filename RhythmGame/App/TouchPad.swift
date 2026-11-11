import BeatCore
import SwiftUI
import UIKit

/// A full-screen surface that turns touches into moves with exact times.
///
/// Accessibility: one element with "allows direct interaction", so with VoiceOver on, touches go straight
/// to the game (no double tap, no delay). A two-finger tap, VoiceOver's magic tap or the escape scrub stops.
final class TouchPadView: UIView {
    var onMove: ((Move, TimeInterval) -> Void)?
    var onStop: (() -> Void)?

    private struct Track { var start: CGPoint; var time: TimeInterval; var done: Bool }
    private var tracks: [ObjectIdentifier: Track] = [:]
    private static let swipeDistance: CGFloat = 32

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        isAccessibilityElement = true
        accessibilityTraits = .allowsDirectInteraction
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self else { return }
            UIAccessibility.post(notification: .screenChanged, argument: self)
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { tracks[ObjectIdentifier(t)] = Track(start: t.location(in: self), time: t.timestamp, done: false) }
        if (event?.allTouches?.count ?? touches.count) >= 2 {
            for k in tracks.keys { tracks[k]?.done = true }
            onStop?()
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            let id = ObjectIdentifier(t)
            guard let track = tracks[id], !track.done else { continue }
            let p = t.location(in: self)
            let dx = p.x - track.start.x, dy = p.y - track.start.y
            guard hypot(dx, dy) >= Self.swipeDistance else { continue }
            tracks[id]?.done = true
            let move: Move? = abs(dx) > abs(dy) ? (dx < 0 ? .left : .right) : (dy < 0 ? .up : nil)
            // The swipe counts from the moment your finger touched down: that's what you time to the beat.
            if let move { onMove?(move, track.time) }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            let id = ObjectIdentifier(t)
            if let track = tracks[id], !track.done, t.timestamp - track.time < 0.4 { onMove?(.tap, track.time) }
            tracks[id] = nil
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { tracks[ObjectIdentifier(t)] = nil }
    }

    override func accessibilityPerformMagicTap() -> Bool { onStop?(); return true }
    override func accessibilityPerformEscape() -> Bool { onStop?(); return true }
}

struct TouchPad: UIViewRepresentable {
    var label: String
    var hint: String
    var onMove: (Move, TimeInterval) -> Void
    var onStop: () -> Void

    func makeUIView(context: Context) -> TouchPadView { TouchPadView() }

    func updateUIView(_ view: TouchPadView, context: Context) {
        view.accessibilityLabel = label
        view.accessibilityHint = hint
        view.onMove = onMove
        view.onStop = onStop
    }
}

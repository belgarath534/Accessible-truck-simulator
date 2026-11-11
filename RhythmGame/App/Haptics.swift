import BeatCore
import UIKit

/// You feel how you did: a strong tap for perfect, a soft one for good, a buzz for a miss.
@MainActor
final class Haptics {
    private let strong = UIImpactFeedbackGenerator(style: .heavy)
    private let soft = UIImpactFeedbackGenerator(style: .light)
    private let notify = UINotificationFeedbackGenerator()

    func prepare() {
        strong.prepare()
        soft.prepare()
        notify.prepare()
    }

    func play(_ j: Judgement) {
        switch j {
        case .perfect: strong.impactOccurred(intensity: 1)
        case .good: soft.impactOccurred(intensity: 0.7)
        case .wrongMove, .miss: notify.notificationOccurred(.error)
        }
    }
}

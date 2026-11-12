import AVFoundation
import UIKit

/// Speaks through VoiceOver when it's on (and chosen), otherwise with the system voice.
final class Speech {
    enum Priority { case normal, high }

    private let synth = AVSpeechSynthesizer()
    var useVoiceOver = true

    func say(_ text: String, priority: Priority = .normal) {
        if useVoiceOver && UIAccessibility.isVoiceOverRunning {
            let attributed = NSAttributedString(string: text,
                                                attributes: [.accessibilitySpeechQueueAnnouncement: priority == .normal])
            UIAccessibility.post(notification: .announcement, argument: attributed)
            return
        }
        if priority == .high { synth.stopSpeaking(at: .immediate) }
        let u = AVSpeechUtterance(string: text)
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 1.08
        synth.speak(u)
    }

    func stop() { synth.stopSpeaking(at: .immediate) }
}

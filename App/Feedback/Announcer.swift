import AVFoundation
import UIKit

enum SpeechPriority {
    /// Skipped if something else is being said (e.g. speed callouts).
    case low
    /// Queued after whatever is being said.
    case normal
    /// Interrupts everything (warnings, things the player asked for).
    case high
}

enum SpeechOutput: String, CaseIterable {
    /// The game speaks with its own synthesizer, using your VoiceOver voice and rate.
    case gameVoice
    /// The game sends announcements to VoiceOver itself (falls back to the game voice if VoiceOver is off).
    case voiceOver
}

final class Announcer {
    private let synthesizer = AVSpeechSynthesizer()
    var output: SpeechOutput = .gameVoice

    func speak(_ text: String, priority: SpeechPriority = .normal) {
        if output == .voiceOver && UIAccessibility.isVoiceOverRunning {
            let attributed = NSAttributedString(
                string: text,
                attributes: [.accessibilitySpeechQueueAnnouncement: priority != .high]
            )
            UIAccessibility.post(notification: .announcement, argument: attributed)
            return
        }
        switch priority {
        case .high:
            synthesizer.stopSpeaking(at: .immediate)
        case .low:
            if synthesizer.isSpeaking { return }
        case .normal:
            break
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.prefersAssistiveTechnologySettings = true
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}

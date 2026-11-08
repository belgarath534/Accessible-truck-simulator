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

final class Announcer: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    var output: SpeechOutput = .gameVoice
    /// Called with true when speech starts and false when it ends (the radio ducks under speech).
    var onSpeakingChanged: ((Bool) -> Void)?
    /// Called with every sentence that is actually spoken, for on-screen captions.
    var onCaption: ((String) -> Void)?
    private var announcementObserver: NSObjectProtocol?

    override init() {
        super.init()
        synthesizer.delegate = self
        announcementObserver = NotificationCenter.default.addObserver(
            forName: UIAccessibility.announcementDidFinishNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.onSpeakingChanged?(false) }
    }

    func speechSynthesizer(_ s: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        onSpeakingChanged?(true)
    }

    func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        if !s.isSpeaking { onSpeakingChanged?(false) }
    }

    func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        if !s.isSpeaking { onSpeakingChanged?(false) }
    }

    func speak(_ text: String, priority: SpeechPriority = .normal) {
        if output == .voiceOver && UIAccessibility.isVoiceOverRunning {
            let attributed = NSAttributedString(
                string: text,
                attributes: [.accessibilitySpeechQueueAnnouncement: priority != .high]
            )
            onSpeakingChanged?(true)
            onCaption?(text)
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
        onCaption?(text)
        let utterance = AVSpeechUtterance(string: text)
        utterance.prefersAssistiveTechnologySettings = true
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}

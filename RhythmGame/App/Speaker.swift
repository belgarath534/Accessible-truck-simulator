import AVFoundation
import UIKit

/// Speaks through VoiceOver when it's on, otherwise with the system voice.
@MainActor
enum Speaker {
    private static let synth = AVSpeechSynthesizer()

    static func say(_ text: String) {
        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification: .announcement, argument: text)
        } else {
            synth.stopSpeaking(at: .immediate)
            synth.speak(AVSpeechUtterance(string: text))
        }
    }
}

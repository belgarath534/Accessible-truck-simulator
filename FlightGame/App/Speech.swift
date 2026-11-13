import AVFoundation
import FlightCore
import UIKit

/// Says things. A sentence with a recorded voice (see VoiceLines) plays its recording; everything else is
/// spoken by VoiceOver when it's on (and chosen), otherwise by the system voice.
final class Speech: NSObject, AVAudioPlayerDelegate {
    enum Priority { case normal, high }

    private enum Item { case clip(URL); case spoken(String) }

    private let synth = AVSpeechSynthesizer()
    private var queue: [Item] = []
    private var player: AVAudioPlayer?
    /// When the spoken (not recorded) sentence in progress should be over: clips wait for it.
    private var spokenUntil = Date.distantPast
    var useVoiceOver = true
    /// Recorded voices on or off (Settings).
    var recordedVoices = true
    static let clipVolume: Float = 1

    private func clip(for text: String) -> URL? {
        guard recordedVoices, let line = VoiceLines.line(for: text) else { return nil }
        return Bundle.main.url(forResource: line.fileName, withExtension: "m4a")
            ?? Bundle.main.url(forResource: line.fileName, withExtension: "m4a", subdirectory: "Voices")
    }

    func say(_ text: String, priority: Priority = .normal) {
        if priority == .high { stop() }
        if let url = clip(for: text) {
            queue.append(.clip(url))
        } else if player == nil && queue.isEmpty {
            speak(text, interrupt: priority == .high)
            return
        } else {
            queue.append(.spoken(text))
        }
        pump()
    }

    private func pump() {
        guard player == nil, !queue.isEmpty else { return }
        // Let a spoken sentence finish before a recording starts.
        let wait = spokenUntil.timeIntervalSinceNow
        if wait > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in self?.pump() }
            return
        }
        switch queue.removeFirst() {
        case let .clip(url):
            guard let p = try? AVAudioPlayer(contentsOf: url) else { return pump() }
            p.delegate = self
            p.volume = Self.clipVolume
            player = p
            p.play()
        case let .spoken(text):
            speak(text, interrupt: false)
            pump()
        }
    }

    func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully flag: Bool) {
        guard p === player else { return }
        player = nil
        pump()
    }

    private func speak(_ text: String, interrupt: Bool) {
        // A rough guess at how long it takes to say, so recordings don't talk over it.
        spokenUntil = Date().addingTimeInterval(min(30, 0.5 + Double(text.count) * 0.06))
        if useVoiceOver && UIAccessibility.isVoiceOverRunning {
            let attributed = NSAttributedString(string: text,
                                                attributes: [.accessibilitySpeechQueueAnnouncement: !interrupt])
            UIAccessibility.post(notification: .announcement, argument: attributed)
            return
        }
        if interrupt { synth.stopSpeaking(at: .immediate) }
        let u = AVSpeechUtterance(string: text)
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 1.08
        synth.speak(u)
    }

    /// Stops everything being said and forgets what was waiting.
    func stop() {
        queue = []
        player?.stop()
        player = nil
        synth.stopSpeaking(at: .immediate)
        spokenUntil = .distantPast
    }
}

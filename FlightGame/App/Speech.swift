import AVFoundation
import FlightCore
import UIKit

/// Says things, strictly one at a time: nothing ever talks over anything else.
///
/// A sentence with a recording (see VoiceLines) plays its recording; everything else is spoken by the game's
/// own voice, using your VoiceOver voice settings. Both go through one queue. Something urgent goes to the
/// front and cuts in; if it cut off the instructor, the instructor starts that sentence again afterwards.
final class Speech: NSObject, AVAudioPlayerDelegate, AVSpeechSynthesizerDelegate {
    enum Priority { case normal, high }

    private enum Item {
        /// A recording. `keep`: the instructor, whose sentences are never dropped.
        case clip(URL, keep: Bool)
        case spoken(String)

        var keep: Bool { if case let .clip(_, keep) = self { return keep }; return false }
    }

    private let synth = AVSpeechSynthesizer()
    private var queue: [Item] = []
    private var current: Item?
    private var player: AVAudioPlayer?
    private var utterance: AVSpeechUtterance?
    /// With recorded voices off: send everything to VoiceOver itself when it's running.
    var useVoiceOver = true
    var recordedVoices = true

    override init() {
        super.init()
        synth.delegate = self
    }

    private func item(for text: String) -> Item {
        if recordedVoices, let line = VoiceLines.line(for: text),
           let url = Bundle.main.url(forResource: line.fileName, withExtension: "m4a")
            ?? Bundle.main.url(forResource: line.fileName, withExtension: "m4a", subdirectory: "Voices") {
            return .clip(url, keep: line.speaker == .instructor)
        }
        return .spoken(text)
    }

    func say(_ text: String, priority: Priority = .normal) {
        // Recorded voices off and VoiceOver on: VoiceOver says everything, in its own queue.
        if !recordedVoices, useVoiceOver, UIAccessibility.isVoiceOverRunning {
            let attributed = NSAttributedString(string: text,
                                                attributes: [.accessibilitySpeechQueueAnnouncement: priority == .normal])
            UIAccessibility.post(notification: .announcement, argument: attributed)
            return
        }
        let new = item(for: text)
        if priority == .high {
            // Cut in. The instructor's interrupted sentence comes back right after.
            let interrupted = current
            stopCurrent()
            queue.removeAll { !$0.keep }
            queue.insert(new, at: 0)
            if let interrupted, interrupted.keep { queue.insert(interrupted, at: 1) }
        } else {
            // Routine lines don't pile up: only the newest one waits (throttle 10, 20, 30 says just 30).
            if !new.keep { queue.removeAll { !$0.keep } }
            queue.append(new)
        }
        pump()
    }

    private func pump() {
        guard current == nil, !queue.isEmpty else { return }
        let next = queue.removeFirst()
        current = next
        switch next {
        case let .clip(url, _):
            guard let p = try? AVAudioPlayer(contentsOf: url) else { current = nil; return pump() }
            p.delegate = self
            player = p
            p.play()
        case let .spoken(text):
            let u = AVSpeechUtterance(string: text)
            u.prefersAssistiveTechnologySettings = true
            utterance = u
            synth.speak(u)
        }
    }

    private func stopCurrent() {
        player?.stop()
        player = nil
        if utterance != nil {
            utterance = nil
            synth.stopSpeaking(at: .immediate)
        }
        current = nil
    }

    func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully flag: Bool) {
        guard p === player else { return }
        player = nil
        current = nil
        pump()
    }

    func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        guard u === utterance else { return }
        utterance = nil
        current = nil
        pump()
    }

    func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {
        guard u === utterance else { return }
        utterance = nil
        current = nil
        pump()
    }

    /// Stops everything being said and forgets what was waiting.
    func stop() {
        queue = []
        stopCurrent()
    }
}

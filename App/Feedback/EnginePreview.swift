import Foundation
import SimCore

/// Plays a truck's engine in the garage: start, a rev up and back down, then off (about 6 seconds).
final class EnginePreview: ObservableObject {
    @Published private(set) var playingTruckID: String?
    private var audio: AudioSynth?
    private var timer: Timer?
    private var t: Double = 0
    private var startedSound = false

    func play(_ truck: TruckSpec, volume: Double) {
        stop()
        MusicPlayer.shared.setPaused(true)
        let audio = AudioSynth()
        audio.state.volume = Float(volume)
        audio.start(sound: truck.sound, idleRPM: Float(truck.idleRPM), maxRPM: Float(truck.maxRPM))
        self.audio = audio
        playingTruckID = truck.id
        t = 0
        startedSound = false
        let idle = Float(truck.idleRPM), top = Float(truck.maxRPM) * 0.9
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            guard let self, let audio = self.audio else { return }
            self.t += 1.0 / 30
            let cyl = Float(truck.cylinders), maxRPM = Float(truck.maxRPM)
            switch self.t {
            case ..<1.6:
                if !self.startedSound { self.startedSound = true; audio.engineStarting() }
                audio.state.cranking = true
                audio.setPreview(rpm: 180, load: 0, running: false, maxRPM: maxRPM, cylinders: cyl)
            case ..<2.6:
                audio.state.cranking = false
                audio.setPreview(rpm: idle, load: 0, running: true, maxRPM: maxRPM, cylinders: cyl)
            case ..<4.2:
                let k = Float((self.t - 2.6) / 1.6)
                audio.setPreview(rpm: idle + (top - idle) * k, load: 1, running: true, maxRPM: maxRPM, cylinders: cyl)
            case ..<5.6:
                let k = Float((self.t - 4.2) / 1.4)
                audio.setPreview(rpm: top - (top - idle) * k, load: 0, running: true, maxRPM: maxRPM, cylinders: cyl)
            case ..<6.4:
                audio.setPreview(rpm: idle, load: 0, running: true, maxRPM: maxRPM, cylinders: cyl)
            default:
                self.stop()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        audio?.stop()
        audio = nil
        if playingTruckID != nil { MusicPlayer.shared.setPaused(false) }
        playingTruckID = nil
    }
}

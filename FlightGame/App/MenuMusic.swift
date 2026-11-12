import AVFoundation

/// Music on the menus: the tracks take turns, fading out when a flight starts and back in after.
final class MenuMusic: NSObject, AVAudioPlayerDelegate {
    static let shared = MenuMusic()

    private let tracks = ["menu_blue_sky", "menu_determined_to_fly"]
    private var index = 0
    private var player: AVAudioPlayer?
    static let volume: Float = 0.45

    var enabled = true {
        didSet { enabled ? play() : stop() }
    }

    func play() {
        guard enabled else { return }
        if let p = player {
            if !p.isPlaying { p.volume = 0; p.play() }
            p.setVolume(Self.volume, fadeDuration: 1.5)
            return
        }
        start(index)
    }

    private func start(_ i: Int) {
        guard let url = Bundle.main.url(forResource: tracks[i % tracks.count], withExtension: "m4a"),
              let p = try? AVAudioPlayer(contentsOf: url) else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        p.delegate = self
        p.volume = 0
        p.prepareToPlay()
        p.play()
        p.setVolume(Self.volume, fadeDuration: 1.5)
        player = p
    }

    /// Fades out and pauses (taking off).
    func fadeOut() {
        guard let p = player, p.isPlaying else { return }
        p.setVolume(0, fadeDuration: 1)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in
            guard let self, let p = self.player, p.volume == 0 else { return }
            p.pause()
        }
    }

    func stop() {
        player?.stop()
        player = nil
    }

    func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully flag: Bool) {
        guard p === player, enabled else { return }
        index += 1
        player = nil
        start(index)
    }
}

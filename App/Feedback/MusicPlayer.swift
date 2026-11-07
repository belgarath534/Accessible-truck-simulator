import AVFoundation

/// Menu music and the in-truck radio. Tracks live in App/Music:
///   menu_*.m4a   main menu music (loops)
///   radio_*.m4a  radio songs, played in file-name order
/// The radio ducks (gets quieter) while the game is speaking, so warnings are never drowned out.
final class MusicPlayer: NSObject, AVAudioPlayerDelegate {
    static let shared = MusicPlayer()

    enum Mode { case off, menu, radio }

    private(set) var mode: Mode = .off
    private var player: AVAudioPlayer?
    private var radioIndex = 0
    private var ducked = false

    /// 0...1, from Settings.
    var volume: Float = 0.5 { didSet { applyVolume(fade: 0.2) } }

    let menuTracks: [URL]
    let radioTracks: [URL]

    private override init() {
        let all = (Bundle.main.urls(forResourcesWithExtension: "m4a", subdirectory: nil) ?? [])
            + (Bundle.main.urls(forResourcesWithExtension: "m4a", subdirectory: "Music") ?? [])
        let unique = Array(Set(all)).sorted { $0.lastPathComponent < $1.lastPathComponent }
        menuTracks = unique.filter { $0.lastPathComponent.hasPrefix("menu_") }
        radioTracks = unique.filter { $0.lastPathComponent.hasPrefix("radio_") }
        super.init()
    }

    var hasRadio: Bool { !radioTracks.isEmpty }

    /// The current radio song's name, for speech ("radio_2_empty_stretch" -> "Empty Stretch").
    var currentSongName: String? {
        guard mode == .radio, radioTracks.indices.contains(radioIndex) else { return nil }
        let base = radioTracks[radioIndex].deletingPathExtension().lastPathComponent
        let words = base.split(separator: "_").dropFirst(2)
        return words.map { $0.capitalized }.joined(separator: " ")
    }

    // MARK: Menu

    func playMenu() {
        if mode == .menu {
            // Already the menu music; make sure it isn't left paused.
            if player?.isPlaying == false { player?.play() }
            return
        }
        guard let url = menuTracks.first else { return }
        prepareSession()
        play(url, loop: true)
        mode = .menu
    }

    // MARK: Radio

    func startRadio() {
        guard hasRadio else { return }
        prepareSession()
        mode = .radio
        play(radioTracks[radioIndex % radioTracks.count], loop: false)
    }

    func nextSong() {
        guard hasRadio else { return }
        radioIndex = (radioIndex + 1) % radioTracks.count
        startRadio()
    }

    func previousSong() {
        guard hasRadio else { return }
        radioIndex = (radioIndex - 1 + radioTracks.count) % radioTracks.count
        startRadio()
    }

    func stop() {
        player?.stop()
        player = nil
        mode = .off
    }

    /// Lowers the music while the game speaks.
    func setDucked(_ duck: Bool) {
        guard duck != ducked else { return }
        ducked = duck
        applyVolume(fade: duck ? 0.15 : 0.6)
    }

    /// Silences everything without losing the place (pause menu, results screen).
    func setPaused(_ paused: Bool) {
        if paused { player?.pause() } else if mode != .off { player?.play() }
    }

    // MARK: Private

    private func play(_ url: URL, loop: Bool) {
        player?.stop()
        guard let p = try? AVAudioPlayer(contentsOf: url) else { player = nil; return }
        p.numberOfLoops = loop ? -1 : 0
        p.delegate = self
        p.volume = 0
        p.prepareToPlay()
        p.play()
        player = p
        DispatchQueue.main.async { self.applyVolume(fade: 1.0) }
    }

    private func applyVolume(fade: TimeInterval) {
        // The menu can be loud; the radio sits lower so the engine, lane beeps and speech stay clear.
        let modeLevel: Float = mode == .radio ? 0.7 : 1
        let target = volume * modeLevel * (ducked ? 0.3 : 1)
        player?.setVolume(target, fadeDuration: fade)
    }

    private func prepareSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [])
        try? session.setActive(true)
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard mode == .radio, player === self.player else { return }
        nextSong()
    }
}

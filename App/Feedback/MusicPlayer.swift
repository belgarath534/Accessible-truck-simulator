import AVFoundation
import MediaPlayer
import SimCore

/// Where the truck radio's music comes from.
enum RadioSource: String, CaseIterable {
    /// Big Rig Radio: the game's own songs, with the DJ.
    case gameRadio
    /// Audio files the player imported (MP3, M4A, WAV...), kept in the app's own folder.
    case myFiles
    /// Songs picked from the iPhone's music library (Apple Music).
    case appleMusic

    var label: String {
        switch self {
        case .gameRadio: return "Big Rig Radio (the game's songs)"
        case .myFiles: return "My music files"
        case .appleMusic: return "Apple Music"
        }
    }
}

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

    /// Today's weather, for the DJ's weather report; set when a drive starts.
    var weatherForDJ: Weather = .clear
    /// Shows a caption when the DJ talks.
    var onDJ: ((RadioLine) -> Void)?
    private var playingDJ = false
    private var songsSinceDJ = 0

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

    /// Where the radio's songs come from (Settings).
    var source: RadioSource = .gameRadio {
        didSet { if oldValue != source && mode == .radio { stop() } }
    }

    // MARK: My music files

    /// The folder imported songs are copied into.
    static var myMusicFolder: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent("My Music", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Imported songs, by name.
    var myFiles: [URL] {
        let exts: Set<String> = ["mp3", "m4a", "wav", "aac", "aif", "aiff", "caf", "flac"]
        let all = (try? FileManager.default.contentsOfDirectory(at: Self.myMusicFolder, includingPropertiesForKeys: nil)) ?? []
        return all.filter { exts.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// Copies picked files into the app's own folder. Returns how many were added.
    @discardableResult
    func importFiles(_ urls: [URL]) -> Int {
        var added = 0
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let dest = Self.myMusicFolder.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.removeItem(at: dest)
            if (try? FileManager.default.copyItem(at: url, to: dest)) != nil { added += 1 }
        }
        return added
    }

    func removeFile(_ url: URL) { try? FileManager.default.removeItem(at: url) }

    // MARK: Apple Music

    private let appleMusicKey = "appleMusicSongIDs"
    private var appleMusicPlayer: MPMusicPlayerController { MPMusicPlayerController.applicationQueuePlayer }

    /// The songs picked from the music library, by persistent ID.
    var appleMusicSongIDs: [UInt64] {
        get { (UserDefaults.standard.array(forKey: appleMusicKey) as? [NSNumber])?.map(\.uint64Value) ?? [] }
        set { UserDefaults.standard.set(newValue.map { NSNumber(value: $0) }, forKey: appleMusicKey) }
    }

    func setAppleMusicSongs(_ items: [MPMediaItem]) {
        appleMusicSongIDs = items.map(\.persistentID)
    }

    private func appleMusicItems() -> [MPMediaItem] {
        guard MPMediaLibrary.authorizationStatus() == .authorized else { return [] }
        return appleMusicSongIDs.compactMap { id in
            let q = MPMediaQuery.songs()
            q.addFilterPredicate(MPMediaPropertyPredicate(value: NSNumber(value: id), forProperty: MPMediaItemPropertyPersistentID))
            return q.items?.first
        }
    }

    /// Titles of the picked Apple Music songs.
    var appleMusicTitles: [String] { appleMusicItems().map { $0.title ?? "Untitled" } }

    var hasRadio: Bool {
        switch source {
        case .gameRadio: return !radioTracks.isEmpty
        case .myFiles: return !myFiles.isEmpty
        case .appleMusic: return !appleMusicSongIDs.isEmpty
        }
    }

    /// The song files the radio plays (game songs or imported files).
    private var currentTracks: [URL] { source == .myFiles ? myFiles : radioTracks }

    /// The current radio song's name, for speech ("radio_2_empty_stretch" -> "Empty Stretch").
    var currentSongName: String? {
        guard mode == .radio else { return nil }
        switch source {
        case .appleMusic:
            return appleMusicPlayer.nowPlayingItem?.title
        case .myFiles:
            let files = myFiles
            guard files.indices.contains(radioIndex % max(1, files.count)) else { return nil }
            return files[radioIndex % files.count].deletingPathExtension().lastPathComponent
        case .gameRadio:
            guard radioTracks.indices.contains(radioIndex) else { return nil }
            let base = radioTracks[radioIndex].deletingPathExtension().lastPathComponent
            let words = base.split(separator: "_").dropFirst(2)
            return words.map { $0.capitalized }.joined(separator: " ")
        }
    }

    // MARK: Menu

    func playMenu() {
        guard !ScreenshotMode.isOn else { return } // no sound device in the screenshot simulator
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
        guard hasRadio, !ScreenshotMode.isOn else { return }
        prepareSession()
        if source == .appleMusic {
            player?.stop()
            player = nil
            let items = appleMusicItems()
            guard !items.isEmpty else { return }
            mode = .radio
            appleMusicPlayer.setQueue(with: MPMediaItemCollection(items: items))
            appleMusicPlayer.play()
            return
        }
        let tracks = currentTracks
        guard !tracks.isEmpty else { return }
        mode = .radio
        play(tracks[radioIndex % tracks.count], loop: false)
    }

    func nextSong() {
        guard hasRadio else { return }
        if source == .appleMusic {
            if mode == .radio { appleMusicPlayer.skipToNextItem() } else { startRadio() }
            return
        }
        radioIndex = (radioIndex + 1) % max(1, currentTracks.count)
        startRadio()
    }

    func previousSong() {
        guard hasRadio else { return }
        if source == .appleMusic {
            if mode == .radio { appleMusicPlayer.skipToPreviousItem() } else { startRadio() }
            return
        }
        let n = max(1, currentTracks.count)
        radioIndex = (radioIndex - 1 + n) % n
        startRadio()
    }

    func stop() {
        player?.stop()
        player = nil
        if source == .appleMusic && mode == .radio { appleMusicPlayer.stop() }
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
        if source == .appleMusic && mode == .radio {
            if paused { appleMusicPlayer.pause() } else { appleMusicPlayer.play() }
            return
        }
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
        // Between songs the DJ talks now and then: a weather report or a word for the truckers.
        if playingDJ {
            playingDJ = false
            nextSong()
            return
        }
        songsSinceDJ += 1
        // The DJ is part of Big Rig Radio only, not your own music.
        if source == .gameRadio, songsSinceDJ >= 1, Bool.random(), playDJ() { return }
        nextSong()
    }

    private func playDJ() -> Bool {
        let line = Bool.random() ? RadioLines.djWeather(weatherForDJ) : RadioLines.dj.randomElement()!
        guard let url = ["wav", "m4a", "caf", "mp3"].lazy.compactMap({
            Bundle.main.url(forResource: line.fileName, withExtension: $0)
                ?? Bundle.main.url(forResource: line.fileName, withExtension: $0, subdirectory: "Sounds")
        }).first else { return false }
        songsSinceDJ = 0
        playingDJ = true
        play(url, loop: false)
        onDJ?(line)
        return true
    }
}

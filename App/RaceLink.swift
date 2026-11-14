import GameKit
import SimCore

/// The connection to the other racer: a Game Center match found by room code, or the practice bot.
///
/// The room code is Game Center's "player group": players who search with the same number are matched with
/// each other. Whoever made the room chooses the route and sends it; both sides then say they're ready.
final class RaceLink: NSObject, ObservableObject, GKMatchDelegate {
    /// The race in progress, for the driving screen.
    static weak var current: RaceLink?

    enum Phase: Equatable {
        case searching, connecting, ready, racing, finished
        case failed(String)
    }

    @Published private(set) var phase: Phase = .searching
    @Published private(set) var rival: RivalState?
    @Published private(set) var rivalName = "Your rival"
    @Published private(set) var setup: RaceSetup?

    let code: Int
    let creator: Bool
    private var bot: RaceBot?
    private var match: GKMatch?
    private var sentReady = false
    private var left = false

    var isPractice: Bool { bot != nil }

    /// Racing a friend: `setup` is the route when you made the room, nil when you're joining.
    init(code: Int, creator: Bool, setup: RaceSetup?) {
        self.code = code
        self.creator = creator
        self.setup = setup
        super.init()
        RaceLink.current = self
    }

    /// Racing the practice bot.
    init(practice setup: RaceSetup, level: RaceBot.Level) {
        code = 0
        creator = true
        self.setup = setup
        let bot = RaceBot(routeLength: setup.job?.distance ?? 5_000, level: level, seed: setup.seed)
        self.bot = bot
        rival = bot.state
        rivalName = RaceBot.name
        super.init()
        phase = .ready
        RaceLink.current = self
    }

    deinit { if match != nil { match?.disconnect() } }

    // MARK: Finding the other player

    func findMatch() {
        guard bot == nil, phase == .searching, match == nil else { return }
        guard GKLocalPlayer.local.isAuthenticated else {
            phase = .failed("Online races need Game Center. Sign in to Game Center in the Settings app, then try again. You can race the practice bot without it.")
            return
        }
        let request = GKMatchRequest()
        request.minPlayers = 2
        request.maxPlayers = 2
        request.playerGroup = code
        GKMatchmaker.shared().findMatch(for: request) { [weak self] match, error in
            DispatchQueue.main.async {
                guard let self, !self.left else { match?.disconnect(); return }
                guard let match else {
                    self.phase = .failed("Couldn't find the race. Check the room code and your internet connection, and try again.")
                    _ = error
                    return
                }
                self.match = match
                match.delegate = self
                self.phase = .connecting
                if match.expectedPlayerCount == 0 { self.connected() }
            }
        }
    }

    private func connected() {
        if let p = match?.players.first { rivalName = p.displayName }
        send(.hello(name: GKLocalPlayer.local.displayName, creator: creator, version: RaceMessage.version), reliable: true)
        if creator, let setup { send(.setup(setup), reliable: true) }
    }

    func match(_ match: GKMatch, player: GKPlayer, didChange state: GKPlayerConnectionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected: if match.expectedPlayerCount == 0 { self.connected() }
            case .disconnected: self.rivalLeft()
            default: break
            }
        }
    }

    func match(_ match: GKMatch, didReceive data: Data, fromRemotePlayer player: GKPlayer) {
        guard let message = RaceMessage.decode(data) else { return }
        DispatchQueue.main.async { self.handle(message) }
    }

    func match(_ match: GKMatch, didFailWithError error: Error?) {
        DispatchQueue.main.async {
            if self.phase == .racing { self.rivalLeft() } else { self.phase = .failed("The connection was lost. Try again.") }
        }
    }

    private func handle(_ message: RaceMessage) {
        switch message {
        case let .hello(name, _, version):
            if !name.isEmpty { rivalName = name }
            if version != RaceMessage.version {
                phase = .failed("You and \(rivalName) have different versions of the game. Both of you update it, then try again.")
            }
        case let .setup(s):
            guard !creator else { return }
            setup = s
            rival = RivalState(remaining: s.job?.distance ?? 0)
            send(.ready, reliable: true)
            sentReady = true
        case .ready:
            if !sentReady {
                send(.ready, reliable: true)
                sentReady = true
            }
            if phase == .searching || phase == .connecting {
                if rival == nil { rival = RivalState(remaining: setup?.job?.distance ?? 0) }
                phase = .ready
            }
        case let .state(s):
            rival = s
        case .quit:
            rivalLeft()
        }
    }

    private func rivalLeft() {
        var r = rival ?? RivalState(remaining: 0)
        r.quit = true
        rival = r
        switch phase {
        case .searching, .connecting, .ready: phase = .failed("\(rivalName) left the race.")
        default: break
        }
    }

    // MARK: During the race

    func startRace() { phase = .racing }
    func endRace() { if phase == .racing { phase = .finished } }

    /// Our state, a few times a second (the last one, finished, is sent reliably).
    func send(_ state: RivalState) {
        guard bot == nil else { return }
        send(.state(state), reliable: state.finished)
    }

    func sendQuit() {
        guard bot == nil else { return }
        send(.quit, reliable: true)
    }

    /// Practice: moves the bot along.
    func tickBot(dt: Double, started: Bool) {
        guard bot != nil else { return }
        rival = bot!.update(dt: dt, started: started)
    }

    private func send(_ message: RaceMessage, reliable: Bool) {
        try? match?.sendData(toAllPlayers: message.encoded(), with: reliable ? .reliable : .unreliable)
    }

    /// Leaving the race screens.
    func leave() {
        left = true
        if bot == nil {
            if match == nil { GKMatchmaker.shared().cancel() }
            if phase != .finished { sendQuit() }
            match?.disconnect()
            match = nil
        }
        if RaceLink.current === self { RaceLink.current = nil }
    }
}

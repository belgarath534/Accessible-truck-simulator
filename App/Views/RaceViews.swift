import SimCore
import SwiftUI

/// Online Race: race a friend over the internet with a room code, or practice against the bot.
struct RaceMenuView: View {
    @EnvironmentObject private var career: CareerStore

    var body: some View {
        List {
            Section {
                NavigationLink("Create a Race") { RaceSetupView(mode: .create) }
                    .font(.title2.bold())
                    .accessibilityHint("Pick the route and get a room code to give your friend.")
                NavigationLink("Join a Race") { RaceJoinView() }
                    .font(.title2)
                    .accessibilityHint("Enter the room code your friend gave you.")
            } header: {
                Text("Race a friend")
            } footer: {
                Text("You both drive the same route at the same time, each in your own truck. The game tells you who's ahead, and when the other truck is near you can hear it, pass it, or bump into it. Fastest time wins, and each crash adds 15 seconds. Both players need Game Center and an internet connection.")
            }
            Section {
                NavigationLink("Race \(RaceBot.name)") { RaceSetupView(mode: .practice) }
                    .accessibilityHint("A practice race against a computer driver. No internet needed.")
            } header: {
                Text("Practice")
            }
            if career.state.racesWon > 0 {
                Section { Text("Online races won: \(career.state.racesWon).") }
            }
        }
        .navigationTitle("Online Race")
    }
}

/// Picks the route (and the bot's level for practice), then opens the lobby.
struct RaceSetupView: View {
    enum Mode { case create, practice }
    let mode: Mode

    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var career: CareerStore
    @State private var from = ""
    @State private var to = ""
    @State private var cargoName = Cargo.catalog[0].name
    @State private var level = RaceBot.Level.normal
    @State private var link: RaceLink?

    private var towns: [MapNode] { WorldMap.standard.towns }

    var body: some View {
        Form {
            Section("Route") {
                Picker("From", selection: $from) {
                    ForEach(towns, id: \.id) { Text($0.name).tag($0.id) }
                }
                Picker("To", selection: $to) {
                    ForEach(towns.filter { $0.id != from }, id: \.id) { Text($0.name).tag($0.id) }
                }
                Picker("Cargo", selection: $cargoName) {
                    ForEach(Cargo.catalog, id: \.name) { Text($0.name).tag($0.name) }
                }
                if let job = setup?.job { Text("Distance: \(settings.units.distance(job.distance)).") }
            }
            if mode == .practice {
                Section {
                    Picker("\(RaceBot.name)'s speed", selection: $level) {
                        ForEach(RaceBot.Level.allCases, id: \.self) { Text($0.name).tag($0) }
                    }
                } footer: {
                    Text("Easy and Normal drive slower and crash once on the way. Hard is fast and never crashes.")
                }
            }
            Section {
                Button(mode == .create ? "Create Race" : "Start Practice Race") { start() }
                    .font(.title2.bold())
                    .disabled(setup?.job == nil)
            }
        }
        .navigationTitle(mode == .create ? "Create a Race" : "Practice Race")
        .onAppear {
            if from.isEmpty { from = career.state.currentTown }
            if to.isEmpty || to == from { to = towns.first { $0.id != from }?.id ?? "" }
        }
        .navigationDestination(item: Binding(get: { link.map(LinkBox.init) }, set: { link = $0?.link })) { box in
            RaceLobbyView(link: box.link) { link = nil }
        }
    }

    private var setup: RaceSetup? {
        guard to != from, !from.isEmpty else { return nil }
        return RaceSetup(from: from, to: to, cargoName: cargoName, seed: 0, weather: .clear)
    }

    private func start() {
        guard var s = setup else { return }
        var rng = SystemRandomNumberGenerator()
        s.seed = UInt64.random(in: 1...UInt64.max)
        s.weather = settings.weather ? Holiday.weather(using: &rng, date: Date()) : .clear
        link = mode == .create ? RaceLink(code: RaceCode.random(), creator: true, setup: s)
                               : RaceLink(practice: s, level: level)
    }
}

/// So a race link can drive a navigation destination.
struct LinkBox: Hashable {
    let link: RaceLink
    static func == (a: LinkBox, b: LinkBox) -> Bool { a.link === b.link }
    func hash(into h: inout Hasher) { h.combine(ObjectIdentifier(link)) }
}

struct RaceJoinView: View {
    @State private var text = ""
    @State private var link: RaceLink?
    @FocusState private var focused: Bool

    var body: some View {
        Form {
            Section {
                TextField("Room code", text: $text)
                    .keyboardType(.numberPad)
                    .focused($focused)
                    .accessibilityHint("The four numbers your friend got when they created the race.")
                Button("Join Race") {
                    if let code = RaceCode.parse(text) { link = RaceLink(code: code, creator: false, setup: nil) }
                }
                .font(.title2.bold())
                .disabled(RaceCode.parse(text) == nil)
            } footer: {
                Text("Your friend creates the race and tells you the four-number room code. You'll drive the route they picked.")
            }
        }
        .navigationTitle("Join a Race")
        .onAppear { focused = true }
        .navigationDestination(item: Binding(get: { link.map(LinkBox.init) }, set: { link = $0?.link })) { box in
            RaceLobbyView(link: box.link) { link = nil }
        }
    }
}

/// Waiting for the other player, the start, and the results.
struct RaceLobbyView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var career: CareerStore
    @ObservedObject var link: RaceLink
    let close: () -> Void
    @State private var driving: DriveMode?
    @State private var mine: DuelResults.Result?
    @State private var announcedOutcome = false
    @AccessibilityFocusState private var focused: Bool

    var body: some View {
        List {
            Section {
                Text(headline)
                    .font(.title2.bold())
                    .accessibilityFocused($focused)
                ForEach(details, id: \.self) { Text($0) }
            }
            Section {
                if link.phase == .ready {
                    Button("Start Race") { startDriving() }
                        .font(.title2.bold())
                }
                Button(link.phase == .finished ? "Done" : "Leave") {
                    link.leave()
                    close()
                }
            }
        }
        .navigationTitle(link.isPractice ? "Practice Race" : "Online Race")
        .navigationBarBackButtonHidden(true)
        .onAppear {
            if !link.isPractice { link.findMatch() }
            focusSoon()
        }
        .onChange(of: link.phase) { _, _ in focusSoon() }
        .onChange(of: outcome) { _, new in
            guard let new, !announcedOutcome else { return }
            announcedOutcome = true
            if new == .won { career.recordRaceWin() }
            UIAccessibility.post(notification: .announcement, argument: headline)
        }
        .fullScreenCover(item: $driving, onDismiss: {
            mine = DuelResults.shared.last
            link.endRace()
        }) { mode in
            DrivingScreen(settings: settings, career: career, drive: mode) { driving = nil }
        }
    }

    private var outcome: RaceOutcome? {
        guard let mine, let rival = link.rival else { return nil }
        if !mine.delivered { return .lost }
        return RaceOutcome.decide(myTime: mine.time, myCrashes: mine.crashes, iFinished: true, rival: rival)
    }

    private var headline: String {
        let name = link.rivalName
        switch link.phase {
        case .searching:
            return link.creator ? "Your room code is \(RaceCode.spoken(link.code))." : "Looking for race \(RaceCode.spoken(link.code))…"
        case .connecting: return "Connecting to \(name)…"
        case .ready: return "Ready to race \(name)!"
        case .racing: return "Racing \(name)…"
        case .finished:
            switch outcome {
            case .won: return "You won!"
            case .lost: return "\(name) won."
            case .tie: return "It's a tie!"
            case nil: return "Waiting for \(name) to finish…"
            }
        case let .failed(message): return message
        }
    }

    private var details: [String] {
        var lines: [String] = []
        switch link.phase {
        case .searching:
            lines.append(link.creator ? "Tell your friend to choose Online Race, Join a Race, and enter this code. Waiting for them to join." : "Waiting for the race to be found. This can take a minute.")
        case .ready:
            if let s = link.setup, let job = s.job {
                lines.append("\(job.cargo.name) from \(job.originName ?? "") to \(job.destinationName ?? ""), \(settings.units.distance(job.distance)).")
            }
            lines.append("You both drive the same route. Your clock starts when you start moving. Each crash adds 15 seconds.")
        case .finished:
            if let mine {
                lines.append(mine.delivered ? Duel.line(entry(name: "You", time: mine.time, crashes: mine.crashes, delivered: true))
                                            : "You left the race.")
            }
            if let r = link.rival {
                if r.finished { lines.append(Duel.line(entry(name: link.rivalName, time: r.drivingTime, crashes: r.crashes, delivered: true))) }
                else if r.quit { lines.append("\(link.rivalName) left the race.") }
                else { lines.append("\(link.rivalName) has \(settings.units.distance(r.remaining)) to go.") }
            }
        default:
            break
        }
        return lines
    }

    private func entry(name: String, time: Double, crashes: Int, delivered: Bool) -> Duel.Entry {
        var e = Duel.Entry(name: name)
        e.time = time
        e.crashes = crashes
        e.delivered = delivered
        return e
    }

    private func startDriving() {
        guard let s = link.setup, let job = s.job else { return }
        DuelResults.shared.last = nil
        let intro = "\(link.isPractice ? "Practice race" : "Online race") against \(link.rivalName). \(job.cargo.name) from \(job.originName ?? "") to \(job.destinationName ?? ""), \(settings.units.distance(job.distance)). Fastest time wins, and each crash adds 15 seconds. The other truck is on the road with you: you'll hear it when it's near, and I'll tell you who's ahead."
        link.startRace()
        driving = .duel(DuelTurn(job: job, seed: s.seed, weather: s.weather, player: 0, intro: intro, raceRival: link.rivalName))
    }

    private func focusSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { focused = true }
    }
}

import SimCore
import SwiftUI

/// Duel Mode: pick a route and players, then pass the phone. Everyone drives the same route with the same
/// traffic and weather. Fastest time wins; each crash adds 15 seconds. No internet, no pay, nothing saved.
struct DuelSetupView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var career: CareerStore
    @AppStorage("duelNames") private var savedNames = "Player 1|Player 2|Player 3|Player 4"
    @State private var playerCount = 2
    @State private var names: [String] = []
    @State private var from = ""
    @State private var to = ""
    @State private var cargoName = Cargo.catalog[0].name
    @State private var duel: Duel?
    @State private var showDuel = false

    private var towns: [MapNode] { WorldMap.standard.towns }

    var body: some View {
        Form {
            Section {
                Stepper("Players: \(playerCount)", value: $playerCount, in: 2...Duel.maxPlayers)
                ForEach(0..<playerCount, id: \.self) { i in
                    TextField("Player \(i + 1) name", text: binding(i))
                        .textInputAutocapitalization(.words)
                        .accessibilityLabel("Player \(i + 1) name")
                }
            } header: {
                Text("Players")
            } footer: {
                Text("Everyone drives on this phone, one after another.")
            }
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
                if let job = makeJob() {
                    Text("Distance: \(settings.units.distance(job.distance)).")
                }
            }
            Section {
                Button("Start Duel") { start() }
                    .font(.title2.bold())
                    .disabled(makeJob() == nil)
            } footer: {
                Text("Same route, same traffic, same weather for everyone. The clock starts when you start moving and stops at the drop-off. Fastest time wins, and each crash adds \(Int(Duel.crashPenalty)) seconds. Uses the truck you drive in the Garage, in new condition with a full tank. Nothing is paid or saved to your career.")
            }
        }
        .navigationTitle("Duel Mode")
        .onAppear(perform: setUp)
        .navigationDestination(isPresented: $showDuel) {
            DuelPlayView(duel: $duel, close: { showDuel = false })
        }
    }

    private func setUp() {
        if names.isEmpty {
            names = savedNames.components(separatedBy: "|")
            while names.count < Duel.maxPlayers { names.append("Player \(names.count + 1)") }
        }
        if from.isEmpty { from = career.state.currentTown }
        if to.isEmpty || to == from { to = towns.first { $0.id != from }?.id ?? "" }
    }

    private func binding(_ i: Int) -> Binding<String> {
        Binding(get: { i < names.count ? names[i] : "" },
                set: { if i < names.count { names[i] = $0 } })
    }

    private func makeJob() -> DeliveryJob? {
        guard let cargo = Cargo.catalog.first(where: { $0.name == cargoName }), to != from else { return nil }
        return Duel.makeJob(from: from, to: to, cargo: cargo)
    }

    private func start() {
        guard let job = makeJob() else { return }
        savedNames = names.joined(separator: "|")
        var rng = SystemRandomNumberGenerator()
        let weather: Weather = settings.weather ? Holiday.weather(using: &rng, date: Date()) : .clear
        duel = Duel(job: job, players: Array(names.prefix(playerCount)), seed: UInt64.random(in: 1...UInt64.max), weather: weather)
        showDuel = true
    }
}

/// Between turns ("Pass the phone to Sam") and the final results.
struct DuelPlayView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var career: CareerStore
    @Binding var duel: Duel?
    let close: () -> Void
    @State private var driving: DriveMode?
    @AccessibilityFocusState private var focused: Bool

    var body: some View {
        List {
            if let duel {
                if let player = duel.current {
                    Section {
                        Text("Pass the phone to \(player.name).")
                            .font(.title.bold())
                            .accessibilityFocused($focused)
                        Text("Player \(duel.turn + 1) of \(duel.players.count). \(duel.job.cargo.name) from \(duel.job.originName ?? "") to \(duel.job.destinationName ?? "").")
                        if let best = duel.standings.first, let total = best.total {
                            Text("Time to beat: \(Duel.clock(total)), by \(best.name).")
                        }
                        Button("Start \(player.name)'s Turn") { startTurn() }
                            .font(.title2.bold())
                    }
                } else {
                    Section {
                        Text(duel.winner.map { "\($0.name) wins!" } ?? (duel.standings.contains { $0.total != nil } ? "It's a tie!" : "Nobody finished."))
                            .font(.largeTitle.bold())
                            .accessibilityFocused($focused)
                        ForEach(Array(duel.standings.enumerated()), id: \.offset) { i, entry in
                            Text("\(i + 1). " + Duel.line(entry))
                        }
                    } header: {
                        Text("Results")
                    }
                    Section {
                        Button("Rematch, Same Route") { rematch() }
                            .font(.title2.bold())
                            .accessibilityHint("Same players and route, new traffic.")
                        Button("New Duel", action: close)
                    }
                }
                if !duel.isOver, duel.standings.count > 0 {
                    Section("So far") {
                        ForEach(Array(duel.standings.enumerated()), id: \.offset) { i, entry in
                            Text("\(i + 1). " + Duel.line(entry))
                        }
                    }
                }
            }
        }
        .navigationTitle("Duel")
        .navigationBarBackButtonHidden(duel.map { $0.turn > 0 && !$0.isOver } ?? false)
        .onAppear { focus() }
        .fullScreenCover(item: $driving, onDismiss: finishTurn) { mode in
            DrivingScreen(settings: settings, career: career, drive: mode) { driving = nil }
        }
    }

    private func focus() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { focused = true }
    }

    private func startTurn() {
        guard let duel, duel.current != nil else { return }
        DuelResults.shared.last = nil
        driving = .duel(DuelTurn(job: duel.job, seed: duel.seed, weather: duel.weather, player: duel.turn,
                                 intro: duel.turnIntro(units: settings.units)))
    }

    private func finishTurn() {
        guard var d = duel, !d.isOver else { return }
        let r = DuelResults.shared.last
        d.record(time: r?.time ?? 0, crashes: r?.crashes ?? 0, delivered: r?.delivered ?? false)
        DuelResults.shared.last = nil
        duel = d
        if d.isOver {
            UIAccessibility.post(notification: .announcement, argument: d.spokenResults)
        }
        focus()
    }

    private func rematch() {
        guard let d = duel else { return }
        duel = Duel(job: d.job, players: d.players.map(\.name), seed: UInt64.random(in: 1...UInt64.max), weather: d.weather)
        focus()
    }
}

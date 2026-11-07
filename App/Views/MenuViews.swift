import SimCore
import SwiftUI

struct MainMenuView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var career: CareerStore
    @State private var drive: DriveMode?
    @State private var showingJobs = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Bank: \(Phrases.money(career.money))")
                        .font(.title2.bold())
                        .accessibilityLabel("Bank balance: \(Phrases.money(career.money))")
                    if career.state.jobsCompleted > 0 {
                        Text("Jobs delivered: \(career.state.jobsCompleted)")
                    }
                    Text("You're in \(career.state.currentTownName).")
                    Text("Driving: \(career.truck.name). Fuel \(Int((career.fuelLiters / career.truck.fuelCapacityLiters * 100).rounded())) percent.")
                }
                Section {
                    NavigationLink {
                        JobBoardView { job in drive = .job(job) }
                    } label: {
                        Text("Job Board").font(.title2.bold())
                    }
                    .accessibilityHint("Pick a delivery. Jobs pay the most.")
                    Button("Free Drive") { drive = .freeDrive }
                        .font(.title2)
                        .accessibilityHint("Roam the map from \(career.state.currentTownName) as long as you like. Pays \(Phrases.money(Int(Payout.freeDriveRatePerKm))) per kilometer.")
                    NavigationLink {
                        GarageView()
                    } label: {
                        Text("Garage").font(.title2)
                    }
                    .accessibilityHint("Buy trucks, hear their engines and choose which one to drive.")
                    Button("Practice Drive") { drive = .practice }
                        .font(.title2)
                        .accessibilityHint("One lap of the country road, then stop at the drop-off. No pay.")
                } footer: {
                    Text("Jobs go from the town you're in to another town and pay the most, with bonuses for arriving on time, not crashing and a perfect stop. Free Drive roams the map and pays a little for every kilometer. Practice Drive is the practice loop and doesn't pay.")
                }
                Section {
                    NavigationLink("How to Drive") { ControlsHelpView() }
                    NavigationLink("Settings") { SettingsView() }
                    NavigationLink("Credits") { CreditsView() }
                }
            }
            .navigationTitle("Truck Sim")
        }
        .onAppear { if settings.menuMusic { MusicPlayer.shared.playMenu() } }
        .onChange(of: settings.menuMusic) { _, on in
            if on { MusicPlayer.shared.playMenu() } else if MusicPlayer.shared.mode == .menu { MusicPlayer.shared.stop() }
        }
        .fullScreenCover(item: $drive, onDismiss: {
            if settings.menuMusic { MusicPlayer.shared.playMenu() }
        }) { mode in
            DrivingScreen(settings: settings, career: career, drive: mode) { drive = nil }
        }
    }
}

struct JobBoardView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var career: CareerStore
    let start: (DeliveryJob) -> Void

    private var phrases: Phrases { Phrases(units: settings.units) }

    var body: some View {
        List {
            Section {
                ForEach(career.jobs) { job in
                    Button {
                        start(job)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(job.cargo.name): \(Phrases.money(job.pay))").font(.headline)
                            Text(phrases.job(job)).font(.subheadline)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(phrases.job(job))
                    .accessibilityHint("Starts this delivery.")
                }
            } header: {
                Text("Available jobs")
            } footer: {
                Text("Heavy loads accelerate slowly and need more room to brake. Fragile loads are damaged more by crashes. Urgent loads have tighter time limits but pay more.")
            }
            Section {
                Button("Get New Jobs") { career.refreshBoard() }
                    .accessibilityHint("Replaces all three jobs with new ones.")
            }
        }
        .navigationTitle("Job Board")
    }
}

struct ControlsHelpView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        List {
            Section("Driving") {
                switch settings.steeringMode {
                case .tilt:
                    Text("Hold the phone sideways, at any angle: upright, tilted back or flat. Lower the right end to steer right, the left end to steer left. However you hold it when the drive starts counts as straight; it re-centers when you resume from pause.")
                    Text("Hold anywhere on the right half of the screen to accelerate. The longer you hold, the harder you press.")
                    Text("Hold anywhere on the left half of the screen to brake.")
                case .joystick:
                    Text("Put one finger anywhere and keep it down. Slide up to accelerate, down to brake, left or right to steer. Lift your finger to coast and straighten the wheel.")
                }
                Text("You can change between tilt and joystick steering in Settings.")
            }
            Section("Gestures") {
                ForEach(GestureMap.help, id: \.self) { item in
                    VStack(alignment: .leading) {
                        Text(item.gesture).font(.headline)
                        Text(item.action)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            Section("What you will hear") {
                Text("The engine gets louder and higher as RPM rises, and you'll hear a hiss on each gear change.")
                Text("Drifting toward the edge of your lane: soft beeps in that ear, faster and higher the further you drift.")
                Text("Too far: a rumble strip on that side, with strong vibration. Go further and you leave the road and crash.")
                Text("Curves are announced ahead of time with a suggested speed. In a curve you must steer, or the truck drifts to the outside.")
                Text("Speed is called out every 10 kilometers or miles per hour.")
                Text("On a Practice Drive you hear the distance left at 10, 5, 2 and 1 kilometers. At 400 meters you're told to slow down; stop at the drop-off to finish. The three-finger tap also tells you the distance left, and the pause menu shows how far you've driven, how far is left, your time and crashes.")
            }
            Section("Money and jobs") {
                Text("The Job Board offers three deliveries. Each one tells you the cargo, distance, pay, time limit and weight. Drive to the drop-off and stop there to deliver.")
                Text("Bonuses: 10 percent for arriving on time, 10 percent for no crashes, and 5 percent for a perfect stop. Being late or crashing takes money off, and fragile cargo is damaged more.")
                Text("Heavy cargo makes the truck slower to speed up and longer to stop.")
                Text("While driving a job, the three-finger tap tells you the distance and time left. You'll hear reminders at 5 minutes and 1 minute.")
                Text("Free Drive pays a little for every kilometer. Pause and choose End Drive and Get Paid, or Quit to Main Menu, which also pays. Each crash costs a repair fee.")
            }
            Section("The map and GPS") {
                Text("Six places: Millbrook, your home yard; Cedar Falls in lumber country, up the mountain Highway 9; Ridgeport, a port town; Ironton, with its mines and steel mill; Bayview, with its farms; and Central Junction, where Interstate 40 meets the roads to Ridgeport and Ironton.")
                Text("Interstate 40 is fast, with a 100 kilometer per hour limit and gentle curves. Country roads are 80 with more curves. Mountain roads are 60 with sharp curves. Towns are 50: you'll hear when you enter and leave them.")
                Text("On a job, the GPS tells you each turn at 1 kilometer and again at 300 meters. Signal left or right before the junction to turn, or no signal to go straight. Take a wrong turn and the GPS recalculates a new route.")
                Text("In Free Drive, the GPS lists the choices before each junction. The three-finger tap tells you what's ahead.")
                Text("After a delivery you're in the destination town, and the Job Board shows jobs from there.")
            }
            Section("Fuel and truck stops") {
                Text("Fuel stays in your truck between drives. A full tank lasts about an hour of driving. The dashboard, two-finger double tap, says how far your fuel will take you.")
                Text("Truck stops are on Interstate 40 and the longer country roads, and there are three on the practice loop. When your fuel is under half you'll hear one coming, and the three-finger tap always tells you the distance to the next one.")
                Text("To fill up: signal right before the truck stop and slow below 50 kilometers or 30 miles per hour as you reach it. Stop at the pump and wait while it fills. Press the gas to leave early.")
                Text("You're warned at a quarter tank and at 10 percent. If you run out, a tow truck takes you to the next truck stop for a fee and puts in a quarter tank. That costs 5 minutes too.")
                Text("Fuel at truck stops costs less than filling up at your yard in the Garage. Fuel and tow costs come off your pay.")
            }
            Section("Keyboard and controller") {
                Text("Keyboard: Up or W accelerate, Down or S brake, Left and Right or A and D steer. Left and right bracket for signals, I dashboard, G GPS, N engine, H horn, Escape pause, R radio on or off, comma and period for the previous or next song.")
                Text("Controller: right trigger accelerate, left trigger brake, left stick steer, shoulder buttons for signals, A dashboard, X GPS, Y engine, B horn, Menu pause, D-pad up radio on or off, D-pad left and right to change songs.")
            }
        }
        .navigationTitle("How to Drive")
    }
}

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section("Steering") {
                Picker("Steering method", selection: $settings.steeringMode) {
                    Text("Tilt the phone").tag(TouchSteeringMode.tilt)
                    Text("One-finger joystick").tag(TouchSteeringMode.joystick)
                }
                if settings.steeringMode == .tilt {
                    Stepper("Tilt for full lock: \(Int(settings.tiltRange)) degrees", value: $settings.tiltRange, in: 10...60, step: 5)
                    Toggle("Invert tilt", isOn: $settings.invertTilt)
                }
                Picker("Steering assist", selection: $settings.assist) {
                    Text("Off").tag(SteeringAssist.off)
                    Text("Low").tag(SteeringAssist.low)
                    Text("Medium").tag(SteeringAssist.medium)
                    Text("High").tag(SteeringAssist.high)
                }
            }
            Section {
                Toggle("Lane guidance beeps", isOn: $settings.laneGuidanceTone)
                Toggle("Call out speed", isOn: $settings.announceSpeed)
                Toggle("Announce gear changes", isOn: $settings.announceGears)
                Picker("Speech", selection: $settings.speechOutput) {
                    Text("Game voice").tag(SpeechOutput.gameVoice)
                    Text("Through VoiceOver").tag(SpeechOutput.voiceOver)
                }
                Toggle("Vibration", isOn: $settings.haptics)
                VStack(alignment: .leading) {
                    Text("Game volume")
                    Slider(value: $settings.volume, in: 0...1)
                        .accessibilityLabel("Game volume")
                }
            } header: {
                Text("Audio and feedback")
            } footer: {
                Text("Steering assist Low, Medium or High: steering moves the truck sideways, and letting go stops the drift. Curves push you toward the outside, so steer into them, harder when you're faster. Leaving the road slowly puts you on the gravel shoulder; leaving it fast is a crash. Off: realistic steering, much harder by ear.")
            }
            Section {
                Toggle("Music in the menus", isOn: $settings.menuMusic)
                Toggle("Radio on when you start driving", isOn: $settings.radioOnStart)
                VStack(alignment: .leading) {
                    Text("Music volume")
                    Slider(value: $settings.musicVolume, in: 0...1)
                        .accessibilityLabel("Music volume")
                }
            } header: {
                Text("Music and radio")
            } footer: {
                Text("While driving, three-finger swipe up turns the radio on or off, and three-finger swipe left or right changes the song. The radio gets quieter whenever the game speaks.")
            }
            Section("Units") {
                Picker("Units", selection: $settings.units) {
                    Text("Metric").tag(UnitSystem.metric)
                    Text("Imperial").tag(UnitSystem.imperial)
                }
            }
        }
        .navigationTitle("Settings")
    }
}

struct CreditsView: View {
    var body: some View {
        List {
            Section("Music") {
                Text("Menu theme and radio songs were made for Accessible Truck Sim with ElevenLabs Music.")
            }
            Section("Sound") {
                Text("Engine, starter, shutdown and air brake sounds were made with ElevenLabs Sound Effects. Road noise, rumble strips, lane guidance beeps and indicator clicks are generated live in the game.")
            }
        }
        .navigationTitle("Credits")
    }
}

struct GarageView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var career: CareerStore
    @StateObject private var preview = EnginePreview()
    @State private var message: String?

    private var phrases: Phrases { Phrases(units: settings.units) }

    var body: some View {
        List {
            Section {
                Text("Bank: \(Phrases.money(career.money))")
            }
            ForEach(TruckSpec.catalog, id: \.id) { truck in
                Section {
                    Text(phrases.truck(career.upgraded(truck)))
                    if career.state.owns(truck) {
                        let capacity = career.upgraded(truck).fuelCapacityLiters
                        let percent = Int((career.state.fuelLiters(for: truck) / capacity * 100).rounded())
                        let fillCost = career.state.yardFillCost(for: truck)
                        Text("Fuel: \(percent) percent.")
                        if fillCost > 0 {
                            Button("Fill Up at the Yard for \(Phrases.money(fillCost))") {
                                let full = career.fillAtYard(truck)
                                announce(full ? "Tank full. \(Phrases.money(career.money)) left in the bank."
                                              : "Not enough money for a full tank. Filled what you could afford.")
                            }
                            .accessibilityHint("Truck stops on the road are cheaper.")
                        }
                        NavigationLink("Upgrades") { UpgradesView(truck: truck) }
                            .accessibilityHint("Engine, brakes, tires and fuel tank for the \(truck.name).")
                    }
                    if career.truck.id == truck.id {
                        Text("You're driving this truck.").font(.headline)
                    } else if career.state.owns(truck) {
                        Button("Drive This Truck") {
                            career.select(truck)
                            announce("You're now driving the \(truck.name).")
                        }
                    } else {
                        Button("Buy for \(Phrases.money(truck.price))") { buy(truck) }
                            .accessibilityHint(career.money >= truck.price
                                ? "You'll start driving it right away."
                                : "You need \(Phrases.money(truck.price - career.money)) more.")
                    }
                    Button(preview.playingTruckID == truck.id ? "Stop Engine" : "Hear the Engine") {
                        if preview.playingTruckID == truck.id { preview.stop() } else { preview.play(career.upgraded(truck), volume: settings.volume) }
                    }
                } header: {
                    Text(truck.price == 0 ? truck.name : "\(truck.name), \(Phrases.money(truck.price))")
                }
            }
        }
        .navigationTitle("Garage")
        .onDisappear { preview.stop() }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    private func buy(_ truck: TruckSpec) {
        switch career.buy(truck) {
        case .bought:
            announce("You bought the \(truck.name) and you're driving it now. \(Phrases.money(career.money)) left in the bank.")
        case .alreadyOwned:
            career.select(truck)
        case let .notEnoughMoney(short):
            announce("Not enough money. You need \(Phrases.money(short)) more. Deliver jobs to earn it.")
        }
    }

    private func announce(_ text: String) {
        message = text
    }
}

struct UpgradesView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var career: CareerStore
    @StateObject private var preview = EnginePreview()
    let truck: TruckSpec
    @State private var message: String?

    var body: some View {
        let levels = career.state.upgradeLevels(for: truck)
        List {
            Section {
                Text("Bank: \(Phrases.money(career.money))")
                Button(preview.playingTruckID == truck.id ? "Stop Engine" : "Hear the Engine") {
                    if preview.playingTruckID == truck.id { preview.stop() } else { preview.play(career.upgraded(truck), volume: settings.volume) }
                }
            }
            ForEach(UpgradeKind.allCases, id: \.self) { kind in
                let level = levels[kind]
                Section {
                    Text("Level \(level) of \(UpgradeKind.maxLevel). \(kind.effect).")
                    if let price = kind.price(after: level) {
                        Button("Upgrade to level \(level + 1) for \(Phrases.money(price))") { buy(kind) }
                            .accessibilityHint(career.money >= price ? "" : "You need \(Phrases.money(price - career.money)) more.")
                    } else {
                        Text("Fully upgraded.").font(.headline)
                    }
                } header: {
                    Text("\(kind.name), level \(level)")
                }
            }
        }
        .navigationTitle("\(truck.name) Upgrades")
        .onDisappear { preview.stop() }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    private func buy(_ kind: UpgradeKind) {
        switch career.buyUpgrade(kind, for: truck) {
        case let .upgraded(level):
            message = "\(kind.name) upgraded to level \(level). \(Phrases.money(career.money)) left in the bank."
        case .maxed:
            message = "\(kind.name) is already fully upgraded."
        case .notOwned:
            message = "Buy the \(truck.name) first."
        case let .notEnoughMoney(short):
            message = "Not enough money. You need \(Phrases.money(short)) more."
        }
    }
}

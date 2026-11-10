import SimCore
import StoreKit
import SwiftUI

struct MainMenuView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var career: CareerStore
    @State private var drive: DriveMode?
    @State private var showingJobs = false
    @State private var driverReport: String?
    /// A new drive picked while a saved drive exists: asks first.
    @State private var replacingSaved: DriveMode?
    /// The main menu itself is showing (not the Garage, Company or another screen on top of it). Achievement
    /// alerts wait for this, so they never knock a screen's own message (like "You hired Rosa") away.
    @State private var atMainMenu = true
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.requestReview) private var requestReview

    /// Starts a drive; if there's a saved drive, asks before replacing it (the tutorial never replaces it).
    private func start(_ mode: DriveMode) {
        if career.savedDrive != nil && mode != .tutorial {
            replacingSaved = mode
        } else {
            drive = mode
        }
    }

    private var savedDriveName: String {
        guard let saved = career.savedDrive else { return "" }
        switch saved.kind {
        case .practice: return "Practice Drive"
        case .freeDrive: return "Free Drive"
        case .job: return saved.job.map { "\($0.cargo.name) to \($0.destinationName ?? "the drop-off")" } ?? "Delivery"
        }
    }

    /// After an update: What's New shows once by itself (not during the welcome setup or screenshots).
    private var showWhatsNew: Bool {
        settings.setupDone && settings.whatsNewSeen != Changelog.current && !ScreenshotMode.isOn && drive == nil
    }

    private var achievementTitle: String {
        career.justUnlocked.count == 1 ? "Achievement Unlocked!" : "\(career.justUnlocked.count) Achievements Unlocked!"
    }

    /// Pays out the drivers' work since last time and tells the player about it.
    private func reportDrivers() {
        guard drive == nil, let report = career.collectDriverEarnings() else { return }
        driverReport = report
    }

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
                    Text("You're in \(career.state.currentTownName). Reputation: \(career.state.reputationLevel.title).")
                    if let company = career.state.companyName {
                        Text(company).font(.headline).accessibilityAddTraits(.isHeader)
                    }
                    Text("Driving: \(career.state.displayName(for: career.truck)). Fuel \(Int((career.fuelLiters / career.truck.fuelCapacityLiters * 100).rounded())) percent.")
                }
                if career.savedDrive != nil {
                    Section {
                        Button("Continue Your Drive: \(savedDriveName)") { drive = career.prepareResume() }
                            .font(.title2.bold())
                            .accessibilityHint("Picks up your saved drive exactly where you left it.")
                    }
                }
                if !settings.tutorialDone {
                    Section {
                        Button("Start Here: Tutorial") { drive = .tutorial }
                            .font(.title2.bold())
                            .accessibilityHint("A guided first drive that teaches you every control, one step at a time.")
                    }
                }
                Section {
                    Toggle("Turbo Mode", isOn: $settings.turbo)
                        .font(.title3.bold())
                        .accessibilityHint("No speed limit, no police, and a bonus for your top speed on jobs and Free Drive. Burns fuel fast. Crashes cut the bonus.")
                    NavigationLink {
                        JobBoardView { job in start(.job(job)) }
                    } label: {
                        Text("Job Board").font(.title2.bold())
                    }
                    .accessibilityHint("Pick a delivery. Jobs pay the most.")
                    Button("Free Drive") { start(.freeDrive) }
                        .font(.title2)
                        .accessibilityHint("Roam the map from \(career.state.currentTownName) as long as you like. Pays \(Phrases.money(Int(Payout.freeDriveRatePerKm))) per kilometer.")
                    NavigationLink {
                        CompanyView()
                    } label: {
                        Text("Company").font(.title2)
                    }
                    .accessibilityHint("Hire drivers who deliver for you, even while the game is closed.")
                    NavigationLink {
                        GarageView()
                    } label: {
                        Text("Garage").font(.title2)
                    }
                    .accessibilityHint("Buy trucks, hear their engines and choose which one to drive.")
                    Button("Practice Drive") { start(.practice) }
                        .font(.title2)
                        .accessibilityHint("One lap of the country road, then stop at the drop-off. No pay.")
                    if settings.tutorialDone {
                        Button("Tutorial") { drive = .tutorial }
                            .font(.title2)
                            .accessibilityHint("The guided first drive again: every control, one step at a time.")
                    }
                } footer: {
                    Text("Jobs go from the town you're in to another town and pay the most, with bonuses for arriving on time, not crashing and a perfect stop. Free Drive roams the map and pays a little for every kilometer. Practice Drive is the practice loop and doesn't pay.")
                }
                Section {
                    NavigationLink("What's New") { WhatsNewView() }
                    NavigationLink("Achievements") { AchievementsView() }
                    NavigationLink("How to Drive") { ControlsHelpView() }
                    NavigationLink("Settings") { SettingsView() }
                    NavigationLink("Credits") { CreditsView() }
                }
            }
            .navigationTitle("Truck Sim")
            .onAppear { atMainMenu = true }
            .onDisappear { atMainMenu = false }
        }
        .sheet(isPresented: Binding(get: { showWhatsNew }, set: { if !$0 { settings.whatsNewSeen = Changelog.current } })) {
            NavigationStack { WhatsNewView { settings.whatsNewSeen = Changelog.current } }
        }
        .onAppear {
            // A brand new player gets the welcome setup instead; What's New starts with the next update.
            if !settings.setupDone && settings.whatsNewSeen.isEmpty { settings.whatsNewSeen = Changelog.current }
            if settings.menuMusic { MusicPlayer.shared.playMenu() }
            reportDrivers()
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { reportDrivers() } }
        .alert(driverReport ?? "", isPresented: Binding(get: { driverReport != nil }, set: { if !$0 { driverReport = nil } })) {
            Button("OK", role: .cancel) {}
        }
        .onChange(of: settings.menuMusic) { _, on in
            if on { MusicPlayer.shared.playMenu() } else if MusicPlayer.shared.mode == .menu { MusicPlayer.shared.stop() }
        }
        .alert(achievementTitle, isPresented: Binding(get: { drive == nil && atMainMenu && !career.justUnlocked.isEmpty },
                                                       set: { if !$0 { career.justUnlocked = [] } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(career.justUnlocked.map { "\($0.title): \($0.detail)" }.joined(separator: "\n"))
        }
        .alert("Start a new drive?", isPresented: Binding(get: { replacingSaved != nil },
                                                          set: { if !$0 { replacingSaved = nil } })) {
            Button("Start New Drive", role: .destructive) {
                career.clearSavedDrive()
                drive = replacingSaved
                replacingSaved = nil
            }
            Button("Keep My Saved Drive", role: .cancel) { replacingSaved = nil }
        } message: {
            Text("Your saved drive, \(savedDriveName), will be lost.")
        }
        .fullScreenCover(item: $drive, onDismiss: {
            if settings.menuMusic { MusicPlayer.shared.playMenu() }
            if career.askForRating {
                career.askForRating = false
                // A moment after the menu is back, so it doesn't land on top of the results speech.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { requestReview() }
            }
        }) { mode in
            DrivingScreen(settings: settings, career: career, drive: mode) { drive = nil }
        }
    }
}

struct JobBoardView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var career: CareerStore
    let start: (DeliveryJob) -> Void
    @State private var confirmAbandon = false

    private var phrases: Phrases { Phrases(units: settings.units, electric: career.truck.isElectric) }

    private func fuelText(_ job: DeliveryJob) -> String {
        phrases.fuelCheck(fuelLiters: career.fuelLiters, capacity: career.truck.fuelCapacityLiters, distance: job.distance,
                          cargoKg: job.cargo.massKg, efficiency: career.truck.fuelEfficiency)
    }

    var body: some View {
        List {
            Section {
                let level = career.state.reputationLevel
                Text("Reputation: \(level.title), \(career.state.reputation) points.")
                    .font(.headline)
                if let next = level.next {
                    Text("\(next.threshold - career.state.reputation) more points to \(next.title). Deliver on time, without crashes, and stop on the mark to earn more.")
                }
                if level < .respected {
                    Text(level < .reliable ? "Oversize loads and contracts open at Reliable. Hazmat opens at Respected."
                                           : "Hazmat loads open at Respected.")
                }
            }
            if let contract = career.state.contract {
                Section {
                    Text("\(contract.client): \(contract.cargoName.lowercased()), \(contract.done) of \(contract.total) delivered. Bonus when all are on time: \(Phrases.money(contract.bonus)).")
                    Text("The contract job is first on the board. A late delivery breaks the contract.")
                    Button("Give Up the Contract", role: .destructive) { confirmAbandon = true }
                        .accessibilityHint("Costs 15 reputation points.")
                } header: {
                    Text("Your contract")
                }
            } else if let offer = career.state.contractOffer {
                Section {
                    Text("\(offer.client) wants \(offer.total) loads of \(offer.cargoName.lowercased()) delivered, each on time. Bonus: \(Phrases.money(offer.bonus)) on top of the pay.")
                    Button("Accept the Contract") { career.acceptContract() }
                        .accessibilityHint("Its first job goes to the top of the board. A late delivery breaks the contract and costs reputation.")
                } header: {
                    Text("Contract offer")
                }
            }
            Section {
                ForEach(career.jobs) { job in
                    Button {
                        start(job)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(job.contractID != nil ? "Contract: " : "")\(job.cargo.name): \(Phrases.money(job.pay))").font(.headline)
                            Text(phrases.job(job)).font(.subheadline)
                            Text(fuelText(job)).font(.subheadline)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(phrases.job(job) + " " + fuelText(job))
                    .accessibilityHint("Starts this delivery.")
                }
            } header: {
                Text("Available jobs")
            } footer: {
                Text("Heavy loads accelerate slowly and need more room to brake. Fragile loads are damaged more by crashes. Urgent loads have tighter time limits but pay more.")
            }
            Section {
                let cost = career.state.yardFillCost(for: career.baseTruck)
                let electric = career.truck.isElectric
                Text("\(electric ? "Battery" : "Fuel"): \(Int((career.fuelLiters / career.truck.fuelCapacityLiters * 100).rounded())) percent.")
                if cost > 0 {
                    Button("\(electric ? "Charge" : "Fill Up") at the Yard for \(Phrases.money(cost))") {
                        _ = career.fillAtYard(career.baseTruck)
                    }
                    .accessibilityHint("Truck stops on the road are cheaper.")
                }
            }
            Section {
                Button("Get New Jobs") { career.refreshBoard() }
                    .accessibilityHint("Replaces all three jobs with new ones.")
            }
        }
        .navigationTitle("Job Board")
        .confirmationDialog("Give up the contract with \(career.state.contract?.client ?? "this client")? You lose 15 reputation points and the bonus.",
                            isPresented: $confirmAbandon, titleVisibility: .visible) {
            Button("Give Up the Contract", role: .destructive) { career.abandonContract() }
            Button("Keep It", role: .cancel) {}
        }
    }
}

struct ControlsHelpView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        List {
            Section("Driving") {
                switch settings.steeringMode {
                case .tilt:
                    Text("Hold the phone sideways, at any angle: upright, tilted back or flat. Lower the right end to steer right, the left end to steer left. However you hold it when you start the engine counts as straight (and again when you resume from pause), and small tilts you hold without meaning to slowly become the new straight, so the truck doesn't creep across the lane.")
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
                Text("Bonuses: 10 percent for arriving on time, 10 percent for no crashes, and 5 percent for a perfect stop. Being late takes money off, and each crash damages the cargo: 5 percent of the pay, 10 percent for fragile cargo, never more than 40 percent.")
                Text("Heavy cargo makes the truck slower to speed up and longer to stop, and it burns more fuel.")
                Text("In the last 150 meters before the drop-off you'll hear a beacon, like a parking sensor: the beeps get faster as you get closer and turn into a steady tone right at the drop-off. Stop there for the perfect-stop bonus. If you go past it, the beeps drop lower.")
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
            Section("Traffic and lanes") {
                Text("Roads have two lanes. You drive in the right one. On country and mountain roads the left lane is oncoming traffic; on Interstate 40 the left lane goes your way and is for passing.")
                Text("You hear each vehicle in 3D: oncoming traffic comes at you on your left, rushes past and fades behind. Drift over the center line with someone coming and they honk, and you'll hear Oncoming traffic, get back in your lane. Hitting them is a crash.")
                Text("Slower vehicles appear ahead in your lane: you'll hear Slow pickup ahead, with its distance and speed. Slow down behind it, or pass. To pass, signal left and steer into the left lane, then signal right and steer back. On two-lane roads only pass when you can't hear oncoming traffic.")
                Text("The lane beeps guide you to the lane you mean to be in: your own, or the left lane after you signal left. Traffic can be turned off in Settings.")
            }
            Section("Police and speed limits") {
                Text("Police cars park in every town and along the interstate and country roads. Not every spot has a cop every time. When you pass one you'll hear a police radio crackle.")
                Text("Go more than 8 kilometers or 5 miles per hour over the limit near a cop and you'll hear the siren and Pull over. Slow down and stop to get your ticket: $100 plus $25 for every kilometer per hour over. If you don't stop within 25 seconds, the fine is much bigger.")
                Text("Tickets come off your pay. The dashboard, two-finger double tap, tells you the speed limit where you are.")
            }
            Section("Fuel and truck stops") {
                Text("Fuel stays in your truck between drives. A full tank lasts about an hour of driving. The dashboard, two-finger double tap, says how far your fuel will take you.")
                Text("Truck stops are on Interstate 40 and the longer country roads, and there are three on the practice loop. When your fuel is under half you'll hear one coming, and the three-finger tap always tells you the distance to the next one.")
                Text("To fill up: signal right before the truck stop and slow below 50 kilometers or 30 miles per hour as you reach it. Stop at the pump and wait while it fills. Press the gas to leave early.")
                Text("You're warned at a quarter tank and at 10 percent. If you run out, a tow truck takes you to the next truck stop for $150 and puts in a quarter tank. That costs 2 minutes too. The Job Board tells you if you have enough fuel for each job.")
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
                Toggle("Traffic", isOn: $settings.traffic)
                    .accessibilityHint("Other vehicles on the map's roads. The practice loop never has traffic.")
                Toggle("Back into the loading dock", isOn: $settings.docking)
                    .accessibilityHint("After stopping at a delivery's drop-off, back the trailer into the dock by ear for a bonus.")
                Toggle("Deer on the road", isOn: $settings.wildlife)
                    .accessibilityHint("Deer sometimes step onto country and mountain roads, more at night. Honk to scare them off, or slow down.")
                Toggle("Weather", isOn: $settings.weather)
                    .accessibilityHint("Rain and storms on some drives: slippery roads, rain sounds and a pay bonus. Off means clear skies every time.")
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
                Text("Steering assist Low, Medium or High: steering moves the truck sideways, and when you let go the truck eases back to the middle of your lane (most with High). Curves push you toward the outside, so steer into them, harder when you're faster. Leaving the road slowly puts you on the gravel shoulder; leaving it fast is a crash. Off: realistic steering, much harder by ear.")
            }
            Section {
                Toggle("Captions", isOn: $settings.captions)
                    .accessibilityHint("Shows everything the game says as text on the driving screen.")
                Toggle("Driving buttons", isOn: $settings.drivingButtons)
                    .accessibilityHint("Big on-screen buttons for every action: engine, faster, slower, stop, steering, signals, dashboard, GPS, horn and pause.")
            } header: {
                Text("Accessibility")
            } footer: {
                Text("Driving buttons work with Voice Control (say \"Tap Faster\"), Switch Control and Full Keyboard Access. Faster and Slower change your speed by 10 and hold it, like cruise control; Steer Left and Steer Right nudge the truck. They turn on by themselves when Switch Control is running. Captions start on if Closed Captions is on in your iPhone's Accessibility settings. The driving screen also follows Larger Text, Increase Contrast and Reduce Motion.")
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
            Section {
                Picker("Menus", selection: $settings.menuOrientation) {
                    ForEach(MenuOrientation.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Button("Run the Setup Again") { settings.setupDone = false }
                    .accessibilityHint("The welcome screen that asks which settings suit you.")
            } header: {
                Text("Screen")
            } footer: {
                Text("Driving is always sideways. Menus, the pause menu and the results can be upright, sideways, or follow how you hold the phone.")
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
                NavigationLink("Horn Shop") { HornShopView() }
                    .accessibilityHint("Your horn: \(career.state.horn.title). Train, ship and musical horns for every truck.")
            }
            ForEach(TruckSpec.catalog, id: \.id) { truck in
                Section {
                    Text(phrases.truck(career.upgraded(truck)))
                    if career.state.owns(truck) {
                        let capacity = career.upgraded(truck).fuelCapacityLiters
                        let percent = Int((career.state.fuelLiters(for: truck) / capacity * 100).rounded())
                        let fillCost = career.state.yardFillCost(for: truck)
                        Text("\(truck.isElectric ? "Battery" : "Fuel"): \(percent) percent.")
                        if fillCost > 0 {
                            Button("\(truck.isElectric ? "Charge" : "Fill Up") at the Yard for \(Phrases.money(fillCost))") {
                                let full = career.fillAtYard(truck)
                                let what = truck.isElectric ? "Battery full" : "Tank full"
                                announce(full ? "\(what). \(Phrases.money(career.money)) left in the bank."
                                              : "Not enough money to fill up completely. Got what you could afford.")
                            }
                            .accessibilityHint("Truck stops on the road are cheaper.")
                        }
                        NameField(label: "Name this truck", current: career.state.nickname(for: truck)) { name in
                            career.setNickname(name, for: truck)
                        }
                        NavigationLink("Upgrades") { UpgradesView(truck: truck) }
                            .accessibilityHint("Engine, brakes, tires and fuel tank for the \(truck.name).")
                    }
                    if let driver = career.driver(using: truck) {
                        Text("\(driver.name) drives this truck for your company.")
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
                    let title = truck.price == 0 ? truck.name : "\(truck.name), \(Phrases.money(truck.price))"
                    Text(career.state.nickname(for: truck).map { "\($0): \(title)" } ?? title)
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

struct CompanyView: View {
    @EnvironmentObject private var career: CareerStore
    @State private var message: String?
    @State private var confirmFire: Driver?

    var body: some View {
        let phrases = Phrases(units: .metric)
        List {
            Section {
                Text("Bank: \(Phrases.money(career.money))")
                NameField(label: "Company name", current: career.state.companyName) { career.setCompanyName($0) }
                Text("Drivers deliver jobs in your trucks and earn money for the company, even while the game is closed, for up to 8 hours at a time. Each driver needs a truck other than the one you drive.")
            }
            Section("Your drivers") {
                if career.state.drivers.isEmpty {
                    Text("No drivers yet. Hire one below.")
                }
                ForEach(career.state.drivers) { driver in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(phrases.driver(driver))
                        if let truckID = driver.truckID {
                            Text("Driving the \(TruckSpec.withID(truckID).name). \(driver.jobsDone) jobs delivered, \(Phrases.money(driver.earned)) earned.")
                        } else {
                            Text("Waiting for a truck. \(driver.jobsDone) jobs delivered, \(Phrases.money(driver.earned)) earned.")
                        }
                    }
                    .accessibilityElement(children: .combine)
                    if let raise = driver.raiseRequest {
                        Text("\(driver.name) has the experience to become a \(driver.skill + 1)-star driver and asks for a raise of \(Phrases.money(raise)). Answer within \(driver.deliveriesUntilQuit ?? Driver.patience) more deliveries, or they may quit.")
                        Button("Give \(driver.name) the Raise: \(Phrases.money(raise))") { giveRaise(driver) }
                            .accessibilityHint("They become a \(driver.skill + 1)-star driver: faster, and they earn more for the company.")
                        Button("Not Now") { career.declineRaise(driver) }
                            .accessibilityHint("They keep working as they are and ask again after \(Driver.patience) more deliveries.")
                    } else if let needed = Driver.deliveriesForRaise(skill: driver.skill) {
                        Text("\(max(0, needed - driver.jobsDone)) more deliveries until \(driver.name) can move up a star.")
                    }
                    ForEach(career.state.freeTrucks, id: \.id) { truck in
                        Button("Give \(driver.name) the \(truck.name)") { career.assign(driver, to: truck) }
                    }
                    if driver.truckID != nil {
                        Button("Park \(driver.name)'s truck") { career.assign(driver, to: nil) }
                            .accessibilityHint("They stop working until you give them a truck again.")
                    }
                    Button("Let \(driver.name) go", role: .destructive) { confirmFire = driver }
                }
            }
            Section {
                ForEach(career.state.candidates) { candidate in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(phrases.driver(candidate))
                        Button("Hire for \(Phrases.money(candidate.hireFee))") { hire(candidate) }
                    }
                }
            } header: {
                Text("Drivers looking for work")
            } footer: {
                Text("Better drivers cost more to hire but deliver faster. You still earn the most by driving yourself.")
            }
        }
        .navigationTitle("Company")
        .onAppear { career.refreshDrivers() }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        }
        .confirmationDialog("Let \(confirmFire?.name ?? "this driver") go? The hiring fee isn't refunded.",
                            isPresented: Binding(get: { confirmFire != nil }, set: { if !$0 { confirmFire = nil } }),
                            titleVisibility: .visible) {
            Button("Let Them Go", role: .destructive) {
                if let d = confirmFire { career.fire(d) }
                confirmFire = nil
            }
        }
    }

    private func giveRaise(_ driver: Driver) {
        switch career.giveRaise(driver) {
        case let .promoted(stars):
            message = "\(driver.name) is now a \(stars)-star driver! Faster deliveries, more money for the company."
        case let .notEnoughMoney(short):
            message = "You need \(Phrases.money(short)) more for that raise."
        case .noRequest:
            break
        }
    }

    private func hire(_ candidate: Driver) {
        switch career.hire(candidate) {
        case .hired:
            if let hired = career.state.drivers.last, let truckID = hired.truckID {
                message = "You hired \(candidate.name). They're out on the road in the \(TruckSpec.withID(truckID).name)."
            } else {
                message = "You hired \(candidate.name). They're waiting for a truck: every truck you own is already in use, by you or your drivers. Buy another truck in the Garage, and give it to them here."
            }
        case let .notEnoughMoney(short):
            message = "Not enough money. You need \(Phrases.money(short)) more."
        case .notACandidate:
            break
        }
    }
}

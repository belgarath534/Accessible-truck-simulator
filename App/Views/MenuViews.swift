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
                        .accessibilityHint("Drive the loop as long as you like. Pays \(Phrases.money(Int(Payout.freeDriveRatePerKm))) per kilometer.")
                    Button("Practice Drive") { drive = .practice }
                        .font(.title2)
                        .accessibilityHint("One lap of the country road, then stop at the drop-off. No pay.")
                } footer: {
                    Text("Jobs pay the most, with bonuses for arriving on time, not crashing and a perfect stop. Free Drive pays a little for every kilometer. Practice Drive doesn't pay.")
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
                    Text("Hold the phone sideways like a steering wheel, screen facing you. Tilt it to steer. The position you hold it in when you start counts as straight.")
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

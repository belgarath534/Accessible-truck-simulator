import SimCore
import SwiftUI

struct MainMenuView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var trip: TripGoal?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Practice Drive") { trip = .practice(on: .practiceLoop) }
                        .font(.title2.bold())
                        .accessibilityHint("One lap of the country road, then stop at the drop-off.")
                    Button("Free Drive") { trip = .freeDrive }
                        .font(.title2)
                        .accessibilityHint("Drive the loop as long as you like, with no destination.")
                } footer: {
                    Text("Practice Drive is one \(settings.units.distance(Road.practiceLoop.totalLength)) lap with curves of every kind, ending at a drop-off where you stop the truck. Free Drive never ends: pause and quit when you're done.")
                }
                Section {
                    NavigationLink("How to Drive") { ControlsHelpView() }
                    NavigationLink("Settings") { SettingsView() }
                }
            }
            .navigationTitle("Truck Sim")
        }
        .fullScreenCover(isPresented: Binding(get: { trip != nil }, set: { if !$0 { trip = nil } })) {
            if let trip {
                DrivingScreen(settings: settings, goal: trip) { self.trip = nil }
            }
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
            Section("Keyboard and controller") {
                Text("Keyboard: Up or W accelerate, Down or S brake, Left and Right or A and D steer. Left and right bracket for signals, I dashboard, G GPS, N engine, H horn, Escape pause.")
                Text("Controller: right trigger accelerate, left trigger brake, left stick steer, shoulder buttons for signals, A dashboard, X GPS, Y engine, B horn, Menu pause.")
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
                Text("Steering assist straightens the truck on straight roads when you're not steering. You always have to steer through curves yourself.")
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

import SimCore
import SwiftUI

/// The first time the game opens: pick the settings that suit you. Everything can be changed later in Settings,
/// and this screen can be run again from there.
struct SetupView: View {
    @EnvironmentObject private var settings: AppSettings
    @AccessibilityFocusState private var titleFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Welcome to Accessible Truck Simulator! Let's set the game up the way that works best for you. You can change any of this later in Settings.")
                        .accessibilityFocused($titleFocused)
                }

                Section {
                    Picker("Speech", selection: $settings.speechOutput) {
                        Text("The game's own voice").tag(SpeechOutput.gameVoice)
                        Text("Through VoiceOver").tag(SpeechOutput.voiceOver)
                    }
                    Toggle("Captions: show what the game says as text", isOn: $settings.captions)
                } header: {
                    Text("Hearing and seeing")
                } footer: {
                    Text("The game's own voice uses your VoiceOver voice and speed and can talk over other sounds. Through VoiceOver sends everything to VoiceOver as announcements. Captions are for deaf and hard-of-hearing players, or anyone who likes to read along.")
                }

                Section {
                    Picker("Steering", selection: $settings.steeringMode) {
                        Text("Tilt the phone like a steering wheel").tag(TouchSteeringMode.tilt)
                        Text("One-finger joystick").tag(TouchSteeringMode.joystick)
                    }
                    Picker("Steering help", selection: $settings.assist) {
                        Text("High: easiest").tag(SteeringAssist.high)
                        Text("Medium").tag(SteeringAssist.medium)
                        Text("Low").tag(SteeringAssist.low)
                        Text("Off: realistic, hardest").tag(SteeringAssist.off)
                    }
                    Toggle("Driving buttons for Voice Control and Switch Control", isOn: $settings.drivingButtons)
                    Toggle("Lane guidance beeps", isOn: $settings.laneGuidanceTone)
                    Toggle("Vibration", isOn: $settings.haptics)
                } header: {
                    Text("Driving")
                } footer: {
                    Text("With steering help on, the truck eases back to the middle of your lane when you're not steering. Driving buttons put big buttons on screen for every action, for players who can't use multi-finger gestures. Lane guidance beeps play in the ear you're drifting toward.")
                }

                Section {
                    Toggle("Weather: rain and storms", isOn: $settings.weather)
                    Toggle("Traffic", isOn: $settings.traffic)
                    Toggle("Deer on the road", isOn: $settings.wildlife)
                } header: {
                    Text("The road")
                } footer: {
                    Text("Weather makes some drives rainy: slippery roads, but deliveries pay extra. Traffic adds other vehicles you can hear around you. Deer sometimes step onto country roads, more at night: honk or slow down.")
                }

                Section {
                    Picker("Menus", selection: $settings.menuOrientation) {
                        ForEach(MenuOrientation.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    Picker("Units", selection: $settings.units) {
                        Text("Miles").tag(UnitSystem.imperial)
                        Text("Kilometers").tag(UnitSystem.metric)
                    }
                } header: {
                    Text("Screen and units")
                } footer: {
                    Text("Driving is always sideways. Menus can be upright, sideways, or follow how you hold the phone.")
                }

                Section {
                    Button("Done: Start Playing") { settings.setupDone = true }
                        .font(.title3.bold())
                        .accessibilityHint("Saves these settings. The main menu starts with the tutorial.")
                }
            }
            .navigationTitle("Welcome")
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { titleFocused = true }
        }
    }
}

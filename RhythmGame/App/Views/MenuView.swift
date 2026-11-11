import BeatCore
import SwiftUI

struct MenuView: View {
    @EnvironmentObject private var settings: GameSettings
    @AppStorage("seenHowToPlay") private var seenHowToPlay = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink("Play") { SongListView() }
                        .font(.title2)
                        .accessibilityHint("Pick a song.")
                    NavigationLink("Learn the Sounds") { LearnView() }
                        .accessibilityHint("Hear each move's sound and practise the gestures.")
                    NavigationLink("How to Play") { HowToPlayView() }
                } footer: {
                    Text(seenHowToPlay ? "" : "New here? Start with How to Play, then Learn the Sounds.")
                }
                Section {
                    NavigationLink("Calibrate Timing") { CalibrationView() }
                        .accessibilityHint("Tap along to a beat so the game knows your phone's or headphones' delay.")
                    NavigationLink("Settings") { SettingsView() }
                }
            }
            .navigationTitle("Beat by Ear")
        }
    }
}

struct HowToPlayView: View {
    @AppStorage("seenHowToPlay") private var seenHowToPlay = false

    var body: some View {
        List {
            Section("The idea") {
                Text("Beat by Ear is call and response. You hear a soft bell, then a bar of cue sounds. In the next bar, you do the same moves on the same beats. Then another bell, and so on until the song ends.")
                Text("Wear headphones if you can: left and right sounds come from their side.")
            }
            Section("The moves") {
                ForEach(Move.allCases, id: \.self) { m in
                    Text("\(m.name): \(m.soundDescription).")
                }
                Text("Anywhere on the screen works. Time the moment your finger touches down to the beat.")
            }
            Section("While playing") {
                Text("VoiceOver steps aside during a song, so your touches go straight to the game.")
                Text("You feel every hit: a strong tap for perfect, a soft one for good, a buzz for a miss.")
                Text("Ten in a row doubles your points, twenty triples them, thirty is four times.")
                Text("Two-finger tap to stop the song.")
            }
            Section("Timing") {
                Text("If hits feel late or early, especially with Bluetooth headphones or AirPods, use Calibrate Timing on the main menu.")
            }
        }
        .navigationTitle("How to Play")
        .onAppear { seenHowToPlay = true }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var settings: GameSettings

    var body: some View {
        Form {
            Section {
                Toggle("Vibration", isOn: $settings.haptics)
                Toggle("Hit sounds", isOn: $settings.hitSounds)
            } footer: {
                Text("Hit sounds are a short tick when you hit and a low thud when you miss.")
            }
            Section {
                Text("Timing offset: \(Int((settings.calibration * 1000).rounded())) milliseconds.")
                Button("Reset timing to zero") { settings.calibration = 0 }
            } footer: {
                Text("Set this with Calibrate Timing on the main menu.")
            }
        }
        .navigationTitle("Settings")
    }
}

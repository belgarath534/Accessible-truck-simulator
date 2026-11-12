import FlightCore
import SwiftUI

struct HowToFlyView: View {
    @EnvironmentObject private var settings: FlightSettings

    var body: some View {
        List {
            Section("Holding the phone") {
                Text("Hold the phone sideways in both hands, like the yoke of a plane. The way you hold it when a flight starts counts as level.")
                Text("Tilt the top edge back toward you to raise the nose and climb. Tip it forward, away from you, to lower the nose and descend.")
                Text("Turn the phone like a steering wheel to bank: lower the right end to bank right. Banking turns the plane. On the runway, the same movement steers the nose wheel.")
                Text("Can't tilt? In Settings, choose Touch stick: a finger on the left half of the screen is the stick. Push up for nose down, pull down for nose up, left and right to bank.")
            }
            Section("Gestures") {
                ForEach(GestureMap.help, id: \.self) { h in
                    Text("\(h.gesture): \(h.action).")
                }
            }
            Section("Flying by ear") {
                Text("Engine: the propeller gets louder and higher with throttle. Wind: louder the faster you fly.")
                Text("Runway centerline: on the runway, a pulsing beep comes from the side you're drifting toward. Steer away from it. Silence means you're centered.")
                Text("Climb tone: rising beeps when you climb, faster the steeper. A low hum when you descend. Silence means level flight.")
                Text("Bank tone: a soft tone from the low wing. Level the wings and it goes quiet.")
                Text("Beacon: a short beep every second or two from the direction of the airport. High when it's ahead, low when it's behind. Turn until it's in the middle.")
                Text("Landing tones: once you're lined up with the runway, the beacon turns into faster beeps. They come from the side to steer toward. A higher pitch means you're too low, so climb a little. A lower pitch means you're too high, so descend.")
                Text("Height callouts near the airport: 1,000, 500, 200, 100, 50, 40, 30, 20, 10 feet. At about 20 feet, raise the nose a little and cut the throttle to land softly.")
                Text("Stall horn: a harsh beeping means you're too slow. Lower the nose and add power.")
            }
            Section("Landing") {
                Text("Slow down before the airport: throttle about 30 percent, flaps 1 below 85 knots, and about 65 knots on the approach. Easy assist holds landing speed for you.")
                Text("After touchdown: throttle idle, and hold one finger still on the screen to brake. Stop on the runway to finish.")
            }
            Section("Assists") {
                Text("Easy: the wings level themselves, the nose eases back to level when you let go, the plane won't pull into a stall, and the throttle holds landing speed on approach. Standard: the wings level themselves. Off: you fly it all.")
                Text("Autopilot: three-finger swipe up holds your height and heading. Move the controls firmly to take over.")
            }
        }
        .navigationTitle("How to Fly")
        .onAppear { settings.seenHowToFly = true }
    }
}

struct LogbookView: View {
    @EnvironmentObject private var settings: FlightSettings

    var body: some View {
        List {
            ForEach(settings.logbook.lines, id: \.self) { Text($0) }
        }
        .navigationTitle("Logbook")
    }
}

struct SettingsView: View {
    @EnvironmentObject private var settings: FlightSettings

    var body: some View {
        Form {
            Section {
                Picker("Controls", selection: $settings.controlMode) {
                    ForEach(ControlMode.allCases, id: \.self) { Text($0.name).tag($0) }
                }
                Picker("Assist", selection: $settings.assist) {
                    ForEach(FlightAssist.allCases, id: \.self) { Text($0.name).tag($0) }
                }
                Toggle("Invert nose up and down", isOn: $settings.invertPitch)
                Picker("Tilt sensitivity", selection: $settings.tiltRange) {
                    Text("High").tag(15.0)
                    Text("Medium").tag(22.0)
                    Text("Low").tag(32.0)
                }
            } header: {
                Text("Controls")
            } footer: {
                Text("Assist changes take effect on your next flight.")
            }
            Section("Sounds") {
                Toggle("Menu music", isOn: $settings.menuMusic)
                Toggle("Climb and descent tone", isOn: $settings.varioTone)
                Toggle("Bank tone", isOn: $settings.bankTone)
                Toggle("Speak through VoiceOver", isOn: $settings.useVoiceOver)
            }
        }
        .navigationTitle("Settings")
    }
}

struct CreditsView: View {
    var body: some View {
        List {
            Section("Sounds") {
                Text("Propeller engine: \"Airplane Prop Loop\" by AntumDeluge, made from airplane prop noise by jakobthiesen. Licensed under Creative Commons Attribution 3.0. From OpenGameArt.org.")
                Text("Runway rumble: \"Background Rumble Noise\" by gryc. Licensed under Creative Commons Attribution 3.0. From OpenGameArt.org.")
                Text("Wind: \"Short wind sound\" by remaxim, public domain (CC0). From OpenGameArt.org.")
                Text("Every other sound, the beeps, tones and warnings, is made live by the game.")
            }
            Section("Music") {
                Text("\"Blue Sky\" by Pro Sensory, public domain (CC0). From OpenGameArt.org.")
                Text("\"Determined to Fly\" by OwlishMedia, from the animated short Cat's Sky, public domain (CC0). From OpenGameArt.org.")
            }
        }
        .navigationTitle("Credits")
    }
}

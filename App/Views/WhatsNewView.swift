import SwiftUI

/// Every version and what it added, plus what's coming. Shown once by itself after an update, and from the menu.
enum Changelog {
    struct Version: Identifiable {
        let number: String
        let title: String
        let items: [String]
        var id: String { number }
    }

    /// Newest first. Add to the top for each update.
    static let versions: [Version] = [
        Version(number: "1.2", title: "The Big Road Update", items: [
            "Save and Continue Later: pause a long drive and pick it up from the main menu, right where you left off.",
            "Drivers grow: after 20 deliveries they ask for a raise to move up a star. Pay it and they're faster and earn more. Ignore them for too long and they quit.",
            "A welcome setup the first time you play, to pick the settings that suit you. Run it again any time from Settings.",
            "Menus are upright now; driving stays sideways. Prefer sideways menus? Settings, Screen.",
            "A warning before each junction when your turn signal doesn't match the GPS route, so you don't miss your turn.",
            "Vibration comes back after you leave the game and return.",
            "VoiceOver stays on the driving screen during a drive.",
            "This What's New page.",
        ]),
        Version(number: "1.1", title: "Big Update", items: [
            "Eight new trucks: 11 in all, each with its own recorded engine sound and its own feel, including the electric Volt and the V12 Titan.",
            "Weather: rain and storms you hear on the cab, with wipers and thunder. Wet roads are slippery, and deliveries pay extra.",
            "23 achievements and Game Center leaderboards.",
            "Captions, driving buttons for Voice Control and Switch Control, Larger Text, Increase Contrast and Reduce Motion.",
            "iPad support.",
            "Steadier steering: the truck eases back to the middle of your lane when you're not steering.",
        ]),
        Version(number: "1.0", title: "First release", items: [
            "Drive a truck by sound: engine, lane beeps, rumble strips and curves called out ahead.",
            "A guided tutorial and a practice road.",
            "Jobs between towns with turn-by-turn GPS, money, three trucks, upgrades, fuel and truck stops.",
            "Police, traffic, hired drivers and a truck radio.",
        ]),
    ]

    static let comingSoon: [String] = [
        "Town sounds: seagulls in Ridgeport, the steel mill in Ironton, the farm in Bayview, the sawmill in Cedar Falls.",
        "Day and night, deer on the road, construction zones and toll booths.",
        "A horn shop, and naming your truck and company.",
        "Backing into the loading dock by ear.",
        "Special cargo: livestock, refrigerated loads, oversize loads and hazmat.",
        "Company contracts, reputation and weigh stations.",
        "A dispatcher with a real voice, CB radio chatter and a radio DJ.",
        "Hills, snow and ice, tire blowouts and detours.",
        "Truck wear, depots in other towns and bank loans.",
    ]

    static var current: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? versions[0].number }
}

struct WhatsNewView: View {
    /// Shown by itself after an update: has a "Let's Drive" button to close it.
    var onDone: (() -> Void)?
    @AccessibilityFocusState private var titleFocused: Bool

    var body: some View {
        List {
            ForEach(Changelog.versions) { version in
                Section {
                    ForEach(version.items, id: \.self) { Text($0) }
                } header: {
                    if version.number == Changelog.versions[0].number {
                        Text("Version \(version.number): \(version.title)")
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityFocused($titleFocused)
                    } else {
                        Text("Version \(version.number): \(version.title)")
                            .accessibilityAddTraits(.isHeader)
                    }
                }
            }
            Section {
                ForEach(Changelog.comingSoon, id: \.self) { Text($0) }
            } header: {
                Text("Coming soon").accessibilityAddTraits(.isHeader)
            } footer: {
                Text("Have an idea or found a problem? We'd love to hear it: what players ask for shapes every update.")
            }
            if let onDone {
                Section {
                    Button("Let's Drive", action: onDone).font(.title3.bold())
                }
            }
        }
        .navigationTitle("What's New")
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { titleFocused = true } }
    }
}

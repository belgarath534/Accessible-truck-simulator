import SwiftUI

/// Every version and what it added, plus what's coming. Shown once by itself after an update, and from the menu.
enum Changelog {
    struct Version: Identifiable {
        let number: String
        let title: String
        let items: [String]
        var id: String { number }
        /// "Version 1.1: Big Update", or "Test build 5: The very first drive" for the builds before the App Store.
        var heading: String { number.contains(".") ? "Version \(number): \(title)" : "Test build \(number): \(title)" }
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
            "Day and night, from your phone's clock: crickets and quiet roads at night, birds at dawn.",
            "Deer on country and mountain roads, more of them at night. You hear them ahead: honk to scare them off, or slow right down. Turn them off in Settings.",
            "Construction zones: machines, backup beepers and a 25 mph (40 km/h) limit.",
            "Toll booths on Interstate 40: slow down to pay $5, or blow through and get a $75 fine.",
            "Every town sounds different: seagulls in Ridgeport, the steel mill in Ironton, the farm in Bayview, the sawmill in Cedar Falls.",
            "The Horn Shop in the Garage: train, ship, musical and twin trumpet horns. Try each one before you buy.",
            "Name your trucks and your company. Your truck's name is called out when you start a drive.",
            "Turbo Mode, a switch on the main menu: no speed limit, toward 200 mph, with your speed called out every 25 mph. Earn a bonus for your top speed on top of the normal pay. No police, but it burns fuel fast and crashes cut the bonus. Thanks to Reece for the idea!",
            "Weigh stations on the longer country roads: signal right and slow down to pull in, or get a $200 fine.",
            "Special cargo: livestock you can hear in the trailer (brake gently or they get scared), refrigerated loads with a humming cooling unit that spoil if you're late, oversize loads you must keep under 45 mph, and hazmat: the best pay, but one crash spills the load.",
            "Reputation, from Rookie to Legend: deliver on time, without crashes and stop on the mark to climb. Higher reputation pays more and unlocks oversize loads, hazmat and contracts.",
            "Company contracts: a client wants several loads delivered on time, for a big bonus at the end. Be late once and the contract is broken.",
            "Back into the loading dock by ear after each delivery: the beeps speed up as you get close, the backup alarm sounds, and the lane beep tells you if the trailer is crooked. A perfect dock pays a bonus. Skip it from the pause menu, or turn it off in Settings.",
            "Three new achievements: Oh Deer, Make Some Noise and Speed Demon. And a new Top Speed leaderboard.",
        ]),
        Version(number: "1.1", title: "Big Update", items: [
            "Eight new trucks: 11 in all, each with its own recorded engine sound and its own feel, including the electric Volt and the V12 Titan.",
            "Weather: rain and storms you hear on the cab, with wipers and thunder. Wet roads are slippery, and deliveries pay extra.",
            "23 achievements and Game Center leaderboards.",
            "Captions, driving buttons for Voice Control and Switch Control, Larger Text, Increase Contrast and Reduce Motion.",
            "iPad support.",
            "Steadier steering: the truck eases back to the middle of your lane when you're not steering.",
        ]),
        Version(number: "1.0", title: "First release on the App Store", items: [
            "Everything from the test builds below, approved by Apple and free for everyone.",
            "Drive a truck by sound: engine, lane beeps, rumble strips and curves called out ahead.",
            "A guided tutorial and a practice road.",
            "Jobs between towns with turn-by-turn GPS, money, three trucks, upgrades, fuel and truck stops.",
            "Police, traffic, hired drivers and a truck radio.",
        ]),
    ]

    /// The test builds before the App Store, oldest last. The whole game went from nothing to the App Store in a
    /// day, November 7, 2026, tested build by build on TestFlight.
    static let earlyBuilds: [Version] = [
        Version(number: "23", title: "The tutorial", items: [
            "A guided first drive that teaches every control, one step at a time.",
            "Traffic off by default; turn it on in Settings.",
            "This build became version 1.0.",
        ]),
        Version(number: "21", title: "Traffic", items: [
            "Oncoming cars, slower vehicles ahead to pass, and a passing lane on the interstate, all in 3D sound.",
        ]),
        Version(number: "20", title: "The drop-off beacon", items: [
            "Beeps like a parking sensor in the last 150 meters, so you can stop right on the drop-off.",
            "The fuel check before a job uses real measured fuel use.",
        ]),
        Version(number: "19", title: "Fairer money", items: [
            "Fuel, tows and crash costs rebalanced, after a job that should have paid $2,000 paid about $300.",
            "A warning before a job if you don't have enough fuel.",
        ]),
        Version(number: "18", title: "Hired drivers", items: [
            "Hire drivers who deliver in your trucks and earn money, even while the game is closed.",
        ]),
        Version(number: "17", title: "Air horn and police", items: [
            "A real air horn for every truck.",
            "Police cars that give you a ticket for speeding, but only when one is nearby.",
        ]),
        Version(number: "16", title: "The map", items: [
            "Towns, highways and turn-by-turn GPS: signal left or right at each junction.",
        ]),
        Version(number: "15", title: "Menu music fix", items: [
            "The menu music comes back after a drive.",
        ]),
        Version(number: "14", title: "Fuel and truck stops", items: [
            "Fuel runs down as you drive. Signal right to pull into a truck stop and fill up, or get towed.",
        ]),
        Version(number: "13", title: "Upgrades", items: [
            "Upgrade the engine, brakes, tires and fuel tank.",
        ]),
        Version(number: "12", title: "The garage", items: [
            "Three trucks to buy, each with its own engine sound: Old Reliable, the Workhorse and the Road King.",
        ]),
        Version(number: "11", title: "Tilt fix", items: [
            "Tilt steering works however you hold the phone, even flat.",
        ]),
        Version(number: "10", title: "Easier steering", items: [
            "Steering help: the truck moves sideways when you steer and stops drifting when you let go. Made after a first delivery with 111 crashes.",
        ]),
        Version(number: "9", title: "Money and jobs", items: [
            "Money in the bank, delivery jobs with pay and bonuses, and pay for Free Drive.",
        ]),
        Version(number: "8", title: "A real engine", items: [
            "Recorded engine sounds for Old Reliable, and new upbeat music.",
        ]),
        Version(number: "7", title: "Music", items: [
            "Menu music and a radio in the truck.",
        ]),
        Version(number: "6", title: "Drives that end", items: [
            "The practice drive ends at a drop-off, and the pause menu shows how your trip is going.",
        ]),
        Version(number: "5", title: "The very first drive", items: [
            "One truck on a practice road full of curves.",
            "Start the engine, accelerate, brake and steer by tilting the phone or with a one-finger joystick.",
            "Lane beeps in the ear you're drifting toward, rumble strips, curves called out ahead, and a spoken dashboard.",
        ]),
    ]

    static let comingSoon: [String] = [
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
                        Text(version.heading)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityFocused($titleFocused)
                    } else {
                        Text(version.heading).accessibilityAddTraits(.isHeader)
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
            Section {
                Text("Accessible Truck Simulator went from nothing to the App Store in one day, November 7, 2026, tested build by build. Here's how it grew, newest first.")
            } header: {
                Text("Before the App Store").accessibilityAddTraits(.isHeader)
            }
            ForEach(Changelog.earlyBuilds) { build in
                Section {
                    ForEach(build.items, id: \.self) { Text($0) }
                } header: {
                    Text(build.heading).accessibilityAddTraits(.isHeader)
                }
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

import AVFoundation
import SimCore
import SwiftUI

/// Plays a horn recording once, for trying horns in the shop.
final class HornPreview {
    private var player: AVAudioPlayer?

    func play(_ horn: Horn, volume: Double) {
        let name = horn.soundFile
        guard let url = ["wav", "m4a", "caf", "mp3"].lazy.compactMap({
            Bundle.main.url(forResource: name, withExtension: $0)
                ?? Bundle.main.url(forResource: name, withExtension: $0, subdirectory: "Sounds")
        }).first else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        player = try? AVAudioPlayer(contentsOf: url)
        player?.volume = Float(volume)
        player?.play()
    }
}

/// Buy horns and choose which one your trucks use.
struct HornShopView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var career: CareerStore
    @State private var message: String?
    private let preview = HornPreview()

    var body: some View {
        List {
            Section {
                Text("Bank: \(Phrases.money(career.money))")
                Text("Your horn: \(career.state.horn.title).")
            } footer: {
                Text("A horn fits every truck you own. Honk with a two-finger swipe up while driving, the Horn button, H on a keyboard or B on a controller.")
            }
            ForEach(Horn.allCases, id: \.self) { horn in
                Section {
                    Text(horn.detail)
                    Button("Hear It") { preview.play(horn, volume: settings.volume) }
                    if career.state.horn == horn {
                        Text("On your trucks now.").font(.headline)
                    } else if career.state.ownsHorn(horn) {
                        Button("Use This Horn") {
                            career.selectHorn(horn)
                            message = "Your trucks now have the \(horn.title.lowercased())."
                        }
                    } else {
                        Button("Buy for \(Phrases.money(horn.price))") { buy(horn) }
                            .accessibilityHint(career.money >= horn.price
                                ? "It goes on your trucks right away."
                                : "You need \(Phrases.money(horn.price - career.money)) more.")
                    }
                } header: {
                    Text(horn.price == 0 ? horn.title : "\(horn.title), \(Phrases.money(horn.price))")
                }
            }
        }
        .navigationTitle("Horn Shop")
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    private func buy(_ horn: Horn) {
        switch career.buyHorn(horn) {
        case .bought:
            message = "You bought the \(horn.title.lowercased()). It's on your trucks now. \(Phrases.money(career.money)) left in the bank."
        case .alreadyOwned:
            career.selectHorn(horn)
        case let .notEnoughMoney(short):
            message = "Not enough money. You need \(Phrases.money(short)) more."
        }
    }
}

/// A text field for a name that saves when you press Done or leave the screen.
struct NameField: View {
    let label: String
    let current: String?
    let save: (String) -> Void
    @State private var text = ""

    var body: some View {
        TextField(label, text: $text)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .accessibilityLabel(label)
            .accessibilityHint("Type a name, then Done. Up to \(CareerState.maxNameLength) letters. Leave it empty for no name.")
            .onAppear { text = current ?? "" }
            .onSubmit { save(text) }
            .onDisappear { if text != (current ?? "") { save(text) } }
    }
}

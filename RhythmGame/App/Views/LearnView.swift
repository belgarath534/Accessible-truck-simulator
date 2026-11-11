import BeatCore
import SwiftUI

struct LearnView: View {
    var body: some View {
        List {
            Section {
                ForEach(Move.allCases, id: \.self) { move in
                    Button("\(move.name): \(move.soundDescription)") { AudioOut.shared.playCue(move) }
                        .accessibilityHint("Plays its sound.")
                }
            } header: {
                Text("Hear each sound")
            }
            Section {
                NavigationLink("Practice Pad") { PracticePadView() }
                    .accessibilityHint("Try the gestures: each one plays its sound and says its name.")
            }
        }
        .navigationTitle("Learn the Sounds")
    }
}

/// Free practice: every gesture plays its sound and says what it was.
struct PracticePadView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var last = "Try a move"

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Text(last).font(.largeTitle.bold()).accessibilityHidden(true)
            TouchPad(label: "Practice pad",
                     hint: "Tap or swipe left, right or up. Two-finger tap to go back.",
                     onMove: { move, _ in
                         AudioOut.shared.playCue(move)
                         last = move.name
                         Speaker.say(move.name)
                     },
                     onStop: { dismiss() })
                .ignoresSafeArea()
        }
        .navigationTitle("Practice Pad")
        .navigationBarTitleDisplayMode(.inline)
    }
}

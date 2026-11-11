import BeatCore
import SwiftUI

struct PlayScreen: View {
    @StateObject private var controller: PlayController
    let close: () -> Void
    private let song: Song
    private let difficulty: Difficulty
    private let settings: GameSettings

    init(song: Song, difficulty: Difficulty, settings: GameSettings, close: @escaping () -> Void) {
        _controller = StateObject(wrappedValue: PlayController(song: song, difficulty: difficulty, settings: settings))
        self.song = song
        self.difficulty = difficulty
        self.settings = settings
        self.close = close
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch controller.phase {
            case .loading, .playing:
                playing
            case .finished, .stopped:
                ResultsView(controller: controller, close: close)
            }
        }
        .onAppear { controller.start() }
        .onDisappear { controller.leave() }
        .statusBarHidden()
    }

    private var playing: some View {
        ZStack {
            VStack(spacing: 24) {
                Text(song.title).font(.title.bold())
                Text(controller.phase == .loading ? "Get ready…" : (controller.lastJudgement?.spoken ?? "Listen…"))
                    .font(.system(size: 54, weight: .heavy))
                    .foregroundStyle(color)
                Text("Combo \(controller.combo)").font(.title2)
                Text("Score \(controller.score)").font(.title3)
                Text("Two-finger tap to stop").font(.footnote).foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)
            TouchPad(label: "Play area",
                     hint: "Touches go straight to the game. Two-finger tap to stop.",
                     onMove: { move, time in controller.move(move, at: time) },
                     onStop: { controller.stop() })
                .ignoresSafeArea()
        }
    }

    private var color: Color {
        switch controller.lastJudgement {
        case .perfect: return .yellow
        case .good: return .green
        case .miss, .wrongMove: return .red
        case nil: return .white
        }
    }
}

struct ResultsView: View {
    @ObservedObject var controller: PlayController
    let close: () -> Void

    var body: some View {
        let judge = controller.judge
        List {
            Section {
                if controller.phase == .stopped {
                    Text("Song stopped.").font(.title2.bold())
                } else {
                    Text("Grade \(judge.grade)").font(.largeTitle.bold())
                    if controller.newBest { Text("New best score!").font(.title3) }
                }
                Text("Score: \(judge.score)")
                Text("Accuracy: \(judge.accuracy) percent")
                Text("Perfect: \(judge.count(.perfect)). Good: \(judge.count(.good)). Missed: \(judge.count(.miss) + judge.count(.wrongMove)).")
                Text("Best combo: \(judge.bestCombo)")
            }
            Section {
                Button("Back to Songs", action: close)
            }
        }
        .scrollContentBackground(.hidden)
    }
}

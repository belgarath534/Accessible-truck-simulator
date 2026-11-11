import BeatCore
import SwiftUI

struct SongListView: View {
    @EnvironmentObject private var settings: GameSettings
    @State private var playing: Song?

    var body: some View {
        List {
            Section {
                Picker("Difficulty", selection: $settings.difficulty) {
                    ForEach(Difficulty.allCases, id: \.self) { Text($0.name).tag($0) }
                }
            } footer: {
                Text("Easy starts with taps only and adds swipes as you go. Hard has more notes, including half beats.")
            }
            Section("Songs") {
                ForEach(Song.all) { song in
                    Button {
                        playing = song
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(song.title).font(.headline)
                            Text("\(song.style), \(Int(song.bpm)) beats per minute").font(.subheadline)
                            let best = settings.best(song, settings.difficulty)
                            if best > 0 { Text("Best on \(settings.difficulty.name): \(best)").font(.subheadline) }
                        }
                    }
                    .accessibilityHint("Starts the song.")
                }
            }
        }
        .navigationTitle("Songs")
        .fullScreenCover(item: $playing) { song in
            PlayScreen(song: song, difficulty: settings.difficulty, settings: settings) { playing = nil }
        }
    }
}

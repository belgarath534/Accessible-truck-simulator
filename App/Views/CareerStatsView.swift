import SwiftUI
import SimCore

/// Career stats: everything you've done, one line each, so VoiceOver reads it a line at a time.
struct CareerStatsView: View {
    @EnvironmentObject private var career: CareerStore
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        List {
            Section {
                ForEach(career.state.statsLines(units: settings.units), id: \.self) { Text($0) }
            }
            Section {
                Text(career.state.raceStatus())
                Text(career.state.streakDays > 0
                     ? "Daily streak: \(career.state.streakDays) day\(career.state.streakDays == 1 ? "" : "s")."
                     : "No daily streak yet. Deliver a load today to start one.")
            } header: {
                Text("This week")
            }
        }
        .navigationTitle("Career Stats")
    }
}

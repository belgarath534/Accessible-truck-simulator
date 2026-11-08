import SimCore
import SwiftUI

/// Every achievement, earned or not, with how to earn it. Works without Game Center.
struct AchievementsView: View {
    @EnvironmentObject private var career: CareerStore
    @ObservedObject private var gameCenter = GameCenter.shared

    private var earnedCount: Int { Achievement.allCases.filter { career.state.has($0) }.count }

    var body: some View {
        List {
            Section {
                Text("\(earnedCount) of \(Achievement.allCases.count) earned.")
                    .font(.title3.bold())
                if gameCenter.isAuthenticated {
                    Button("Open Game Center") { gameCenter.showDashboard(.achievements) }
                    Button("Leaderboards") { gameCenter.showDashboard(.leaderboards) }
                } else {
                    Text("Sign in to Game Center in the Settings app to compare with friends. Achievements are saved in the game either way.")
                        .font(.footnote)
                }
            }
            Section("Earned") {
                ForEach(Achievement.allCases.filter { career.state.has($0) }, id: \.self) { row($0, earned: true) }
            }
            Section("Not yet") {
                ForEach(Achievement.allCases.filter { !career.state.has($0) }, id: \.self) { row($0, earned: false) }
            }
        }
        .navigationTitle("Achievements")
    }

    private func row(_ a: Achievement, earned: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(a.title).font(.headline)
            Text(a.detail)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(a.title), \(earned ? "earned" : "not yet earned"). \(a.detail)")
    }
}

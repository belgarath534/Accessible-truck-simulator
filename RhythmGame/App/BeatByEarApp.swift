import SwiftUI

@main
struct BeatByEarApp: App {
    @StateObject private var settings = GameSettings()

    var body: some Scene {
        WindowGroup {
            MenuView()
                .environmentObject(settings)
                .preferredColorScheme(.dark)
        }
    }
}

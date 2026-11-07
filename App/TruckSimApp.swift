import SwiftUI

@main
struct TruckSimApp: App {
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            MainMenuView()
                .environmentObject(settings)
        }
    }
}

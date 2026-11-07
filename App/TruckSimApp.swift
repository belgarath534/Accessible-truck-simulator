import SwiftUI

@main
struct TruckSimApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var career = CareerStore()

    var body: some Scene {
        WindowGroup {
            MainMenuView()
                .environmentObject(settings)
                .environmentObject(career)
        }
    }
}

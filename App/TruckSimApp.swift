import SwiftUI

@main
struct TruckSimApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var career = CareerStore(demo: ScreenshotMode.isOn ? ScreenshotMode.demoCareer() : nil)

    var body: some Scene {
        WindowGroup {
            Group {
                switch ScreenshotMode.screen {
                case "jobs": NavigationStack { JobBoardView { _ in } }
                case "garage": NavigationStack { GarageView() }
                case "company": NavigationStack { CompanyView() }
                case "drive":
                    DrivingScreen(settings: settings, career: career,
                                  drive: career.jobs.first.map { DriveMode.job($0) } ?? DriveMode.freeDrive) {}
                default: MainMenuView()
                }
            }
            .environmentObject(settings)
            .environmentObject(career)
            .onAppear {
                GameCenter.shared.onAuthenticated = { [career] in career.syncGameCenter() }
                GameCenter.shared.authenticate()
            }
        }
    }
}

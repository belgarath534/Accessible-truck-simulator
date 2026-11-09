import SwiftUI

@main
struct TruckSimApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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
            .fullScreenCover(isPresented: Binding(get: { !settings.setupDone && !ScreenshotMode.isOn },
                                                  set: { if !$0 { settings.setupDone = true } })) {
                SetupView().environmentObject(settings)
            }
            .onChange(of: settings.menuOrientation) { _, orientation in OrientationLock.menus(orientation) }
            .onAppear {
                OrientationLock.menus(settings.menuOrientation)
                // Store screenshots show a player who has finished the tutorial.
                if ScreenshotMode.isOn { settings.tutorialDone = true }
                GameCenter.shared.onAuthenticated = { [career] in career.syncGameCenter() }
                GameCenter.shared.authenticate()
            }
        }
    }
}

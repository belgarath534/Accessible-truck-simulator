import SwiftUI
import UIKit

@main
struct FlightSimApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settings = FlightSettings()

    var body: some Scene {
        WindowGroup {
            MenuView()
                .environmentObject(settings)
                .onAppear {
                    OrientationLock.menus()
                    MenuMusic.shared.enabled = settings.menuMusic
                }
        }
    }
}

/// Menus face any way; flying is always sideways, like holding a yoke.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?)
        -> UIInterfaceOrientationMask {
        OrientationLock.mask
    }
}

enum OrientationLock {
    static private(set) var mask: UIInterfaceOrientationMask = .allButUpsideDown

    static func set(_ newMask: UIInterfaceOrientationMask) {
        guard newMask != mask else { return }
        mask = newMask
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        for window in scene.windows {
            var vc = window.rootViewController
            while let current = vc {
                current.setNeedsUpdateOfSupportedInterfaceOrientations()
                vc = current.presentedViewController
            }
        }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: newMask)) { _ in }
    }

    static func flying() { set(.landscape) }
    static func menus() { set(.allButUpsideDown) }
}

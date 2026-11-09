import SwiftUI
import UIKit

/// Which way the menus face. Driving is always sideways.
enum MenuOrientation: String, CaseIterable {
    /// Upright, like most apps.
    case portrait
    /// Sideways, like the driving screen.
    case landscape
    /// Whichever way the phone is held.
    case any

    var label: String {
        switch self {
        case .portrait: return "Upright"
        case .landscape: return "Sideways"
        case .any: return "Follow my phone"
        }
    }
}

/// Tells iOS which orientations the app allows right now (driving sideways, menus as the player prefers).
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?)
        -> UIInterfaceOrientationMask {
        OrientationLock.mask
    }
}

enum OrientationLock {
    static private(set) var mask: UIInterfaceOrientationMask = .landscape

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

    /// The driving screen: sideways, either way round.
    static func driving() { set(.landscape) }

    static func menus(_ orientation: MenuOrientation) {
        // Store screenshots stay sideways, like the driving screen.
        guard !ScreenshotMode.isOn else { return set(.landscape) }
        switch orientation {
        case .portrait: set(.portrait)
        case .landscape: set(.landscape)
        case .any: set(.allButUpsideDown)
        }
    }
}

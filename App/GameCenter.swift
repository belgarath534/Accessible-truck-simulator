import GameKit
import SimCore
import UIKit

/// Game Center: signs the player in, reports achievements and leaderboard scores, and shows the dashboard.
/// Achievements are also kept in the save file, so nothing is lost when Game Center isn't available;
/// everything already earned is sent again each time the player signs in.
final class GameCenter: NSObject, ObservableObject, GKGameCenterControllerDelegate {
    static let shared = GameCenter()

    @Published private(set) var isAuthenticated = false
    /// Called after signing in, to send what was earned before.
    var onAuthenticated: (() -> Void)?

    func authenticate() {
        guard !ScreenshotMode.isOn else { return }
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, _ in
            guard let self else { return }
            if let viewController {
                // Apple's sign-in screen; it only appears if the player isn't signed in on this device.
                Self.topViewController()?.present(viewController, animated: true)
                return
            }
            let signedIn = GKLocalPlayer.local.isAuthenticated
            DispatchQueue.main.async {
                self.isAuthenticated = signedIn
                // Our own spoken announcements cover achievements; the access point would cover the game.
                GKAccessPoint.shared.isActive = false
                if signedIn { self.onAuthenticated?() }
            }
        }
    }

    func report(_ achievements: [Achievement]) {
        guard isAuthenticated, !achievements.isEmpty else { return }
        let items = achievements.map { a -> GKAchievement in
            let item = GKAchievement(identifier: a.gameCenterID)
            item.percentComplete = 100
            // Game Center's banner. Achievements are only checked when a drive ends, so it never appears mid-drive.
            item.showsCompletionBanner = true
            return item
        }
        GKAchievement.report(items) { _ in }
    }

    func submitScores(_ career: CareerState) {
        guard isAuthenticated else { return }
        for board in Leaderboard.allCases {
            GKLeaderboard.submitScore(board.score(career), context: 0, player: GKLocalPlayer.local,
                                      leaderboardIDs: [board.rawValue]) { _ in }
        }
    }

    /// Sends everything earned so far (after signing in).
    func sync(_ career: CareerState) {
        report(career.achievements.compactMap(Achievement.init(rawValue:)))
        submitScores(career)
    }

    func showDashboard(_ state: GKGameCenterViewControllerState = .achievements) {
        guard isAuthenticated else { return }
        let vc = GKGameCenterViewController(state: state)
        vc.gameCenterDelegate = self
        Self.topViewController()?.present(vc, animated: true)
    }

    func gameCenterViewControllerDidFinish(_ controller: GKGameCenterViewController) {
        controller.dismiss(animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

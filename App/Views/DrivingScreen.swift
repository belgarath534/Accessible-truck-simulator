import SimCore
import SwiftUI

struct DrivingScreen: View {
    @StateObject private var controller: DrivingController
    let onExit: () -> Void

    init(settings: AppSettings, career: CareerStore, drive: DriveMode, onExit: @escaping () -> Void) {
        _controller = StateObject(wrappedValue: DrivingController(settings: settings, career: career, drive: drive))
        self.onExit = onExit
    }

    private var showButtons: Bool { controller.settings.drivingButtons || UIAccessibility.isSwitchControlRunning }

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                DrivingSurface(controller: controller, isPaused: controller.isPaused || controller.finished != nil)
                    .ignoresSafeArea()
                    .accessibilityHidden(controller.isPaused || controller.finished != nil)
                if showButtons && controller.finished == nil && !controller.isPaused {
                    DrivingButtons(controller: controller)
                }
            }
            if controller.settings.captions && !controller.caption.isEmpty && controller.finished == nil {
                VStack {
                    Spacer()
                    Text(controller.caption)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.bottom, 18).padding(.horizontal, 40)
                        // VoiceOver and the game voice already say this out loud.
                        .accessibilityHidden(true)
                }
                .allowsHitTesting(false)
            }

            if let summary = controller.finished {
                TripCompleteView(
                    summary: summary,
                    payout: controller.payout,
                    balance: controller.career.money,
                    isFreeDrive: controller.drive == .freeDrive,
                    isTutorial: controller.drive.isTutorial,
                    isAdvancedTutorial: controller.drive == .advancedTutorial,
                    units: controller.settings.units,
                    driveAgain: controller.drive.job == nil && !controller.drive.isTutorial ? controller.restart : nil,
                    quit: {
                        controller.stop()
                        onExit()
                    }
                )
            } else if controller.isPaused {
                PauseMenuView(
                    status: controller.tripStatus,
                    drive: controller.drive,
                    resume: controller.resume,
                    skipDocking: controller.session.docking == nil ? nil : {
                        controller.resume()
                        controller.perform(.skipDocking)
                    },
                    restart: controller.restart,
                    endFreeDrive: controller.endFreeDrive,
                    saveForLater: controller.drive.isTutorial || controller.drive.isDuel ? nil : {
                        controller.saveForLater()
                        onExit()
                    },
                    quit: {
                        controller.quit()
                        onExit()
                    }
                )
            }
        }
        .onAppear {
            OrientationLock.driving()
            controller.start()
        }
        .onDisappear {
            controller.stop()
            OrientationLock.menus(controller.settings.menuOrientation)
        }
        // The pause menu and the results are menus: they face the way menus do; driving turns sideways again.
        .onChange(of: controller.isPaused || controller.finished != nil) { _, inMenu in
            if inMenu { OrientationLock.menus(controller.settings.menuOrientation) } else { OrientationLock.driving() }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }
}

struct PauseMenuView: View {
    let status: String
    let drive: DriveMode
    let resume: () -> Void
    /// Finishes a delivery without docking (nil unless backing into the dock).
    let skipDocking: (() -> Void)?
    let restart: () -> Void
    let endFreeDrive: () -> Void
    /// Saves the drive to continue later (nil for the tutorial).
    let saveForLater: (() -> Void)?
    let quit: () -> Void
    @AccessibilityFocusState private var focused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.75).ignoresSafeArea()
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Text("Paused")
                        .font(.largeTitle.bold())
                    Text(status)
                        .font(.body)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.white)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focused)
                Button("Resume Driving", action: resume)
                    .buttonStyle(.borderedProminent)
                if let skipDocking {
                    Button("Skip Docking", action: skipDocking)
                        .buttonStyle(.bordered)
                        .accessibilityHint("Finishes the delivery without backing into the dock. No docking bonus.")
                }
                if let saveForLater {
                    Button("Save and Continue Later", action: saveForLater)
                        .buttonStyle(.bordered)
                        .accessibilityHint("Saves this drive exactly where you are. Continue it from the main menu any time.")
                }
                switch drive {
                case .freeDrive:
                    Button("End Drive and Get Paid", action: endFreeDrive)
                        .buttonStyle(.bordered)
                    Button("Restart from the Start", action: restart)
                        .buttonStyle(.bordered)
                        .accessibilityHint("Starts a new Free Drive. The distance so far is not paid.")
                case .job:
                    Button("Restart This Job", action: restart)
                        .buttonStyle(.bordered)
                    Button("Abandon Job", role: .destructive, action: quit)
                        .buttonStyle(.bordered)
                        .accessibilityHint("Returns to the main menu. Unfinished jobs don't pay.")
                case let .duel(turn):
                    Button(turn.raceRival == nil ? "Give Up This Turn" : "Leave the Race", role: .destructive, action: quit)
                        .buttonStyle(.bordered)
                        .accessibilityHint(turn.raceRival == nil ? "Ends your turn. It counts as not finished."
                                                                 : "You lose the race, and the other player is told you left.")
                case .practice:
                    Button("Restart from the Start", action: restart)
                        .buttonStyle(.bordered)
                case .tutorial, .advancedTutorial:
                    Button("Start the Tutorial Over", action: restart)
                        .buttonStyle(.bordered)
                }
                if drive.job == nil {
                    Button("Quit to Main Menu", role: .destructive, action: quit)
                        .buttonStyle(.bordered)
                        .accessibilityHint(drive == .freeDrive ? "You're paid for the distance driven so far." : "")
                }
            }
            .font(.title2)
            .padding()
        }
        .accessibilityAction(.escape, resume)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { focused = true }
        }
    }
}

struct TripCompleteView: View {
    let summary: TripSummary
    let payout: Payout?
    let balance: Int
    let isFreeDrive: Bool
    var isTutorial = false
    var isAdvancedTutorial = false
    let units: UnitSystem
    let driveAgain: (() -> Void)?
    let quit: () -> Void
    @AccessibilityFocusState private var focused: Bool

    private var phrases: Phrases { Phrases(units: units) }

    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 8) {
                        Text(isTutorial ? "Tutorial Complete!" : isFreeDrive ? "Drive Ended" : "Delivered!")
                            .font(.largeTitle.bold())
                        if isTutorial {
                            Text(isAdvancedTutorial
                                 ? "You've learned what's around me, pulling into a truck stop, and the engine brake on a steep hill. Duel Mode and Online Race are on the main menu, the Road Train is in the Garage, and the manual gearbox and Tiredness and naps are in Settings."
                                 : "You've learned the engine, pedals, steering, the dashboard, GPS, signals, curves, the horn and stopping. Take a job from the Job Board to start earning money, or try a Practice Drive. The controls are always in How to Drive on the main menu.")
                                .font(.body)
                                .multilineTextAlignment(.center)
                        } else {
                        Text(isFreeDrive ? phrases.tripResults(summary.stats)
                                         : phrases.arrived(summary).replacingOccurrences(of: "Delivered! ", with: ""))
                            .font(.body)
                            .multilineTextAlignment(.center)
                        }
                        if isTutorial {
                            EmptyView()
                        } else if let payout {
                            Text(phrases.payout(payout))
                                .font(.title3.bold())
                                .multilineTextAlignment(.center)
                            Text("Bank balance: \(Phrases.money(balance)).")
                                .font(.body)
                        } else {
                            Text("Practice drives don't pay. Take a job from the Job Board to earn money.")
                                .font(.body)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .foregroundStyle(.white)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($focused)
                    if let driveAgain {
                        Button("Drive Again", action: driveAgain)
                            .buttonStyle(.borderedProminent)
                    }
                    Button("Main Menu", action: quit)
                        .buttonStyle(.bordered)
                }
                .font(.title2)
                .padding()
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            // The spoken summary plays first; then VoiceOver lands on the results.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { focused = true }
        }
    }
}

/// Big buttons for every driving action: for Voice Control ("Tap Faster"), Switch Control, or anyone who prefers buttons.
struct DrivingButtons: View {
    @ObservedObject var controller: DrivingController

    private struct Item: Identifiable {
        let id: String
        let hint: String
        let action: () -> Void
    }

    private var items: [Item] {
        let c = controller
        return [
            Item(id: "Engine", hint: "Start or stop the engine.") { c.perform(.toggleEngine) },
            Item(id: "Faster", hint: "Speed up by 10 and hold that speed.") { c.buttonFaster() },
            Item(id: "Slower", hint: "Slow down by 10.") { c.buttonSlower() },
            Item(id: "Stop", hint: "Brake to a stop.") { c.buttonStop() },
            Item(id: "Steer Left", hint: "A short nudge to the left.") { c.buttonSteer(-1) },
            Item(id: "Steer Right", hint: "A short nudge to the right.") { c.buttonSteer(1) },
            Item(id: "Signal Left", hint: "Turn signal left.") { c.perform(.signal(.left)) },
            Item(id: "Signal Right", hint: "Turn signal right.") { c.perform(.signal(.right)) },
            Item(id: "Cancel Signal", hint: "Turn the signal off.") { c.perform(.cancelSignal) },
            Item(id: "Dashboard", hint: "Speed, gear, fuel and more.") { c.perform(.speakDashboard) },
            Item(id: "GPS", hint: "What's on the road ahead.") { c.perform(.speakRoadAhead) },
            Item(id: "Around Me", hint: "Traffic, deer, hills and more near the truck.") { c.perform(.speakAroundMe) },
            Item(id: "Horn", hint: "Sound the horn.") { c.perform(.horn) },
            Item(id: "Pause", hint: "The pause menu.") { c.perform(.pause) },
        ]
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(items) { item in
                    Button(action: item.action) {
                        Text(item.id)
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(item.id == "Stop" ? .red : .blue)
                    .accessibilityHint(item.hint)
                }
            }
            .padding(8)
        }
        .frame(width: 280)
        .background(Color.black)
    }
}

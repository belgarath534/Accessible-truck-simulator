import SimCore
import SwiftUI

struct DrivingScreen: View {
    @StateObject private var controller: DrivingController
    let onExit: () -> Void

    init(settings: AppSettings, career: CareerStore, drive: DriveMode, onExit: @escaping () -> Void) {
        _controller = StateObject(wrappedValue: DrivingController(settings: settings, career: career, drive: drive))
        self.onExit = onExit
    }

    var body: some View {
        ZStack {
            DrivingSurface(controller: controller, isPaused: controller.isPaused || controller.finished != nil)
                .ignoresSafeArea()
                .accessibilityHidden(controller.isPaused || controller.finished != nil)

            if let summary = controller.finished {
                TripCompleteView(
                    summary: summary,
                    payout: controller.payout,
                    balance: controller.career.money,
                    isFreeDrive: controller.drive == .freeDrive,
                    isTutorial: controller.drive == .tutorial,
                    units: controller.settings.units,
                    driveAgain: controller.drive.job == nil && controller.drive != .tutorial ? controller.restart : nil,
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
                    restart: controller.restart,
                    endFreeDrive: controller.endFreeDrive,
                    quit: {
                        controller.quit()
                        onExit()
                    }
                )
            }
        }
        .onAppear { controller.start() }
        .onDisappear { controller.stop() }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }
}

struct PauseMenuView: View {
    let status: String
    let drive: DriveMode
    let resume: () -> Void
    let restart: () -> Void
    let endFreeDrive: () -> Void
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
                case .practice:
                    Button("Restart from the Start", action: restart)
                        .buttonStyle(.bordered)
                case .tutorial:
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
                            Text("You've learned the engine, pedals, steering, the dashboard, GPS, signals, curves, the horn and stopping. Take a job from the Job Board to start earning money, or try a Practice Drive. The controls are always in How to Drive on the main menu.")
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

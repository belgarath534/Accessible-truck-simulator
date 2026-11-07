import SimCore
import SwiftUI

struct DrivingScreen: View {
    @StateObject private var controller: DrivingController
    let onExit: () -> Void

    init(settings: AppSettings, goal: TripGoal, onExit: @escaping () -> Void) {
        _controller = StateObject(wrappedValue: DrivingController(settings: settings, goal: goal))
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
                    units: controller.settings.units,
                    driveAgain: controller.restart,
                    quit: {
                        controller.stop()
                        onExit()
                    }
                )
            } else if controller.isPaused {
                PauseMenuView(
                    status: controller.tripStatus,
                    resume: controller.resume,
                    restart: controller.restart,
                    quit: {
                        controller.stop()
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
    let resume: () -> Void
    let restart: () -> Void
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
                Button("Restart from the Start", action: restart)
                    .buttonStyle(.bordered)
                Button("Quit to Main Menu", role: .destructive, action: quit)
                    .buttonStyle(.bordered)
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
    let units: UnitSystem
    let driveAgain: () -> Void
    let quit: () -> Void
    @AccessibilityFocusState private var focused: Bool

    private var phrases: Phrases { Phrases(units: units) }

    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 8) {
                        Text("Delivered!")
                            .font(.largeTitle.bold())
                        Text(phrases.arrived(summary).replacingOccurrences(of: "Delivered! ", with: ""))
                            .font(.body)
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.white)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($focused)
                    Button("Drive Again", action: driveAgain)
                        .buttonStyle(.borderedProminent)
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

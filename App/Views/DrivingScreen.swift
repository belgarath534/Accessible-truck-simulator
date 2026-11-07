import SwiftUI

struct DrivingScreen: View {
    @StateObject private var controller: DrivingController
    let onExit: () -> Void

    init(settings: AppSettings, onExit: @escaping () -> Void) {
        _controller = StateObject(wrappedValue: DrivingController(settings: settings))
        self.onExit = onExit
    }

    var body: some View {
        ZStack {
            DrivingSurface(controller: controller, isPaused: controller.isPaused)
                .ignoresSafeArea()
                .accessibilityHidden(controller.isPaused)

            if controller.isPaused {
                PauseMenuView(
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
    let resume: () -> Void
    let restart: () -> Void
    let quit: () -> Void
    @AccessibilityFocusState private var focused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.75).ignoresSafeArea()
            VStack(spacing: 20) {
                Text("Paused")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
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

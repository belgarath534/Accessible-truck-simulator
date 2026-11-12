import FlightCore
import SwiftUI

struct FlightScreen: View {
    @StateObject private var controller: FlightController
    let close: () -> Void

    init(request: FlightRequest, settings: FlightSettings, close: @escaping () -> Void) {
        _controller = StateObject(wrappedValue: FlightController(request: request, settings: settings))
        self.close = close
    }

    var body: some View {
        ZStack {
            HorizonView(reading: controller.reading)
                .ignoresSafeArea()
                .accessibilityHidden(true)
            FlightSurface(controller: controller)
                .ignoresSafeArea()
                .accessibilityHidden(controller.isPaused || controller.finished != nil)
            if let summary = controller.finished {
                ResultsOverlay(summary: summary, retry: controller.restart) {
                    controller.stop()
                    close()
                }
            } else if controller.isPaused {
                PauseOverlay(resume: controller.resume, restart: controller.restart) {
                    controller.quit()
                    close()
                }
            }
        }
        .onAppear {
            OrientationLock.flying()
            controller.start()
        }
        .onDisappear {
            controller.stop()
            OrientationLock.menus()
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }
}

/// A simple artificial horizon and the main numbers, for sighted players. Never needed to fly.
struct HorizonView: View {
    let reading: InstrumentReading

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Canvas { context, size in
                    let c = CGPoint(x: size.width / 2, y: size.height / 2)
                    let offset = CGFloat(reading.pitch) * size.height / 40
                    var ground = Path()
                    let w = max(size.width, size.height) * 2
                    ground.addRect(CGRect(x: -w, y: offset, width: w * 2, height: w))
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.25, green: 0.5, blue: 0.85)))
                    var t = context
                    t.translateBy(x: c.x, y: c.y)
                    t.rotate(by: .degrees(-reading.bank))
                    t.fill(ground, with: .color(Color(red: 0.45, green: 0.32, blue: 0.18)))
                    t.stroke(Path { p in p.move(to: CGPoint(x: -w, y: offset)); p.addLine(to: CGPoint(x: w, y: offset)) },
                             with: .color(.white), lineWidth: 2)
                    // The little plane in the middle.
                    var wings = Path()
                    wings.move(to: CGPoint(x: c.x - 60, y: c.y)); wings.addLine(to: CGPoint(x: c.x - 15, y: c.y))
                    wings.move(to: CGPoint(x: c.x + 15, y: c.y)); wings.addLine(to: CGPoint(x: c.x + 60, y: c.y))
                    context.stroke(wings, with: .color(.yellow), lineWidth: 5)
                    context.fill(Path(ellipseIn: CGRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10)), with: .color(.yellow))
                }
                VStack {
                    HStack {
                        Text("\(reading.airspeedKnots) kt")
                        Spacer()
                        Text(String(format: "HDG %03d", Int(reading.heading.rounded()) % 360))
                        Spacer()
                        Text("\(reading.altitudeFeet) ft")
                    }
                    .font(.title2.monospacedDigit().bold())
                    Spacer()
                    HStack {
                        Text("Throttle \(reading.throttlePercent)%")
                        Spacer()
                        Text("Flaps \(reading.flaps)")
                        Spacer()
                        Text("\(reading.verticalSpeedFPM) fpm")
                    }
                    .font(.headline.monospacedDigit())
                }
                .foregroundStyle(.white)
                .shadow(radius: 3)
                .padding(24)
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
    }
}

struct PauseOverlay: View {
    let resume: () -> Void
    let restart: () -> Void
    let quit: () -> Void
    @AccessibilityFocusState private var focused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.8).ignoresSafeArea()
            VStack(spacing: 18) {
                Text("Paused").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader).accessibilityFocused($focused)
                Button("Resume Flying", action: resume).buttonStyle(.borderedProminent)
                Button("Restart This Flight", action: restart).buttonStyle(.bordered)
                Button("Quit to Main Menu", role: .destructive, action: quit).buttonStyle(.bordered)
            }
            .font(.title2)
            .foregroundStyle(.white)
        }
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { focused = true } }
    }
}

struct ResultsOverlay: View {
    let summary: FlightSummary
    let retry: () -> Void
    let done: () -> Void
    @AccessibilityFocusState private var focused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    Text(summary.crash != nil ? "Crashed" : summary.completed ? "Flight Complete" : "Flight Ended")
                        .font(.largeTitle.bold())
                        .accessibilityFocused($focused)
                    Text(summary.message).multilineTextAlignment(.center)
                    if let fpm = summary.touchdownFPM, summary.crash == nil {
                        Text("Touchdown: \(abs(fpm)) feet per minute.")
                    }
                    if let off = summary.centrelineOffset, summary.crash == nil {
                        Text(abs(off) < 3 ? "Right on the centerline." : "\(Units.feet(abs(off))) feet \(off > 0 ? "right" : "left") of the centerline.")
                    }
                    Text(String(format: "Flight time: %d minutes %d seconds.", Int(summary.flightTime) / 60, Int(summary.flightTime) % 60))
                    Button(summary.completed ? "Fly It Again" : "Try Again", action: retry).buttonStyle(.borderedProminent)
                    Button("Main Menu", action: done).buttonStyle(.bordered)
                }
                .font(.title3)
                .foregroundStyle(.white)
                .padding(30)
            }
        }
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { focused = true } }
    }
}

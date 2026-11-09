import CoreHaptics
import QuartzCore

/// Engine vibration that follows RPM and load, plus jolts for the rumble strip and crashes.
final class Haptics {
    var enabled = true
    private var engine: CHHapticEngine?
    private var rumblePlayer: CHHapticAdvancedPatternPlayer?
    private var lastUpdate: CFTimeInterval = 0
    /// iOS stops the haptic engine when the game goes to the background (or for other reasons); it's started
    /// again on the next update, so vibration comes back by itself.
    private var needsRestart = false

    var isSupported: Bool { CHHapticEngine.capabilitiesForHardware().supportsHaptics }

    func start() {
        guard enabled, isSupported else { return }
        do {
            let engine = try CHHapticEngine()
            engine.isAutoShutdownEnabled = false
            engine.playsHapticsOnly = true
            engine.resetHandler = { [weak self] in
                try? self?.engine?.start()
                self?.makeContinuousPlayer()
            }
            engine.stoppedHandler = { [weak self] _ in
                DispatchQueue.main.async { self?.needsRestart = true }
            }
            try engine.start()
            self.engine = engine
            makeContinuousPlayer()
        } catch {
            engine = nil
        }
    }

    func stop() {
        try? rumblePlayer?.stop(atTime: CHHapticTimeImmediate)
        engine?.stop()
        engine = nil
        rumblePlayer = nil
    }

    private func makeContinuousPlayer() {
        guard let engine else { return }
        let event = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2),
            ],
            relativeTime: 0,
            duration: 30
        )
        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makeAdvancedPlayer(with: pattern)
            player.loopEnabled = true
            try player.start(atTime: CHHapticTimeImmediate)
            rumblePlayer = player
            setContinuous(intensity: 0, sharpness: 0.2)
        } catch {
            rumblePlayer = nil
        }
    }

    private func setContinuous(intensity: Float, sharpness: Float) {
        try? rumblePlayer?.sendParameters([
            CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: intensity, relativeTime: 0),
            CHHapticDynamicParameter(parameterID: .hapticSharpnessControl, value: sharpness, relativeTime: 0),
        ], atTime: CHHapticTimeImmediate)
    }

    /// Call every frame; rate-limited internally.
    func update(engineRunning: Bool, rpmFraction: Double, load: Double, onRumbleStrip: Bool) {
        guard enabled, let engine else { return }
        let now = CACurrentMediaTime()
        guard now - lastUpdate > 0.05 else { return }
        lastUpdate = now
        if needsRestart {
            // Back from the background: start the engine and the continuous vibration again.
            guard (try? engine.start()) != nil else { return }
            needsRestart = false
            makeContinuousPlayer()
        }
        var intensity: Float = engineRunning ? Float(0.06 + 0.18 * load + 0.06 * rpmFraction) : 0
        var sharpness: Float = Float(0.1 + 0.3 * rpmFraction)
        if onRumbleStrip {
            intensity = max(intensity, 0.75)
            sharpness = 0.7
        }
        setContinuous(intensity: intensity, sharpness: sharpness)
    }

    func tap(intensity: Float, sharpness: Float) {
        guard enabled, let engine else { return }
        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ],
            relativeTime: 0
        )
        if let pattern = try? CHHapticPattern(events: [event], parameters: []),
           let player = try? engine.makePlayer(with: pattern) {
            try? player.start(atTime: CHHapticTimeImmediate)
        }
    }

    func crash() {
        guard enabled, let engine else { return }
        let events = [
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 1),
            ], relativeTime: 0),
            CHHapticEvent(eventType: .hapticContinuous, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3),
            ], relativeTime: 0.05, duration: 0.8),
        ]
        if let pattern = try? CHHapticPattern(events: events, parameters: []),
           let player = try? engine.makePlayer(with: pattern) {
            try? player.start(atTime: CHHapticTimeImmediate)
        }
    }
}

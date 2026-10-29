import CoreHaptics
import UIKit

/// The app's haptic vocabulary. Stock generators cover the small stuff; the
/// moments that stand for something physical on the car (a lock actuator, the
/// horn, current starting to flow) get their own Core Haptics patterns.
@MainActor
final class Haptics {
    static let shared = Haptics()

    static let enabledKey = "haptics.enabled"

    private var engine: CHHapticEngine?
    private var holdPlayer: CHHapticAdvancedPatternPlayer?
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let soft = UIImpactFeedbackGenerator(style: .soft)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let selection = UISelectionFeedbackGenerator()
    private let notification = UINotificationFeedbackGenerator()

    private var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    private init() {}

    func prepare() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics, engine == nil else { return }
        do {
            let engine = try CHHapticEngine()
            engine.isAutoShutdownEnabled = true
            engine.resetHandler = { [weak engine] in try? engine?.start() }
            try engine.start()
            self.engine = engine
        } catch {
            engine = nil
        }
    }

    // MARK: Everyday feedback

    /// Finger lands on a control.
    func touch() {
        guard isEnabled else { return }
        light.impactOccurred(intensity: 0.6)
    }

    /// A value clicks over to its next step.
    func tick() {
        guard isEnabled else { return }
        selection.selectionChanged()
    }

    /// A step that matters more than its neighbours, like 80% on the charge limit.
    func detent() {
        guard isEnabled else { return }
        rigid.impactOccurred(intensity: 0.9)
    }

    /// Something settles back into place.
    func settle() {
        guard isEnabled else { return }
        soft.impactOccurred(intensity: 0.7)
    }

    func success() {
        guard isEnabled else { return }
        notification.notificationOccurred(.success)
    }

    func failure() {
        guard isEnabled else { return }
        notification.notificationOccurred(.error)
    }

    // MARK: The car

    /// Two actuators closing: a sharp click, then a heavier one right behind it.
    func lock() {
        play([
            transient(at: 0, intensity: 0.75, sharpness: 0.85),
            transient(at: 0.085, intensity: 1.0, sharpness: 0.35),
        ], fallback: { self.rigid.impactOccurred(intensity: 1) })
    }

    /// The same mechanism releasing: heavy first, then a light spring-back.
    func unlock() {
        play([
            transient(at: 0, intensity: 0.9, sharpness: 0.3),
            transient(at: 0.11, intensity: 0.5, sharpness: 0.9),
        ], fallback: { self.soft.impactOccurred(intensity: 1) })
    }

    /// Current ramping up into the pack.
    func chargeStart() {
        let rise = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.7),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.25),
            ],
            relativeTime: 0,
            duration: 0.42
        )
        let ramp = CHHapticParameterCurve(
            parameterID: .hapticIntensityControl,
            controlPoints: [
                .init(relativeTime: 0, value: 0.1),
                .init(relativeTime: 0.36, value: 1.0),
                .init(relativeTime: 0.42, value: 0.0),
            ],
            relativeTime: 0
        )
        let brighten = CHHapticParameterCurve(
            parameterID: .hapticSharpnessControl,
            controlPoints: [
                .init(relativeTime: 0, value: -0.2),
                .init(relativeTime: 0.4, value: 0.5),
            ],
            relativeTime: 0
        )
        play([rise, transient(at: 0.44, intensity: 0.9, sharpness: 0.7)], curves: [ramp, brighten]) {
            self.notification.notificationOccurred(.success)
        }
    }

    func chargeStop() {
        play([
            transient(at: 0, intensity: 0.8, sharpness: 0.5),
            buzz(at: 0.03, duration: 0.18, intensity: 0.35, sharpness: 0.1),
        ], fallback: { self.soft.impactOccurred(intensity: 0.8) })
    }

    /// Two short blasts.
    func honk() {
        play([
            buzz(at: 0, duration: 0.16, intensity: 1, sharpness: 0.2),
            buzz(at: 0.26, duration: 0.22, intensity: 1, sharpness: 0.2),
        ], fallback: { self.notification.notificationOccurred(.warning) })
    }

    /// Light flicker for the indicator flash.
    func flash() {
        play([
            transient(at: 0, intensity: 0.6, sharpness: 1),
            transient(at: 0.18, intensity: 0.6, sharpness: 1),
            transient(at: 0.36, intensity: 0.8, sharpness: 1),
        ], fallback: { self.light.impactOccurred(intensity: 1) })
    }

    /// Air coming on: a soft swell.
    func climateOn() {
        let swell = buzz(at: 0, duration: 0.5, intensity: 0.5, sharpness: 0.05)
        let curve = CHHapticParameterCurve(
            parameterID: .hapticIntensityControl,
            controlPoints: [
                .init(relativeTime: 0, value: 0.0),
                .init(relativeTime: 0.3, value: 1.0),
                .init(relativeTime: 0.5, value: 0.2),
            ],
            relativeTime: 0
        )
        play([swell], curves: [curve]) { self.soft.impactOccurred(intensity: 0.8) }
    }

    // MARK: Hold to confirm

    /// A hum that tightens while the finger stays down.
    func holdBegan(duration: TimeInterval) {
        guard isEnabled else { return }
        prepare()
        guard let engine else {
            light.impactOccurred(intensity: 0.5)
            return
        }
        let hum = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2),
            ],
            relativeTime: 0,
            duration: duration
        )
        let ramp = CHHapticParameterCurve(
            parameterID: .hapticIntensityControl,
            controlPoints: [
                .init(relativeTime: 0, value: 0.15),
                .init(relativeTime: duration, value: 1.0),
            ],
            relativeTime: 0
        )
        let sharpen = CHHapticParameterCurve(
            parameterID: .hapticSharpnessControl,
            controlPoints: [
                .init(relativeTime: 0, value: -0.1),
                .init(relativeTime: duration, value: 0.6),
            ],
            relativeTime: 0
        )
        do {
            let pattern = try CHHapticPattern(events: [hum], parameterCurves: [ramp, sharpen])
            let player = try engine.makeAdvancedPlayer(with: pattern)
            try engine.start()
            try player.start(atTime: CHHapticTimeImmediate)
            holdPlayer = player
        } catch {
            holdPlayer = nil
        }
    }

    func holdCancelled() {
        try? holdPlayer?.stop(atTime: CHHapticTimeImmediate)
        holdPlayer = nil
        settle()
    }

    func holdCompleted() {
        try? holdPlayer?.stop(atTime: CHHapticTimeImmediate)
        holdPlayer = nil
    }

    // MARK: Building blocks

    private func transient(at time: TimeInterval, intensity: Float, sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ],
            relativeTime: time
        )
    }

    private func buzz(at time: TimeInterval, duration: TimeInterval, intensity: Float, sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ],
            relativeTime: time,
            duration: duration
        )
    }

    private func play(_ events: [CHHapticEvent], curves: [CHHapticParameterCurve] = [], fallback: () -> Void) {
        guard isEnabled else { return }
        prepare()
        guard let engine else {
            fallback()
            return
        }
        do {
            let pattern = try CHHapticPattern(events: events, parameterCurves: curves)
            let player = try engine.makePlayer(with: pattern)
            try engine.start()
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            fallback()
        }
    }
}

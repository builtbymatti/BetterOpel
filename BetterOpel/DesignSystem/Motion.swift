import SwiftUI

/// Springs only, so every animation can be interrupted and retargeted. Bounce is
/// reserved for motion that follows a gesture carrying momentum.
enum Motion {
    /// State changes on small controls.
    static let snappy = Animation.spring(response: 0.28, dampingFraction: 1)
    /// Default for layout and value changes.
    static let fluid = Animation.spring(response: 0.42, dampingFraction: 0.92)
    /// Releases after a drag or a hold.
    static let release = Animation.spring(response: 0.38, dampingFraction: 0.74)
    /// Large, slow settles such as the car arriving.
    static let arrive = Animation.spring(response: 0.9, dampingFraction: 0.86)
    /// Finger down: effectively instant.
    static let press = Animation.spring(response: 0.16, dampingFraction: 1)
}

/// Feedback on touch-down, commit on touch-up. No lift, no glow: the control
/// just gives under the finger.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.96
    var dim: Double = 0.82

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? dim : 1)
            .animation(configuration.isPressed ? Motion.press : Motion.release, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { Haptics.shared.touch() }
            }
    }
}

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
    static func pressable(scale: CGFloat) -> PressableStyle { PressableStyle(scale: scale) }
}

/// Progressive resistance past a boundary instead of a hard stop.
func rubberBand(_ overshoot: CGFloat, dimension: CGFloat, constant: CGFloat = 0.55) -> CGFloat {
    guard dimension > 0 else { return 0 }
    return (overshoot * dimension * constant) / (dimension + constant * abs(overshoot))
}

/// One damped wave across a view, driven by a trigger value.
struct RippleModifier<Trigger: Equatable & Sendable>: ViewModifier {
    var origin: CGPoint
    var trigger: Trigger
    var amplitude: Double = 9
    var frequency: Double = 15
    var decay: Double = 5.5
    var speed: Double = 620

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let duration = 1.6
        let origin = origin, amplitude = amplitude, frequency = frequency, decay = decay, speed = speed
        let isAllowed = !reduceMotion
        content.keyframeAnimator(initialValue: 0.0, trigger: trigger) { view, elapsed in
            view.layerEffect(
                ShaderLibrary.ripple(
                    .float2(origin),
                    .float(elapsed),
                    .float(amplitude),
                    .float(frequency),
                    .float(decay),
                    .float(speed)
                ),
                maxSampleOffset: CGSize(width: amplitude, height: amplitude),
                isEnabled: isAllowed && elapsed > 0 && elapsed < duration
            )
        } keyframes: { _ in
            MoveKeyframe(0)
            LinearKeyframe(duration, duration: duration)
        }
    }
}

extension View {
    func ripple<Trigger: Equatable & Sendable>(at origin: CGPoint, trigger: Trigger, amplitude: Double = 9) -> some View {
        modifier(RippleModifier(origin: origin, trigger: trigger, amplitude: amplitude))
    }
}

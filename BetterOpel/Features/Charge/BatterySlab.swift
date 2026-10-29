import SwiftUI

/// The battery, drawn as one slab you can read and adjust in the same place:
/// the lit part is the charge it holds, the hatched part is what the car will
/// add, and the marker is the limit. Drag the marker to move the limit.
struct BatterySlab: View {
    var level: Double
    var limit: Int
    var isCharging: Bool
    var rippleTrigger: Int
    /// Called while dragging with the snapped value, for live read-outs.
    var onPreview: (Int?) -> Void
    var onCommit: (Int) -> Void

    static let height: CGFloat = 96
    private static let range: ClosedRange<Double> = 50...100
    private static let step = 5.0

    @State private var dragValue: Double?
    @State private var dragStart: Double?
    @State private var lastSnap: Int?

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let shown = dragValue ?? Double(limit)
            let limitX = width * shown / 100

            ZStack(alignment: .topLeading) {
                SlabFace(
                    shown: shown,
                    width: width,
                    level: level,
                    isCharging: isCharging,
                    isDragging: dragValue != nil
                )

                // The whole marker, flag included, is one place to take hold of.
                Color.clear
                    .frame(width: MarkerMetrics.hitWidth, height: MarkerMetrics.flagHeight + 4 + Self.height + 10)
                    .contentShape(.rect)
                    .offset(x: limitX - MarkerMetrics.hitWidth / 2, y: -MarkerMetrics.flagHeight - 6)
                    .gesture(drag(width: width))
            }
            .ripple(at: CGPoint(x: width * level / 100, y: Self.height / 2), trigger: rippleTrigger, amplitude: 8)
        }
        .frame(height: Self.height)
        .padding(.top, MarkerMetrics.flagHeight + 6)
        .animation(Motion.fluid, value: level)
        .accessibilityElement()
        .accessibilityLabel("Charge limit")
        .accessibilityValue("\(limit) percent. Battery at \(Int(level)) percent.")
        .accessibilityAdjustableAction { direction in
            let next = limit + (direction == .increment ? 5 : -5)
            onCommit(min(100, max(50, next)))
        }
    }

    // MARK: Gesture

    private func drag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                if dragStart == nil {
                    // Respect where the marker was grabbed; never jump to the finger.
                    dragStart = Double(limit)
                    lastSnap = limit
                    Haptics.shared.touch()
                }
                let raw = (dragStart ?? Double(limit)) + Double(value.translation.width / width) * 100
                dragValue = resist(raw, width: width)
                let snapped = Self.snap(raw)
                if snapped != lastSnap {
                    lastSnap = snapped
                    if snapped == 80 || snapped == 100 { Haptics.shared.detent() } else { Haptics.shared.tick() }
                    onPreview(snapped)
                }
            }
            .onEnded { value in
                // Project the release so a flick carries the marker a little further.
                let raw = (dragStart ?? Double(limit)) + Double(value.predictedEndTranslation.width / width) * 100
                let near = (dragStart ?? Double(limit)) + Double(value.translation.width / width) * 100
                let target = Self.snap(near + (raw - near) * 0.25)
                dragStart = nil
                lastSnap = nil
                withAnimation(Motion.release) { dragValue = nil }
                onPreview(nil)
                onCommit(target)
                Haptics.shared.settle()
            }
    }

    /// Follows the finger inside the range and rubber-bands past its ends.
    private func resist(_ value: Double, width: CGFloat) -> Double {
        let lower = Self.range.lowerBound, upper = Self.range.upperBound
        if value < lower {
            return lower - rubberBand(lower - value, dimension: 14)
        }
        if value > upper {
            return upper + rubberBand(value - upper, dimension: 4)
        }
        return value
    }

    fileprivate static func snap(_ value: Double) -> Int {
        let clamped = min(range.upperBound, max(range.lowerBound, value))
        return Int((clamped / step).rounded() * step)
    }
}

private enum MarkerMetrics {
    static let hitWidth: CGFloat = 64
    static let flagHeight: CGFloat = 26
}

// MARK: Face

/// Everything that is drawn. The limit is its animatable value, so the marker,
/// the hatching and the ink all see the same in-between positions while a
/// release settles.
private struct SlabFace: View, @preconcurrency Animatable {
    var shown: Double
    var width: CGFloat
    var level: Double
    var isCharging: Bool
    var isDragging: Bool

    var animatableData: Double {
        get { shown }
        set { shown = newValue }
    }

    @State private var goo = LimitGoo()
    @State private var isAwake = false
    @State private var flagWidth: CGFloat = 50
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    /// The bar stands a little proud of the slab, more below than above.
    private static let barTop: CGFloat = -2
    private static let barBottom: CGFloat = BatterySlab.height + 8
    /// Room around the slab for the ink to move in.
    private static let inkMargin = CGSize(width: 44, height: 50)

    var body: some View {
        let height = BatterySlab.height
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        let fillWidth = width * level / 100
        let limitX = width * shown / 100
        let snapped = BatterySlab.snap(shown)
        // Near 100% the flag stays inside the slab while the bar goes on.
        let flagHome = limitX + min(0, width - limitX - 30)
        let isLive = isAwake && !reduceMotion
        let isDark = scheme == .dark

        // Full rate while the ink is moving, a calm rate for the charging fill.
        TimelineView(.animation(minimumInterval: isLive ? nil : 1 / 30, paused: !(isLive || isCharging && !reduceMotion))) { context in
            let time = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 600)
            let pose = goo.advance(
                marker: limitX,
                flagHome: flagHome,
                flagWidth: flagWidth,
                isHeld: isDragging,
                isLive: isLive,
                at: context.date
            )
            // Held, the flag lifts off the bar and grows a little.
            let scale = 1 + 0.028 * pose.lift
            let flagCentre = CGPoint(x: pose.flagX, y: -6 - pose.lift - MarkerMetrics.flagHeight / 2 * scale)

            ZStack(alignment: .topLeading) {
                shape.fill(Palette.well)
                    .frame(height: height)

                ZStack(alignment: .topLeading) {
                    // What the car plans to add.
                    Rectangle()
                        .colorEffect(
                            ShaderLibrary.plannedHatch(
                                .float(isCharging ? time : 0),
                                .themed(\.accent, dark: isDark),
                                .float4(limitX - fillWidth, pose.bow, Self.barTop, Self.barBottom)
                            )
                        )
                        .frame(width: max(0, limitX - fillWidth) + 34, height: height)
                        .offset(x: fillWidth)

                    // What it holds now.
                    Rectangle()
                        .fill(Palette.fill)
                        .colorEffect(
                            ShaderLibrary.energyFill(
                                .float2(max(fillWidth, 1), height),
                                .float(time),
                                .float(isCharging ? 1 : 0),
                                .themed(\.fill, dark: isDark),
                                .themed(\.fillDeep, dark: isDark),
                                .themed(\.fillHot, dark: isDark)
                            )
                        )
                        .frame(width: fillWidth, height: height)
                }
                .frame(width: width, height: height, alignment: .topLeading)
                .clipShape(shape)

                ticks

                // The marker: bar, flag and the neck between them, as one body.
                Rectangle()
                    .colorEffect(
                        ShaderLibrary.limitGoo(
                            .float2(Self.inkMargin.width, Self.inkMargin.height),
                            .float4(limitX, Self.barTop, Self.barBottom, isDragging ? 3 : 2.5),
                            .float4(flagCentre.x, flagCentre.y, pose.flagWidth / 2 * scale, MarkerMetrics.flagHeight / 2 * scale),
                            .float2(pose.bow, pose.tilt),
                            .themed(\.ink, dark: isDark),
                            .themed(\.canvas, dark: isDark)
                        )
                    )
                    .frame(width: width + Self.inkMargin.width * 2, height: height + Self.inkMargin.height + 14)
                    .offset(x: -Self.inkMargin.width, y: -Self.inkMargin.height)
                    .allowsHitTesting(false)

                Text("\(snapped)%")
                    .font(.displayFixed(15, .semibold))
                    .foregroundStyle(Palette.canvas)
                    .contentTransition(.numericText(value: Double(snapped)))
                    .animation(Motion.snappy, value: snapped)
                    .fixedSize()
                    .frame(width: flagWidth, height: MarkerMetrics.flagHeight)
                    .scaleEffect(scale)
                    .rotationEffect(.radians(pose.tilt))
                    .offset(x: flagCentre.x - flagWidth / 2, y: flagCentre.y - MarkerMetrics.flagHeight / 2)
                    .allowsHitTesting(false)
            }
        }
        // The flag is as wide as its figure; measured, not guessed.
        .background {
            Text("\(snapped)%")
                .font(.displayFixed(15, .semibold))
                .padding(.horizontal, 9)
                .fixedSize()
                .hidden()
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.width
                } action: { measured in
                    flagWidth = measured
                }
        }
        .onChange(of: isDragging) { _, held in
            if held { isAwake = true }
        }
        .task(id: isDragging) {
            // Let the ink come to rest after a release, then stop redrawing.
            guard !isDragging else { return }
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            isAwake = false
        }
    }

    private var ticks: some View {
        Canvas { context, size in
            for decade in 1..<10 {
                let x = size.width * CGFloat(decade) / 10
                let tall = decade == 5
                let rect = CGRect(x: x - 0.75, y: size.height - (tall ? 12 : 7) - 7, width: 1.5, height: tall ? 12 : 7)
                context.fill(Path(roundedRect: rect, cornerRadius: 0.75), with: .color(Palette.onFill.opacity(0.28)))
            }
        }
        .frame(width: width, height: BatterySlab.height)
        .allowsHitTesting(false)
    }
}

// MARK: Ink

/// The marker's ink has weight. Three small springs follow the finger: the
/// belly of the bar, the flag, and the lift of the flag off the bar. A fourth
/// lets the flag change width without a jump.
@MainActor
final class LimitGoo {
    struct Pose {
        /// How far the belly of the bar trails the marker.
        var bow = 0.0
        var flagX = 0.0
        var tilt = 0.0
        var lift = 0.0
        var flagWidth = 50.0
    }

    private struct Spring {
        var x = 0.0
        var v = 0.0

        mutating func step(toward target: Double, frequency: Double, damping: Double, dt: Double) {
            let omega = 2 * Double.pi * frequency
            v += (omega * omega * (target - x) - 2 * damping * omega * v) * dt
            x += v * dt
        }

        mutating func rest(at target: Double) {
            x = target
            v = 0
        }
    }

    private var belly = Spring()
    private var flag = Spring()
    private var lift = Spring()
    private var breadth = Spring()
    private var last: Date?

    func advance(marker: Double, flagHome: Double, flagWidth: Double, isHeld: Bool, isLive: Bool, at now: Date) -> Pose {
        let gap = last.map { now.timeIntervalSince($0) } ?? .infinity
        last = now

        if !isLive || gap > 0.25 {
            // Nothing to carry over: everything sits where it belongs.
            belly.rest(at: marker)
            flag.rest(at: flagHome)
            lift.rest(at: isHeld ? Self.heldLift : 0)
            breadth.rest(at: flagWidth)
        } else if gap > 0 {
            var remaining = min(gap, 1.0 / 20)
            while remaining > 0 {
                let dt = min(remaining, 1.0 / 240)
                belly.step(toward: marker, frequency: 2.6, damping: 0.3, dt: dt)
                flag.step(toward: flagHome, frequency: 2.0, damping: 0.36, dt: dt)
                lift.step(toward: isHeld ? Self.heldLift : 0, frequency: 3.4, damping: 0.42, dt: dt)
                breadth.step(toward: flagWidth, frequency: 5, damping: 0.8, dt: dt)
                remaining -= dt
            }
        }

        // Soft limits, so a hard flick bends the ink a long way but never tears it.
        let bow = 28 * tanh((marker - belly.x) / 28)
        let trail = 20 * tanh((flagHome - flag.x) / 20)
        return Pose(bow: bow, flagX: flagHome - trail, tilt: -trail * 0.011, lift: lift.x, flagWidth: breadth.x)
    }

    private static let heldLift = 5.0
}

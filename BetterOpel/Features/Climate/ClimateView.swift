import SwiftUI

/// Where a climate request stands, from the tap to a ready cabin.
enum ClimatePhase: Equatable {
    case off
    case sending
    case stopping
    /// Sent; the car is asleep and has not confirmed yet.
    case waking
    case running(minutesLeft: Int, progress: Double)
    /// The ten-minute cycle is over and the car still reports it as on.
    case ready

    /// Air is actually moving.
    var isFlowing: Bool {
        switch self {
        case .running, .ready: true
        default: false
        }
    }

    /// The next tap stops rather than starts.
    var isEngaged: Bool {
        switch self {
        case .waking, .running, .ready, .stopping: true
        default: false
        }
    }

    var isBusy: Bool { self == .sending || self == .stopping }
}

/// The car chooses by itself whether to heat or cool. This mirrors its choice
/// from the outside temperature, for the wording and the colour of the air.
private struct ClimateMode {
    var warmth: Double
    var action: String
    var running: String
    var promise: String

    init(outside: Double?) {
        switch outside {
        case .some(let t) where t < 18:
            (warmth, action, running, promise) = (1, "Warm the cabin", "Warming", "Warm in ten minutes.")
        case .some(let t) where t > 24:
            (warmth, action, running, promise) = (-1, "Cool the cabin", "Cooling", "Cool in ten minutes.")
        case .some:
            (warmth, action, running, promise) = (0.25, "Air the cabin", "Airing", "Fresh air in ten minutes.")
        case .none:
            (warmth, action, running, promise) = (0.25, "Start climate", "Conditioning", "Comfortable in ten minutes.")
        }
    }
}

struct ClimateView: View {
    @Environment(VehicleModel.self) private var model

    var body: some View {
        let snapshot = model.snapshot
        GeometryReader { outer in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Re-read every second so the countdown stays true between readings.
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        ClimateStage(
                            phase: phase(snapshot),
                            mode: ClimateMode(outside: snapshot.outsideTempC),
                            outside: snapshot.outsideTempC,
                            nextStart: model.nextWarmUp?.nextStart,
                            height: outer.size.height
                        ) {
                            Task { await model.setClimate(!snapshot.climate.isOn, announce: false) }
                        }
                    }

                    WarmUpSection()
                    .padding(.horizontal, 20)
                    // Starts behind the navigation bar, so the stage owns the first screen.
                    .padding(.top, 48)
                    .padding(.bottom, 32)
                }
            }
            .scrollIndicators(.hidden)
        }
        .statusBarFade()
        .background(Palette.canvas.ignoresSafeArea())
    }

    private func phase(_ snapshot: VehicleSnapshot) -> ClimatePhase {
        #if DEBUG
        // `-climatePhase waking` shows one phase, for UI checks.
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-climatePhase"), arguments.indices.contains(index + 1) {
            switch arguments[index + 1] {
            case "sending": return .sending
            case "waking": return .waking
            case "running": return .running(minutesLeft: 7, progress: 0.34)
            case "ready": return .ready
            default: break
            }
        }
        #endif
        if model.isPending(.climate) { return snapshot.climate.isOn ? .stopping : .sending }
        guard snapshot.climate.isOn else { return .off }
        if model.isAwaiting(.climate) { return .waking }
        let left = snapshot.climateMinutesRemaining ?? 0
        guard left > 0 else { return .ready }
        return .running(minutesLeft: max(1, Int(left.rounded(.up))), progress: 1 - left / ClimateState.cycleMinutes)
    }
}

// MARK: Stage

/// The first screen: what the climate is doing, and the one control for it.
/// The car stands in a bay; the bay's edge is the ten-minute clock and the
/// knob set into it starts and stops the air.
private struct ClimateStage: View {
    let phase: ClimatePhase
    let mode: ClimateMode
    let outside: Double?
    let nextStart: Date?
    /// Height of the screen between the status bar and the navigation bar.
    let height: CGFloat
    var toggle: () -> Void

    private static let chrome: CGFloat = 226

    var body: some View {
        let bayHeight = min(468, max(300, height - Self.chrome))
        VStack(alignment: .leading, spacing: 0) {
            headline
                .padding(.horizontal, 20)
                .padding(.top, 8)

            Spacer(minLength: 12)

            HStack(alignment: .center, spacing: 0) {
                Readout(
                    value: outside.map { "\(Int($0.rounded()))" } ?? "–",
                    unit: outside == nil ? nil : "°C",
                    caption: "Outside",
                    size: 24
                )
                control(bayHeight: bayHeight)
                Readout(value: minutes, unit: "min", caption: minutesCaption, size: 24, alignment: .trailing)
            }
            .padding(.horizontal, 20)

            Spacer(minLength: 8)
        }
        .frame(height: max(height, bayHeight + Self.chrome))
        .animation(Motion.snappy, value: phaseKey)
    }

    // MARK: Words

    private var headline: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.displayFixed(34, .semibold))
                .foregroundStyle(Palette.ink)
                .contentTransition(.interpolate)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Palette.inkSoft)
                .contentTransition(.interpolate)
                .lineLimit(2)
                // Two lines are always reserved, so the bay never shifts.
                .frame(minHeight: 40, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        switch phase {
        case .off: "Climate off"
        case .sending: "Sending"
        case .stopping: "Stopping"
        case .waking: "Waking the car"
        case .running: mode.running
        case .ready: "Cabin ready"
        }
    }

    private var subtitle: String {
        switch phase {
        case .off:
            // Only worth saying while the next start is close enough to matter.
            if let nextStart, nextStart.timeIntervalSinceNow < 18 * 3600, nextStart > .now {
                "\(mode.promise) Starts by itself \(Weekday.word(for: nextStart)) at \(Weekday.clock(nextStart))."
            } else {
                mode.promise
            }
        case .sending, .stopping: "One moment."
        case .waking: "It is asleep and can take a minute or two to answer."
        case .running: "The car stops by itself after ten minutes."
        case .ready: "The ten minutes are up."
        }
    }

    private var minutes: String {
        switch phase {
        case .running(let left, _): "\(left)"
        case .ready: "0"
        default: "\(Int(ClimateState.cycleMinutes))"
        }
    }

    private var minutesCaption: String {
        switch phase {
        case .running, .ready: "Left"
        default: "Cycle"
        }
    }

    private var actionLabel: String {
        switch phase {
        case .off: mode.action
        case .sending: "Sending"
        case .stopping: "Stopping"
        case .waking: "Cancel"
        case .running, .ready: "Stop"
        }
    }

    /// Changes when the wording should animate, not on every countdown tick.
    private var phaseKey: Int {
        switch phase {
        case .off: 0
        case .sending: 1
        case .stopping: 2
        case .waking: 3
        case .running: 4
        case .ready: 5
        }
    }

    // MARK: Control

    private func control(bayHeight: CGFloat) -> some View {
        Button(action: toggle) {
            VStack(spacing: 12) {
                ClimateBay(phase: phase, warmth: mode.warmth, size: CGSize(width: ClimateBay.width, height: bayHeight))
                Text(actionLabel)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.interpolate)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(height: 22)
            }
            .contentShape(.rect)
        }
        .buttonStyle(PressableStyle(scale: 0.98, dim: 0.96))
        .disabled(phase.isBusy)
        .accessibilityLabel("Climate")
        .accessibilityValue(title)
        .accessibilityHint(actionLabel)
    }
}

// MARK: Bay

/// The outline of the bay, drawn from the knob at the bottom centre and round
/// clockwise, so a trimmed stroke grows out of the knob like a clock hand.
private struct BayShape: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.width / 2, rect.height / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r), radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r), radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r), radius: r, startAngle: .degrees(270), endAngle: .degrees(360), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.closeSubpath()
        return path
    }

    func length(in size: CGSize) -> CGFloat {
        let r = min(radius, size.width / 2, size.height / 2)
        return 2 * (size.width - 2 * r) + 2 * (size.height - 2 * r) + 2 * .pi * r
    }
}

/// The car from above in its bay, with the knob set into the bottom edge.
private struct ClimateBay: View {
    var phase: ClimatePhase
    var warmth: Double
    var size: CGSize

    static let width: CGFloat = 244
    static let knob: CGFloat = 72
    private static let radius: CGFloat = 84
    private static let socket: CGFloat = 7
    private static let carAspect: CGFloat = 1130 / 2121
    /// Where the windscreen and the rear window sit in the top view, as
    /// fractions of the car's width and height.
    private static let glass: [(y: CGFloat, width: CGFloat, height: CGFloat)] = [
        (y: 0.245, width: 0.70, height: 0.125),
        (y: 0.845, width: 0.62, height: 0.075),
    ]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var strength = 0.0
    @State private var ripples = 0

    var body: some View {
        let shape = BayShape(radius: Self.radius)
        ZStack(alignment: .top) {
            interior(shape)
                .frame(width: size.width, height: size.height)
                .clipShape(shape)
                // One wave runs up from the knob when the air starts or stops.
                .ripple(at: CGPoint(x: size.width / 2, y: size.height), trigger: ripples, amplitude: 6)

            track(shape)
                .frame(width: size.width, height: size.height)

            knob
                .offset(y: size.height - Self.knob / 2 - Self.socket)
        }
        .frame(width: size.width, height: size.height + Self.knob / 2, alignment: .top)
        .onChange(of: phase.isFlowing, initial: true) { was, flowing in
            withAnimation(.easeInOut(duration: flowing ? 1.4 : 0.7)) { strength = flowing ? 1 : 0 }
            if was != flowing, !reduceMotion { ripples += 1 }
        }
    }

    // MARK: Interior

    private func interior(_ shape: BayShape) -> some View {
        // The car stands clear of the knob at the bottom.
        let carHeight = size.height - 92
        let carWidth = carHeight * Self.carAspect
        return ZStack(alignment: .top) {
            shape.fill(Palette.surface)

            TimelineView(.animation(minimumInterval: 1 / 30, paused: strength < 0.01 || reduceMotion)) { context in
                let time = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 600)
                ZStack(alignment: .top) {
                    // Air through the whole bay, faint.
                    Rectangle()
                        .colorEffect(ShaderLibrary.airflow(.float2(size), .float(time), .float(warmth), .float(strength * 0.7)))
                        .mask {
                            shape.padding(10).blur(radius: 12)
                        }

                    Image("CarTop")
                        .resizable()
                        .interpolation(.high)
                        .frame(width: carWidth, height: carHeight)
                        // One light from the upper left: a tight shadow down and to the right.
                        .shadow(color: .black.opacity(0.3), radius: 9, x: 4, y: 8)
                        .padding(.top, 30)

                    // Air seen through the glass: the windscreen and the rear window.
                    ForEach(Self.glass, id: \.y) { pane in
                        let paneSize = CGSize(width: carWidth * pane.width, height: carHeight * pane.height)
                        Rectangle()
                            .colorEffect(ShaderLibrary.airflow(.float2(paneSize), .float(time), .float(warmth), .float(strength)))
                            .frame(width: paneSize.width, height: paneSize.height)
                            .mask {
                                RoundedRectangle(cornerRadius: paneSize.height * 0.3, style: .continuous)
                                    .padding(3)
                                    .blur(radius: 5)
                            }
                            .blendMode(.plusLighter)
                            .padding(.top, 30 + carHeight * pane.y)
                    }
                }
            }
        }
    }

    // MARK: Track

    @ViewBuilder
    private func track(_ shape: BayShape) -> some View {
        shape.stroke(Palette.wellStrong, lineWidth: 3)

        switch phase {
        case .running(_, let progress):
            shape
                .trim(from: 0, to: max(0.001, progress))
                .stroke(Palette.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .animation(.linear(duration: 1), value: progress)
        case .ready:
            shape.stroke(Palette.accent, lineWidth: 4)
        case .waking, .sending:
            // No answer yet: a single segment keeps circling the bay.
            let length = shape.length(in: size)
            TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion)) { context in
                let turn = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.6) / 2.6
                shape.stroke(
                    Palette.accent,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [length * 0.14, length * 0.86], dashPhase: -turn * length)
                )
            }
        case .off, .stopping:
            EmptyView()
        }
    }

    // MARK: Knob

    private var knob: some View {
        ZStack {
            // The socket: a ring of the page's own colour that parts the track.
            Circle()
                .fill(Palette.canvas)
                .frame(width: Self.knob + Self.socket * 2, height: Self.knob + Self.socket * 2)
            Circle()
                .fill(phase.isEngaged ? Palette.ink : Palette.fill)
                .frame(width: Self.knob, height: Self.knob)
            glyph
                .foregroundStyle(phase.isEngaged ? Palette.canvas : Palette.onFill)
        }
        .animation(Motion.snappy, value: phase.isEngaged)
        .animation(Motion.snappy, value: phase.isBusy)
    }

    @ViewBuilder
    private var glyph: some View {
        if phase.isBusy {
            Spinner(size: 22)
                .transition(.blurReplace)
        } else if phase.isEngaged {
            IconView(.stop, size: 24)
                .transition(.blurReplace)
        } else {
            IconView(.climate, size: 30)
                .transition(.blurReplace)
        }
    }
}

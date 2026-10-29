import SwiftUI

// MARK: Panel

/// A tonal surface. Depth comes from the value step against the canvas and, in
/// the dark, a lip of the surface's own colour along the top edge. No shadow.
struct PanelBackground: View {
    var radius: CGFloat = 28
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        shape
            .fill(Palette.surface)
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [
                            Palette.ink.opacity(scheme == .dark ? 0.10 : 0.0),
                            Palette.ink.opacity(0.0),
                        ],
                        startPoint: .top,
                        endPoint: .center
                    ),
                    lineWidth: 1
                )
            }
    }
}

extension View {
    func panel(padding: CGFloat = 20, radius: CGFloat = 28) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PanelBackground(radius: radius))
    }
}

// MARK: Spinner

/// Small activity arc that takes the colour of the text around it.
struct Spinner: View {
    var size: CGFloat = 17
    @State private var turn = 0.0

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.72)
            .stroke(style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(turn))
            .onAppear {
                withAnimation(.linear(duration: 0.75).repeatForever(autoreverses: false)) { turn = 360 }
            }
            .accessibilityLabel("Working")
    }
}

// MARK: Row divider

/// Separates rows inside a panel: a tonal, round-capped line that stops short of
/// both edges.
struct RowDivider: View {
    var leading: CGFloat = 20

    var body: some View {
        Capsule()
            .fill(Palette.well)
            .frame(height: 1.5)
            .padding(.leading, leading)
            .padding(.trailing, 20)
            .accessibilityHidden(true)
    }
}

// MARK: Status bar fade

/// Scrolling content dissolves into the canvas before it reaches the clock,
/// instead of sliding underneath it at full strength.
private struct StatusBarFade: ViewModifier {
    /// Off while nothing has scrolled under the clock, so the top edge of the
    /// page itself can be seen.
    var isActive = true

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            GeometryReader { proxy in
                let height = proxy.safeAreaInsets.top + 22
                LinearGradient(
                    stops: [
                        .init(color: Palette.canvas, location: 0),
                        .init(color: Palette.canvas.opacity(0.94), location: 0.5),
                        .init(color: Palette.canvas.opacity(0.7), location: 0.72),
                        .init(color: Palette.canvas.opacity(0.32), location: 0.88),
                        .init(color: Palette.canvas.opacity(0), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: height)
                .offset(y: -proxy.safeAreaInsets.top)
            }
            .opacity(isActive ? 1 : 0)
            .animation(Motion.snappy, value: isActive)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

extension View {
    func statusBarFade(isActive: Bool = true) -> some View { modifier(StatusBarFade(isActive: isActive)) }
}

// MARK: Readout

/// A figure with its unit and a plain caption, set on a shared baseline so a row
/// of them lines up whatever the values are.
struct Readout: View {
    var value: String
    var unit: String? = nil
    var caption: String
    var size: CGFloat = 26
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.display(size, .medium, relativeTo: .title2))
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.numericText())
                if let unit {
                    Text(unit)
                        .font(.display(size * 0.52, .medium, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkSoft)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            Text(caption)
                .font(.footnote)
                .foregroundStyle(Palette.inkSoft)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(caption): \(value) \(unit ?? "")")
    }
}

// MARK: Blitz refresh mark

/// The Blitz as a live status mark. While the car is being woken the two halves
/// of the bolt slide apart and the ring turns; when the answer arrives they
/// close again.
struct BlitzRefreshMark: View {
    var isWorking: Bool
    var height: CGFloat = 26

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin = 0.0

    var body: some View {
        let width = height * BlitzShape.aspectRatio
        let gap = isWorking && !reduceMotion ? height * 0.16 : 0
        ZStack {
            BlitzShape(parts: .ring)
                .rotationEffect(.degrees(spin))
            BlitzShape(parts: .upperBolt)
                .offset(x: -gap)
            BlitzShape(parts: .lowerBolt)
                .offset(x: gap)
        }
        .frame(width: width, height: height)
        .opacity(isWorking ? 0.75 : 1)
        .animation(Motion.release, value: isWorking)
        .onChange(of: isWorking, initial: true) { _, working in
            guard !reduceMotion else { return }
            if working {
                spin = 0
                withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) { spin = 360 }
            } else {
                // Finish the turn it is in rather than snapping back.
                withAnimation(Motion.fluid) { spin = 0 }
            }
        }
        .accessibilityLabel(isWorking ? "Contacting the car" : "Opel")
    }
}

// MARK: Notice

/// Short confirmation that rises above the navigation bar: a solid capsule in
/// the page's ink, the inverse of everything around it.
struct NoticeBanner: View {
    let notice: VehicleModel.Notice

    var body: some View {
        HStack(spacing: 9) {
            IconView(notice.icon, size: 17)
                .foregroundStyle(notice.tone == .problem ? Palette.alert : Palette.canvas)
            Text(notice.text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.canvas)
        }
        .padding(.horizontal, 18)
        .frame(height: 44)
        .background(Palette.ink, in: .capsule)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}

// MARK: Brand button

/// Opel's button: a flat, solid capsule with a bold label. No border, no
/// shadow, no gradient. It answers a press by giving slightly and darkening.
struct BrandButtonStyle: ButtonStyle {
    enum Kind { case primary, quiet, inverse }

    var kind: Kind = .primary
    var height: CGFloat = 54

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.bold))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(background(pressed: configuration.isPressed), in: .capsule)
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .animation(configuration.isPressed ? Motion.press : Motion.release, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { Haptics.shared.touch() }
            }
    }

    private var foreground: Color {
        switch kind {
        case .primary: Palette.onFill
        case .quiet: Palette.ink
        case .inverse: Palette.canvas
        }
    }

    private func background(pressed: Bool) -> Color {
        switch kind {
        case .primary: pressed ? Palette.fillDeep : Palette.fill
        case .quiet: pressed ? Palette.wellStrong : Palette.well
        case .inverse: Palette.ink.opacity(pressed ? 0.82 : 1)
        }
    }
}

extension ButtonStyle where Self == BrandButtonStyle {
    static func brand(_ kind: BrandButtonStyle.Kind = .primary, height: CGFloat = 54) -> BrandButtonStyle {
        BrandButtonStyle(kind: kind, height: height)
    }
}

/// A round, solid control for a single glyph: settings, back, close.
struct RoundButtonStyle: ButtonStyle {
    var diameter: CGFloat = 44
    var onImage = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(onImage ? Palette.canvas : Palette.ink)
            .frame(width: diameter, height: diameter)
            .background(
                onImage ? Palette.ink : (configuration.isPressed ? Palette.wellStrong : Palette.well),
                in: .circle
            )
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(configuration.isPressed ? Motion.press : Motion.release, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { Haptics.shared.touch() }
            }
    }
}

// MARK: Brand toggle

/// A switch in the same flat language: a squared track and knob that borrow
/// their corners from the typeface. The two radii are concentric, so the gap
/// between knob and track is the same along the sides and around the corners.
struct BrandSwitch: View {
    @Binding var isOn: Bool

    private static let inset: CGFloat = 4
    private static let knobRadius: CGFloat = 7
    private static let trackRadius = knobRadius + inset

    var body: some View {
        RoundedRectangle(cornerRadius: Self.trackRadius, style: .continuous)
            .fill(isOn ? Palette.fill : Palette.wellStrong)
            .frame(width: 54, height: 30)
            .overlay(alignment: isOn ? .trailing : .leading) {
                RoundedRectangle(cornerRadius: Self.knobRadius, style: .continuous)
                    .fill(isOn ? Palette.onFill : Palette.inkSoft)
                    .frame(width: 22, height: 22)
                    .padding(Self.inset)
            }
            .animation(Motion.snappy, value: isOn)
            // The switch is small; give the finger the full 44 points.
            .frame(minWidth: 54, minHeight: 44)
            .contentShape(.rect)
            .onTapGesture {
                Haptics.shared.tick()
                isOn.toggle()
            }
            .accessibilityElement()
            .accessibilityAddTraits(.isToggle)
            .accessibilityValue(isOn ? "On" : "Off")
            .accessibilityAction { isOn.toggle() }
    }
}

struct BrandToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.label
            Spacer(minLength: 8)
            BrandSwitch(isOn: configuration.$isOn)
        }
    }
}

extension ToggleStyle where Self == BrandToggleStyle {
    static var brand: BrandToggleStyle { BrandToggleStyle() }
}

// MARK: Action orb

/// A round, solid control for one thing the car can do. It shows three things at
/// once: what it is, whether that thing is on, and whether a command is in
/// flight. Guarded actions can ask for a hold instead of a tap.
struct ActionOrb<Glyph: View>: View {
    var title: String
    var isActive = false
    var isBusy = false
    var holdDuration: TimeInterval? = nil
    var action: () -> Void
    @ViewBuilder var glyph: () -> Glyph

    @State private var holdProgress = 0.0
    @State private var isPressed = false
    @State private var busySpin = 0.0

    var body: some View {
        VStack(spacing: 13) {
            orb
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(isActive ? Palette.ink : Palette.inkSoft)
                .lineLimit(1)
                .contentTransition(.opacity)
        }
        .frame(maxWidth: .infinity)
        .animation(Motion.snappy, value: isActive)
        .animation(Motion.snappy, value: title)
    }

    private var orb: some View {
        glyph()
            .frame(width: 26, height: 26)
            .foregroundStyle(isActive ? Palette.onFill : Palette.ink)
            .frame(width: ActionOrbMetrics.diameter, height: ActionOrbMetrics.diameter)
            .background(background, in: .circle)
            .overlay { rings }
            .scaleEffect(isPressed ? 0.93 : 1)
            .animation(isPressed ? Motion.press : Motion.release, value: isPressed)
            .contentShape(.circle)
            .modifier(OrbGesture(holdDuration: holdDuration, isBusy: isBusy, onTap: fire, onPressChanged: { isPressed = $0 }, onHoldChanged: holdChanged, onHoldCompleted: holdCompleted))
            .accessibilityElement()
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(holdDuration == nil ? "" : "Touch and hold to confirm")
            .accessibilityAction { fire() }
    }

    private var background: Color {
        if isActive { return isPressed ? Palette.fillDeep : Palette.fill }
        return isPressed ? Palette.wellStrong : Palette.well
    }

    @ViewBuilder
    private var rings: some View {
        // Hold-to-confirm fills clockwise from twelve o'clock.
        Circle()
            .trim(from: 0, to: holdProgress)
            .stroke(Palette.accent, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .padding(-7)
            .opacity(holdProgress > 0 ? 1 : 0)

        if isBusy {
            Circle()
                .trim(from: 0, to: 0.22)
                .stroke(Palette.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(busySpin))
                .padding(-7)
                .transition(.opacity)
                .onAppear {
                    busySpin = 0
                    withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) { busySpin = 360 }
                }
        }
    }

    private func fire() {
        guard !isBusy else { return }
        action()
    }

    private func holdChanged(_ pressing: Bool) {
        guard let holdDuration, !isBusy else { return }
        if pressing {
            Haptics.shared.holdBegan(duration: holdDuration)
            withAnimation(.linear(duration: holdDuration)) { holdProgress = 1 }
        } else {
            // Let go early: the ring unwinds.
            Haptics.shared.holdCancelled()
            withAnimation(Motion.release) { holdProgress = 0 }
        }
    }

    private func holdCompleted() {
        Haptics.shared.holdCompleted()
        fire()
        withAnimation(Motion.fluid.delay(0.2)) { holdProgress = 0 }
    }
}

enum ActionOrbMetrics {
    static let diameter: CGFloat = 66
}

/// Touch handling for an orb: feedback on touch-down, the action on release, or
/// a press-and-hold with live progress for guarded actions. It runs alongside
/// the scroll view's own pan and gives way as soon as the finger travels.
private struct OrbGesture: ViewModifier {
    var holdDuration: TimeInterval?
    var isBusy: Bool
    var onTap: () -> Void
    var onPressChanged: (Bool) -> Void
    var onHoldChanged: (Bool) -> Void
    var onHoldCompleted: () -> Void

    @State private var isDown = false
    @State private var isSpent = false
    @State private var timer: Task<Void, Never>?

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let travel = hypot(value.translation.width, value.translation.height)
                    if !isDown, !isSpent, !isBusy, travel < 10 {
                        begin()
                    } else if isDown, travel > 16 {
                        cancel()
                    }
                }
                .onEnded { _ in
                    if isDown {
                        if holdDuration == nil {
                            isDown = false
                            onPressChanged(false)
                            onTap()
                        } else {
                            cancel()
                        }
                    }
                    isSpent = false
                }
        )
    }

    private func begin() {
        isDown = true
        onPressChanged(true)
        Haptics.shared.touch()
        guard let holdDuration else { return }
        onHoldChanged(true)
        timer = Task {
            try? await Task.sleep(for: .seconds(holdDuration))
            guard !Task.isCancelled, isDown else { return }
            isDown = false
            isSpent = true
            onPressChanged(false)
            onHoldCompleted()
        }
    }

    private func cancel() {
        timer?.cancel()
        timer = nil
        isDown = false
        // Don't restart while the same touch is still down.
        isSpent = true
        onPressChanged(false)
        if holdDuration != nil { onHoldChanged(false) }
    }
}

// MARK: Themed shader arguments

extension Shader.Argument {
    /// A colourway role as a float3, for shaders that paint in the accent.
    static func themed(_ role: KeyPath<AppTheme.Tokens, AppTheme.Pair>, dark: Bool) -> Shader.Argument {
        let c = Palette.components(role, dark: dark)
        return .float3(c.0, c.1, c.2)
    }
}

// MARK: Battery line

/// Slim state-of-charge bar with the charge limit marked on it.
struct BatteryLine: View {
    var level: Double
    var limit: Int
    var isCharging: Bool
    var height: CGFloat = 10

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let fill = max(height, width * level / 100)
            let dark = scheme == .dark
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.well)
                TimelineView(.animation(minimumInterval: 1 / 30, paused: !isCharging || reduceMotion)) { context in
                    let time = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 600)
                    Capsule()
                        .fill(Palette.fill)
                        .colorEffect(
                            ShaderLibrary.energyFill(
                                .float2(fill, height),
                                .float(time),
                                .float(isCharging ? 1 : 0),
                                .themed(\.fill, dark: dark),
                                .themed(\.fillDeep, dark: dark),
                                .themed(\.fillHot, dark: dark)
                            )
                        )
                        .frame(width: fill)
                }
                Capsule()
                    .fill(Palette.ink)
                    .frame(width: 3, height: height + 10)
                    .offset(x: width * Double(limit) / 100 - 1.5)
            }
        }
        .frame(height: height)
        .animation(Motion.fluid, value: level)
        .animation(Motion.release, value: limit)
        .accessibilityElement()
        .accessibilityLabel("Battery")
        .accessibilityValue("\(Int(level)) percent, limit \(limit) percent")
    }
}

// MARK: Route glyph

/// The actual shape of a drive, drawn from its coordinates.
struct RouteGlyph: View {
    var route: [Coordinate]
    var lineWidth: CGFloat = 2.2

    var body: some View {
        Canvas { context, size in
            guard route.count > 1 else { return }
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: lineWidth + 3, dy: lineWidth + 3)
            let points = Self.project(route, in: rect)
            guard let first = points.first, let last = points.last else { return }
            var path = Path()
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
            context.stroke(path, with: .color(Palette.ink), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            context.fill(Path(ellipseIn: CGRect(x: first.x - 2.5, y: first.y - 2.5, width: 5, height: 5)), with: .color(Palette.ink))
            context.fill(Path(ellipseIn: CGRect(x: last.x - 3.5, y: last.y - 3.5, width: 7, height: 7)), with: .color(Palette.accent))
        }
        .accessibilityHidden(true)
    }

    private static func project(_ route: [Coordinate], in rect: CGRect) -> [CGPoint] {
        let lats = route.map(\.latitude), lons = route.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(), let minLon = lons.min(), let maxLon = lons.max() else { return [] }
        // Longitude degrees shrink with latitude; correct so the shape isn't stretched.
        let lonScale = cos((minLat + maxLat) / 2 * .pi / 180)
        let spanX = max((maxLon - minLon) * lonScale, 0.0001)
        let spanY = max(maxLat - minLat, 0.0001)
        let scale = min(rect.width / spanX, rect.height / spanY)
        let offsetX = rect.midX - spanX * scale / 2
        let offsetY = rect.midY - spanY * scale / 2
        return route.map {
            CGPoint(
                x: offsetX + ($0.longitude - minLon) * lonScale * scale,
                y: offsetY + (maxLat - $0.latitude) * scale
            )
        }
    }
}

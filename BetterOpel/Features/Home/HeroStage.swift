import SwiftUI

/// The first screen's composition: the range set large on the studio wall, the
/// car standing in front of it. The car's glass is translucent in the render, so
/// the figure reads through the windscreen.
struct HeroStage: View {
    @Environment(VehicleModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var safeTop: CGFloat
    var width: CGFloat
    var openSettings: () -> Void

    @State private var arrived = false
    @State private var nudges = 0

    private static let carAspect = CarRender.aspect

    var body: some View {
        let snapshot = model.snapshot
        let headerHeight: CGFloat = 60
        let numeralSize = min(width * 0.47, 210)
        // Technor's figures stand 0.64 em tall and start 0.27 em below the line top.
        let capHeight = numeralSize * 0.64
        let capTop = safeTop + headerHeight + 36
        let carWidth = width * 0.97
        let carHeight = carWidth / Self.carAspect
        let carTop = capTop + capHeight * 0.7
        let stageHeight = carTop + carHeight + 26
        let floorLine = carTop + carHeight * 0.83

        ZStack(alignment: .topLeading) {
            backdrop(height: stageHeight, horizon: floorLine / stageHeight)

            // Re-read every half minute, so the figure ages while the screen is open.
            TimelineView(.periodic(from: .now, by: 30)) { context in
                numeral(
                    range: model.hasReading ? snapshot.rangeKm : nil,
                    size: numeralSize,
                    staleness: model.hasReading ? Self.staleness(of: snapshot.updatedAt, at: context.date) : 0
                )
            }
                .frame(width: width)
                .offset(y: capTop - numeralSize * 0.27)
                .visualEffect { content, proxy in
                    // Scroll-linked: the figure lags behind the car as the stage leaves.
                    let travel = min(0, proxy.frame(in: .scrollView(axis: .vertical)).minY)
                    return content.offset(y: -travel * 0.32)
                }

            car(width: carWidth, height: carHeight, snapshot: snapshot)
                .offset(x: (width - carWidth) / 2 + (arrived ? 0 : width * 0.16), y: carTop)

            header(snapshot: snapshot)
                .padding(.horizontal, 20)
                .frame(width: width, height: headerHeight)
                .offset(y: safeTop + 4)
        }
        .frame(width: width, height: stageHeight, alignment: .topLeading)
        .onAppear {
            guard !arrived else { return }
            if reduceMotion {
                arrived = true
            } else {
                withAnimation(Motion.arrive) { arrived = true }
            }
        }
        .onChange(of: model.lockCue) { nudge() }
    }

    // MARK: Layers

    private func backdrop(height: CGFloat, horizon: CGFloat) -> some View {
        Rectangle()
            .colorEffect(
                // The room takes its tones from the colourway, so the stage and
                // the page around it stay one surface.
                ShaderLibrary.studio(
                    .float2(width, height),
                    .float(scheme == .dark ? 1 : 0),
                    .float(horizon),
                    .themed(\.canvas, dark: scheme == .dark),
                    .themed(scheme == .dark ? \.wellStrong : \.surface, dark: scheme == .dark),
                    floorTone
                )
            )
            .frame(width: width, height: height)
            .accessibilityHidden(true)
    }

    /// The floor sits a step below the wall: deeper than the canvas at night,
    /// a shade under it by day.
    private var floorTone: Shader.Argument {
        let dark = scheme == .dark
        let c = Palette.components(dark ? \.canvas : \.well, dark: dark)
        let k: Float = dark ? 0.35 : 0.97
        return .float3(c.0 * k, c.1 * k, c.2 * k)
    }

    /// How worn the range figure is drawn: untouched for five minutes after the
    /// car reported, fully worn once the reading is an hour old.
    private static func staleness(of reported: Date, at now: Date) -> Double {
        var minutes = now.timeIntervalSince(reported) / 60
        #if DEBUG
        // `-stale 40` ages the reading by forty minutes, for UI checks.
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-stale"), arguments.indices.contains(index + 1) {
            minutes += Double(arguments[index + 1]) ?? 0
        }
        #endif
        return min(1, max(0, (minutes - 5) / 55))
    }

    private func numeral(range: Int?, size: CGFloat, staleness: Double) -> some View {
        // A dash until the car has reported for the first time.
        Text(range.map(String.init) ?? "–")
            .font(.displayFixed(size, .bold))
            .kerning(size * 0.012)
            .foregroundStyle(Palette.ink)
            .contentTransition(.numericText(value: Double(range ?? 0)))
            .animation(Motion.fluid, value: range)
            .fixedSize()
            // An old reading is drawn worn; a fresh report makes it whole again.
            .modifier(StaleGrain(amount: staleness))
            .animation(Motion.fluid, value: staleness)
            .overlay(alignment: .topTrailing) {
                // The unit rides on the cap line, flush with the last figure.
                Text("km")
                    .font(.displayFixed(17, .semibold))
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize()
                    .alignmentGuide(.top) { $0.height - (size * 0.27 - 9) }
                    .padding(.trailing, size * 0.02)
            }
            .accessibilityElement()
            .accessibilityLabel(range.map { "Range \($0) kilometres" } ?? "Range not known yet")
    }

    private func car(width: CGFloat, height: CGFloat, snapshot: VehicleSnapshot) -> some View {
        ZStack(alignment: .top) {
            // Contact shadow: tight, under the tyres only.
            Ellipse()
                .fill(.black.opacity(scheme == .dark ? 0.7 : 0.3))
                .frame(width: width * 0.86, height: height * 0.09)
                .blur(radius: 9)
                .offset(x: width * 0.01, y: height * 0.9)

            CarRender(isLarge: true)
                .frame(width: width, height: height)
                // The body settles on its springs when the car locks or is touched.
                .keyframeAnimator(initialValue: 0.0, trigger: nudges) { view, dip in
                    view.offset(y: dip)
                } keyframes: { _ in
                    SpringKeyframe(3.5, duration: 0.12, spring: .snappy)
                    SpringKeyframe(0, duration: 0.55, spring: .bouncy)
                }
        }
        .frame(width: width, height: height, alignment: .top)
        .contentShape(.rect)
        .onTapGesture {
            Haptics.shared.settle()
            nudge()
        }
        .accessibilityElement()
        .accessibilityLabel("\(snapshot.model), \(snapshot.isLocked ? "locked" : "unlocked")")
    }

    private func header(snapshot: VehicleSnapshot) -> some View {
        HStack(spacing: 12) {
            Button {
                Task { await model.refresh() }
            } label: {
                BlitzRefreshMark(isWorking: model.isPending(.refresh), height: 24)
                    .foregroundStyle(Palette.ink)
                    .frame(width: 44, height: 44, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Refresh")

            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.name)
                    .font(.display(22, .semibold, relativeTo: .title3))
                    .foregroundStyle(Palette.ink)
                Text(model.headline)
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSoft)
                    .contentTransition(.numericText())
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button(action: openSettings) {
                IconView(.sliders, size: 20)
            }
            .buttonStyle(RoundButtonStyle())
            .accessibilityLabel("Settings")
        }
    }

    private func nudge() {
        guard !reduceMotion else { return }
        nudges += 1
    }
}

/// Feeds the wear to the shader as an animatable value, so a fresh reading
/// resolves the figure instead of switching it.
private struct StaleGrain: ViewModifier, @preconcurrency Animatable {
    var amount: Double

    var animatableData: Double {
        get { amount }
        set { amount = newValue }
    }

    func body(content: Content) -> some View {
        let amount = amount
        // Room at the sides, so the scattered samples are not cut at the frame.
        return content
            .padding(.horizontal, 18)
            .visualEffect { view, proxy in
                view.layerEffect(
                    ShaderLibrary.staleBlur(.float2(proxy.size), .float(amount)),
                    maxSampleOffset: CGSize(width: 18, height: 18),
                    isEnabled: amount > 0.001
                )
            }
            .padding(.horizontal, -18)
    }
}

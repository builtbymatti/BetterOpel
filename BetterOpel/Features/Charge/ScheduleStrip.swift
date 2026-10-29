import SwiftUI

/// One night on a strip, noon to noon, so an overnight charging window is a
/// single unbroken span. The darker band is the cheap tariff; the yellow span is
/// when the car may charge. Drag either end, or the whole span.
struct ScheduleStrip: View {
    @Binding var start: TimeOfDay
    @Binding var stop: TimeOfDay
    var isEnabled: Bool
    var tariff: ElectricityTariff
    var onCommit: () -> Void

    private static let trackHeight: CGFloat = 52
    private static let flagHeight: CGFloat = 22
    private static let snap = 15
    private static let minimumWindow = 60
    /// 11:45 the next morning; noon itself would wrap onto the start of the strip.
    private static let lastSlot = 1440 - snap

    private enum Part { case start, stop, span }

    @State private var active: Part?
    @State private var origin: (start: Int, stop: Int)?
    @State private var lastTick: Int?

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { proxy in
                let width = proxy.size.width
                let a = axis(start)
                let b = max(a + Self.minimumWindow, axis(stop))
                let x0 = width * CGFloat(a) / 1440
                let x1 = width * CGFloat(b) / 1440
                let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

                ZStack(alignment: .topLeading) {
                    // Track with the night-tariff band.
                    shape.fill(Palette.well)
                        .overlay(alignment: .leading) {
                            let n0 = width * CGFloat(axis(tariff.nightStart)) / 1440
                            let n1 = width * CGFloat(axis(tariff.nightEnd)) / 1440
                            Rectangle()
                                .fill(Palette.wellStrong)
                                .frame(width: max(0, n1 - n0))
                                .offset(x: n0)
                        }
                        .clipShape(shape)
                        .frame(height: Self.trackHeight)
                        .offset(y: Self.flagHeight + 6)

                    // The charging window.
                    // Concentric with the track: its 16 pt corner less the 6 pt inset.
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isEnabled ? Palette.fill : Palette.inkFaint.opacity(0.35))
                        .frame(width: max(0, x1 - x0), height: Self.trackHeight - 12)
                        .offset(x: x0, y: Self.flagHeight + 12)
                        .gesture(drag(.span, width: width))

                    handle(time: start, isActive: active == .start)
                        .offset(x: x0 - 22)
                        .gesture(drag(.start, width: width))
                    handle(time: stop, isActive: active == .stop)
                        .offset(x: x1 - 22)
                        .gesture(drag(.stop, width: width))
                }
            }
            .frame(height: Self.flagHeight + 6 + Self.trackHeight)

            // Hour scale: first and last labels sit flush with the track ends.
            GeometryReader { proxy in
                let labels = ["12", "18", "00", "06", "12"]
                ForEach(labels.indices, id: \.self) { index in
                    let x = proxy.size.width * CGFloat(index) / CGFloat(labels.count - 1)
                    let isFirst = index == 0, isLast = index == labels.count - 1
                    Text(labels[index])
                        .fixedSize()
                        .frame(width: 30, alignment: isFirst ? .leading : (isLast ? .trailing : .center))
                        .offset(x: isFirst ? x : (isLast ? x - 30 : x - 15))
                }
            }
            .font(.display(12, .medium, relativeTo: .caption))
            .foregroundStyle(Palette.inkFaint)
            .frame(height: 16)
            .accessibilityHidden(true)
        }
        .opacity(isEnabled ? 1 : 0.6)
        .animation(Motion.snappy, value: isEnabled)
        .accessibilityElement()
        .accessibilityLabel("Charging window")
        .accessibilityValue("\(start.label) to \(stop.label)")
    }

    private func handle(time: TimeOfDay, isActive: Bool) -> some View {
        VStack(spacing: 6) {
            Text(time.label)
                .font(.displayFixed(13, .semibold))
                .foregroundStyle(Palette.ink)
                .contentTransition(.numericText())
                .frame(height: Self.flagHeight)
                .fixedSize()
                .scaleEffect(isActive ? 1.12 : 1, anchor: .bottom)
            Capsule()
                .fill(Palette.ink)
                .frame(width: isActive ? 6 : 5, height: Self.trackHeight)
        }
        .frame(width: 44)
        .contentShape(.rect)
        .animation(Motion.press, value: isActive)
        .animation(Motion.snappy, value: time)
    }

    // MARK: Axis

    /// Minutes since noon, 0...1440.
    private func axis(_ time: TimeOfDay) -> Int {
        (time.minutes - 720 + 1440) % 1440
    }

    private func time(fromAxis value: Int) -> TimeOfDay {
        TimeOfDay(minutes: value + 720)
    }

    private func drag(_ part: Part, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: part == .span ? 6 : 0, coordinateSpace: .global)
            .onChanged { value in
                guard isEnabled else { return }
                if origin == nil {
                    let a = axis(start)
                    origin = (a, max(a + Self.minimumWindow, axis(stop)))
                    active = part
                    Haptics.shared.touch()
                }
                guard let origin else { return }
                let delta = Int((value.translation.width / width * 1440 / CGFloat(Self.snap)).rounded()) * Self.snap
                var a = origin.start, b = origin.stop
                switch part {
                case .start:
                    a = min(max(0, origin.start + delta), origin.stop - Self.minimumWindow)
                case .stop:
                    b = max(min(Self.lastSlot, origin.stop + delta), origin.start + Self.minimumWindow)
                case .span:
                    let length = origin.stop - origin.start
                    a = min(max(0, origin.start + delta), Self.lastSlot - length)
                    b = a + length
                }
                let marker = a * 10_000 + b
                if marker != lastTick {
                    lastTick = marker
                    let onTheHour = (part == .stop ? b : a) % 60 == 0
                    if onTheHour { Haptics.shared.detent() } else { Haptics.shared.tick() }
                }
                start = time(fromAxis: a)
                stop = time(fromAxis: b)
            }
            .onEnded { _ in
                guard origin != nil else { return }
                origin = nil
                lastTick = nil
                active = nil
                Haptics.shared.settle()
                onCommit()
            }
    }
}

import SwiftUI

enum Weekday {
    static let letters = ["M", "T", "W", "T", "F", "S", "S"]
    static let names = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    static func summary(_ days: Set<Int>) -> String {
        if days.isEmpty { return "once" }
        if days.count == 7 { return "every day" }
        if days == [1, 2, 3, 4, 5] { return "weekdays" }
        if days == [6, 7] { return "weekends" }
        return days.sorted().map { names[$0 - 1] }.joined(separator: ", ")
    }

    /// "today", "tomorrow", or the name of the day.
    static func word(for date: Date, now: Date = .now) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return "today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "tomorrow"
        }
        return names[(calendar.component(.weekday, from: date) + 5) % 7]
    }

    static func clock(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return TimeOfDay(hour: parts.hour ?? 0, minute: parts.minute ?? 0).label
    }
}

// MARK: Section

/// The times the server starts the climate by itself, as a list on the Climate
/// screen.
struct WarmUpSection: View {
    @Environment(VehicleModel.self) private var model
    @State private var editing: WarmUp?

    private static let most = 12

    var body: some View {
        // Re-read every half minute, so "starts today" stays true.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date
            let list = model.warmUps
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Ready by")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    Text(note(now: now))
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSoft)
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 8)

                VStack(spacing: 0) {
                    switch model.warmUpLink {
                    case .loading:
                        HStack(spacing: 10) {
                            Spinner()
                            Text("Asking your server")
                                .font(.body)
                            Spacer()
                        }
                        .foregroundStyle(Palette.inkSoft)
                        .padding(.horizontal, 20)
                        .frame(height: 58)
                    case .unavailable(let reason):
                        unavailable(reason)
                    case .ready:
                        if list.isEmpty {
                            Text("Nothing planned. Add a time and the server starts the climate ten minutes before it.")
                                .font(.subheadline)
                                .foregroundStyle(Palette.inkSoft)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 20)
                                .padding(.top, 18)
                                .padding(.bottom, 14)
                            RowDivider()
                        }
                        ForEach(list) { warmUp in
                            WarmUpRow(
                                warmUp: warmUp,
                                now: now,
                                onToggle: { toggle(warmUp) },
                                onEdit: { editing = warmUp }
                            )
                            if warmUp.id != list.last?.id || list.count < Self.most {
                                RowDivider()
                            }
                        }
                        if list.count < Self.most {
                            Button {
                                Haptics.shared.touch()
                                editing = WarmUp(hour: 7, minute: 30, days: [1, 2, 3, 4, 5])
                            } label: {
                                HStack(spacing: 10) {
                                    IconView(.plus, size: 18)
                                    Text("Add a time")
                                        .font(.body.weight(.semibold))
                                    Spacer()
                                }
                                .foregroundStyle(Palette.accent)
                                .padding(.horizontal, 20)
                                .frame(height: 58)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.pressable(scale: 0.985))
                        }
                    }
                }
                .background(PanelBackground())
                .animation(Motion.fluid, value: list)
                .animation(Motion.fluid, value: model.warmUpLink)

                Text(model.isLive
                    ? "Your server starts the climate ten minutes before each time. The programmes stored in the car are not used."
                    : "A demo schedule. Nothing is sent to a car.")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .padding(.top, 8)
            }
        }
        .task {
            await model.loadWarmUps()
            #if DEBUG
            // `-warmUp edit` or `-warmUp new` opens the editor directly, for UI checks.
            let arguments = ProcessInfo.processInfo.arguments
            if let index = arguments.firstIndex(of: "-warmUp"), arguments.indices.contains(index + 1) {
                editing = arguments[index + 1] == "new" ? WarmUp(hour: 7, minute: 30, days: [1, 2, 3, 4, 5]) : model.warmUps.first
            }
            #endif
        }
        .sheet(item: $editing) { warmUp in
            WarmUpEditor(
                warmUp: warmUp,
                isNew: !model.warmUps.contains { $0.id == warmUp.id },
                onSave: { save($0) },
                onDelete: { delete($0) }
            )
            .presentationDetents([.height(486)])
            .presentationDragIndicator(.visible)
        }
    }

    private func unavailable(_ reason: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(reason)
                .font(.body.weight(.semibold))
                .foregroundStyle(Palette.ink)
            Text("Timed starts are kept on your server, so they need it to answer.")
                .font(.subheadline)
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Haptics.shared.touch()
                Task { await model.loadWarmUps() }
            } label: {
                Text("Try again")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.accent)
                    .frame(height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.pressable(scale: 0.97))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 6)
    }

    private func note(now: Date) -> String {
        guard model.warmUpLink == .ready else { return "" }
        guard let start = model.nextWarmUp?.nextStart else { return model.warmUps.isEmpty ? "" : "Nothing planned" }
        return "Next start \(Weekday.word(for: start, now: now)) \(Weekday.clock(start))"
    }

    private func toggle(_ warmUp: WarmUp) {
        var list = model.warmUps
        guard let index = list.firstIndex(where: { $0.id == warmUp.id }) else { return }
        list[index].isOn.toggle()
        Task { await model.setWarmUps(list) }
    }

    private func save(_ warmUp: WarmUp) {
        var list = model.warmUps
        if let index = list.firstIndex(where: { $0.id == warmUp.id }) {
            list[index] = warmUp
        } else {
            list.append(warmUp)
        }
        Haptics.shared.success()
        Task { await model.setWarmUps(list) }
    }

    private func delete(_ warmUp: WarmUp) {
        let list = model.warmUps.filter { $0.id != warmUp.id }
        Haptics.shared.settle()
        Task { await model.setWarmUps(list) }
    }
}

// MARK: Row

private struct WarmUpRow: View {
    let warmUp: WarmUp
    var now: Date
    var onToggle: () -> Void
    var onEdit: () -> Void

    var body: some View {
        let status = status
        HStack(spacing: 14) {
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 9) {
                    Text(warmUp.ready.label)
                        .font(.display(30, .medium, relativeTo: .title))
                        .foregroundStyle(warmUp.isOn ? Palette.ink : Palette.inkFaint)
                        .contentTransition(.numericText())

                    if warmUp.runsOnce {
                        Text("Once")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(warmUp.isOn ? Palette.ink : Palette.inkFaint)
                            .frame(height: WeekInk.height(radius: 10), alignment: .center)
                    } else {
                        WeekInk(days: warmUp.days, slot: 24, radius: 10, fontSize: 11, isQuiet: !warmUp.isOn)
                            // The ink reaches the edge of its first slot; pull the
                            // first letter back onto the row's left margin.
                            .padding(.leading, -6)
                    }

                    Text(status.text)
                        .font(.footnote)
                        .foregroundStyle(status.isProblem ? Palette.alert : Palette.inkSoft)
                        .contentTransition(.numericText())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.pressable(scale: 0.98))
            .accessibilityLabel("Ready by \(warmUp.ready.label), \(Weekday.summary(warmUp.days)). \(status.text)")
            .accessibilityHint("Edit")

            BrandSwitch(isOn: Binding(get: { warmUp.isOn }, set: { _ in onToggle() }))
                .accessibilityLabel("Ready by \(warmUp.ready.label)")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 15)
        .animation(Motion.snappy, value: warmUp.isOn)
    }

    /// What the server last did for this time, or what it will do next.
    private var status: (text: String, isProblem: Bool) {
        if let run = warmUp.lastRun, now.timeIntervalSince(run.at) < 3 * 3600, now >= run.at {
            let at = Weekday.clock(run.at)
            switch run.outcome {
            case .confirmed: return ("Started at \(at), the car confirmed", false)
            case .sent: return ("Started at \(at), no word from the car", true)
            case .failed: return ("Could not start at \(at)", true)
            }
        }
        guard warmUp.isOn else { return (warmUp.runsOnce && warmUp.lastRun != nil ? "Done" : "Off", false) }
        guard let start = warmUp.nextStart else { return ("Nothing planned", false) }
        return ("Starts \(Weekday.word(for: start, now: now)) at \(Weekday.clock(start))", false)
    }
}

// MARK: Week ink

/// How chosen each day of the week is, as something SwiftUI can animate.
struct WeekWeights: VectorArithmetic, Sendable {
    var values = SIMD8<Double>(repeating: 0)

    init() {}

    init(days: Set<Int>) {
        for day in 1...7 where days.contains(day) { values[day - 1] = 1 }
    }

    static var zero: WeekWeights { WeekWeights() }

    static func + (lhs: WeekWeights, rhs: WeekWeights) -> WeekWeights {
        var result = lhs
        result.values += rhs.values
        return result
    }

    static func - (lhs: WeekWeights, rhs: WeekWeights) -> WeekWeights {
        var result = lhs
        result.values -= rhs.values
        return result
    }

    mutating func scale(by rhs: Double) { values *= rhs }

    var magnitudeSquared: Double { (values * values).sum() }
}

/// Seven initials with the chosen days set in ink. Neighbouring chosen days run
/// together into one bar; taking a day out of the middle pulls the bar apart.
struct WeekInk: View {
    var days: Set<Int>
    var slot: CGFloat
    var radius: CGFloat
    var fontSize: CGFloat
    /// For a time that is switched off: the ink steps back to a tone.
    var isQuiet = false

    static func height(radius: CGFloat) -> CGFloat { (radius * 2.5).rounded() }

    var body: some View {
        ZStack {
            WeekInkBlot(weights: WeekWeights(days: days), slot: slot, radius: radius, isQuiet: isQuiet)
                // A touch of bounce, so a day lands like a drop.
                .animation(.spring(response: 0.36, dampingFraction: 0.6), value: days)

            HStack(spacing: 0) {
                ForEach(1...7, id: \.self) { day in
                    let on = days.contains(day)
                    Text(Weekday.letters[day - 1])
                        .font(.system(size: fontSize, weight: on ? .bold : .medium))
                        .foregroundStyle(on ? (isQuiet ? Palette.inkSoft : Palette.canvas) : Palette.inkFaint)
                        .frame(width: slot)
                }
            }
            .animation(Motion.snappy, value: days)
        }
        .frame(width: slot * 7, height: Self.height(radius: radius))
        .accessibilityHidden(true)
    }
}

private struct WeekInkBlot: View, @preconcurrency Animatable {
    var weights: WeekWeights
    var slot: CGFloat
    var radius: CGFloat
    var isQuiet: Bool

    var animatableData: WeekWeights {
        get { weights }
        set { weights = newValue }
    }

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let v = weights.values
        let size = CGSize(width: slot * 7, height: WeekInk.height(radius: radius))
        Rectangle()
            .colorEffect(
                ShaderLibrary.weekInk(
                    .float2(size),
                    .float4(v[0], v[1], v[2], v[3]),
                    .float3(v[4], v[5], v[6]),
                    .float(radius),
                    .themed(isQuiet ? \.wellStrong : \.ink, dark: scheme == .dark)
                )
            )
            .frame(width: size.width, height: size.height)
    }
}

/// The week as something to paint: touch a day to change it, and keep the
/// finger down to carry the same change across its neighbours.
private struct WeekPainter: View {
    @Binding var days: Set<Int>

    @State private var painting: Bool?
    @State private var lastDay: Int?

    private static let radius: CGFloat = 19

    var body: some View {
        GeometryReader { proxy in
            let slot = proxy.size.width / 7
            WeekInk(days: days, slot: slot, radius: Self.radius, fontSize: 15)
                .contentShape(.rect)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let day = min(7, max(1, Int(value.location.x / slot) + 1))
                            guard day != lastDay else { return }
                            lastDay = day
                            // The first day touched decides: choosing or clearing.
                            let choose = painting ?? !days.contains(day)
                            painting = choose
                            guard days.contains(day) != choose else { return }
                            if choose { days.insert(day) } else { days.remove(day) }
                            Haptics.shared.tick()
                        }
                        .onEnded { _ in
                            painting = nil
                            lastDay = nil
                        }
                )
        }
        .frame(height: WeekInk.height(radius: Self.radius))
        .accessibilityRepresentation {
            HStack {
                ForEach(1...7, id: \.self) { day in
                    Toggle(Weekday.names[day - 1], isOn: Binding(
                        get: { days.contains(day) },
                        set: { on in if on { days.insert(day) } else { days.remove(day) } }
                    ))
                }
            }
        }
    }
}

// MARK: Time tape

/// Sets a time by pulling a ruler of the day under a fixed needle. The needle
/// is the same reed as the charge limit's: it bows in the stream of the tape
/// and swings back when the tape stops. The warm band behind it is the ten
/// minutes the climate runs before the time is reached.
private struct TimeTape: View {
    /// Minutes into the day, in steps of five.
    @Binding var minutes: Int

    static let height: CGFloat = 96
    private static let step = 5
    private static let stepWidth: CGFloat = 22
    private static let last = 1435

    @State private var position: ScrollPosition
    @State private var offset: CGFloat
    @State private var goo = LimitGoo()
    @State private var isAwake = false
    @State private var rest: Task<Void, Never>?
    @State private var lastTick = Date.distantPast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    init(minutes: Binding<Int>) {
        _minutes = minutes
        let x = CGFloat(minutes.wrappedValue) / CGFloat(Self.step) * Self.stepWidth
        _position = State(initialValue: ScrollPosition(x: x))
        _offset = State(initialValue: x)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let needle = width / 2
            let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
            let isLive = isAwake && !reduceMotion
            let isDark = scheme == .dark
            let lead = CGFloat(WarmUp.leadMinutes) / CGFloat(Self.step) * Self.stepWidth

            ZStack(alignment: .topLeading) {
                shape.fill(Palette.well)
                    .frame(width: width, height: Self.height)

                TimelineView(.animation(minimumInterval: isLive ? nil : 1 / 30, paused: reduceMotion)) { context in
                    let pose = goo.advance(marker: offset, flagHome: 0, flagWidth: 0, isHeld: false, isLive: isLive, at: context.date)
                    let time = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 600)
                    Rectangle()
                        .colorEffect(
                            ShaderLibrary.warmBand(
                                .float4(needle, pose.bow, -2, Self.height + 8),
                                .float(lead),
                                .float(time),
                                .themed(\.fill, dark: isDark),
                                .themed(\.fillHot, dark: isDark)
                            )
                        )
                        .frame(width: width, height: Self.height)
                        .clipShape(shape)
                }
                .allowsHitTesting(false)

                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(0..<24, id: \.self) { hour in
                            HourCell(hour: hour, stepWidth: Self.stepWidth, height: Self.height)
                        }
                    }
                    .padding(.leading, needle)
                    // 23:55 is the last time that can sit under the needle.
                    .padding(.trailing, needle - Self.stepWidth)
                }
                .scrollIndicators(.hidden)
                .scrollPosition($position)
                .scrollTargetBehavior(StepSnap(step: Self.stepWidth))
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.x
                } action: { _, x in
                    moved(to: x)
                }
                .frame(width: width, height: Self.height)
                // The ruler dissolves toward both ends instead of stopping.
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.16),
                            .init(color: .black, location: 0.84),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
                .clipShape(shape)

                TimelineView(.animation(paused: !isLive)) { context in
                    let pose = goo.advance(marker: offset, flagHome: 0, flagWidth: 0, isHeld: false, isLive: isLive, at: context.date)
                    Rectangle()
                        .colorEffect(
                            ShaderLibrary.limitGoo(
                                .float2(Self.margin, Self.margin),
                                .float4(needle, -2, Self.height + 8, 2.5),
                                // No flag here, only a small head to the pin.
                                .float4(needle, -3, 4.5, 4.5),
                                .float2(pose.bow, 0),
                                .themed(\.ink, dark: isDark),
                                .themed(\.canvas, dark: isDark)
                            )
                        )
                        .frame(width: width + Self.margin * 2, height: Self.height + Self.margin * 2)
                        .offset(x: -Self.margin, y: -Self.margin)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(height: Self.height)
        .accessibilityElement()
        .accessibilityLabel("Ready by")
        .accessibilityValue(TimeOfDay(minutes: minutes).label)
        .accessibilityAdjustableAction { direction in
            let next = min(Self.last, max(0, minutes + (direction == .increment ? Self.step : -Self.step)))
            position.scrollTo(x: CGFloat(next) / CGFloat(Self.step) * Self.stepWidth)
        }
    }

    private static let margin: CGFloat = 40

    private func moved(to x: CGFloat) {
        offset = x
        let stepped = Int((x / Self.stepWidth).rounded()) * Self.step
        let clamped = min(Self.last, max(0, stepped))
        if clamped != minutes {
            minutes = clamped
            // A flick passes dozens of steps a second; the hand only needs some.
            if Date.now.timeIntervalSince(lastTick) > 0.03 {
                lastTick = .now
                if clamped % 60 == 0 { Haptics.shared.detent() } else { Haptics.shared.tick() }
            }
        }
        isAwake = true
        rest?.cancel()
        rest = Task {
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            isAwake = false
        }
    }
}

/// Lets the tape come to rest on a five-minute step only.
private struct StepSnap: ScrollTargetBehavior {
    var step: CGFloat

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        target.rect.origin.x = (target.rect.origin.x / step).rounded() * step
    }
}

/// One hour of the ruler: a tick every five minutes and the hour set above.
private struct HourCell: View {
    var hour: Int
    var stepWidth: CGFloat
    var height: CGFloat

    var body: some View {
        Canvas { context, size in
            for index in 0..<12 {
                let x = CGFloat(index) * stepWidth
                let length: CGFloat = index == 0 ? 26 : (index == 6 ? 16 : 9)
                let rect = CGRect(x: x - 0.75, y: size.height - length - 12, width: 1.5, height: length)
                context.fill(Path(roundedRect: rect, cornerRadius: 0.75), with: .color(Palette.ink.opacity(index == 0 ? 0.6 : 0.3)))
            }
        }
        .frame(width: stepWidth * 12, height: height)
        .overlay(alignment: .topLeading) {
            Text(String(format: "%02d", hour))
                .font(.displayFixed(15, .semibold))
                .foregroundStyle(Palette.inkSoft)
                .fixedSize()
                .frame(width: 40)
                // Centred on the hour's own tick, which is this cell's left edge.
                .offset(x: -20, y: 18)
        }
    }
}

// MARK: Editor

private struct WarmUpEditor: View {
    @State var warmUp: WarmUp
    var isNew: Bool
    var onSave: (WarmUp) -> Void
    var onDelete: (WarmUp) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var minutes: Int

    init(warmUp: WarmUp, isNew: Bool, onSave: @escaping (WarmUp) -> Void, onDelete: @escaping (WarmUp) -> Void) {
        _warmUp = State(initialValue: warmUp)
        self.isNew = isNew
        self.onSave = onSave
        self.onDelete = onDelete
        _minutes = State(initialValue: warmUp.hour * 60 + warmUp.minute)
    }

    var body: some View {
        let ready = TimeOfDay(minutes: minutes)
        let start = TimeOfDay(minutes: minutes - WarmUp.leadMinutes)

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text(ready.label)
                    .font(.displayFixed(76, .bold))
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.numericText(value: Double(minutes)))
                    .animation(Motion.snappy, value: minutes)
                    .fixedSize()
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
                if !isNew {
                    Button(role: .destructive) {
                        onDelete(warmUp)
                        dismiss()
                    } label: {
                        IconView(.trash, size: 20)
                            .foregroundStyle(Palette.alert)
                            .frame(width: 44, height: 44, alignment: .trailing)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel("Delete this time")
                }
            }

            Text("Ready by then. The car starts at \(start.label).")
                .font(.subheadline)
                .foregroundStyle(Palette.inkSoft)
                .contentTransition(.numericText(value: Double(minutes)))
                .animation(Motion.snappy, value: minutes)
                .padding(.top, 2)

            TimeTape(minutes: $minutes)
                .padding(.top, 26)

            WeekPainter(days: $warmUp.days)
                .padding(.top, 26)

            Text(daysLine(start: start))
                .font(.subheadline)
                .foregroundStyle(Palette.inkSoft)
                .contentTransition(.opacity)
                .animation(Motion.snappy, value: warmUp.days)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 8)

            Spacer(minLength: 16)

            Button {
                warmUp.hour = ready.hour
                warmUp.minute = ready.minute
                warmUp.isOn = true
                onSave(warmUp)
                dismiss()
            } label: {
                Text(isNew ? "Add" : "Save")
            }
            .buttonStyle(.brand())
        }
        .padding(.horizontal, 24)
        .padding(.top, 30)
        .padding(.bottom, 12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Palette.canvas.ignoresSafeArea())
    }

    /// The chosen days in words. With none chosen, the time runs once.
    private func daysLine(start: TimeOfDay) -> String {
        guard warmUp.days.isEmpty else {
            let summary = Weekday.summary(warmUp.days)
            return summary.prefix(1).uppercased() + summary.dropFirst()
        }
        let now = Calendar.current.dateComponents([.hour, .minute], from: .now)
        let nowMinutes = (now.hour ?? 0) * 60 + (now.minute ?? 0)
        // A start that has already gone by today means tomorrow.
        let isToday = minutes - WarmUp.leadMinutes > nowMinutes
        return "No days chosen: once, \(isToday ? "today" : "tomorrow")"
    }
}

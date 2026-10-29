import AppIntents
import SwiftUI
import WidgetKit

@main
struct BetterOpelWidgetBundle: WidgetBundle {
    var body: some Widget {
        RangeWidget()
        VehicleWidget()
        LockScreenWidget()
        PreheatWidget()
        ChargingLiveActivityWidget()
        LockControl()
        ClimateControl()
        FlashControl()
    }
}

// MARK: Timeline

struct VehicleEntry: TimelineEntry {
    let date: Date
    let snapshot: VehicleSnapshot
}

struct VehicleTimeline: TimelineProvider {
    func placeholder(in context: Context) -> VehicleEntry {
        VehicleEntry(date: .now, snapshot: MockData.initialSnapshot())
    }

    func getSnapshot(in context: Context, completion: @escaping (VehicleEntry) -> Void) {
        completion(VehicleEntry(date: .now, snapshot: context.isPreview ? MockData.initialSnapshot() : SnapshotStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<VehicleEntry>) -> Void) {
        // The colourway may have changed since this process last looked.
        ThemeStore.reload()

        if ConnectionStore.isLive {
            // A real car: ask the server, and fall back to the last reading.
            let reply = TimelineReply(completion)
            Task {
                let snapshot = (try? await VehicleService.background.vehicleInfo(fromCache: true)) ?? SnapshotStore.load()
                let refresh = Date.now.addingTimeInterval(snapshot.isCharging ? 5 * 60 : 15 * 60)
                reply.send(Timeline(entries: [VehicleEntry(date: .now, snapshot: snapshot)], policy: .after(refresh)))
            }
            return
        }

        let now = Date.now
        let current = SnapshotStore.load(now: now)
        var entries = [VehicleEntry(date: now, snapshot: current)]

        // While a session runs, project the level forward so the widget keeps
        // moving without waking the app.
        if current.isCharging {
            var projected = current
            for step in 1...16 {
                let date = now.addingTimeInterval(Double(step) * 15)
                SnapshotStore.advance(&projected, to: date)
                entries.append(VehicleEntry(date: date, snapshot: projected))
                if !projected.isCharging { break }
            }
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(15 * 60))))
    }
}

/// WidgetKit's completion handler predates Swift concurrency. It is called
/// exactly once, from the task that fetched the reading.
private struct TimelineReply: @unchecked Sendable {
    private let completion: (Timeline<VehicleEntry>) -> Void

    init(_ completion: @escaping (Timeline<VehicleEntry>) -> Void) {
        self.completion = completion
    }

    func send(_ timeline: Timeline<VehicleEntry>) {
        completion(timeline)
    }
}

// MARK: Small

struct RangeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.example.betteropel.range", provider: VehicleTimeline()) { entry in
            RangeWidgetView(snapshot: entry.snapshot)
                .containerBackground(Palette.canvas, for: .widget)
        }
        .configurationDisplayName("Range")
        .description("Range and battery at a glance.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: Medium

struct VehicleWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.example.betteropel.vehicle", provider: VehicleTimeline()) { entry in
            VehicleWidgetView(snapshot: entry.snapshot)
                .containerBackground(Palette.canvas, for: .widget)
        }
        .configurationDisplayName("Grandland")
        .description("Range, battery, and the controls you reach for most.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: Lock Screen

struct LockScreenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.example.betteropel.lockscreen", provider: VehicleTimeline()) { entry in
            LockScreenWidgetView(snapshot: entry.snapshot)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Battery")
        .description("Battery and range on the Lock Screen.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: Preheat

struct PreheatEntry: TimelineEntry {
    let date: Date
    let status: PreheatStatus
    let minutesLeft: Int?
}

struct PreheatTimeline: TimelineProvider {
    func placeholder(in context: Context) -> PreheatEntry {
        PreheatEntry(date: .now, status: PreheatStatus(), minutesLeft: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (PreheatEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entries(from: .now).first ?? placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PreheatEntry>) -> Void) {
        ThemeStore.reload()
        // Every entry is known ahead of time; the app and the intent reload
        // this timeline whenever something actually changes.
        completion(Timeline(entries: entries(from: .now), policy: .never))
    }

    /// Now, then one entry a minute while a cycle counts down, then the moment
    /// the widget goes back to rest.
    private func entries(from now: Date) -> [PreheatEntry] {
        let status = PreheatStore.current(now: now)
        let snapshot = SnapshotStore.load(now: now)

        if snapshot.climate.isOn, let left = snapshot.climateMinutesRemaining, left > 0 {
            var list: [PreheatEntry] = []
            var minutes = Int(left.rounded(.up))
            var date = now
            while minutes > 0 {
                list.append(PreheatEntry(date: date, status: status, minutesLeft: minutes))
                // Step to the next whole minute left.
                date = now.addingTimeInterval((left - Double(minutes - 1)) * 60)
                minutes -= 1
            }
            list.append(PreheatEntry(date: date, status: PreheatStatus(), minutesLeft: nil))
            return list
        }

        var list = [PreheatEntry(date: now, status: status, minutesLeft: nil)]
        if status.phase != .idle {
            let end = status.at.addingTimeInterval(PreheatStore.lifetime(of: status.phase))
            list.append(PreheatEntry(date: end, status: PreheatStatus(), minutesLeft: nil))
        }
        return list
    }
}

struct PreheatWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: PreheatStore.widgetKind, provider: PreheatTimeline()) { entry in
            PreheatWidgetView(status: entry.status, minutesLeft: entry.minutesLeft)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Preheat")
        .description("Start the climate from the Lock Screen.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

// MARK: Control Center

struct LockControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.example.betteropel.control.lock", provider: Provider()) { isLocked in
            ControlWidgetToggle("Doors", isOn: isLocked, action: SetLockedIntent()) { on in
                Label(on ? "Locked" : "Unlocked", systemImage: on ? "lock.fill" : "lock.open.fill")
            }
            .tint(.yellow)
        }
        .displayName("Door Lock")
        .description("Lock or unlock your Opel.")
    }

    struct Provider: ControlValueProvider {
        var previewValue: Bool { true }
        func currentValue() async throws -> Bool { SnapshotStore.load().isLocked }
    }
}

struct ClimateControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.example.betteropel.control.climate", provider: Provider()) { isOn in
            ControlWidgetToggle("Climate", isOn: isOn, action: SetClimateIntent()) { on in
                Label(on ? "On" : "Off", systemImage: on ? "fan.fill" : "fan")
            }
            .tint(.yellow)
        }
        .displayName("Climate")
        .description("Precondition the cabin.")
    }

    struct Provider: ControlValueProvider {
        var previewValue: Bool { false }
        func currentValue() async throws -> Bool { SnapshotStore.load().climate.isOn }
    }
}

struct FlashControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.example.betteropel.control.flash") {
            ControlWidgetButton(action: FlashLightsIntent()) {
                Label("Flash Lights", systemImage: "headlight.high.beam.fill")
            }
        }
        .displayName("Flash Lights")
        .description("Find your Opel in a car park.")
    }
}

import AppIntents
import SwiftUI
import WidgetKit

// The views behind the widgets. They live in the shared code so the app can
// show the very same views in its widget guide.

struct RangeWidgetView: View {
    let snapshot: VehicleSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                BlitzMark(height: 13)
                    .foregroundStyle(Palette.ink)
                    .widgetAccentable()
                Spacer()
                IconView(statusIcon, size: 15)
                    .foregroundStyle(snapshot.isCharging ? Palette.accent : Palette.inkSoft)
                    .widgetAccentable(snapshot.isCharging)
            }

            Spacer(minLength: 0)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(snapshot.rangeKm)")
                    .font(.displayFixed(46, .bold))
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.numericText(value: Double(snapshot.rangeKm)))
                Text("km")
                    .font(.displayFixed(15, .semibold))
                    .foregroundStyle(Palette.inkSoft)
            }
            .minimumScaleFactor(0.7)
            .lineLimit(1)

            Text(snapshot.isCharging ? chargingLine : "\(snapshot.batteryPercent)% · \(snapshot.isLocked ? "locked" : "unlocked")")
                .font(.caption)
                .foregroundStyle(Palette.inkSoft)
                .lineLimit(1)
                .padding(.top, 1)

            WidgetBatteryLine(level: snapshot.batteryLevel, limit: snapshot.charging.thresholdPercent)
                .padding(.top, 10)
        }
        .accessibilityElement(children: .combine)
    }

    private var statusIcon: OpelIcon {
        if snapshot.isCharging { return .bolt }
        return snapshot.isLocked ? .lock : .unlock
    }

    private var chargingLine: String {
        guard let minutes = snapshot.minutesToLimit else { return "\(snapshot.batteryPercent)%" }
        return "\(snapshot.batteryPercent)% · \(Format.duration(minutes: minutes))"
    }
}

struct WidgetBatteryLine: View {
    var level: Double
    var limit: Int
    var height: CGFloat = 7

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.well)
                Capsule()
                    .fill(Palette.fill)
                    .frame(width: max(height, width * level / 100))
                    .widgetAccentable()
                Capsule()
                    .fill(Palette.ink)
                    .frame(width: 2.5, height: height + 6)
                    .offset(x: width * Double(limit) / 100 - 1.25)
            }
        }
        .frame(height: height)
    }
}

struct VehicleWidgetView: View {
    let snapshot: VehicleSnapshot

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                BlitzMark(height: 13)
                    .foregroundStyle(Palette.ink)
                    .widgetAccentable()

                Spacer(minLength: 0)

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(snapshot.rangeKm)")
                        .font(.displayFixed(44, .bold))
                        .foregroundStyle(Palette.ink)
                        .contentTransition(.numericText(value: Double(snapshot.rangeKm)))
                    Text("km")
                        .font(.displayFixed(15, .semibold))
                        .foregroundStyle(Palette.inkSoft)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)

                Text(snapshot.statusLine)
                    .font(.caption)
                    .foregroundStyle(Palette.inkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.top, 1)

                WidgetBatteryLine(level: snapshot.batteryLevel, limit: snapshot.charging.thresholdPercent)
                    .padding(.top, 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 8) {
                CarRender()
                    .frame(maxWidth: .infinity)

                HStack(spacing: 10) {
                    Button(intent: SetLockedIntent(value: !snapshot.isLocked)) {
                        WidgetOrb(icon: snapshot.isLocked ? .lock : .unlock, isActive: !snapshot.isLocked)
                    }
                    .accessibilityLabel(snapshot.isLocked ? "Unlock" : "Lock")
                    Button(intent: SetClimateIntent(value: !snapshot.climate.isOn)) {
                        WidgetOrb(icon: .climate, isActive: snapshot.climate.isOn)
                    }
                    .accessibilityLabel(snapshot.climate.isOn ? "Stop climate" : "Start climate")
                    Button(intent: SetChargingIntent(value: !snapshot.isCharging)) {
                        WidgetOrb(icon: .bolt, isActive: snapshot.isCharging)
                    }
                    .accessibilityLabel(snapshot.isCharging ? "Pause charging" : "Start charging")
                }
                .buttonStyle(.plain)
            }
            .frame(width: 150)
        }
    }
}

struct WidgetOrb: View {
    var icon: OpelIcon
    var isActive: Bool

    var body: some View {
        IconView(icon, size: 18)
            .foregroundStyle(isActive ? Palette.onFill : Palette.ink)
            .frame(width: 40, height: 40)
            .background(isActive ? Palette.fill : Palette.well, in: .circle)
    }
}

struct LockScreenWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: VehicleSnapshot

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: snapshot.batteryLevel, in: 0...100) {
                IconView(snapshot.isCharging ? .bolt : .car, size: 14)
            } currentValueLabel: {
                Text("\(snapshot.batteryPercent)")
                    .font(.displayFixed(20, .semibold))
            }
            .gaugeStyle(.accessoryCircular)
            .accessibilityLabel("Battery \(snapshot.batteryPercent) percent")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    BlitzMark(height: 10)
                    Text(snapshot.name)
                        .font(.headline)
                        .widgetAccentable()
                }
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(snapshot.rangeKm)")
                        .font(.displayFixed(22, .semibold))
                    Text("km · \(snapshot.batteryPercent)%")
                        .font(.subheadline)
                }
                Text(snapshot.isCharging ? "Charging to \(snapshot.charging.thresholdPercent)%" : (snapshot.isLocked ? "Locked" : "Unlocked"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            Text("\(snapshot.rangeKm) km · \(snapshot.batteryPercent)%")
        }
    }
}

// MARK: Preheat

/// A Lock Screen button that starts the climate, and shows how that is going.
struct PreheatWidgetView: View {
    @Environment(\.widgetFamily) private var widgetFamily
    let status: PreheatStatus
    /// Minutes left of a running cycle, whoever started it.
    let minutesLeft: Int?
    /// Set where the view is shown outside a widget, as in the app's guide.
    var shownAs: WidgetFamily?

    private var family: WidgetFamily { shownAs ?? widgetFamily }

    private enum Face {
        case rest, busy, sent, running(Int), failed
    }

    private var face: Face {
        if let minutesLeft, minutesLeft > 0 { return .running(minutesLeft) }
        switch status.phase {
        case .idle: return .rest
        case .sending, .waking: return .busy
        case .sent: return .sent
        case .running: return .running(Int(ClimateState.cycleMinutes))
        case .failed: return .failed
        }
    }

    var body: some View {
        Button(intent: PreheatIntent()) {
            switch family {
            case .accessoryCircular: circular
            default: rectangular
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(line)
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            switch face {
            case .rest:
                IconView(.climate, size: 26)
            case .busy, .sent:
                // A widget cannot spin; a part-drawn ring says "under way".
                ring(0.28)
                IconView(.climate, size: 22)
            case .running(let left):
                ring(1 - Double(left) / ClimateState.cycleMinutes)
                VStack(spacing: -1) {
                    Text("\(left)")
                        .font(.displayFixed(20, .semibold))
                    Text("min")
                        .font(.system(size: 9, weight: .semibold))
                }
            case .failed:
                IconView(.warning, size: 24)
            }
        }
        .widgetAccentable()
    }

    private func ring(_ amount: Double) -> some View {
        Circle()
            .trim(from: 0, to: max(0.04, min(1, amount)))
            .stroke(style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .padding(3.5)
    }

    private var rectangular: some View {
        HStack(spacing: 9) {
            IconView(isProblem ? .warning : .climate, size: 26)
                .widgetAccentable()
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.headline)
                    .widgetAccentable()
                Text(line)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var isProblem: Bool {
        if case .failed = face { return true }
        return false
    }

    private var title: String {
        switch face {
        case .rest: "Preheat"
        case .busy: status.phase == .waking ? "Waking the car" : "Sending"
        case .sent: "Start sent"
        case .running: "Climate on"
        case .failed: "Not started"
        }
    }

    private var line: String {
        switch face {
        case .rest: "Tap to start the climate"
        case .busy: status.phase == .waking ? "A minute or two" : "Asking your server"
        case .sent: "Waiting for the car"
        case .running(let left): "\(left) min left"
        case .failed: "Tap to try again"
        }
    }
}

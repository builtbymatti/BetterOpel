import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// The charging session on the Lock Screen and in the Dynamic Island.
struct ChargingLiveActivityWidget: Widget {
    // The activity always sits on its own dark ground, so its colours are fixed
    // rather than following the system appearance.
    private static let ink = ChargingActivityView.ink
    private static let inkSoft = ChargingActivityView.inkSoft

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ChargingActivityAttributes.self) { context in
            ChargingActivityView(state: context.state, vehicleName: context.attributes.vehicleName)
                .activityBackgroundTint(ChargingActivityView.ground)
                .activitySystemActionForegroundColor(Palette.fillOnDark)
        } dynamicIsland: { context in
            ThemeStore.reload()
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 7) {
                        BlitzMark(height: 13)
                            .foregroundStyle(Palette.fillOnDark)
                        Text(state.isFinished ? "Charged" : "Charging")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Self.ink)
                    }
                    .padding(.leading, 4)
                    .padding(.top, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text("\(Int(state.level))")
                            .font(.displayFixed(26, .semibold))
                            .contentTransition(.numericText(value: state.level))
                        Text("%")
                            .font(.displayFixed(13, .medium))
                            .foregroundStyle(Self.inkSoft)
                    }
                    .foregroundStyle(Self.ink)
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 9) {
                        ChargingSessionBar(state: state)
                        HStack {
                            Text(state.isFinished ? "\(state.rangeKm) km of range" : "\(Format.duration(minutes: state.minutesRemaining)) to \(state.limit)% · \(Format.kWh(state.powerKW)) kW")
                                .font(.footnote)
                                .foregroundStyle(Self.inkSoft)
                                .contentTransition(.numericText())
                            Spacer()
                            if !state.isFinished {
                                Button(intent: StopChargingIntent()) {
                                    Text("Pause")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(Palette.onFillOnDark)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Palette.fillOnDark, in: .capsule)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 2)
                }
            } compactLeading: {
                IconView(state.isFinished ? .check : .bolt, size: 16)
                    .foregroundStyle(Palette.fillOnDark)
            } compactTrailing: {
                Text("\(Int(state.level))%")
                    .font(.displayFixed(14, .semibold))
                    .foregroundStyle(Self.ink)
                    .contentTransition(.numericText(value: state.level))
            } minimal: {
                IconView(.bolt, size: 16)
                    .foregroundStyle(Palette.fillOnDark)
            }
            .keylineTint(Palette.fillOnDark)
        }
    }
}

import ActivityKit
import SwiftUI
import WidgetKit

/// The Lock Screen face of the charging Live Activity.
struct ChargingActivityView: View {
    // The activity always sits on its own dark ground, so its colours are fixed
    // rather than following the system appearance.
    static let ground = Color(red: 0.035, green: 0.039, blue: 0.024)
    static let ink = Color(red: 0.957, green: 0.965, blue: 0.91)
    static let inkSoft = Color(red: 0.663, green: 0.678, blue: 0.608)

    let state: ChargingActivityAttributes.ContentState
    let vehicleName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                BlitzMark(height: 13)
                    .foregroundStyle(Palette.fillOnDark)
                Text(vehicleName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Self.ink)
                Spacer()
                Text(state.isFinished ? "Charged" : "\(Format.kWh(state.powerKW)) kW")
                    .font(.subheadline)
                    .foregroundStyle(Self.inkSoft)
            }

            HStack(alignment: .lastTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(Int(state.level))")
                        .font(.displayFixed(44, .bold))
                        .contentTransition(.numericText(value: state.level))
                    Text("%")
                        .font(.displayFixed(18, .semibold))
                        .foregroundStyle(Self.inkSoft)
                }
                .foregroundStyle(Self.ink)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(state.isFinished ? "Ready" : "\(Format.duration(minutes: state.minutesRemaining)) left")
                        .font(.headline)
                        .foregroundStyle(Self.ink)
                        .contentTransition(.numericText())
                    Text("\(state.rangeKm) km · limit \(state.limit)%")
                        .font(.footnote)
                        .foregroundStyle(Self.inkSoft)
                }
            }

            ChargingSessionBar(state: state)
        }
        .padding(18)
    }
}

/// Runs on the system clock between updates, so the bar keeps filling while the
/// app is suspended.
struct ChargingSessionBar: View {
    let state: ChargingActivityAttributes.ContentState

    var body: some View {
        if state.isFinished || state.expectedEnd <= state.startedAt {
            ProgressView(value: 1)
                .progressViewStyle(.linear)
                .tint(Palette.fillOnDark)
        } else {
            ProgressView(timerInterval: state.startedAt...state.expectedEnd, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.linear)
            .tint(Palette.fillOnDark)
        }
    }
}

import ActivityKit
import Foundation

struct ChargingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var level: Double
        var limit: Int
        var powerKW: Double
        var rangeKm: Int
        var minutesRemaining: Int
        var isFinished: Bool
        /// Wall-clock window the progress bar runs over, so it keeps moving on
        /// the Lock Screen between updates.
        var startedAt: Date
        var expectedEnd: Date
        var startLevel: Double
    }

    var vehicleName: String
}

/// Keeps the charging Live Activity in step with the vehicle snapshot.
enum ChargingLiveActivity {
    static let enabledKey = "liveActivity.enabled"

    private static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    static func sync(with snapshot: VehicleSnapshot) async {
        let current = Activity<ChargingActivityAttributes>.activities.first

        guard isEnabled, ActivityAuthorizationInfo().areActivitiesEnabled else {
            await current?.end(nil, dismissalPolicy: .immediate)
            return
        }

        switch snapshot.charging.status {
        case .inProgress:
            let state = contentState(for: snapshot, finished: false)
            let content = ActivityContent(state: state, staleDate: state.expectedEnd.addingTimeInterval(120))
            if let current {
                await current.update(content)
            } else {
                _ = try? Activity.request(
                    attributes: ChargingActivityAttributes(vehicleName: snapshot.name),
                    content: content
                )
            }
        case .finished:
            guard let current else { return }
            let state = contentState(for: snapshot, finished: true)
            await current.end(
                ActivityContent(state: state, staleDate: nil),
                dismissalPolicy: .after(.now.addingTimeInterval(20 * 60))
            )
        case .stopped, .scheduled, .disconnected:
            await current?.end(nil, dismissalPolicy: .immediate)
        }
    }

    static func contentState(for snapshot: VehicleSnapshot, finished: Bool) -> ChargingActivityAttributes.ContentState {
        let minutes = snapshot.minutesToLimit ?? 0
        // The demo car charges faster than real time, so the wall-clock end is
        // the vehicle's estimate divided by the simulation scale.
        let secondsLeft = Double(minutes) * 60 / MockClock.chargeScale
        let startLevel = snapshot.charging.sessionStartLevel ?? snapshot.batteryLevel
        // Place the bar's start so that "now" sits at the session's real progress.
        let span = max(1, Double(snapshot.charging.thresholdPercent) - startLevel)
        let progress = min(0.98, max(0, (snapshot.batteryLevel - startLevel) / span))
        let now = Date.now
        return .init(
            level: snapshot.batteryLevel,
            limit: snapshot.charging.thresholdPercent,
            powerKW: snapshot.charging.powerKW,
            rangeKm: snapshot.rangeKm,
            minutesRemaining: minutes,
            isFinished: finished,
            startedAt: now.addingTimeInterval(-max(1, secondsLeft) * progress / (1 - progress)),
            expectedEnd: now.addingTimeInterval(max(1, secondsLeft)),
            startLevel: startLevel
        )
    }
}

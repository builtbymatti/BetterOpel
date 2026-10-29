import AppIntents
import SwiftUI
import WidgetKit

extension Notification.Name {
    /// Posted whenever an intent changed the car outside the app's own model.
    static let vehicleSnapshotChanged = Notification.Name("vehicleSnapshotChanged")
}

/// Shared tail for every intent that changes the car: refresh widgets, controls
/// and the Live Activity, and tell a running app to re-read the snapshot.
private func publish(_ snapshot: VehicleSnapshot) async {
    WidgetCenter.shared.reloadAllTimelines()
    ControlCenter.shared.reloadAllControls()
    await ChargingLiveActivity.sync(with: snapshot)
    NotificationCenter.default.post(name: .vehicleSnapshotChanged, object: nil)
}

/// The real car when a server is configured, the demo car otherwise.
private var api: any VehicleAPI { VehicleService.background }

// MARK: Doors

struct LockDoorsIntent: AppIntent {
    static let title: LocalizedStringResource = "Lock Doors"
    static let description = IntentDescription("Locks your Opel.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let snapshot = try await api.setLocked(true)
        await publish(snapshot)
        return .result(dialog: "\(snapshot.name) is locked.")
    }
}

struct UnlockDoorsIntent: AppIntent {
    static let title: LocalizedStringResource = "Unlock Doors"
    static let description = IntentDescription("Unlocks your Opel. Asks for Face ID when the phone is locked.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let snapshot = try await api.setLocked(false)
        await publish(snapshot)
        return .result(dialog: "\(snapshot.name) is unlocked.")
    }
}

// MARK: Climate

struct StartClimateIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Climate"
    static let description = IntentDescription("Starts preconditioning the cabin.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let snapshot = try await api.setPreconditioning(true)
        await publish(snapshot)
        return .result(dialog: "Preconditioning started. The cabin is ready in about ten minutes.")
    }
}

/// The Lock Screen's start. It runs in the app rather than in the widget, so
/// it has the app's time and its notifications to report each step with.
struct PreheatIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Preheat"
    static let description = IntentDescription("Starts the climate and tells you how it goes.")

    func perform() async throws -> some IntentResult {
        await Preheat.start()
        if let snapshot = try? await api.vehicleInfo(fromCache: false) {
            await publish(snapshot)
        }
        return .result()
    }
}

struct StopClimateIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Climate"
    static let description = IntentDescription("Stops preconditioning.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let snapshot = try await api.setPreconditioning(false)
        await publish(snapshot)
        return .result(dialog: "Preconditioning stopped.")
    }
}

// MARK: Charging

struct StartChargingIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Charging"
    static let description = IntentDescription("Starts charging right away, ignoring the schedule.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            let snapshot = try await api.setCharging(true)
            await publish(snapshot)
            return .result(dialog: "Charging to \(snapshot.charging.thresholdPercent) percent.")
        } catch VehicleError.notPlugged {
            return .result(dialog: "The cable isn't plugged in.")
        }
    }
}

struct StopChargingIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Charging"
    static let description = IntentDescription("Pauses the current charging session.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            let snapshot = try await api.setCharging(false)
            await publish(snapshot)
            return .result(dialog: "Charging paused at \(snapshot.batteryPercent) percent.")
        } catch VehicleError.notPlugged {
            return .result(dialog: "The cable isn't plugged in.")
        }
    }
}

struct SetChargeLimitIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Charge Limit"
    static let description = IntentDescription("Sets how full the battery charges.")

    @Parameter(title: "Limit", description: "Percent, from 50 to 100.", inclusiveRange: (50, 100))
    var percent: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Charge to \(\.$percent) percent")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let snapshot = try await api.setChargeThreshold(percent)
        await publish(snapshot)
        return .result(dialog: "Charge limit set to \(percent) percent, about \(snapshot.rangeKm(at: Double(percent))) kilometres.")
    }
}

// MARK: Find

struct FlashLightsIntent: AppIntent {
    static let title: LocalizedStringResource = "Flash Lights"
    static let description = IntentDescription("Flashes the lights for about ten seconds.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await api.flashLights(seconds: 10)
        return .result(dialog: "Lights are flashing.")
    }
}

struct HonkHornIntent: AppIntent {
    static let title: LocalizedStringResource = "Honk Horn"
    static let description = IntentDescription("Sounds the horn twice.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await api.honk(count: 2)
        return .result(dialog: "Honked twice.")
    }
}

// MARK: Reading the car

struct BatteryLevelIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Battery Level"
    static let description = IntentDescription("Returns the battery level in percent, for use in automations.")

    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let snapshot = try await api.vehicleInfo(fromCache: true)
        return .result(value: snapshot.batteryPercent, dialog: "\(snapshot.batteryPercent) percent, about \(snapshot.rangeKm) kilometres.")
    }
}

struct RangeIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Range"
    static let description = IntentDescription("Returns the remaining range in kilometres.")

    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let snapshot = try await api.vehicleInfo(fromCache: true)
        return .result(value: snapshot.rangeKm, dialog: "About \(snapshot.rangeKm) kilometres.")
    }
}

struct VehicleStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Car Status"
    static let description = IntentDescription("Shows battery, range and whether the car is locked.")

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let snapshot = try await api.wakeUp()
        await publish(snapshot)
        return .result(
            dialog: "\(snapshot.statusLine). \(snapshot.batteryPercent) percent, \(snapshot.rangeKm) kilometres.",
            view: StatusSnippet(snapshot: snapshot)
        )
    }
}

struct StatusSnippet: View {
    let snapshot: VehicleSnapshot

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(snapshot.rangeKm)")
                        .font(.displayFixed(44, .semibold))
                    Text("km")
                        .font(.displayFixed(18, .medium))
                        .foregroundStyle(.secondary)
                }
                Text("\(snapshot.batteryPercent)% · \(snapshot.isLocked ? "Locked" : "Unlocked")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            CarRender()
                .frame(width: 150)
        }
        .padding(18)
    }
}

// MARK: Toggles for widgets and Control Center

struct SetLockedIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Set Door Lock"
    static let isDiscoverable = false

    @Parameter(title: "Locked")
    var value: Bool

    init() {}
    init(value: Bool) { self.value = value }

    func perform() async throws -> some IntentResult {
        let snapshot = try await api.setLocked(value)
        await publish(snapshot)
        return .result()
    }
}

struct SetClimateIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Set Climate"
    static let isDiscoverable = false

    @Parameter(title: "On")
    var value: Bool

    init() {}
    init(value: Bool) { self.value = value }

    func perform() async throws -> some IntentResult {
        let snapshot = try await api.setPreconditioning(value)
        await publish(snapshot)
        return .result()
    }
}

struct SetChargingIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Set Charging"
    static let isDiscoverable = false

    @Parameter(title: "Charging")
    var value: Bool

    init() {}
    init(value: Bool) { self.value = value }

    func perform() async throws -> some IntentResult {
        if let snapshot = try? await api.setCharging(value) {
            await publish(snapshot)
        }
        return .result()
    }
}

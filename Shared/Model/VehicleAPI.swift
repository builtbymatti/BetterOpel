import Foundation

/// Everything the interface needs from the car. Each requirement maps onto one
/// psa_car_controller endpoint so a network client can drop in later.
protocol VehicleAPI: Sendable {
    /// `GET /get_vehicleinfo/{vin}` (`?from_cache=1` when `fromCache`).
    func vehicleInfo(fromCache: Bool) async throws -> VehicleSnapshot
    /// `GET /wakeup/{vin}` asks the car to report fresh state.
    func wakeUp() async throws -> VehicleSnapshot
    /// `GET /charge_now/{vin}/{1|0}`
    func setCharging(_ on: Bool) async throws -> VehicleSnapshot
    /// `GET /charge_control?vin=&percentage=`
    func setChargeThreshold(_ percent: Int) async throws -> VehicleSnapshot
    /// `GET /charge_hour?vin=&hour=&minute=` and `GET /charge_control?vin=&hour=&minute=`
    func setChargeSchedule(enabled: Bool, start: TimeOfDay, stop: TimeOfDay?) async throws -> VehicleSnapshot
    /// `GET /preconditioning/{vin}/{1|0}`
    func setPreconditioning(_ on: Bool) async throws -> VehicleSnapshot
    /// Preconditioning programmes stored on the car.
    func setClimatePrograms(_ programs: [ClimateProgram]) async throws -> VehicleSnapshot
    /// `GET /lock_door/{vin}/{1|0}`
    func setLocked(_ locked: Bool) async throws -> VehicleSnapshot
    /// `GET /horn/{vin}/{count}`
    func honk(count: Int) async throws
    /// `GET /lights/{vin}/{duration}`
    func flashLights(seconds: Int) async throws
    /// `GET /vehicles/trips`
    func trips() async throws -> [Trip]
    /// `GET /vehicles/chargings`
    func chargingSessions() async throws -> [ChargingSession]
}

enum VehicleError: LocalizedError, Equatable {
    case notPlugged
    case unreachable
    /// The server answered, but it has not been signed in to MyOpel yet.
    case serverNotReady
    case server(String)
    case unsupported

    var errorDescription: String? {
        switch self {
        case .notPlugged: "Plug in the cable first."
        case .unreachable: "Can't reach the server."
        case .serverNotReady: "The server isn't signed in to MyOpel yet."
        case .server(let message): message
        case .unsupported: "The car doesn't offer this remotely."
        }
    }
}

/// How fast the demo car lives. A real car runs on the wall clock.
enum MockClock {
    /// Charging runs faster than real time so a demo session visibly progresses.
    static var chargeScale: Double { ConnectionStore.isLive ? 1 : 40 }
    /// One ten-minute conditioning cycle plays out in a minute.
    static var climateScale: Double { ConnectionStore.isLive ? 1 : 10 }
}

/// Persists the single vehicle snapshot in the App Group so the app, the widgets
/// and App Intents all read and write the same car.
enum SnapshotStore {
    static let appGroup = "group.com.example.betteropel"
    // The demo car and the real car are kept apart, so switching between them
    // never shows one car's state as the other's.
    private static let demoKey = "vehicle.snapshot.v5"
    private static let liveKey = "vehicle.snapshot.live.v1"
    private static var key: String { ConnectionStore.isLive ? liveKey : demoKey }

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    /// The last known car. In demo mode this also moves the simulation forward;
    /// for a real car it is simply what the server last told us.
    static func load(now: Date = .now) -> VehicleSnapshot {
        let stored = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(VehicleSnapshot.self, from: $0) }
        if ConnectionStore.isLive {
            return stored ?? .awaitingFirstContact(now: now)
        }
        guard var snapshot = stored else {
            let fresh = MockData.initialSnapshot(now: now)
            save(fresh)
            return fresh
        }
        if advance(&snapshot, to: now) {
            save(snapshot)
        }
        return snapshot
    }

    /// Whether the real car has reported at least once.
    static var hasLiveSnapshot: Bool { defaults.data(forKey: liveKey) != nil }

    static func save(_ snapshot: VehicleSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }

    static func reset() {
        defaults.removeObject(forKey: key)
    }

    /// Moves the simulated car forward to `now`. Returns whether anything changed.
    @discardableResult
    static func advance(_ snapshot: inout VehicleSnapshot, to now: Date) -> Bool {
        let elapsed = now.timeIntervalSince(snapshot.simulatedAt)
        guard elapsed > 0.2 else { return false }
        var changed = false

        if snapshot.charging.status == .inProgress {
            let hours = elapsed / 3600 * MockClock.chargeScale
            let gained = snapshot.charging.powerKW * hours / snapshot.batteryCapacityKWh * 100
            let limit = Double(snapshot.charging.thresholdPercent)
            snapshot.batteryLevel = min(limit, snapshot.batteryLevel + gained)
            if snapshot.batteryLevel >= limit - 0.001 {
                snapshot.charging.status = .finished
                snapshot.charging.powerKW = 0
            }
            changed = true
        }

        if snapshot.climate.isOn, let start = snapshot.climate.startedAt {
            let minutes = now.timeIntervalSince(start) / 60 * MockClock.climateScale
            if minutes >= ClimateState.cycleMinutes {
                snapshot.climate.isOn = false
                snapshot.climate.startedAt = nil
            }
            changed = true
        }

        snapshot.simulatedAt = now
        return changed
    }
}

/// Stand-in for the real car. It behaves like the PSA cloud: commands take a
/// moment, then the snapshot reflects the new state.
struct MockVehicleAPI: VehicleAPI {
    var latency: Duration = .milliseconds(1100)

    private func commit(_ change: (inout VehicleSnapshot) throws -> Void) async throws -> VehicleSnapshot {
        try await Task.sleep(for: latency)
        var snapshot = SnapshotStore.load()
        try change(&snapshot)
        snapshot.updatedAt = .now
        SnapshotStore.save(snapshot)
        return snapshot
    }

    func vehicleInfo(fromCache: Bool) async throws -> VehicleSnapshot {
        if !fromCache { try await Task.sleep(for: .milliseconds(500)) }
        return SnapshotStore.load()
    }

    func wakeUp() async throws -> VehicleSnapshot {
        try await commit { _ in }
    }

    func setCharging(_ on: Bool) async throws -> VehicleSnapshot {
        try await commit { snapshot in
            guard snapshot.charging.status.isPlugged else { throw VehicleError.notPlugged }
            if on {
                guard snapshot.batteryLevel < Double(snapshot.charging.thresholdPercent) else {
                    snapshot.charging.status = .finished
                    return
                }
                snapshot.charging.status = .inProgress
                snapshot.charging.powerKW = snapshot.onboardChargerKW
                snapshot.charging.sessionStartedAt = .now
                snapshot.charging.sessionStartLevel = snapshot.batteryLevel
            } else {
                snapshot.charging.status = .stopped
                snapshot.charging.powerKW = 0
            }
        }
    }

    func setChargeThreshold(_ percent: Int) async throws -> VehicleSnapshot {
        try await commit { snapshot in
            snapshot.charging.thresholdPercent = percent
            if snapshot.charging.status == .finished, snapshot.batteryLevel < Double(percent) - 0.5 {
                snapshot.charging.status = .inProgress
                snapshot.charging.powerKW = snapshot.onboardChargerKW
            } else if snapshot.charging.status == .inProgress, snapshot.batteryLevel >= Double(percent) {
                snapshot.charging.status = .finished
                snapshot.charging.powerKW = 0
            }
        }
    }

    func setChargeSchedule(enabled: Bool, start: TimeOfDay, stop: TimeOfDay?) async throws -> VehicleSnapshot {
        try await commit { snapshot in
            snapshot.charging.isScheduleEnabled = enabled
            snapshot.charging.startTime = start
            snapshot.charging.stopTime = stop
        }
    }

    func setPreconditioning(_ on: Bool) async throws -> VehicleSnapshot {
        try await commit { snapshot in
            snapshot.climate.isOn = on
            snapshot.climate.startedAt = on ? .now : nil
        }
    }

    func setClimatePrograms(_ programs: [ClimateProgram]) async throws -> VehicleSnapshot {
        try await commit { snapshot in
            snapshot.climate.programs = programs
        }
    }

    func setLocked(_ locked: Bool) async throws -> VehicleSnapshot {
        try await commit { snapshot in
            snapshot.isLocked = locked
        }
    }

    func honk(count: Int) async throws {
        try await Task.sleep(for: latency)
    }

    func flashLights(seconds: Int) async throws {
        try await Task.sleep(for: latency)
    }

    func trips() async throws -> [Trip] {
        MockData.trips()
    }

    func chargingSessions() async throws -> [ChargingSession] {
        MockData.chargingSessions()
    }
}

extension VehicleSnapshot {
    /// Shown for a real car before the server has answered for the first time.
    static func awaitingFirstContact(now: Date = .now) -> VehicleSnapshot {
        VehicleSnapshot(
            name: "Grandland",
            model: "Grandland",
            vin: ConnectionStore.vin,
            powertrain: .electric,
            updatedAt: now,
            batteryLevel: 0,
            batteryCapacityKWh: 73,
            fullRangeKm: 0,
            fuelLevel: 0,
            fuelRangeKm: 0,
            healthPercent: nil,
            charging: ChargingState(
                status: .disconnected,
                powerKW: 0,
                thresholdPercent: 100,
                startTime: TimeOfDay(hour: 22, minute: 0),
                stopTime: nil,
                isScheduleEnabled: false,
                sessionStartedAt: nil,
                sessionStartLevel: nil
            ),
            climate: ClimateState(isOn: false, startedAt: nil, programs: []),
            isLocked: true,
            odometerKm: 0,
            outsideTempC: nil,
            location: MockData.home,
            heading: nil,
            address: "",
            locality: "",
            parkedAt: now,
            simulatedAt: now
        )
    }
}

extension MockVehicleAPI {
    /// Demo-only: plug or unplug the cable, which no remote API can do.
    func setPlugged(_ plugged: Bool) async -> VehicleSnapshot {
        var snapshot = SnapshotStore.load()
        if plugged {
            snapshot.charging.status = .stopped
        } else {
            snapshot.charging.status = .disconnected
            snapshot.charging.powerKW = 0
        }
        snapshot.updatedAt = .now
        SnapshotStore.save(snapshot)
        return snapshot
    }

    func setPowertrain(_ powertrain: Powertrain) -> VehicleSnapshot {
        var snapshot = SnapshotStore.load()
        snapshot.powertrain = powertrain
        snapshot.model = powertrain == .electric ? "Grandland Electric" : "Grandland Plug-in Hybrid"
        snapshot.batteryCapacityKWh = powertrain == .electric ? 73 : 17.9
        snapshot.fullRangeKm = powertrain == .electric ? 482 : 82
        if snapshot.isCharging { snapshot.charging.powerKW = snapshot.onboardChargerKW }
        SnapshotStore.save(snapshot)
        return snapshot
    }
}

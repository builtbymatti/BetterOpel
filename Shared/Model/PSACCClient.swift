import CoreLocation
import Foundation

/// Talks to a psa_car_controller server. The JSON shapes here were taken from
/// the server's own output (version 3.7.9), not from the PSA documentation: the
/// server re-serialises the car's status with snake_case keys and Python-style
/// dates.
struct PSACCClient: VehicleAPI {
    var baseURL: URL
    var vin: String

    // MARK: Transport

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 25
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    private func get(_ path: String, _ query: [String: String] = [:]) async throws -> Data {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            components?.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components?.url else { throw VehicleError.unreachable }

        let data: Data, response: URLResponse
        do {
            (data, response) = try await Self.session.data(from: url)
        } catch {
            throw VehicleError.unreachable
        }
        guard let http = response as? HTTPURLResponse else { throw VehicleError.unreachable }
        switch http.statusCode {
        case 200: break
        // Before the MyOpel sign-in is done, every data endpoint fails this way.
        case 500: throw VehicleError.serverNotReady
        default: throw VehicleError.server("The server answered with status \(http.statusCode).")
        }
        if let failure = try? JSONDecoder().decode(ServerFailure.self, from: data) {
            throw VehicleError.server(failure.error)
        }
        return data
    }

    /// Remote commands answer `true` once they are on their way to the car.
    private func command(_ path: String, _ query: [String: String] = [:]) async throws {
        let data = try await get(path, query)
        if String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) == "false" {
            throw VehicleError.server("The car didn't accept that.")
        }
    }

    private static var snakeCase: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    // MARK: Discovery

    struct DiscoveredCar: Sendable, Equatable {
        var vin: String
        var car: ConnectionStore.Car
    }

    /// The cars on the MyOpel account the server is signed in to.
    static func discover(at baseURL: URL) async throws -> [DiscoveredCar] {
        let data = try await PSACCClient(baseURL: baseURL, vin: "").get("get_vehicles")
        let cars = (try? snakeCase.decode([Wire.Vehicle].self, from: data)) ?? []
        return cars.map {
            DiscoveredCar(
                vin: $0.vin,
                car: ConnectionStore.Car(label: $0.label ?? "Opel", batteryKWh: $0.batteryPower ?? 0, fuelLitres: $0.fuelCapacity ?? 0)
            )
        }
    }

    // MARK: Reading the car

    func vehicleInfo(fromCache: Bool) async throws -> VehicleSnapshot {
        async let statusData = get("get_vehicleinfo/\(vin)", ["from_cache": fromCache ? "1" : "0"])
        async let control = chargeControl()
        async let health = stateOfHealth()

        let status = try Self.snakeCase.decode(Wire.Status.self, from: try await statusData)
        if ConnectionStore.car == nil, let found = try? await Self.discover(at: baseURL).first(where: { $0.vin == vin }) {
            ConnectionStore.car = found.car
        }

        let previous = SnapshotStore.hasLiveSnapshot ? SnapshotStore.load() : nil
        let snapshot = Self.snapshot(
            from: status,
            control: await control,
            health: await health,
            car: ConnectionStore.car,
            vin: vin,
            previous: previous
        )
        SnapshotStore.save(snapshot)
        return snapshot
    }

    private func chargeControl() async -> Wire.ChargeControl? {
        guard let data = try? await get("charge_control", ["vin": vin]) else { return nil }
        return try? JSONDecoder().decode(Wire.ChargeControl.self, from: data)
    }

    private func stateOfHealth() async -> Double? {
        guard let data = try? await get("battery/soh/\(vin)") else { return nil }
        return (try? JSONDecoder().decode(Wire.Health.self, from: data))?.soh
    }

    func wakeUp() async throws -> VehicleSnapshot {
        do {
            try await command("wakeup/\(vin)")
            // Give the car a moment to report before asking the cloud.
            try await Task.sleep(for: .seconds(4))
        } catch VehicleError.server {
            // The server limits wake-ups; a plain refresh is still worth having.
        }
        return try await vehicleInfo(fromCache: false)
    }

    // MARK: Commands

    /// Commands travel to the car over the mobile network and its answer takes a
    /// while to come back. Until it does, the app shows what was asked for.
    private func settle(_ expectation: Expectations.Kind, _ value: Bool) async throws -> VehicleSnapshot {
        Expectations.set(expectation, to: value)
        try await Task.sleep(for: .seconds(2))
        return try await vehicleInfo(fromCache: false)
    }

    func setCharging(_ on: Bool) async throws -> VehicleSnapshot {
        if SnapshotStore.hasLiveSnapshot, !SnapshotStore.load().charging.status.isPlugged {
            throw VehicleError.notPlugged
        }
        try await command("charge_now/\(vin)/\(on ? 1 : 0)")
        return try await settle(.charging, on)
    }

    func setChargeThreshold(_ percent: Int) async throws -> VehicleSnapshot {
        _ = try await get("charge_control", ["vin": vin, "percentage": String(percent)])
        return try await vehicleInfo(fromCache: true)
    }

    func setChargeSchedule(enabled: Bool, start: TimeOfDay, stop: TimeOfDay?) async throws -> VehicleSnapshot {
        if enabled {
            try await command("charge_hour", ["vin": vin, "hour": String(start.hour), "minute": String(start.minute)])
            // The server reads a stop time of 00:00 as "no stop time".
            var end = stop ?? TimeOfDay(hour: 6, minute: 0)
            if end.minutes == 0 { end = TimeOfDay(hour: 0, minute: 1) }
            _ = try await get("charge_control", ["vin": vin, "hour": String(end.hour), "minute": String(end.minute)])
        } else {
            _ = try await get("charge_control", ["vin": vin, "hour": "0", "minute": "0"])
        }
        return try await vehicleInfo(fromCache: true)
    }

    func setPreconditioning(_ on: Bool) async throws -> VehicleSnapshot {
        try await command("preconditioning/\(vin)/\(on ? 1 : 0)")
        return try await settle(.climate, on)
    }

    func setClimatePrograms(_ programs: [ClimateProgram]) async throws -> VehicleSnapshot {
        throw VehicleError.unsupported
    }

    func setLocked(_ locked: Bool) async throws -> VehicleSnapshot {
        try await command("lock_door/\(vin)/\(locked ? 1 : 0)")
        return try await settle(.locked, locked)
    }

    func honk(count: Int) async throws {
        try await command("horn/\(vin)/\(count)")
    }

    func flashLights(seconds: Int) async throws {
        try await command("lights/\(vin)/\(seconds)")
    }

    // MARK: History

    func trips() async throws -> [Trip] {
        let data = try await get("vehicles/trips")
        // With no recorded drives yet the server sends an empty object or list.
        let rows = (try? Self.snakeCase.decode([Wire.Lossy<Wire.Trip>].self, from: data))?.compactMap(\.value) ?? []
        return rows.compactMap { row -> Trip? in
            guard let start = row.startAt.flatMap(PSAFormat.date), let distance = row.distance, distance > 0 else { return nil }
            let minutes = row.duration ?? 0
            let lat = row.positions?.lat ?? [], lon = row.positions?.long ?? []
            let route = zip(lat, lon).map { Coordinate(latitude: $0, longitude: $1) }
            let energy = row.consumptionKm.map { $0 * distance / 100 } ?? row.consumption ?? 0
            return Trip(
                id: row.id ?? Int(start.timeIntervalSince1970),
                start: start,
                end: start.addingTimeInterval(minutes * 60),
                from: "",
                to: "",
                distanceKm: distance,
                energyKWh: energy,
                startLevel: nil,
                endLevel: nil,
                outsideTempC: row.consumptionByTemp?.value,
                route: route,
                elevation: [],
                altitudeChange: row.altitudeDiff
            )
        }
        .sorted { $0.start > $1.start }
    }

    func chargingSessions() async throws -> [ChargingSession] {
        let data = try await get("vehicles/chargings")
        let rows = (try? Self.snakeCase.decode([Wire.Lossy<Wire.Charging>].self, from: data))?.compactMap(\.value) ?? []
        return rows.enumerated().compactMap { index, row -> ChargingSession? in
            guard let start = row.startAt.flatMap(PSAFormat.date),
                  let end = row.stopAt.flatMap(PSAFormat.date),
                  let from = row.startLevel, let to = row.endLevel
            else { return nil }
            let isFast = (row.chargingMode ?? "").lowercased() == "quick"
            return ChargingSession(
                id: index,
                start: start,
                end: end,
                place: isFast ? "Fast charge" : "AC charge",
                connector: isFast ? .dc : .ac,
                startLevel: Int(from),
                endLevel: Int(to),
                energyKWh: row.kw ?? 0,
                cost: row.price,
                gramsCO2PerKWh: row.co2.map { Int($0) },
                curve: []
            )
        }
        .sorted { $0.start > $1.start }
    }

    // MARK: Mapping

    static func snapshot(
        from status: Wire.Status,
        control: Wire.ChargeControl?,
        health: Double?,
        car: ConnectionStore.Car?,
        vin: String,
        previous: VehicleSnapshot?,
        now: Date = .now
    ) -> VehicleSnapshot {
        let electric = status.energy?.first { $0.type == "Electric" }
        let fuel = status.energy?.first { $0.type == "Fuel" }
        let charging = electric?.charging

        let level = electric?.level ?? previous?.batteryLevel ?? 0
        let capacity = (car?.batteryKWh).flatMap { $0 > 0 ? $0 : nil } ?? previous?.batteryCapacityKWh ?? 73
        // The car reports range for the present level; scale it to a full pack.
        var fullRange = previous?.fullRangeKm ?? 0
        if let autonomy = electric?.autonomy, level > 1 { fullRange = autonomy / level * 100 }

        let threshold = control?.percentageThreshold ?? previous?.charging.thresholdPercent ?? 100
        let plugged = charging?.plugged ?? false
        var chargeStatus: ChargingStatus = switch (plugged, charging?.status ?? "") {
        case (false, _): .disconnected
        case (_, "InProgress"): .inProgress
        case (_, "Finished"): .finished
        default: .stopped
        }

        // Range gained per hour is what the car reports; turn it into kilowatts.
        var power = 0.0
        if chargeStatus == .inProgress, let rate = charging?.chargingRate, fullRange > 0 {
            power = rate / fullRange * capacity
        }

        let doors = status.doorsState?.value?.lockedState ?? []
        var isLocked = previous?.isLocked ?? true
        if !doors.isEmpty {
            isLocked = doors.contains { $0.lowercased().contains("locked") && !$0.lowercased().contains("unlocked") }
        }

        var climateOn = status.preconditionning?.value?.airConditioning?.status == "Enabled"

        // What was just asked of the car stands until the car confirms or the
        // wait runs out.
        if let expected = Expectations.resolve(.locked, reported: isLocked, now: now) { isLocked = expected }
        let climateWasAwaited = Expectations.isWaiting(.climate, now: now)
        let climateReported = climateOn
        if let expected = Expectations.resolve(.climate, reported: climateOn, now: now) { climateOn = expected }
        // The ten-minute cycle starts when the car confirms, not when it was asked.
        let climateConfirmedNow = climateWasAwaited && climateReported && !Expectations.isWaiting(.climate, now: now)
        if let expected = Expectations.resolve(.charging, reported: chargeStatus == .inProgress, now: now), plugged {
            if expected, level < Double(threshold) {
                chargeStatus = .inProgress
                if power == 0 { power = previous?.charging.powerKW ?? 0 }
            } else if !expected {
                chargeStatus = .stopped
                power = 0
            }
        }

        // Session totals are not in the car's status, so follow them here.
        var sessionStart = previous?.charging.sessionStartedAt
        var sessionLevel = previous?.charging.sessionStartLevel
        if chargeStatus == .inProgress, previous?.charging.status != .inProgress || sessionStart == nil {
            sessionStart = now
            sessionLevel = level
        } else if chargeStatus == .disconnected {
            sessionStart = nil
            sessionLevel = nil
        }

        let climateStart: Date? = if !climateOn {
            nil
        } else if climateConfirmedNow {
            now
        } else {
            (previous?.climate.isOn == true ? previous?.climate.startedAt : nil) ?? now
        }

        var location = previous?.location ?? MockData.home
        var address = previous?.address ?? ""
        var locality = previous?.locality ?? ""
        if let position = status.lastPosition?.value, let coordinates = position.geometry?.coordinates, coordinates.count >= 2 {
            let reported = Coordinate(latitude: coordinates[1], longitude: coordinates[0])
            let moved = CLLocation(latitude: reported.latitude, longitude: reported.longitude)
                .distance(from: CLLocation(latitude: location.latitude, longitude: location.longitude))
            if previous == nil || moved > 40 {
                // A new spot: the app names it once it has looked the address up.
                address = ""
                locality = ""
            }
            location = reported
        }
        let positionTime = status.lastPosition?.value?.properties?.updatedAt.flatMap(PSAFormat.date)
            ?? status.lastPosition?.value?.properties?.createdAt.flatMap(PSAFormat.date)

        let label = car?.label ?? previous?.model ?? "Opel"
        let isHybrid = (car?.fuelLitres ?? 0) > 0 && capacity > 0

        return VehicleSnapshot(
            name: label.split(separator: " ").first.map(String.init) ?? label,
            model: label,
            vin: vin,
            powertrain: isHybrid ? .plugInHybrid : .electric,
            updatedAt: electric?.updatedAt.flatMap(PSAFormat.date) ?? now,
            batteryLevel: level,
            batteryCapacityKWh: capacity,
            fullRangeKm: fullRange,
            fuelLevel: fuel?.level ?? 0,
            fuelRangeKm: fuel?.autonomy ?? 0,
            healthPercent: electric?.battery?.value?.health?.capacity ?? electric?.battery?.value?.health?.resistance ?? health ?? previous?.healthPercent,
            charging: ChargingState(
                status: chargeStatus,
                powerKW: power,
                thresholdPercent: threshold,
                startTime: charging?.nextDelayedTime.flatMap(PSAFormat.timeOfDay) ?? previous?.charging.startTime ?? TimeOfDay(hour: 22, minute: 0),
                stopTime: control.map { $0.stopHour } ?? previous?.charging.stopTime,
                isScheduleEnabled: control.map { $0.stopHour != nil } ?? previous?.charging.isScheduleEnabled ?? false,
                sessionStartedAt: sessionStart,
                sessionStartLevel: sessionLevel
            ),
            climate: ClimateState(isOn: climateOn, startedAt: climateStart, programs: []),
            isLocked: isLocked,
            odometerKm: status.timedOdometer?.value?.mileage ?? previous?.odometerKm ?? 0,
            outsideTempC: status.environment?.value?.air?.temp ?? previous?.outsideTempC,
            location: location,
            heading: status.lastPosition?.value?.properties?.heading ?? previous?.heading,
            address: address,
            locality: locality,
            parkedAt: positionTime ?? previous?.parkedAt ?? now,
            simulatedAt: now
        )
    }
}

// MARK: Pending commands

/// What the app has asked of the car and not yet seen confirmed.
enum Expectations {
    enum Kind: String { case locked, climate, charging }

    private struct Entry: Codable {
        var value: Bool
        var until: Date
    }

    // A sleeping car has to be woken over the mobile network first, which can
    // take a minute or two before it answers.
    private static let patience: TimeInterval = 150
    private static let unconfirmedKey = "live.expectation.unconfirmed"
    private static func key(_ kind: Kind) -> String { "live.expectation.\(kind.rawValue)" }

    /// A command whose wait ran out without the car reporting the new state.
    /// Read once, then cleared.
    static func takeUnconfirmed() -> Kind? {
        guard let raw = SnapshotStore.defaults.string(forKey: unconfirmedKey) else { return nil }
        SnapshotStore.defaults.removeObject(forKey: unconfirmedKey)
        return Kind(rawValue: raw)
    }

    /// Whether a command of this kind is still waiting for the car to confirm.
    static func isWaiting(_ kind: Kind, now: Date = .now) -> Bool {
        guard let data = SnapshotStore.defaults.data(forKey: key(kind)),
              let entry = try? JSONDecoder().decode(Entry.self, from: data)
        else { return false }
        return entry.until >= now
    }

    static func set(_ kind: Kind, to value: Bool, now: Date = .now) {
        let entry = Entry(value: value, until: now.addingTimeInterval(patience))
        SnapshotStore.defaults.set(try? JSONEncoder().encode(entry), forKey: key(kind))
    }

    /// The value to show instead of the reported one, if a command is still
    /// waiting on the car.
    static func resolve(_ kind: Kind, reported: Bool, now: Date = .now) -> Bool? {
        guard let data = SnapshotStore.defaults.data(forKey: key(kind)),
              let entry = try? JSONDecoder().decode(Entry.self, from: data)
        else { return nil }
        if entry.value == reported {
            SnapshotStore.defaults.removeObject(forKey: key(kind))
            return nil
        }
        if entry.until < now {
            SnapshotStore.defaults.removeObject(forKey: key(kind))
            SnapshotStore.defaults.set(kind.rawValue, forKey: unconfirmedKey)
            return nil
        }
        return entry.value
    }
}

// MARK: Formats

enum PSAFormat {
    /// The server writes dates two ways: Python's `str(datetime)` inside the
    /// car's status, and HTTP dates in the trip and charging lists.
    static func date(_ text: String) -> Date? {
        var iso = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "T")
        // Drop fractional seconds, which ISO8601DateFormatter rejects by default.
        if let dot = iso.firstIndex(of: "."), let zone = iso[dot...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) {
            iso.removeSubrange(dot..<zone)
        }
        if let date = try? Date(iso, strategy: .iso8601) { return date }
        if let date = try? Date(iso + "Z", strategy: .iso8601) { return date }

        let http = DateFormatter()
        http.locale = Locale(identifier: "en_US_POSIX")
        http.timeZone = TimeZone(identifier: "GMT")
        http.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return http.date(from: text)
    }

    /// ISO 8601 durations such as `PT21H30M` or `PT0S`, in minutes.
    static func minutes(_ text: String) -> Int? {
        guard text.hasPrefix("P") else { return nil }
        var total = 0.0, number = "", inTime = false
        for character in text.dropFirst() {
            switch character {
            case "T": inTime = true
            case "0"..."9", ".": number.append(character)
            case "D": total += (Double(number) ?? 0) * 1440; number = ""
            case "H" where inTime: total += (Double(number) ?? 0) * 60; number = ""
            case "M" where inTime: total += Double(number) ?? 0; number = ""
            case "S" where inTime: total += (Double(number) ?? 0) / 60; number = ""
            default: number = ""
            }
        }
        return Int(total.rounded())
    }

    /// The car expresses a time of day as a duration since midnight.
    static func timeOfDay(_ text: String) -> TimeOfDay? {
        minutes(text).map { TimeOfDay(minutes: $0) }
    }
}

// MARK: Wire types

/// The server's JSON, decoded with snake_case keys converted to camelCase.
enum Wire {
    /// Decodes to `nil` instead of failing, so one unexpected field in a part of
    /// the status the app can live without never costs the whole reading.
    struct Lossy<Value: Decodable & Sendable>: Decodable, Sendable {
        var value: Value?

        init(from decoder: Decoder) throws {
            value = try? Value(from: decoder)
        }
    }

    struct Status: Decodable, Sendable {
        var energy: [Energy]?
        var lastPosition: Lossy<Position>?
        // The misspelling is the server's.
        var preconditionning: Lossy<Preconditioning>?
        var doorsState: Lossy<Doors>?
        var environment: Lossy<Environment>?
        var timedOdometer: Lossy<Odometer>?
    }

    struct Energy: Decodable, Sendable {
        var type: String?
        var level: Double?
        var autonomy: Double?
        var updatedAt: String?
        var charging: Charging?
        var battery: Lossy<Battery>?

        struct Charging: Decodable, Sendable {
            var status: String?
            var plugged: Bool?
            var chargingRate: Double?
            var chargingMode: String?
            var remainingTime: String?
            var nextDelayedTime: String?
        }

        struct Battery: Decodable, Sendable {
            var capacity: Double?
            var health: Health?

            struct Health: Decodable, Sendable {
                var capacity: Double?
                var resistance: Double?
            }
        }
    }

    struct Position: Decodable, Sendable {
        var geometry: Geometry?
        var properties: Properties?

        struct Geometry: Decodable, Sendable {
            var coordinates: [Double]?
        }

        struct Properties: Decodable, Sendable {
            var heading: Double?
            var updatedAt: String?
            var createdAt: String?
        }
    }

    struct Preconditioning: Decodable, Sendable {
        var airConditioning: Air?

        struct Air: Decodable, Sendable {
            var status: String?
        }
    }

    struct Doors: Decodable, Sendable {
        var lockedState: [String]?
    }

    struct Environment: Decodable, Sendable {
        var air: Air?

        struct Air: Decodable, Sendable {
            var temp: Double?
        }
    }

    struct Odometer: Decodable, Sendable {
        var mileage: Double?
    }

    struct Vehicle: Decodable, Sendable {
        var vin: String
        var label: String?
        var batteryPower: Double?
        var fuelCapacity: Double?
    }

    /// Decoded with plain keys: the server's own names start with an underscore.
    struct ChargeControl: Decodable, Sendable {
        var percentageThreshold: Int?
        var stopHour: TimeOfDay?

        private enum CodingKeys: String, CodingKey {
            case percentageThreshold = "percentage_threshold"
            case stopHour = "_stop_hour"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            percentageThreshold = try? container.decode(Int.self, forKey: .percentageThreshold)
            if let parts = try? container.decode([Int].self, forKey: .stopHour), parts.count >= 2 {
                stopHour = TimeOfDay(hour: parts[0], minute: parts[1])
            }
        }
    }

    struct Health: Decodable, Sendable {
        var soh: Double?
    }

    struct Trip: Decodable, Sendable {
        var id: Int?
        var startAt: String?
        var duration: Double?
        var distance: Double?
        var consumption: Double?
        var consumptionKm: Double?
        var consumptionByTemp: Lossy<Double>?
        var altitudeDiff: Double?
        var positions: Positions?

        struct Positions: Decodable, Sendable {
            var lat: [Double]?
            var long: [Double]?
        }
    }

    struct Charging: Decodable, Sendable {
        var startAt: String?
        var stopAt: String?
        var startLevel: Double?
        var endLevel: Double?
        var kw: Double?
        var price: Double?
        var co2: Double?
        var chargingMode: String?
    }
}

private struct ServerFailure: Decodable {
    var error: String
}

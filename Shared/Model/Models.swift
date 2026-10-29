import CoreLocation
import Foundation

// The shapes below mirror what psa_car_controller (PSACC) exposes for a Stellantis
// vehicle, so a real client can fill them without touching the interface.

enum Powertrain: String, Codable, Sendable, CaseIterable, Identifiable {
    case electric
    case plugInHybrid

    var id: String { rawValue }
    var title: String {
        switch self {
        case .electric: "Electric"
        case .plugInHybrid: "Plug-in Hybrid"
        }
    }
}

enum ChargingStatus: String, Codable, Sendable {
    case disconnected
    case inProgress
    case scheduled
    case stopped
    case finished

    var isPlugged: Bool { self != .disconnected }
}

struct TimeOfDay: Codable, Hashable, Sendable, Comparable {
    var hour: Int
    var minute: Int

    init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    init(minutes: Int) {
        let wrapped = ((minutes % 1440) + 1440) % 1440
        hour = wrapped / 60
        minute = wrapped % 60
    }

    var minutes: Int { hour * 60 + minute }

    var label: String {
        String(format: "%02d:%02d", hour, minute)
    }

    static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool { lhs.minutes < rhs.minutes }
}

struct Coordinate: Codable, Hashable, Sendable {
    var latitude: Double
    var longitude: Double

    var location: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct ChargingState: Codable, Hashable, Sendable {
    var status: ChargingStatus
    var powerKW: Double
    var thresholdPercent: Int
    /// The car's delayed-charge start (`/charge_hour`).
    var startTime: TimeOfDay
    /// PSACC's stop hour (`/charge_control?hour=`). `nil` charges until the limit.
    var stopTime: TimeOfDay?
    var isScheduleEnabled: Bool
    var sessionStartedAt: Date?
    var sessionStartLevel: Double?
}

struct ClimateProgram: Codable, Hashable, Sendable, Identifiable {
    /// PSA keeps four numbered programme slots on the car.
    var slot: Int
    var isEnabled: Bool
    var time: TimeOfDay
    /// 1 = Monday ... 7 = Sunday.
    var weekdays: Set<Int>

    var id: Int { slot }
}

struct ClimateState: Codable, Hashable, Sendable {
    var isOn: Bool
    var startedAt: Date?
    var programs: [ClimateProgram]

    /// The car runs one conditioning cycle and then stops by itself.
    static let cycleMinutes = 10.0
}

struct VehicleSnapshot: Codable, Sendable, Equatable {
    var name: String
    var model: String
    var vin: String
    var powertrain: Powertrain
    var updatedAt: Date

    var batteryLevel: Double
    var batteryCapacityKWh: Double
    var fullRangeKm: Double
    var fuelLevel: Double
    var fuelRangeKm: Double
    /// Not every car reports it.
    var healthPercent: Double?

    var charging: ChargingState
    var climate: ClimateState

    var isLocked: Bool
    var odometerKm: Double
    var outsideTempC: Double?

    var location: Coordinate
    /// Compass heading the car is parked at, when known.
    var heading: Double?
    var address: String
    var locality: String
    var parkedAt: Date

    /// Wall-clock moment the mock simulation last advanced the state.
    var simulatedAt: Date
}

extension VehicleSnapshot {
    var batteryPercent: Int { Int(batteryLevel.rounded(.down)) }

    var rangeKm: Int { Int((batteryLevel / 100 * fullRangeKm).rounded()) }

    func rangeKm(at percent: Double) -> Int { Int((percent / 100 * fullRangeKm).rounded()) }

    var isCharging: Bool { charging.status == .inProgress }

    /// What the onboard charger draws from a wallbox: 11 kW on the electric car,
    /// 7.4 kW on the plug-in hybrid.
    var onboardChargerKW: Double { powertrain == .electric ? 11 : 7.4 }

    /// Range gained per hour at the current power.
    var chargeRateKmPerHour: Int {
        guard isCharging else { return 0 }
        return Int((charging.powerKW / batteryCapacityKWh * fullRangeKm).rounded())
    }

    /// Time until the charge limit at the present power, in real vehicle time.
    var minutesToLimit: Int? {
        guard isCharging, charging.powerKW > 0 else { return nil }
        let missing = max(0, Double(charging.thresholdPercent) - batteryLevel) / 100 * batteryCapacityKWh
        return Int((missing / charging.powerKW * 60).rounded(.up))
    }

    var sessionEnergyKWh: Double {
        guard let start = charging.sessionStartLevel else { return 0 }
        return max(0, batteryLevel - start) / 100 * batteryCapacityKWh
    }

    var climateMinutesRemaining: Double? {
        guard climate.isOn, let start = climate.startedAt else { return nil }
        let elapsed = Date.now.timeIntervalSince(start) / 60 * MockClock.climateScale
        return max(0, ClimateState.cycleMinutes - elapsed)
    }
}

enum ChargeConnector: String, Codable, Sendable {
    case ac = "AC"
    case dc = "DC"
}

struct CurvePoint: Codable, Hashable, Sendable, Identifiable {
    var level: Double
    var powerKW: Double
    var id: Double { level }
}

struct ChargingSession: Codable, Hashable, Sendable, Identifiable {
    var id: Int
    var start: Date
    var end: Date
    var place: String
    var connector: ChargeConnector
    var startLevel: Int
    var endLevel: Int
    var energyKWh: Double
    /// Missing when the server has no tariff configured.
    var cost: Double?
    var gramsCO2PerKWh: Int?
    /// Empty when the server only reports the session's totals.
    var curve: [CurvePoint]

    var duration: TimeInterval { end.timeIntervalSince(start) }
    var peakKW: Double { curve.map(\.powerKW).max() ?? 0 }
    var averageKW: Double { duration > 0 ? energyKWh / (duration / 3600) : 0 }
    var pricePerKWh: Double? { cost.flatMap { energyKWh > 0 ? $0 / energyKWh : nil } }
}

struct Trip: Codable, Hashable, Sendable, Identifiable {
    var id: Int
    var start: Date
    var end: Date
    var from: String
    var to: String
    var distanceKm: Double
    var energyKWh: Double
    var startLevel: Int?
    var endLevel: Int?
    var outsideTempC: Double?
    var route: [Coordinate]
    /// Elevation samples in metres, evenly spaced along the route. Empty when
    /// only the net change is known.
    var elevation: [Double]
    /// Net height gained from start to end, in metres.
    var altitudeChange: Double?

    var duration: TimeInterval { end.timeIntervalSince(start) }

    /// "Rüsselsheim to Mainz", or just what is known.
    var title: String {
        switch (from.isEmpty, to.isEmpty) {
        case (false, false): from == to ? "Around \(to)" : "\(from) to \(to)"
        case (true, false): "To \(to)"
        case (false, true): "From \(from)"
        case (true, true): "Drive"
        }
    }

    /// The destination, falling back to something that still reads as a row title.
    var destination: String { to.isEmpty ? "Drive" : to }

    var consumption: Double { distanceKm > 0 ? energyKWh / distanceKm * 100 : 0 }
    var averageSpeed: Double { duration > 0 ? distanceKm / (duration / 3600) : 0 }
    var climb: Double {
        zip(elevation, elevation.dropFirst()).reduce(0) { $0 + max(0, $1.1 - $1.0) }
    }
}

struct ElectricityTariff: Codable, Hashable, Sendable {
    var dayPrice: Double
    var nightPrice: Double
    var nightStart: TimeOfDay
    var nightEnd: TimeOfDay
    var currencyCode: String

    static let standard = ElectricityTariff(
        dayPrice: 0.34,
        nightPrice: 0.24,
        nightStart: TimeOfDay(hour: 22, minute: 0),
        nightEnd: TimeOfDay(hour: 6, minute: 0),
        currencyCode: "EUR"
    )

    func isNight(_ time: TimeOfDay) -> Bool {
        let m = time.minutes
        if nightStart.minutes <= nightEnd.minutes {
            return m >= nightStart.minutes && m < nightEnd.minutes
        }
        return m >= nightStart.minutes || m < nightEnd.minutes
    }
}

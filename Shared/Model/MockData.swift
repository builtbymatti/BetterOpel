import Foundation

struct RouteSeed: Sendable {
    var distanceKm: Double
    var minutes: Double
    var polyline: String

    var coordinates: [Coordinate] { Polyline.decode(polyline) }
}

enum Polyline {
    /// Google encoded polyline algorithm, precision 5.
    static func decode(_ string: String) -> [Coordinate] {
        var result: [Coordinate] = []
        var lat = 0, lon = 0
        var iterator = string.utf8.makeIterator()

        func next(_ it: inout String.UTF8View.Iterator) -> Int? {
            var value = 0, shift = 0
            while let byte = it.next() {
                let chunk = Int(byte) - 63
                value |= (chunk & 0x1F) << shift
                shift += 5
                if chunk < 0x20 {
                    return (value & 1) != 0 ? ~(value >> 1) : (value >> 1)
                }
            }
            return nil
        }

        while let dLat = next(&iterator), let dLon = next(&iterator) {
            lat += dLat
            lon += dLon
            result.append(Coordinate(latitude: Double(lat) / 1e5, longitude: Double(lon) / 1e5))
        }
        return result
    }
}

/// Small deterministic generator so the demo data is identical on every launch
/// and in every process (app, widgets, intents).
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

enum MockData {
    static let home = Coordinate(latitude: 49.99212, longitude: 8.41262)

    static func initialSnapshot(now: Date = .now) -> VehicleSnapshot {
        VehicleSnapshot(
            name: "Grandland",
            model: "Grandland Electric",
            vin: "DEMO0000000000000",
            powertrain: .electric,
            updatedAt: now,
            batteryLevel: 64.2,
            batteryCapacityKWh: 73,
            fullRangeKm: 482,
            fuelLevel: 71,
            fuelRangeKm: 540,
            healthPercent: 98,
            charging: ChargingState(
                status: .inProgress,
                powerKW: 11,
                thresholdPercent: 80,
                startTime: TimeOfDay(hour: 22, minute: 30),
                stopTime: TimeOfDay(hour: 6, minute: 0),
                isScheduleEnabled: false,
                sessionStartedAt: now.addingTimeInterval(-52 * 60),
                sessionStartLevel: 51
            ),
            climate: ClimateState(
                isOn: false,
                startedAt: nil,
                programs: [
                    ClimateProgram(slot: 1, isEnabled: true, time: TimeOfDay(hour: 7, minute: 10), weekdays: [1, 2, 3, 4, 5]),
                    ClimateProgram(slot: 2, isEnabled: false, time: TimeOfDay(hour: 17, minute: 30), weekdays: [1, 2, 3, 4]),
                    ClimateProgram(slot: 3, isEnabled: true, time: TimeOfDay(hour: 9, minute: 45), weekdays: [6]),
                ]
            ),
            isLocked: true,
            odometerKm: 12_486,
            outsideTempC: 9,
            location: home,
            heading: 24,
            address: "Bahnhofsplatz 1",
            locality: "Rüsselsheim am Main",
            parkedAt: now.addingTimeInterval(-58 * 60),
            simulatedAt: now
        )
    }

    // MARK: Trips

    static func trips(now: Date = .now) -> [Trip] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        var generator = SeededGenerator(state: 0x0BE1_2024)

        struct Plan {
            var dayOffset: Int
            var hour: Int
            var minute: Int
            var seed: RouteSeed
            var place: String
            var outbound: Bool
            var temp: Double
        }

        let frankfurt = RoutePolylines.frankfurt
        let mainz = RoutePolylines.mainz
        let wiesbaden = RoutePolylines.wiesbaden
        let heidelberg = RoutePolylines.heidelberg
        let airport = RoutePolylines.airport
        let darmstadt = RoutePolylines.darmstadt

        let plans: [Plan] = [
            Plan(dayOffset: 0, hour: 8, minute: 4, seed: frankfurt, place: "Sachsenhausen", outbound: true, temp: 7),
            Plan(dayOffset: 0, hour: 13, minute: 32, seed: frankfurt, place: "Sachsenhausen", outbound: false, temp: 11),
            Plan(dayOffset: 1, hour: 17, minute: 48, seed: mainz, place: "Mainz Altstadt", outbound: true, temp: 12),
            Plan(dayOffset: 1, hour: 21, minute: 15, seed: mainz, place: "Mainz Altstadt", outbound: false, temp: 8),
            Plan(dayOffset: 2, hour: 7, minute: 52, seed: airport, place: "Frankfurt Airport", outbound: true, temp: 5),
            Plan(dayOffset: 2, hour: 9, minute: 10, seed: airport, place: "Frankfurt Airport", outbound: false, temp: 6),
            Plan(dayOffset: 4, hour: 10, minute: 20, seed: heidelberg, place: "Heidelberg", outbound: true, temp: 13),
            Plan(dayOffset: 4, hour: 18, minute: 2, seed: heidelberg, place: "Heidelberg", outbound: false, temp: 10),
            Plan(dayOffset: 5, hour: 8, minute: 15, seed: wiesbaden, place: "Wiesbaden", outbound: true, temp: 4),
            Plan(dayOffset: 5, hour: 16, minute: 40, seed: wiesbaden, place: "Wiesbaden", outbound: false, temp: 9),
            Plan(dayOffset: 6, hour: 9, minute: 30, seed: darmstadt, place: "Darmstadt", outbound: true, temp: 8),
            Plan(dayOffset: 6, hour: 14, minute: 5, seed: darmstadt, place: "Darmstadt", outbound: false, temp: 12),
            Plan(dayOffset: 8, hour: 8, minute: 1, seed: frankfurt, place: "Sachsenhausen", outbound: true, temp: 3),
            Plan(dayOffset: 8, hour: 17, minute: 22, seed: frankfurt, place: "Sachsenhausen", outbound: false, temp: 7),
            Plan(dayOffset: 10, hour: 11, minute: 12, seed: mainz, place: "Mainz Altstadt", outbound: true, temp: 14),
            Plan(dayOffset: 10, hour: 15, minute: 47, seed: mainz, place: "Mainz Altstadt", outbound: false, temp: 15),
            Plan(dayOffset: 12, hour: 7, minute: 58, seed: darmstadt, place: "Darmstadt", outbound: true, temp: 2),
            Plan(dayOffset: 12, hour: 18, minute: 30, seed: darmstadt, place: "Darmstadt", outbound: false, temp: 6),
        ]

        var level = 64
        var result: [Trip] = []
        for (index, plan) in plans.enumerated() {
            guard let day = calendar.date(byAdding: .day, value: -plan.dayOffset, to: today),
                  let start = calendar.date(bySettingHour: plan.hour, minute: plan.minute, second: 0, of: day),
                  start < now
            else { continue }

            // Colder air and motorway stretches cost more energy.
            let cold = max(0, 15 - plan.temp) * 0.22
            let motorway = plan.seed.distanceKm > 60 ? 2.4 : 0
            let consumption = 15.6 + cold + motorway + Double.random(in: -0.9...0.9, using: &generator)
            let energy = plan.seed.distanceKm * consumption / 100
            let minutes = plan.seed.minutes * Double.random(in: 1.02...1.22, using: &generator)
            let used = Int((energy / 73 * 100).rounded())
            let endLevel = max(18, level)
            let startLevel = min(100, endLevel + used)

            var route = plan.seed.coordinates
            if !plan.outbound { route.reverse() }

            result.append(
                Trip(
                    id: 4_000 - index,
                    start: start,
                    end: start.addingTimeInterval(minutes * 60),
                    from: plan.outbound ? "Rüsselsheim" : plan.place,
                    to: plan.outbound ? plan.place : "Rüsselsheim",
                    distanceKm: plan.seed.distanceKm,
                    energyKWh: energy,
                    startLevel: startLevel,
                    endLevel: endLevel,
                    outsideTempC: plan.temp,
                    route: route,
                    elevation: elevation(for: plan.seed, outbound: plan.outbound, generator: &generator),
                    altitudeChange: nil
                )
            )
            level = startLevel > 88 ? 47 + index % 9 : startLevel
        }
        return result
    }

    private static func elevation(for seed: RouteSeed, outbound: Bool, generator: inout SeededGenerator) -> [Double] {
        let count = 48
        // The Rhine-Main plain sits near 90 m; longer routes roll more.
        let amplitude = min(70, 8 + seed.distanceKm * 0.7)
        let phase = Double.random(in: 0...(2 * .pi), using: &generator)
        var samples = (0..<count).map { i -> Double in
            let t = Double(i) / Double(count - 1)
            let roll = sin(t * 5.3 + phase) * 0.55 + sin(t * 12.1 + phase * 1.7) * 0.25 + sin(t * 23 + phase * 0.6) * 0.1
            return 92 + amplitude * (0.5 + 0.5 * roll) * sin(t * .pi * 0.92 + 0.12)
        }
        if !outbound { samples.reverse() }
        return samples
    }

    // MARK: Charging sessions

    static func chargingSessions(now: Date = .now, tariff: ElectricityTariff = .standard) -> [ChargingSession] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)

        struct Plan {
            var dayOffset: Int
            var hour: Int
            var minute: Int
            var place: String
            var connector: ChargeConnector
            var from: Int
            var to: Int
            var peak: Double
            var price: Double
            var co2: Int
        }

        let plans: [Plan] = [
            Plan(dayOffset: 1, hour: 22, minute: 30, place: "Home", connector: .ac, from: 38, to: 80, peak: 11, price: tariff.nightPrice, co2: 312),
            Plan(dayOffset: 3, hour: 22, minute: 30, place: "Home", connector: .ac, from: 52, to: 80, peak: 11, price: tariff.nightPrice, co2: 288),
            Plan(dayOffset: 4, hour: 12, minute: 41, place: "Ionity, Heidelberg", connector: .dc, from: 21, to: 82, peak: 158, price: 0.59, co2: 341),
            Plan(dayOffset: 6, hour: 22, minute: 30, place: "Home", connector: .ac, from: 33, to: 80, peak: 11, price: tariff.nightPrice, co2: 296),
            Plan(dayOffset: 9, hour: 18, minute: 12, place: "EnBW, Frankfurt Ost", connector: .dc, from: 28, to: 70, peak: 149, price: 0.61, co2: 365),
            Plan(dayOffset: 11, hour: 22, minute: 30, place: "Home", connector: .ac, from: 44, to: 100, peak: 11, price: tariff.nightPrice, co2: 274),
            Plan(dayOffset: 14, hour: 9, minute: 20, place: "Mainz, Rheinufer", connector: .ac, from: 61, to: 78, peak: 7.4, price: 0.45, co2: 330),
        ]

        return plans.enumerated().compactMap { index, plan in
            guard let day = calendar.date(byAdding: .day, value: -plan.dayOffset, to: today),
                  let start = calendar.date(bySettingHour: plan.hour, minute: plan.minute, second: 0, of: day)
            else { return nil }
            let curve = curve(from: plan.from, to: plan.to, peak: plan.peak, connector: plan.connector)
            let energy = Double(plan.to - plan.from) / 100 * 73
            // Integrate time over the curve: each step adds energy at its own power.
            let hours = zip(curve, curve.dropFirst()).reduce(0.0) { total, pair in
                let stepEnergy = (pair.1.level - pair.0.level) / 100 * 73
                return total + stepEnergy / max(1, (pair.0.powerKW + pair.1.powerKW) / 2)
            }
            return ChargingSession(
                id: 900 - index,
                start: start,
                end: start.addingTimeInterval(hours * 3600),
                place: plan.place,
                connector: plan.connector,
                startLevel: plan.from,
                endLevel: plan.to,
                energyKWh: energy * 1.07,
                cost: energy * 1.07 * plan.price,
                gramsCO2PerKWh: plan.co2,
                curve: curve
            )
        }
    }

    private static func curve(from: Int, to: Int, peak: Double, connector: ChargeConnector) -> [CurvePoint] {
        stride(from: Double(from), through: Double(to), by: 1).map { level in
            let power: Double
            switch connector {
            case .ac:
                // An AC wallbox holds its power and only tapers in the last few percent.
                let taper = level > 94 ? max(0.25, 1 - (level - 94) / 8) : 1
                power = peak * taper
            case .dc:
                // DC: quick ramp, a plateau, then a long taper as the pack fills.
                let ramp = min(1, (level - Double(from) + 2) / 5)
                let plateau = level < 42 ? 1.0 : max(0.26, 1 - (level - 42) / 62)
                power = peak * ramp * plateau
            }
            return CurvePoint(level: level, powerKW: power)
        }
    }
}

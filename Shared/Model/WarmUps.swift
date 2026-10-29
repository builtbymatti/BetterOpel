import Foundation

/// A time the cabin should be ready by. The server starts the climate ten
/// minutes ahead of it; the programmes stored in the car are not involved.
struct WarmUp: Identifiable, Hashable, Sendable {
    var id: String = UUID().uuidString
    /// The time to be ready by.
    var hour: Int
    var minute: Int
    /// 1 Monday to 7 Sunday. Empty means once, at the next such time.
    var days: Set<Int>
    var isOn = true

    /// When the server will next start the climate for this, if it will.
    var nextStart: Date?
    var lastRun: Run?

    struct Run: Hashable, Sendable {
        var at: Date
        var outcome: Outcome
    }

    enum Outcome: String, Sendable {
        /// The car reported its climate running.
        case confirmed
        /// The command went out, but the car never said it was running.
        case sent
        case failed
    }

    /// How long before the ready time the climate starts: one cycle of the car.
    static let leadMinutes = 10

    var ready: TimeOfDay { TimeOfDay(hour: hour, minute: minute) }
    var start: TimeOfDay { TimeOfDay(minutes: hour * 60 + minute - Self.leadMinutes) }
    var runsOnce: Bool { days.isEmpty }

    /// The same in everything a person can set, whatever the server has added.
    func matches(_ other: WarmUp) -> Bool {
        id == other.id && hour == other.hour && minute == other.minute && days == other.days && isOn == other.isOn
    }
}

protocol WarmUpAPI: Sendable {
    func load() async throws -> [WarmUp]
    /// Replaces the whole list and returns it as the server now holds it.
    func save(_ list: [WarmUp]) async throws -> [WarmUp]
}

extension VehicleService {
    /// The scheduler lives next to the car server, under the same address.
    static var warmUps: any WarmUpAPI {
        #if DEBUG
        // `-scheduler http://host:5056` points at a scheduler directly, for checks.
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-scheduler"), arguments.indices.contains(index + 1),
           let url = ConnectionStore.url(from: arguments[index + 1]) {
            return ServerWarmUps(baseURL: url, vin: ConnectionStore.vin)
        }
        #endif
        if let url = ConnectionStore.baseURL, !ConnectionStore.vin.isEmpty {
            return ServerWarmUps(baseURL: url.appending(path: "scheduler"), vin: ConnectionStore.vin)
        }
        return DemoWarmUps()
    }
}

// MARK: Server

struct ServerWarmUps: WarmUpAPI {
    var baseURL: URL
    var vin: String

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    func load() async throws -> [WarmUp] {
        try await send(URLRequest(url: baseURL.appending(path: "schedules")))
    }

    func save(_ list: [WarmUp]) async throws -> [WarmUp] {
        var request = URLRequest(url: baseURL.appending(path: "schedules"))
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = Wire.Upload(
            vin: vin,
            schedules: list.map { Wire.Entry(id: $0.id, hour: $0.hour, minute: $0.minute, days: $0.days.sorted(), enabled: $0.isOn) }
        )
        request.httpBody = try JSONEncoder().encode(body)
        return try await send(request)
    }

    /// A start asked for by hand, as the server reports it.
    struct ManualRun: Sendable {
        /// waking, sending, waiting, then confirmed, sent or failed.
        var phase: String
        var detail: String
    }

    /// Asks the server to wake the car and start its climate now.
    func startNow() async throws -> ManualRun {
        var request = URLRequest(url: baseURL.appending(path: "run"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["vin": vin])
        guard let run = try await manual(request) else { throw VehicleError.unreachable }
        return run
    }

    func runState() async throws -> ManualRun? {
        try await manual(URLRequest(url: baseURL.appending(path: "run")))
    }

    private func manual(_ request: URLRequest) async throws -> ManualRun? {
        guard let (data, response) = try? await Self.session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let reply = try? JSONDecoder().decode(Wire.RunReply.self, from: data)
        else { throw VehicleError.unreachable }
        return reply.run.map { ManualRun(phase: $0.phase, detail: $0.detail ?? "") }
    }

    private func send(_ request: URLRequest) async throws -> [WarmUp] {
        let data: Data, response: URLResponse
        do {
            (data, response) = try await Self.session.data(for: request)
        } catch {
            throw VehicleError.unreachable
        }
        guard let http = response as? HTTPURLResponse else { throw VehicleError.unreachable }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard http.statusCode == 200 else {
            if let failure = try? decoder.decode(Wire.Failure.self, from: data), http.statusCode == 400 {
                throw VehicleError.server(failure.error)
            }
            // An older server set-up has the car server but no scheduler beside it.
            throw VehicleError.server("Your server has no timed starts yet.")
        }
        guard let listing = try? decoder.decode(Wire.Listing.self, from: data) else {
            throw VehicleError.server("Your server has no timed starts yet.")
        }
        return listing.schedules.map(\.warmUp)
    }

    private enum Wire {
        struct Upload: Encodable {
            var vin: String
            var schedules: [Entry]
        }

        struct Entry: Encodable {
            var id: String
            var hour: Int
            var minute: Int
            var days: [Int]
            var enabled: Bool
        }

        struct Failure: Decodable {
            var error: String
        }

        struct RunReply: Decodable {
            var run: Run?

            struct Run: Decodable {
                var phase: String
                var detail: String?
            }
        }

        struct Listing: Decodable {
            var schedules: [Stored]
        }

        struct Stored: Decodable {
            var id: String
            var hour: Int
            var minute: Int
            var days: [Int]
            var enabled: Bool
            var nextStart: String?
            var lastRun: Run?

            struct Run: Decodable {
                var at: String
                var outcome: String
            }

            var warmUp: WarmUp {
                var run: WarmUp.Run?
                if let lastRun, let at = Self.date(lastRun.at) {
                    run = WarmUp.Run(at: at, outcome: WarmUp.Outcome(rawValue: lastRun.outcome) ?? .failed)
                }
                return WarmUp(
                    id: id, hour: hour, minute: minute, days: Set(days), isOn: enabled,
                    nextStart: nextStart.flatMap(Self.date), lastRun: run
                )
            }

            static func date(_ text: String) -> Date? {
                ISO8601DateFormatter().date(from: text)
            }
        }
    }
}

// MARK: Demo

/// The demo car's schedule: kept on the phone, timed the way the server would,
/// and never sent anywhere.
struct DemoWarmUps: WarmUpAPI {
    private static let key = "demo.warmups"

    func load() async throws -> [WarmUp] {
        Self.stored().map { Self.timed($0, now: .now) }
    }

    func save(_ list: [WarmUp]) async throws -> [WarmUp] {
        try await Task.sleep(for: .milliseconds(350))
        let plain = list.map { Stored(id: $0.id, hour: $0.hour, minute: $0.minute, days: $0.days.sorted(), isOn: $0.isOn, setAt: .now) }
        SnapshotStore.defaults.set(try? JSONEncoder().encode(plain), forKey: Self.key)
        return plain.map { Self.timed($0, now: .now) }
    }

    static func reset() {
        SnapshotStore.defaults.removeObject(forKey: key)
    }

    private struct Stored: Codable {
        var id: String
        var hour: Int
        var minute: Int
        var days: [Int]
        var isOn: Bool
        var setAt: Date
    }

    private static func stored() -> [Stored] {
        if let data = SnapshotStore.defaults.data(forKey: key), let list = try? JSONDecoder().decode([Stored].self, from: data) {
            return list
        }
        let long = Date.distantPast
        return [
            Stored(id: "demo-morning", hour: 7, minute: 10, days: [1, 2, 3, 4, 5], isOn: true, setAt: long),
            Stored(id: "demo-evening", hour: 17, minute: 30, days: [1, 2, 3, 4], isOn: false, setAt: long),
            Stored(id: "demo-weekend", hour: 9, minute: 45, days: [6, 7], isOn: true, setAt: long),
        ]
    }

    /// Works out the next start, and for a time that has passed today, a run.
    private static func timed(_ stored: Stored, now: Date) -> WarmUp {
        var warmUp = WarmUp(id: stored.id, hour: stored.hour, minute: stored.minute, days: Set(stored.days), isOn: stored.isOn)
        let calendar = Calendar.current
        let lead = TimeInterval(WarmUp.leadMinutes * 60)

        func ready(daysFromNow offset: Int) -> Date? {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now),
                  let ready = calendar.date(bySettingHour: stored.hour, minute: stored.minute, second: 0, of: day) else { return nil }
            // Calendar counts Sunday as 1; the schedule counts Monday as 1.
            let weekday = (calendar.component(.weekday, from: ready) + 5) % 7 + 1
            return stored.days.isEmpty || stored.days.contains(weekday) ? ready : nil
        }

        if stored.isOn {
            for offset in 0...8 {
                guard let ready = ready(daysFromNow: offset) else { continue }
                let start = ready.addingTimeInterval(-lead)
                if start > now, stored.days.isEmpty ? start > stored.setAt : true {
                    warmUp.nextStart = start
                    break
                }
            }
            // A one-off whose time has come is spent.
            if stored.days.isEmpty, warmUp.nextStart == nil { warmUp.isOn = false }
        }
        if let ready = ready(daysFromNow: 0), !stored.days.isEmpty, stored.isOn {
            let start = ready.addingTimeInterval(-lead)
            if start <= now, start > stored.setAt { warmUp.lastRun = WarmUp.Run(at: start, outcome: .confirmed) }
        }
        return warmUp
    }
}

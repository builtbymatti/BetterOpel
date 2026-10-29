import Foundation

/// Where the car's data comes from. With a server address and a VIN the app
/// talks to a real psa_car_controller; without them it runs the demo car.
/// Stored in the App Group so the widgets and Siri use the same connection.
enum ConnectionStore {
    static let serverKey = "connection.server"
    static let vinKey = "connection.vin"
    private static let carKey = "connection.car"

    private static var defaults: UserDefaults { SnapshotStore.defaults }

    static var server: String {
        get { defaults.string(forKey: serverKey) ?? "" }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: serverKey) }
    }

    static var vin: String {
        get { defaults.string(forKey: vinKey) ?? "" }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), forKey: vinKey) }
    }

    static var isLive: Bool { baseURL != nil && !vin.isEmpty }

    static var baseURL: URL? { url(from: server) }

    /// Accepts what people actually type: a bare host, a host with a port, or a
    /// full URL. Hosts on the local network default to http, everything else to
    /// https.
    static func url(from text: String) -> URL? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        while value.hasSuffix("/") { value.removeLast() }
        if !value.contains("://") {
            let host = value.split(separator: ":").first.map(String.init)?.lowercased() ?? ""
            let isLocal = host == "localhost" || host.hasSuffix(".local") || host.allSatisfy { $0.isNumber || $0 == "." }
            value = (isLocal ? "http://" : "https://") + value
        }
        guard let url = URL(string: value), url.host() != nil else { return nil }
        return url
    }

    /// What the server knows about the car itself, fetched once on connecting.
    struct Car: Codable, Sendable, Equatable {
        var label: String
        var batteryKWh: Double
        var fuelLitres: Double
    }

    static var car: Car? {
        get { defaults.data(forKey: carKey).flatMap { try? JSONDecoder().decode(Car.self, from: $0) } }
        set { defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: carKey) }
    }

    static func disconnect() {
        defaults.removeObject(forKey: serverKey)
        defaults.removeObject(forKey: vinKey)
        defaults.removeObject(forKey: carKey)
    }
}

/// Hands out the vehicle API that matches the current connection.
enum VehicleService {
    static var current: any VehicleAPI {
        if let url = ConnectionStore.baseURL, !ConnectionStore.vin.isEmpty {
            return PSACCClient(baseURL: url, vin: ConnectionStore.vin)
        }
        return MockVehicleAPI()
    }

    /// For Siri, widgets and controls, where the demo should answer a little
    /// faster than it does in the app.
    static var background: any VehicleAPI {
        if let url = ConnectionStore.baseURL, !ConnectionStore.vin.isEmpty {
            return PSACCClient(baseURL: url, vin: ConnectionStore.vin)
        }
        return MockVehicleAPI(latency: .milliseconds(600))
    }
}

import CoreLocation
@preconcurrency import MapKit

/// Turns coordinates into place names and remembers what it has looked up, so a
/// spot is only ever asked about once.
actor PlaceNamer {
    static let shared = PlaceNamer()

    struct Place: Codable, Sendable, Equatable {
        var street: String
        var locality: String
    }

    private static let cacheKey = "places.cache.v1"
    private var cache: [String: Place]

    private init() {
        let stored = UserDefaults.standard.data(forKey: Self.cacheKey)
        cache = stored.flatMap { try? JSONDecoder().decode([String: Place].self, from: $0) } ?? [:]
    }

    /// Rounded to about a hundred metres: close enough to share a name.
    private func key(_ coordinate: Coordinate) -> String {
        String(format: "%.3f,%.3f", coordinate.latitude, coordinate.longitude)
    }

    func place(for coordinate: Coordinate) async -> Place? {
        let key = key(coordinate)
        if let known = cache[key] { return known }

        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let request = MKReverseGeocodingRequest(location: location),
              let item = try? await request.mapItems.first
        else { return nil }

        let city = item.addressRepresentations?.cityName ?? ""
        // The short address leads with street and number; the rest repeats the city.
        let short = item.address?.shortAddress ?? item.address?.fullAddress ?? ""
        let street = short.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
        let place = Place(street: street.isEmpty ? city : street, locality: city)
        guard !place.street.isEmpty else { return nil }

        cache[key] = place
        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
        }
        return place
    }
}

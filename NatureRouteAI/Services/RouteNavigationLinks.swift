import Foundation
import CoreLocation

struct NavigationStop: Equatable {
    let name: String
    let latitude: Double
    let longitude: Double

    init(name: String, latitude: Double, longitude: Double) throws {
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              CLLocationCoordinate2DIsValid(coordinate) else {
            throw NavigationLinkError.invalidStop
        }

        self.name = name
        self.latitude = latitude
        self.longitude = longitude
    }

    var coordinateQuery: String {
        "\(latitude),\(longitude)"
    }
}

enum NavigationProvider: String, CaseIterable, Identifiable {
    case appleMaps
    case googleMaps

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appleMaps: "Apple Maps"
        case .googleMaps: "Google Maps"
        }
    }
}

enum NavigationLinkError: LocalizedError {
    case invalidStop
    case noStops
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .invalidStop: "A stop has a missing name or invalid coordinates."
        case .noStops: "There are no stops to navigate to."
        case .invalidURL: "Could not create a valid navigation link."
        }
    }
}

enum RouteNavigationLinks {
    /// Google Maps URLs work as universal links: iOS opens the app when available
    /// and otherwise opens the same route in a browser. Mobile browsers support
    /// at most three waypoints. With the current location as origin, that means
    /// three intermediate stops plus the destination.
    static let googleMaximumStops = 4

    static func url(
        for provider: NavigationProvider,
        stops: [NavigationStop],
        transport: TransportMode
    ) throws -> URL {
        guard !stops.isEmpty else { throw NavigationLinkError.noStops }

        let boundedStops = provider == .googleMaps
            ? Array(stops.prefix(googleMaximumStops))
            : stops

        var components: URLComponents
        var items: [URLQueryItem]

        switch provider {
        case .appleMaps:
            components = URLComponents()
            components.scheme = "https"
            components.host = "maps.apple.com"
            components.path = "/directions"
            let destination = boundedStops[boundedStops.count - 1]
            items = [
                URLQueryItem(name: "destination", value: destination.coordinateQuery),
                URLQueryItem(name: "mode", value: transport.appleMapsMode)
            ]
            for stop in boundedStops.dropLast() {
                items.append(URLQueryItem(name: "waypoint", value: stop.coordinateQuery))
            }

        case .googleMaps:
            components = URLComponents()
            components.scheme = "https"
            components.host = "www.google.com"
            components.path = "/maps/dir/"
            let destination = boundedStops[boundedStops.count - 1]
            items = [
                URLQueryItem(name: "api", value: "1"),
                URLQueryItem(name: "destination", value: destination.coordinateQuery),
                URLQueryItem(name: "travelmode", value: transport.googleMapsMode)
            ]
            let waypoints = boundedStops.dropLast().map(\.coordinateQuery)
            if !waypoints.isEmpty {
                items.append(URLQueryItem(name: "waypoints", value: waypoints.joined(separator: "|")))
            }
        }

        components.queryItems = items
        guard let url = components.url,
              let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme),
              url.host != nil else {
            throw NavigationLinkError.invalidURL
        }
        return url
    }
}

private extension TransportMode {
    var appleMapsMode: String {
        switch self {
        case .walking: "walking"
        case .cycling: "cycling"
        case .car: "driving"
        }
    }

    var googleMapsMode: String {
        switch self {
        case .walking: "walking"
        case .cycling: "bicycling"
        case .car: "driving"
        }
    }
}

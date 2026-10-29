import Foundation
import CoreLocation
import MapKit

struct RouteMetrics: Equatable {
    let distanceMeters: Double
    let expectedTravelTime: TimeInterval
}

@MainActor
protocol RouteMetricsProviding {
    func metrics(from latitude: Double, longitude: Double, to candidate: RoutePlaceCandidate, transport: TransportMode) async throws -> RouteMetrics
}

enum RouteMetricsError: Error {
    case unsupportedTransport
    case noRoute
    case requestLimitReached
}

@MainActor
final class MapKitRouteMetricsService: RouteMetricsProviding {
    private struct Key: Hashable {
        let fromLatitude: Double
        let fromLongitude: Double
        let toLatitude: Double
        let toLongitude: Double
        let transport: TransportMode
    }

    private let requestLimit: Int
    private var requestCount = 0
    private var cache: [Key: RouteMetrics] = [:]

    init(requestLimit: Int = 40) { self.requestLimit = requestLimit }

    func metrics(from latitude: Double, longitude: Double, to candidate: RoutePlaceCandidate, transport: TransportMode) async throws -> RouteMetrics {
        let key = Key(fromLatitude: latitude, fromLongitude: longitude, toLatitude: candidate.latitude, toLongitude: candidate.longitude, transport: transport)
        if let cached = cache[key] { return cached }
        guard requestCount < requestLimit else { throw RouteMetricsError.requestLimitReached }
        let type: MKDirectionsTransportType
        switch transport {
        case .walking: type = .walking
        case .cycling: type = .cycling
        case .car: type = .automobile
        case .publicTransport: throw RouteMetricsError.unsupportedTransport
        }
        requestCount += 1
        let request = MKDirections.Request()
        request.source = MKMapItem(location: CLLocation(latitude: latitude, longitude: longitude), address: nil)
        request.destination = MKMapItem(location: CLLocation(latitude: candidate.latitude, longitude: candidate.longitude), address: nil)
        request.transportType = type
        let response = try await MKDirections(request: request).calculate()
        guard let route = response.routes.first else { throw RouteMetricsError.noRoute }
        let result = RouteMetrics(distanceMeters: route.distance, expectedTravelTime: route.expectedTravelTime)
        cache[key] = result
        return result
    }
}

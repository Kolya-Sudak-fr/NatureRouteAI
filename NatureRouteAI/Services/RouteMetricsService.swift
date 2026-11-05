import Foundation
import CoreLocation
import MapKit

struct RouteMetrics: Equatable {
    let distanceMeters: Double
    let expectedTravelTime: TimeInterval
}

@MainActor
protocol RouteMetricsProviding {
    func beginPlanningSession()
    func metrics(from latitude: Double, longitude: Double, to candidate: RoutePlaceCandidate, transport: TransportMode) async throws -> RouteMetrics
}

@MainActor
extension RouteMetricsProviding {
    func beginPlanningSession() { }
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
    private var planningSessionID = UUID()

    init(requestLimit: Int = 40) { self.requestLimit = max(0, requestLimit) }

    func beginPlanningSession() {
        planningSessionID = UUID()
        requestCount = 0
        cache.removeAll(keepingCapacity: true)
    }

    func metrics(from latitude: Double, longitude: Double, to candidate: RoutePlaceCandidate, transport: TransportMode) async throws -> RouteMetrics {
        let key = Key(fromLatitude: latitude, fromLongitude: longitude, toLatitude: candidate.latitude, toLongitude: candidate.longitude, transport: transport)
        if let cached = cache[key] { return cached }
        let requestSessionID = planningSessionID
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
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: candidate.latitude, longitude: candidate.longitude)))
        request.transportType = type
        let directions = MKDirections(request: request)
        let response = try await withTaskCancellationHandler {
            try await directions.calculate()
        } onCancel: {
            Task { @MainActor in directions.cancel() }
        }
        try Task.checkCancellation()
        guard requestSessionID == planningSessionID else { throw CancellationError() }
        guard let route = response.routes.first else { throw RouteMetricsError.noRoute }
        let result = RouteMetrics(distanceMeters: route.distance, expectedTravelTime: route.expectedTravelTime)
        cache[key] = result
        return result
    }
}

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
    case throttled
    case serviceUnavailable

    /// Separates MapKit's rate limiting and outages from a real "no route"
    /// answer, because each one needs a different message for the user.
    static func classify(_ error: Error) -> Error {
        if error is URLError { return RouteMetricsError.serviceUnavailable }
        guard let mapKitError = error as? MKError else { return error }
        switch mapKitError.code {
        case .loadingThrottled: return RouteMetricsError.throttled
        case .serverFailure, .unknown: return RouteMetricsError.serviceUnavailable
        case .directionsNotFound, .placemarkNotFound: return RouteMetricsError.noRoute
        default: return error
        }
    }
}

/// Resumes a continuation exactly once, whichever comes first: the request's
/// result or the task's cancellation.
private nonisolated final class ResumeGate<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var result: Result<Value, Error>?

    /// Returns false when the gate already finished, so the request must not start.
    func install(_ continuation: CheckedContinuation<Value, Error>) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if let result {
            continuation.resume(with: result)
            return false
        }
        self.continuation = continuation
        return true
    }

    func finish(_ newResult: Result<Value, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard result == nil else { return }
        result = newResult
        continuation?.resume(with: newResult)
        continuation = nil
    }
}

/// Ends with `CancellationError` as soon as the task is cancelled, without
/// waiting for the request. A cancelled MKDirections may never call back, so
/// waiting for it would leave the caller suspended forever.
@MainActor
func withPromptCancellation<Value>(
    start: (@escaping (Result<Value, Error>) -> Void) -> Void,
    cancel: @escaping @MainActor @Sendable () -> Void
) async throws -> Value {
    let gate = ResumeGate<Value>()
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            guard gate.install(continuation) else { return }
            start { gate.finish($0) }
        }
    } onCancel: {
        gate.finish(.failure(CancellationError()))
        Task { @MainActor in cancel() }
    }
}

extension MKDirections {
    @MainActor
    func calculateRoute() async throws -> MKDirections.Response {
        try await withPromptCancellation(
            start: { finish in
                self.calculate { response, error in
                    if let response {
                        finish(.success(response))
                    } else {
                        finish(.failure(error ?? MKError(.unknown)))
                    }
                }
            },
            cancel: { self.cancel() }
        )
    }
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

    init(requestLimit: Int = RoutePlanningAlgorithm.defaultRequestBudget) { self.requestLimit = max(0, requestLimit) }

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
        let response: MKDirections.Response
        do {
            response = try await directions.calculateRoute()
        } catch {
            throw RouteMetricsError.classify(error)
        }
        try Task.checkCancellation()
        guard requestSessionID == planningSessionID else { throw CancellationError() }
        guard let route = response.routes.first else { throw RouteMetricsError.noRoute }
        let result = RouteMetrics(distanceMeters: route.distance, expectedTravelTime: route.expectedTravelTime)
        cache[key] = result
        return result
    }
}

import Foundation
import CoreLocation
import MapKit

struct ResolvedCity: Equatable {
    let name: String
    let latitude: Double
    let longitude: Double
}

@MainActor
protocol CityGeocoding {
    func resolveCity(named name: String) async throws -> ResolvedCity
}

/// Uses Apple's search instead of OpenTripMap's geoname endpoint, which resolves
/// "New York" to Albany and "Amster" to a town in Colombia.
@MainActor
final class MapKitCityGeocoder: CityGeocoding {
    func resolveCity(named name: String) async throws -> ResolvedCity {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = name
        request.resultTypes = .address
        let search = MKLocalSearch(request: request)

        let response: MKLocalSearch.Response
        do {
            response = try await withPromptCancellation(
                start: { finish in
                    search.start { response, error in
                        if let response {
                            finish(.success(response))
                        } else {
                            finish(.failure(error ?? MKError(.unknown)))
                        }
                    }
                },
                cancel: { search.cancel() }
            )
        } catch {
            throw Self.appError(for: error)
        }

        guard let item = response.mapItems.first,
              CLLocationCoordinate2DIsValid(item.placemark.coordinate) else {
            throw AppError.cityNotFound
        }
        return ResolvedCity(
            name: item.placemark.locality ?? item.name ?? name,
            latitude: item.placemark.coordinate.latitude,
            longitude: item.placemark.coordinate.longitude
        )
    }

    static func appError(for error: Error) -> Error {
        switch RouteMetricsError.classify(error) {
        case RouteMetricsError.noRoute: return AppError.cityNotFound
        case RouteMetricsError.throttled, RouteMetricsError.serviceUnavailable: return AppError.routeServiceUnavailable
        default: return error
        }
    }
}

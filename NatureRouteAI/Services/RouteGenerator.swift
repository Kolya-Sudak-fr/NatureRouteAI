import Foundation
import CoreLocation

@MainActor
protocol RouteGenerating {
    func generateRoute(
        city: String,
        days: Int,
        placesPerDay: Int,
        preferences: [String],
        transport: TransportMode
    ) async throws -> Route
}

@MainActor
class RouteGenerator: RouteGenerating {
    
    private let networkService: NetworkService
    private let metricsProvider: RouteMetricsProviding
    private let placeSearchRadiusMeters = 50_000

    init(metricsProvider: RouteMetricsProviding? = nil, networkService: NetworkService? = nil) {
        self.networkService = networkService ?? NetworkService()
        self.metricsProvider = metricsProvider ?? MapKitRouteMetricsService()
    }
    
    // Маппинг предпочтений пользователя в категории OpenTripMap
    private func kindsFor(preference: String) -> String {
        switch preference {
        case "Mountains":      return "mountain_peaks"
        case "Forest":         return "nature_reserves"
        case "Lakes":          return "water"
        case "Waterfalls":     return "waterfalls"
        case "National Parks": return "national_parks"
        default:               return "natural"
        }
    }
    
    func generateRoute(
        city: String,
        days: Int,
        placesPerDay: Int,
        preferences: [String],
        transport: TransportMode = .walking
    ) async throws -> Route {
        guard days > 0, placesPerDay > 0, !preferences.isEmpty else {
            throw AppError.invalidRouteRequest
        }
        metricsProvider.beginPlanningSession()
        try Task.checkCancellation()
        
        // Шаг 1 — получаем реальные координаты города
        let cityCoord = try await networkService.fetchCityCoordinate(city: city)
        try Task.checkCancellation()
        
        let dayPreferences = (0..<days).map { preferences[$0 % preferences.count] }
        var seenPreferences = Set<String>()
        let uniquePreferences = dayPreferences.filter { seenPreferences.insert($0).inserted }
        var candidates: [RoutePlaceCandidate] = []
        var firstSearchError: Error?

        // Search each selected preference once, requesting enough alternatives
        // to distribute unique spots across every day that uses that preference.
        for preference in uniquePreferences {
            try Task.checkCancellation()
            let requiredForPreference = dayPreferences.filter { $0 == preference }.count * placesPerDay
            let candidateLimit = min(max(requiredForPreference * 2 + 10, requiredForPreference), 200)
            do {
                let fetchedCandidates = try await networkService.fetchPlaces(
                    lat: cityCoord.lat,
                    lon: cityCoord.lon,
                    kinds: kindsFor(preference: preference),
                    preference: preference,
                    count: candidateLimit,
                    radiusMeters: placeSearchRadiusMeters
                )
                try Task.checkCancellation()
                candidates += fetchedCandidates
            } catch AppError.noPlacesFound {
                try Task.checkCancellation()
                // Other preferences may still have valid places.
            } catch {
                try Task.checkCancellation()
                // Keep usable results from other preference searches. If every
                // search fails, preserve the API/network error for the caller.
                if firstSearchError == nil {
                    firstSearchError = error
                }
            }
        }

        if candidates.isEmpty, let firstSearchError {
            throw firstSearchError
        }

        let planningResult = try await RoutePlanningAlgorithm.distribute(
            candidates: candidates,
            dayPreferences: dayPreferences,
            placesPerDay: placesPerDay,
            transport: transport,
            originLatitude: cityCoord.lat,
            originLongitude: cityCoord.lon,
            metricsProvider: metricsProvider
        )
        try Task.checkCancellation()
        // A route cut short by MapKit would look like a shortage of places.
        if planningResult.routingInterrupted,
           planningResult.days.flatMap({ $0 }).count < days * placesPerDay {
            throw AppError.routeServiceUnavailable
        }
        let routeDays = planningResult.days.enumerated().map { index, candidates in
            RouteDay(
                dayNumber: index + 1,
                places: candidates.map {
                    Place(
                        name: $0.name,
                        type: $0.type,
                        city: city,
                        latitude: $0.latitude,
                        longitude: $0.longitude
                    )
                }
            )
        }

        guard routeDays.contains(where: { !$0.places.isEmpty }) else {
            if planningResult.hadServiceFailure {
                throw AppError.routeServiceUnavailable
            }
            if planningResult.requestLimitReached {
                throw AppError.routePlanningLimitReached
            }
            if !candidates.isEmpty, transport != .publicTransport {
                throw AppError.noRouteablePlaces
            }
            throw AppError.noPlacesFound
        }

        return Route(city: city, days: routeDays, transport: transport)
    }
}

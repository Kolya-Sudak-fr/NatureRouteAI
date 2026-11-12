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
    private let cityGeocoder: CityGeocoding
    private let metricsProvider: RouteMetricsProviding
    private let placeSearchRadiusMeters = 50_000

    init(
        metricsProvider: RouteMetricsProviding? = nil,
        networkService: NetworkService? = nil,
        cityGeocoder: CityGeocoding? = nil
    ) {
        self.cityGeocoder = cityGeocoder ?? MapKitCityGeocoder()
        self.networkService = networkService ?? NetworkService()
        self.metricsProvider = metricsProvider ?? MapKitRouteMetricsService()
    }
    
    // Маппинг предпочтений пользователя в категории OpenTripMap
    private func kindsFor(preference: String) -> String {
        TripInterest(title: preference)?.openTripMapKinds ?? "natural"
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
        let resolvedCity = try await cityGeocoder.resolveCity(named: city)
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
                    lat: resolvedCity.latitude,
                    lon: resolvedCity.longitude,
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
            originLatitude: resolvedCity.latitude,
            originLongitude: resolvedCity.longitude,
            metricsProvider: metricsProvider
        )
        try Task.checkCancellation()
        // A route cut short by MapKit would look like a shortage of places.
        if planningResult.routingInterrupted,
           planningResult.days.flatMap({ $0 }).count < days * placesPerDay {
            throw AppError.routeServiceUnavailable
        }
        // With too few places, the last days stay empty. Saying "3 days" for a
        // two-day route would be wrong, so they are dropped.
        var plannedDays = planningResult.days
        while plannedDays.last?.isEmpty == true {
            plannedDays.removeLast()
        }
        let routeDays = plannedDays.enumerated().map { index, candidates in
            RouteDay(
                dayNumber: index + 1,
                places: candidates.map { candidate in
                    let place = Place(
                        name: candidate.name,
                        type: candidate.type,
                        city: resolvedCity.name,
                        latitude: candidate.latitude,
                        longitude: candidate.longitude
                    )
                    place.legDistanceMeters = candidate.legMetrics?.distanceMeters
                    place.legTravelTime = candidate.legMetrics?.expectedTravelTime
                    return place
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

        return Route(city: resolvedCity.name, days: routeDays, transport: transport)
    }
}

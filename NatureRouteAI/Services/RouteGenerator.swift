import Foundation
import CoreLocation

class RouteGenerator {
    
    private let networkService = NetworkService()
    private let placeSearchRadiusMeters = 50_000
    
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
        
        // Шаг 1 — получаем реальные координаты города
        let cityCoord = try await networkService.fetchCityCoordinate(city: city)
        
        var routeDays: [RouteDay] = []
        
        for day in 1...days {
            
            // Берём предпочтение для этого дня по кругу
            let preference = preferences[(day - 1) % preferences.count]
            let kinds = kindsFor(preference: preference)
            
            // Шаг 2 — получаем реальные места
            // Ищем природные места независимо от выбранного транспорта.
            // Режим влияет на построение/открытие маршрута, но не на наличие POI.
            let places = try await networkService.fetchPlaces(
                lat: cityCoord.lat,
                lon: cityCoord.lon,
                kinds: kinds,
                count: placesPerDay,
                radiusMeters: placeSearchRadiusMeters
            )
            
            routeDays.append(RouteDay(dayNumber: day, places: places))
        }
        
        return Route(city: city, days: routeDays, transport: transport)
    }
}

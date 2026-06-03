import Foundation
import CoreLocation

class RouteGenerator {
    
    private let networkService = NetworkService()
    
    // Маппинг предпочтений пользователя в категории OpenTripMap
    private func kindsFor(preference: String) -> String {
        switch preference {
        case "Mountains":   return "mountain_peaks"
        case "Forest":      return "nature_reserves"
        case "Lakes":       return "lakes"
        case "Waterfalls":  return "waterfalls"
        case "National Parks": return "national_parks"
        default:            return "natural"
        }
    }
    
    func generateRoute(
        city: String,
        days: Int,
        placesPerDay: Int,
        preferences: [String]
    ) async throws -> Route {
        
        // Шаг 1 — получаем реальные координаты города
        let cityCoord = try await networkService.fetchCityCoordinate(city: city)
        
        var routeDays: [RouteDay] = []
        
        for day in 1...days {
            
            // Берём предпочтение для этого дня по кругу
            let preference = preferences[(day - 1) % preferences.count]
            let kinds = kindsFor(preference: preference)
            
            // Шаг 2 — получаем реальные места
            let places = try await networkService.fetchPlaces(
                lat: cityCoord.lat,
                lon: cityCoord.lon,
                kinds: kinds,
                count: placesPerDay
            )
            
            routeDays.append(RouteDay(dayNumber: day, places: places))
        }
        
        return Route(days: routeDays)
    }
}

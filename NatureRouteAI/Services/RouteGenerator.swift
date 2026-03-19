import Foundation
import CoreLocation

class RouteGenerator {

    private func cityCoordinate(for city: String) -> CLLocationCoordinate2D {
        switch city.lowercased() {
        case "amsterdam":
            return CLLocationCoordinate2D(latitude: 52.37, longitude: 4.89)
        case "paris":
            return CLLocationCoordinate2D(latitude: 48.85, longitude: 2.35)
        case "barcelona":
            return CLLocationCoordinate2D(latitude: 41.38, longitude: 2.15)
        case "rome":
            return CLLocationCoordinate2D(latitude: 41.90, longitude: 12.49)
        case "vienna":
            return CLLocationCoordinate2D(latitude: 48.20, longitude: 16.37)
        case "prague":
            return CLLocationCoordinate2D(latitude: 50.07, longitude: 14.43)
        case "zurich":
            return CLLocationCoordinate2D(latitude: 47.37, longitude: 8.54)
        case "lisbon":
            return CLLocationCoordinate2D(latitude: 38.71, longitude: -9.13)
        default:
            return CLLocationCoordinate2D(latitude: 48.85, longitude: 2.35)
        }
    }

    func generateRoute(
        city: String,
        days: Int,
        placesPerDay: Int,
        preferences: [String]
    ) -> Route {

        let center = cityCoordinate(for: city)
        var routeDays: [RouteDay] = []

        for day in 1...days {
            var places: [Place] = []

            for index in 1...placesPerDay {
                let randomPreference = preferences.randomElement() ?? "Nature"

                // Смещаем координату от центра города на случайное расстояние
                // 0.05 градуса ≈ 5км — реалистичный разброс для городских мест
                let lat = center.latitude  + Double.random(in: -0.05...0.05)
                let lon = center.longitude + Double.random(in: -0.05...0.05)

                let place = Place(
                    name: "\(randomPreference) Spot \(index)",
                    type: randomPreference,
                    city: city,
                    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)
                )
                places.append(place)
            }

            routeDays.append(RouteDay(dayNumber: day, places: places))
        }

        return Route(days: routeDays)
    }
}

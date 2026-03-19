import Foundation

class RouteGenerator{
    
    func generateRoute(
        city: String,
        days: Int,
        placesPerDay: Int,
        preferences: [String]
    ) -> Route{
        
        var routeDays: [RouteDay] = []
        
        for day in 1...days{
            
            var places: [Place] = []
            
            for index in 1...placesPerDay{
                
                let randomPreference = preferences.randomElement() ?? "Nature"
                
                let place = Place(
                    name: "\(randomPreference) Spot \(index)",
                    type: randomPreference,
                    city: city) 
                places.append(place)
            }
            
            let routeDay = RouteDay(
                dayNumber: day,
                places: places
            )
            routeDays.append(routeDay)
        }
        return Route(days: routeDays)
    }
}

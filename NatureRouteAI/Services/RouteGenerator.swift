import Foundation

class RouteGeneretator{
    
    func generateRoute(
        city: String,
        days: Int,
        placesperday: Int,
        preferences: [String]
    ) -> Route{
        
        var routeDays: [RouteDay] = []
        
        for day in 1...days{
            
            var places: [String] = []
            
            for index in 1...placesperday{
                
                let randomPreference = preferences.randomElement() ?? "Nature"
                
                let place = "\(randomPreference) Spot \(index) in \(city)"
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

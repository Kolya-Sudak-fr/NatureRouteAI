import Foundation
import CoreLocation
import SwiftData

@Model class Route: Identifiable {
    var id: UUID = UUID()
    var city: String?
    var createdAt: Date = Date()
    /// Транспорт для маршрута (walking/cycling/car). Optional — миграция старых записей не ломается
    var transport: String? = TransportMode.walking.rawValue
    @Relationship(deleteRule: .cascade) var days: [RouteDay]

    var transportMode: TransportMode {
        get { TransportMode(rawValue: transport ?? TransportMode.walking.rawValue) ?? .walking }
        set { transport = newValue.rawValue }
    }

    init(city: String? = nil, days: [RouteDay], transport: TransportMode = .walking) {
        self.city = city
        self.days = days
        self.transport = transport.rawValue
    }
}

@Model class RouteDay: Identifiable {
    var id: UUID = UUID()
    var dayNumber: Int
    @Relationship(deleteRule: .cascade) var places: [Place]

    /// SwiftData doesn't keep the order of a to-many relationship, so the
    /// planned stop order is stored on each place.
    var orderedPlaces: [Place] {
        places.sorted { $0.position < $1.position }
    }

    init(dayNumber: Int, places: [Place]) {
        for (index, place) in places.enumerated() {
            place.position = index
        }
        self.dayNumber = dayNumber
        self.places = places
    }
}

@Model class Place: Identifiable {
    var id = UUID()
    var name: String
    var type: String
    var city: String?
    var latitude: Double
    var longitude: Double
    /// Default value lets routes saved before this field existed migrate.
    var position: Int = 0
    @Transient var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    init(name: String, type: String, city: String? = nil, latitude: Double, longitude: Double) {
        self.name = name
        self.type = type
        self.city = city
        self.latitude = latitude
        self.longitude = longitude
    }
    

}

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

    init(dayNumber: Int, places: [Place]) {
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
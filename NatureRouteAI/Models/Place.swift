import Foundation
import CoreLocation

struct Place: Identifiable {
    let id = UUID()
    let name: String
    let type: String
    let city: String
    let latitude: Double
    let longitude: Double
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

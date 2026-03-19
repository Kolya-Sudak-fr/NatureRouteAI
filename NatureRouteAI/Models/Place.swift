import Foundation
import CoreLocation

struct Place: Identifiable {
    let id = UUID()
    let name: String
    let type: String
    let city: String
    let coordinate: CLLocationCoordinate2D
}

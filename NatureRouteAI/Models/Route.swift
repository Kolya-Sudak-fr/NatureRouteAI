import Foundation

struct Route {
    let days: [RouteDay]
}

struct RouteDay: Identifiable {
    let id = UUID()
    let dayNumber: Int
    let places: [String]
}

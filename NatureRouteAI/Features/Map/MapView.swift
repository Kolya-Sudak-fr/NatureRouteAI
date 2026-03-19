import SwiftUI
import MapKit

struct MapView: View {

    var route: Route? = nil  // опциональный — может быть nil если маршрута ещё нет

    var allPlaces: [Place] {
        route?.days.flatMap { $0.places } ?? []  // если route nil — пустой массив
    }

    var body: some View {
        Map {
            ForEach(allPlaces) { place in
                Marker(place.name, coordinate: place.coordinate)
                    .tint(.green)
            }
        }
        .ignoresSafeArea()
    }
}

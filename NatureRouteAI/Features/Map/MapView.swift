import SwiftUI
import MapKit

struct MapView: View {
    
    var route: Route? = nil
    
    private let dayColors: [Color] = [
        .green, .blue, .orange, .purple, .red, .yellow, .cyan
    ]
    
    // Камера хранится в @State — можем обновлять программно
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 48.85, longitude: 2.35),
            span: MKCoordinateSpan(latitudeDelta: 10, longitudeDelta: 10)
        )
    )
    
    var allPlaces: [Place] {
        route?.days.flatMap { $0.places } ?? []
    }
    
    // Вычисляем регион который охватывает все точки маршрута
    var fitRegion: MKCoordinateRegion {
        guard !allPlaces.isEmpty else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 48.85, longitude: 2.35),
                span: MKCoordinateSpan(latitudeDelta: 10, longitudeDelta: 10)
            )
        }
        
        let lats = allPlaces.map { $0.coordinate.latitude }
        let lons = allPlaces.map { $0.coordinate.longitude }
        
        let center = CLLocationCoordinate2D(
            latitude: ((lats.min()! + lats.max()!) / 2),
            longitude: ((lons.min()! + lons.max()!) / 2)
        )
        
        let latDelta = max((lats.max()! - lats.min()!) * 1.5, 0.05)
        let lonDelta = max((lons.max()! - lons.min()!) * 1.5, 0.05)

        let span = MKCoordinateSpan(
            latitudeDelta: latDelta,
            longitudeDelta: lonDelta
        )
        
        return MKCoordinateRegion(center: center, span: span)
    }
    
    var body: some View {
        Map(position: $cameraPosition) {
            
            // Маркеры
            ForEach(Array((route?.days ?? []).enumerated()), id: \.element.id) { index, day in
                ForEach(day.places) { place in
                    Marker(place.name, coordinate: place.coordinate)
                        .tint(dayColors[index % dayColors.count])
                }
            }
            
            // Линии между точками
            ForEach(Array((route?.days ?? []).enumerated()), id: \.element.id) { index, day in
                let coordinates = day.places.map { $0.coordinate }
                MapPolyline(coordinates: coordinates)
                    .stroke(dayColors[index % dayColors.count], lineWidth: 3)
            }
        }
        .ignoresSafeArea()
        // Когда маршрут появляется или меняется — центрируем камеру
        .onChange(of: allPlaces.count) {
            withAnimation {
                cameraPosition = .region(fitRegion)
            }
        }
    }
}

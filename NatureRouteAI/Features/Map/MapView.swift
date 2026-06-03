import SwiftUI
import MapKit

struct MapView: View {
    
    var route: Route? = nil
    
    // Цвета для каждого дня — до 7 дней
    private let dayColors: [Color] = [
        .green, .blue, .orange, .purple, .red, .yellow, .cyan
    ]
    
    var allPlaces: [Place] {
        route?.days.flatMap { $0.places } ?? []
    }
    
    // Вычисляем регион который охватывает все точки маршрута
    var fitRegion: MKCoordinateRegion {
        guard !allPlaces.isEmpty else {
            // Если мест нет — показываем центр Европы
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 48.85, longitude: 2.35),
                span: MKCoordinateSpan(latitudeDelta: 10, longitudeDelta: 10)
            )
        }
        
        let lats = allPlaces.map { $0.coordinate.latitude }
        let lons = allPlaces.map { $0.coordinate.longitude }
        
        let minLat = lats.min()!
        let maxLat = lats.max()!
        let minLon = lons.min()!
        let maxLon = lons.max()!
        
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        
        // Добавляем отступ 0.02 чтобы маркеры не были на краю экрана
        let span = MKCoordinateSpan(
            latitudeDelta: (maxLat - minLat) + 0.02,
            longitudeDelta: (maxLon - minLon) + 0.02
        )
        
        return MKCoordinateRegion(center: center, span: span)
    }
    
    var body: some View {
        Map(initialPosition: .region(fitRegion)) {
            
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
    }
}

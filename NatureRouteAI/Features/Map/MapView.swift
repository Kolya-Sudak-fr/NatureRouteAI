import SwiftUI
import MapKit
import CoreLocation

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

    // Дорожные полилинии, построенные MKDirections (реальные дороги)
    @State private var dayRoads: [DayRoadLines] = []
    @State private var isCalculating = false
    @State private var attemptedLegCount = 0
    @State private var failedLegCount = 0

    struct DayRoadLines: Identifiable {
        let id = UUID()
        let dayIndex: Int
        var lines: [MKPolyline]
    }

    var allPlaces: [Place] {
        route?.days.flatMap { $0.places } ?? []
    }

    // Слой дорог: линии от MKDirections, цвет по номеру дня
    private var roadLayer: some MapContent {
        ForEach(dayRoads) { dayRoad in
            ForEach(Array(dayRoad.lines.enumerated()), id: \.offset) { _, line in
                MapPolyline(line)
                    .stroke(dayColors[dayRoad.dayIndex % dayColors.count], lineWidth: 4)
            }
        }
    }

    // Слой маркеров: точки мест, цвет по номеру дня
    private var markerLayer: some MapContent {
        ForEach(Array(sortedDays.enumerated()), id: \.element.id) { index, day in
            ForEach(day.places) { place in
                Marker(place.name, coordinate: place.coordinate)
                    .tint(dayColors[index % dayColors.count])
            }
        }
    }

    private var sortedDays: [RouteDay] {
        route?.days.sorted { $0.dayNumber < $1.dayNumber } ?? []
    }

    var body: some View {
        ZStack {
            Map(position: $cameraPosition) {
                // ЛИНИИ ПО РЕАЛЬНЫМ ДОРОГАМ (от MKDirections)
                roadLayer

                // Маркеры
                markerLayer
            }
            .ignoresSafeArea()

            // Индикатор построения маршрутов
            if isCalculating {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Drawing real roads...")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    .padding(12)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 28)
                }
                .transition(.opacity)
            }

            if !isCalculating, let routingMessage {
                VStack {
                    Text(routingMessage)
                        .font(.footnote)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 16)
                        .padding(.top, 58)
                    Spacer()
                }
                .transition(.opacity)
            }
        }
        .onAppear {
            if !allPlaces.isEmpty {
                cameraPosition = .region(fitRegion)
            }
            calculateRoadRoutes()
        }
        .onChange(of: route?.id) {
            dayRoads = []
            calculateRoadRoutes()
        }
    }

    // MARK: - Построение маршрута по реальным дорогам

    /// Запрашивает у MapKit дорогу между каждой парой соседних мест дня.
    /// MKDirections (.automobile) — путь строится по реальной дорожной сети Apple Maps.
    private func calculateRoadRoutes() {
        guard !sortedDays.isEmpty else {
            attemptedLegCount = 0
            failedLegCount = 0
            isCalculating = false
            return
        }
        isCalculating = true
        dayRoads = []
        attemptedLegCount = 0
        failedLegCount = 0

        Task { @MainActor in
            var result: [DayRoadLines] = []
            var attempted = 0
            var failed = 0

            for (dayIndex, day) in sortedDays.enumerated() {
                let places = day.places
                guard places.count > 1 else {
                    result.append(DayRoadLines(dayIndex: dayIndex, lines: []))
                    continue
                }

                var lines: [MKPolyline] = []
                for i in 0..<(places.count - 1) {
                    let sourceCoordinate = places[i].coordinate
                    let destinationCoordinate = places[i + 1].coordinate
                    attempted += 1
                    guard CLLocationCoordinate2DIsValid(sourceCoordinate),
                          CLLocationCoordinate2DIsValid(destinationCoordinate) else {
                        failed += 1
                        continue
                    }

                    let request = MKDirections.Request()
                    request.source = MKMapItem(location: CLLocation(
                        latitude: sourceCoordinate.latitude,
                        longitude: sourceCoordinate.longitude
                    ), address: nil)
                    request.destination = MKMapItem(location: CLLocation(
                        latitude: destinationCoordinate.latitude,
                        longitude: destinationCoordinate.longitude
                    ), address: nil)
                    switch route?.transportMode {
                    case .walking: request.transportType = .walking
                    case .cycling: request.transportType = .cycling
                    default:       request.transportType = .automobile
                    }

                    do {
                        let response = try await MKDirections(request: request).calculate()
                        if let line = response.routes.first?.polyline {
                            lines.append(line)
                        } else {
                            failed += 1
                        }
                    } catch {
                        failed += 1
                    }
                }
                result.append(DayRoadLines(dayIndex: dayIndex, lines: lines))
            }

            dayRoads = result
            attemptedLegCount = attempted
            failedLegCount = failed
            isCalculating = false

            // Перекатываем камеру, чтобы весь маршрут по дороге был виден
            withAnimation(.easeInOut(duration: 0.6)) {
                cameraPosition = .region(fitRegion)
            }
        }
    }

    private var routingMessage: String? {
        guard attemptedLegCount > 0, failedLegCount > 0 else { return nil }
        let modeName: String
        switch route?.transportMode {
        case .walking: modeName = "walking"
        case .cycling: modeName = "cycling"
        case .car, .none: modeName = "driving"
        }

        if failedLegCount == attemptedLegCount {
            return "Places were found, but MapKit couldn't build any \(modeName) route segments (\(failedLegCount)/\(attemptedLegCount)). The points remain on the map; open a stop individually from the route details."
        }
        return "MapKit couldn't build \(failedLegCount) of \(attemptedLegCount) \(modeName) route segments. All found places remain on the map; you can navigate to each stop individually."
    }

    // MARK: - Область видимости (точки + построенные дороги)

    var fitRegion: MKCoordinateRegion {
        // Собираем все точки мест
        var lats: [Double] = []
        var lons: [Double] = []
        for place in allPlaces {
            lats.append(place.coordinate.latitude)
            lons.append(place.coordinate.longitude)
        }

        // Если дороги уже построены — расширяем область до их границ,
        // чтобы маршрут по дорогам полностью входил в экран
        var roadRect: MKMapRect? = nil
        for dayRoad in dayRoads {
            for line in dayRoad.lines {
                let rect = line.boundingMapRect
                roadRect = roadRect?.union(rect) ?? rect
            }
        }
        if let roadRect, !roadRect.isEmpty {
            return MKCoordinateRegion(roadRect.insetBy(dx: -roadRect.width * 0.15, dy: -roadRect.height * 0.15))
        }

        guard !lats.isEmpty else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 48.85, longitude: 2.35),
                span: MKCoordinateSpan(latitudeDelta: 10, longitudeDelta: 10)
            )
        }

        let center = CLLocationCoordinate2D(
            latitude: ((lats.min()! + lats.max()!) / 2),
            longitude: ((lons.min()! + lons.max()!) / 2)
        )
        let latDelta = max((lats.max()! - lats.min()!) * 1.5, 0.05)
        let lonDelta = max((lons.max()! - lons.min()!) * 1.5, 0.05)

        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
        )
    }
}

#Preview {
    MapView()
}

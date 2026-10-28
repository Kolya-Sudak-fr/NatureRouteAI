import SwiftUI
import SwiftData
import MapKit
import UIKit

struct RouteDetailView: View {
    let route: Route
    @State private var showMap = false
    @State private var isShowingNavigationPicker = false
    @State private var pendingStops: [NavigationStop] = []
    @State private var pendingProgressIndex: Int?
    @State private var navigationError: String?
    @AppStorage private var nextStopIndex: Int

    // Единая палитра приложения
    private let darkBg = Color(red: 0.08, green: 0.10, blue: 0.08)
    private let cardBg = Color(red: 0.15, green: 0.18, blue: 0.15)
    private let green = Color(red: 0.2, green: 0.85, blue: 0.4)

    init(route: Route) {
        self.route = route
        _nextStopIndex = AppStorage(wrappedValue: 0, "route.navigation.\(route.id.uuidString)")
    }

    private var orderedDays: [RouteDay] {
        route.days.sorted { $0.dayNumber < $1.dayNumber }
    }

    private var orderedPlaces: [Place] {
        orderedDays.flatMap(\.places)
    }

    var body: some View {
        ZStack {
            darkBg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    HStack(spacing: 12) {
                        Image(systemName: "leaf.fill")
                            .font(.title2)
                            .foregroundColor(green)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(route.city ?? "Unknown City")
                                .font(.title)
                                .bold()
                                .foregroundColor(.white)
                            Text("Generated on \(route.createdAt.formatted(date: .abbreviated, time: .omitted))")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                        Spacer()
                    }

                    // Summary chips
                    HStack(spacing: 10) {
                        InfoChip(icon: route.transportMode.systemIcon, text: route.transportMode.displayName)
                        InfoChip(icon: "calendar", text: "\(route.days.count) days")
                        InfoChip(icon: "mappin", text: "\(totalPlaces) places")
                    }

                    if let nextStop = orderedPlaces[safe: nextStopIndex] {
                        VStack(spacing: 10) {
                            Button {
                                prepareNavigation(to: nextStop, progressIndex: nextStopIndex)
                            } label: {
                                Label("Следующая остановка", systemImage: "arrow.turn.up.right")
                                    .font(.headline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.black)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 15)
                                    .background(green, in: RoundedRectangle(cornerRadius: 14))
                            }

                            Text("Далее: \(nextStop.name)")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        Label("Все остановки пройдены", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(green)
                    }

                    if orderedPlaces[safe: nextStopIndex] != nil {
                        Button {
                            startCurrentDayRoute()
                        } label: {
                            Label("Начать маршрут", systemImage: "play.fill")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(cardBg, in: RoundedRectangle(cornerRadius: 14))
                        }
                    }

                    Text("Google Maps включает до четырёх остановок в одной ссылке. Для продолжения откройте следующую точку из NatureRouteAI.")
                        .font(.caption)
                        .foregroundColor(.gray)

                    // Days List (sorted by day number)
                    ForEach(orderedDays) { day in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Day \(day.dayNumber)")
                                    .font(.headline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                Spacer()
                                Image(systemName: "calendar")
                                    .font(.subheadline)
                                    .foregroundColor(green)
                            }

                            if day.places.isEmpty {
                                Text("No places planned for this day.")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            } else {
                                ForEach(Array(day.places.enumerated()), id: \.element.id) { index, place in
                                    HStack(spacing: 10) {
                                        Text("\(index + 1)")
                                            .font(.caption)
                                            .fontWeight(.bold)
                                            .foregroundColor(.black)
                                            .frame(width: 22, height: 22)
                                            .background(Circle().fill(green))
                                        Text(place.name)
                                            .font(.subheadline)
                                            .foregroundColor(.white)
                                        Spacer()
                                        Text(place.type)
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                        Button {
                                            prepareNavigation(to: place, progressIndex: nil)
                                        } label: {
                                            Image(systemName: "arrow.turn.up.right")
                                                .foregroundColor(green)
                                                .padding(.leading, 6)
                                        }
                                        .accessibilityLabel("Navigate to \(place.name)")
                                    }
                                }
                            }
                        }
                        .padding(16)
                        .background(cardBg)
                        .cornerRadius(16)
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle("Route")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(darkBg, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showMap = true
                } label: {
                    Image(systemName: "map.fill")
                        .foregroundColor(green)
                }
            }
        }
        .sheet(isPresented: $showMap) {
            ZStack {
                MapView(route: route)
            }
            .overlay(alignment: .topTrailing) {
                Button {
                    showMap = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Circle().fill(Color.black.opacity(0.65)))
                }
                .padding(.trailing, 16)
                .padding(.top, 60)
            }
        }
        .confirmationDialog("Открыть навигацию", isPresented: $isShowingNavigationPicker, titleVisibility: .visible) {
            ForEach(NavigationProvider.allCases) { provider in
                Button(provider.title) {
                    openNavigation(using: provider)
                }
            }
            Button("Отмена", role: .cancel) { }
        } message: {
            Text("Маршрут откроется для режима «\(route.transportMode.displayName)».")
        }
        .alert("Не удалось открыть навигатор", isPresented: Binding(
            get: { navigationError != nil },
            set: { if !$0 { navigationError = nil } }
        )) {
            Button("OK", role: .cancel) { navigationError = nil }
        } message: {
            Text(navigationError ?? "Попробуйте ещё раз.")
        }
    }

    var totalPlaces: Int {
        route.days.reduce(0) { $0 + $1.places.count }
    }

    private func prepareNavigation(to place: Place, progressIndex: Int?) {
        prepareNavigation(to: [place], progressIndex: progressIndex)
    }

    private func startCurrentDayRoute() {
        guard let currentPlace = orderedPlaces[safe: nextStopIndex],
              let day = orderedDays.first(where: { $0.places.contains(where: { $0.id == currentPlace.id }) }),
              let startIndex = day.places.firstIndex(where: { $0.id == currentPlace.id }) else {
            navigationError = NavigationLinkError.noStops.localizedDescription
            return
        }
        prepareNavigation(to: Array(day.places.dropFirst(startIndex)), progressIndex: nextStopIndex)
    }

    private func prepareNavigation(to places: [Place], progressIndex: Int?) {
        do {
            pendingStops = try places.map {
                try NavigationStop(name: $0.name, latitude: $0.latitude, longitude: $0.longitude)
            }
            guard !pendingStops.isEmpty else { throw NavigationLinkError.noStops }
            pendingProgressIndex = progressIndex
            isShowingNavigationPicker = true
        } catch {
            navigationError = error.localizedDescription
        }
    }

    private func openNavigation(using provider: NavigationProvider) {
        do {
            let url = try RouteNavigationLinks.url(
                for: provider,
                stops: pendingStops,
                transport: route.transportMode
            )
            Task { @MainActor in
                let didOpen = await UIApplication.shared.open(url)
                guard didOpen else {
                    navigationError = "\(provider.title) is unavailable. Check the link and try again."
                    return
                }
                if let pendingProgressIndex {
                    nextStopIndex = pendingProgressIndex + 1
                }
            }
        } catch {
            navigationError = error.localizedDescription
        }
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Small info chip
struct InfoChip: View {
    let icon: String
    let text: String

    private let chipBg = Color(red: 0.15, green: 0.18, blue: 0.15)
    private let green = Color(red: 0.2, green: 0.85, blue: 0.4)

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(chipBg))
            .overlay(Capsule().stroke(green.opacity(0.3), lineWidth: 1))
    }
}

#Preview {
    NavigationStack {
        RouteDetailView(route: Route(city: "Amsterdam", days: [
            RouteDay(dayNumber: 1, places: [Place(name: "Place 1", type: "Nature", latitude: 52.3, longitude: 4.8)])
        ]))
    }
}

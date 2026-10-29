import Foundation
import Combine
import SwiftData

@MainActor
class RoutePlannerViewModel: ObservableObject {

    // Всё что раньше было @State в View — теперь здесь
    @Published var preferences: [NaturePreference] = [
        NaturePreference(title: "Mountains", isSelected: false),
        NaturePreference(title: "Forest", isSelected: false),
        NaturePreference(title: "Lakes", isSelected: false),
        NaturePreference(title: "Waterfalls", isSelected: false),
        NaturePreference(title: "National Parks", isSelected: false),
    ]
    @Published private(set) var savedRouteIDs: Set<UUID> = []
    @Published var city: String = ""
    @Published var tripDays: Int = 3
    @Published var placesPerDay: Int = 3
    @Published var transport: TransportMode = .walking
    @Published var route: Route?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    // View спрашивает ViewModel — можно ли нажать кнопку
    var canGenerate: Bool {
        !city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && preferences.contains { $0.isSelected }
            && !isLoading
    }

    var selectedPreferences: [NaturePreference] {
        preferences.filter { $0.isSelected }
    }

    private let generator = RouteGenerator()

    init(initialCity: String = "", initialPreference: String? = nil) {
        city = initialCity
        if let initialPreference,
           let index = preferences.firstIndex(where: { $0.title == initialPreference }) {
            preferences[index].isSelected = true
        }
    }

    func isSaved(in context: ModelContext) -> Bool {
        guard let route else { return false }
        if savedRouteIDs.contains(route.id) { return true }

        let routeID = route.id
        let descriptor = FetchDescriptor<Route>(predicate: #Predicate { $0.id == routeID })
        return (try? context.fetch(descriptor).isEmpty) == false
    }

    // Вся логика генерации теперь здесь, не в View
    func generateRoute() {
        guard !isLoading else { return }
        let requestedCity = city.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedDays = tripDays
        let requestedPlacesPerDay = placesPerDay
        let requestedPreferences = selectedPreferences.map(\.title)
        let requestedTransport = transport

        isLoading = true
        errorMessage = nil
        route = nil

        Task {
            do {
                let generatedRoute = try await generator.generateRoute(
                    city: requestedCity,
                    days: requestedDays,
                    placesPerDay: requestedPlacesPerDay,
                    preferences: requestedPreferences,
                    transport: requestedTransport
                )
                route = generatedRoute
                let requestedCount = requestedDays * requestedPlacesPerDay
                let availableCount = generatedRoute.days.reduce(0) { $0 + $1.places.count }
                if availableCount < requestedCount {
                    errorMessage = "Only \(availableCount) unique, routeable nature spots could be planned for the \(requestedCount) requested places. This partial route keeps every stop unique."
                }
            } catch let appError as AppError {
                errorMessage = appError.userMessage
            } catch let urlError as URLError where Self.isConnectionError(urlError) {
                errorMessage = AppError.noInternetConnection.userMessage
            } catch {
                errorMessage = AppError.unknown.userMessage
            }
            isLoading = false
        }
    }

    func saveRoute(context: ModelContext) {
        guard let sourceRoute = route else { return }
        let routeID = sourceRoute.id
        guard !savedRouteIDs.contains(routeID) else { return }

        // Keep a failed save isolated from the view's context so a later save
        // cannot accidentally persist this route along with unrelated changes.
        let persistenceContext = ModelContext(context.container)
        let descriptor = FetchDescriptor<Route>(predicate: #Predicate { $0.id == routeID })
        do {
            if try !persistenceContext.fetch(descriptor).isEmpty {
                savedRouteIDs.insert(routeID)
                return
            }

            persistenceContext.insert(persistentCopy(of: sourceRoute))
            try persistenceContext.save()
            savedRouteIDs.insert(routeID)
        } catch {
            persistenceContext.rollback()
            errorMessage = "Failed to save route: \(error.localizedDescription)"
        }
    }

    private func persistentCopy(of route: Route) -> Route {
        let copiedDays = route.days.map { day in
            let copiedPlaces = day.places.map { place in
                let copy = Place(
                    name: place.name,
                    type: place.type,
                    city: place.city,
                    latitude: place.latitude,
                    longitude: place.longitude
                )
                copy.id = place.id
                return copy
            }
            let copy = RouteDay(dayNumber: day.dayNumber, places: copiedPlaces)
            copy.id = day.id
            return copy
        }
        let copy = Route(city: route.city, days: copiedDays, transport: route.transportMode)
        copy.id = route.id
        copy.createdAt = route.createdAt
        copy.transport = route.transport
        return copy
    }

    private static func isConnectionError(_ error: URLError) -> Bool {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost,
             .cannotFindHost, .dnsLookupFailed, .timedOut:
            return true
        default:
            return false
        }
    }
}

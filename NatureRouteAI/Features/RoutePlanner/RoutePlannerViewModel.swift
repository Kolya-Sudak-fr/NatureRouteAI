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
    @Published private(set) var isCancelling = false
    @Published var errorMessage: String?

    // 7 × 5 = 35 stops stays within RoutePlanningAlgorithm.defaultRequestBudget.
    static let tripDaysRange = 1...7
    static let placesPerDayRange = 1...5

    // View спрашивает ViewModel — можно ли нажать кнопку
    var canGenerate: Bool {
        !city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && preferences.contains { $0.isSelected }
            && !isLoading
    }

    var selectedPreferences: [NaturePreference] {
        preferences.filter { $0.isSelected }
    }

    private let generator: RouteGenerating
    private var generationTask: Task<Void, Never>?
    private var generationID = UUID()

    init(initialCity: String = "", initialPreference: String? = nil, generator: RouteGenerating? = nil) {
        if let generator {
            self.generator = generator
        } else {
            self.generator = RouteGenerator()
        }
        city = initialCity
        if let initialPreference,
           let index = preferences.firstIndex(where: { $0.title == initialPreference }) {
            var updatedPreferences = preferences
            updatedPreferences[index].isSelected = true
            preferences = updatedPreferences
        }
    }

    func setPreferenceSelection(at index: Int, isSelected: Bool) {
        guard preferences.indices.contains(index) else { return }
        var updatedPreferences = preferences
        updatedPreferences[index].isSelected = isSelected
        preferences = updatedPreferences
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
        guard !isLoading || isCancelling else { return }
        generationTask?.cancel()
        let currentGenerationID = UUID()
        generationID = currentGenerationID
        let requestedCity = city.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedDays = tripDays
        let requestedPlacesPerDay = placesPerDay
        let requestedPreferences = selectedPreferences.map(\.title)
        let requestedTransport = transport

        isLoading = true
        isCancelling = false
        errorMessage = nil
        route = nil

        generationTask = Task {
            defer {
                if generationID == currentGenerationID {
                    isLoading = false
                    isCancelling = false
                    generationTask = nil
                }
            }
            do {
                let generatedRoute = try await generator.generateRoute(
                    city: requestedCity,
                    days: requestedDays,
                    placesPerDay: requestedPlacesPerDay,
                    preferences: requestedPreferences,
                    transport: requestedTransport
                )
                try Task.checkCancellation()
                guard generationID == currentGenerationID else { return }
                route = generatedRoute
                let requestedCount = requestedDays * requestedPlacesPerDay
                let availableCount = generatedRoute.days.reduce(0) { $0 + $1.places.count }
                if availableCount < requestedCount {
                    errorMessage = "Only \(availableCount) unique nature spots could be added to the requested \(requestedCount)-stop plan. This partial route keeps every stop unique."
                }
            } catch where Task.isCancelled {
                // The user cancelled, so a late answer from the service isn't news.
                guard generationID == currentGenerationID else { return }
                errorMessage = nil
            } catch let appError as AppError {
                guard generationID == currentGenerationID else { return }
                errorMessage = appError.userMessage
            } catch is CancellationError {
                guard generationID == currentGenerationID else { return }
                errorMessage = nil
            } catch let urlError as URLError where urlError.code == .cancelled {
                guard generationID == currentGenerationID else { return }
                errorMessage = nil
            } catch let urlError as URLError where Self.isConnectionError(urlError) {
                guard generationID == currentGenerationID else { return }
                errorMessage = AppError.noInternetConnection.userMessage
            } catch {
                guard generationID == currentGenerationID else { return }
                errorMessage = AppError.unknown.userMessage
            }
        }
    }

    func cancelGeneration() {
        guard isLoading, !isCancelling else { return }
        isCancelling = true
        errorMessage = nil
        generationTask?.cancel()
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
            let copiedPlaces = day.orderedPlaces.map { place in
                let copy = Place(
                    name: place.name,
                    type: place.type,
                    city: place.city,
                    latitude: place.latitude,
                    longitude: place.longitude
                )
                copy.id = place.id
                copy.legDistanceMeters = place.legDistanceMeters
                copy.legTravelTime = place.legTravelTime
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

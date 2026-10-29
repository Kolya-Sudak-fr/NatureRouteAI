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
        !city.isEmpty && preferences.contains { $0.isSelected } && !isLoading
    }

    var selectedPreferences: [NaturePreference] {
        preferences.filter { $0.isSelected }
    }

    private let generator = RouteGenerator()
    private var pendingRouteIDs: Set<UUID> = []

    func isSaved(in context: ModelContext) -> Bool {
        guard let route else { return false }
        if savedRouteIDs.contains(route.id) { return true }
        if pendingRouteIDs.contains(route.id) { return false }

        let routeID = route.id
        let descriptor = FetchDescriptor<Route>(predicate: #Predicate { $0.id == routeID })
        return (try? context.fetch(descriptor).isEmpty) == false
    }

    // Вся логика генерации теперь здесь, не в View
    func generateRoute() {
        isLoading = true
        errorMessage = nil
        route = nil

        Task {
            do {
                route = try await generator.generateRoute(
                    city: city,
                    days: tripDays,
                    placesPerDay: placesPerDay,
                    preferences: selectedPreferences.map { $0.title },
                    transport: transport
                )
                if let route {
                    let requestedCount = tripDays * placesPerDay
                    let availableCount = route.days.reduce(0) { $0 + $1.places.count }
                    if availableCount < requestedCount {
                        errorMessage = "Only \(availableCount) unique nature spots were found for \(requestedCount) requested places. This partial route keeps every stop unique."
                    }
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

        // Detect routes already persisted by this or another ViewModel instance.
        if !pendingRouteIDs.contains(routeID) {
            let descriptor = FetchDescriptor<Route>(predicate: #Predicate { $0.id == routeID })
            do {
                if try !context.fetch(descriptor).isEmpty {
                    savedRouteIDs.insert(routeID)
                    return
                }
            } catch {
                errorMessage = "Failed to check saved routes: \(error.localizedDescription)"
                return
            }

            context.insert(sourceRoute)
            pendingRouteIDs.insert(routeID)
        }

        do {
            try context.save()
            pendingRouteIDs.remove(routeID)
            savedRouteIDs.insert(routeID)
        } catch {
            errorMessage = "Failed to save route: \(error.localizedDescription)"
        }
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

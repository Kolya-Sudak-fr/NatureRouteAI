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

    var isSaved: Bool {
        guard let route else { return false }
        return savedRouteIDs.contains(route.id)
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

        // Не вставляем один объект повторно, если предыдущий context.save завершился ошибкой.
        if pendingRouteIDs.insert(routeID).inserted {
            context.insert(sourceRoute)
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

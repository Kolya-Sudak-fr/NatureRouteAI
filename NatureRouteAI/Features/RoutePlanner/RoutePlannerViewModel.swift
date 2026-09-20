import Foundation
import Combine

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

    @Published var city: String = ""
    @Published var tripDays: Int = 3
    @Published var placesPerDay: Int = 3
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

    // Вся логика генерации теперь здесь, не в View
    func generateRoute() {
        let selected = preferences
            .filter { $0.isSelected }
            .map { $0.title }

        isLoading = true
        errorMessage = nil
        route = nil

        // Task — запускает async код из обычного контекста.
                // Сетевой запрос нельзя запустить напрямую из функции — нужен Task.
                // @MainActor выше гарантирует что когда Task завершится
                // и мы обновим route или errorMessage — это произойдёт на main thread.
        Task {
            do {
                route = try await generator.generateRoute(
                    city: city,
                    days: tripDays,
                    placesPerDay: placesPerDay,
                    preferences: selected
                )
            } catch {
                errorMessage = "Could not generate route. Check the city name and try again."
            }
            isLoading = false
        }
    }
}

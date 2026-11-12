import Foundation

/// Один вариант маршрута из тех, что предлагает ассистент.
struct RouteOption: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let route: Route
}

@MainActor
protocol RouteOptionsPlanning {
    func options(for request: TripRequest, transport: TransportMode) async throws -> [RouteOption]
}

/// Строит до трёх маршрутов из одного запроса, без уточняющих вопросов.
///
/// Варианты отличаются темпом и набором интересов:
/// - Balanced: все интересы, 3 остановки в день;
/// - Focused: только первый интерес, 4 остановки в день (если интерес один, вариант не добавляем);
/// - Relaxed: все интересы, на день больше, 2 остановки в день.
///
/// Маршруты строятся по очереди. Каждый тратит лимит запросов MapKit,
/// и параллельные запросы быстрее упираются в этот лимит.
@MainActor
final class RouteOptionsPlanner: RouteOptionsPlanning {

    private let generator: RouteGenerating
    private let defaultDays = 2

    init(generator: RouteGenerating) {
        self.generator = generator
    }

    func options(for request: TripRequest, transport: TransportMode) async throws -> [RouteOption] {
        guard let city = request.city?.trimmingCharacters(in: .whitespacesAndNewlines), !city.isEmpty else {
            throw AppError.cityNotFound
        }
        let variants = Self.variants(
            interests: request.interestsOrDefault,
            days: request.days ?? defaultDays
        )

        var options: [RouteOption] = []
        var firstError: Error?
        for variant in variants {
            try Task.checkCancellation()
            do {
                let route = try await generator.generateRoute(
                    city: city,
                    days: variant.days,
                    placesPerDay: variant.placesPerDay,
                    preferences: variant.preferences,
                    transport: transport
                )
                options.append(RouteOption(title: variant.title, subtitle: variant.subtitle, route: route))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Один неудачный вариант не отменяет остальные.
                if firstError == nil { firstError = error }
            }
        }

        if options.isEmpty, let firstError {
            throw firstError
        }
        return options
    }

    struct Variant: Equatable {
        let title: String
        let preferences: [String]
        let days: Int
        let placesPerDay: Int

        var subtitle: String {
            "\(days) \(days == 1 ? "day" : "days") · \(placesPerDay) stops a day"
        }
    }

    static func variants(interests: [TripInterest], days: Int) -> [Variant] {
        let allTitles = interests.map(\.title)
        let tripDays = min(max(days, 1), 7)
        var result = [Variant(title: "Balanced", preferences: allTitles, days: tripDays, placesPerDay: 3)]

        if interests.count > 1, let first = interests.first {
            result.append(Variant(
                title: "Focused: \(first.title)",
                preferences: [first.title],
                days: tripDays,
                placesPerDay: 4
            ))
        }

        result.append(Variant(
            title: "Relaxed",
            preferences: allTitles,
            days: min(tripDays + 1, 7),
            placesPerDay: 2
        ))
        return result
    }
}

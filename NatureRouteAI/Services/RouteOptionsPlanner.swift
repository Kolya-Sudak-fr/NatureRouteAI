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
/// Варианты отличаются длиной, а не интересами: все они берут все интересы запроса.
/// - Shorter: 2 остановки в день;
/// - Standard: 3 остановки в день;
/// - Longer: 4 остановки в день.
///
/// Места не повторяются между вариантами: каждый следующий вариант пропускает места,
/// уже показанные предыдущими. Поэтому Standard строится первым и получает лучшие места.
/// Маршруты строятся по очереди, потому что каждый тратит лимит запросов MapKit.
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

        var built: [(placesPerDay: Int, option: RouteOption)] = []
        var firstError: Error?
        // Places already used by an earlier option. Later options skip them, so the
        // variants offer different stops instead of the same ones in another order.
        var usedPlaceNames = Set<String>()
        for variant in variants {
            try Task.checkCancellation()
            do {
                let route = try await generator.generateRoute(
                    city: city,
                    days: variant.days,
                    placesPerDay: variant.placesPerDay,
                    preferences: variant.preferences,
                    transport: transport,
                    excludingPlaceNames: usedPlaceNames
                )
                usedPlaceNames.formUnion(route.days.flatMap(\.places).map(\.name))
                built.append((
                    variant.placesPerDay,
                    RouteOption(title: variant.title, subtitle: variant.subtitle, route: route)
                ))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Один неудачный вариант не отменяет остальные.
                if firstError == nil { firstError = error }
            }
        }

        if built.isEmpty, let firstError {
            throw firstError
        }
        // Show the options from shortest to longest, whatever order they were built in.
        return built.sorted { $0.placesPerDay < $1.placesPerDay }.map(\.option)
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

    /// Standard идёт первым: он получает лучшие места, остальные обходят их.
    static func variants(interests: [TripInterest], days: Int) -> [Variant] {
        let allTitles = interests.map(\.title)
        let tripDays = min(max(days, 1), 7)
        return [
            Variant(title: "Standard", preferences: allTitles, days: tripDays, placesPerDay: 3),
            Variant(title: "Shorter", preferences: allTitles, days: tripDays, placesPerDay: 2),
            Variant(title: "Longer", preferences: allTitles, days: tripDays, placesPerDay: 4)
        ]
    }
}

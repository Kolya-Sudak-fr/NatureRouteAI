import XCTest
@testable import NatureRouteAI

@MainActor
final class RouteOptionsPlannerTests: XCTestCase {

    func testBuildsThreeDistinctOptionsForSeveralInterests() async throws {
        let generator = RecordingRouteGenerator()
        let planner = RouteOptionsPlanner(generator: generator)

        let options = try await planner.options(
            for: TripRequest(city: "Middelburg", interests: [.castlesAndAbbeys, .historicSites], days: nil),
            transport: .car
        )

        XCTAssertEqual(options.map(\.title), ["Balanced", "Focused: Castles & Abbeys", "Relaxed"])
        XCTAssertEqual(generator.calls.map(\.days), [2, 2, 3])
        XCTAssertEqual(generator.calls.map(\.placesPerDay), [3, 4, 2])
        XCTAssertEqual(generator.calls.map(\.preferences), [
            ["Castles & Abbeys", "Historic Sites"],
            ["Castles & Abbeys"],
            ["Castles & Abbeys", "Historic Sites"]
        ])
        XCTAssertTrue(generator.calls.allSatisfy { $0.city == "Middelburg" && $0.transport == .car })
    }

    func testSingleInterestSkipsTheFocusedVariant() async throws {
        let generator = RecordingRouteGenerator()
        let planner = RouteOptionsPlanner(generator: generator)

        let options = try await planner.options(
            for: TripRequest(city: "Innsbruck", interests: [.lakes], days: 1),
            transport: .car
        )

        XCTAssertEqual(options.map(\.title), ["Balanced", "Relaxed"])
        XCTAssertEqual(generator.calls.map(\.days), [1, 2])
    }

    func testUsesEveryInterestWhenNoneWereNamed() async throws {
        let generator = RecordingRouteGenerator()
        let planner = RouteOptionsPlanner(generator: generator)

        _ = try await planner.options(for: TripRequest(city: "Leiden", interests: [], days: nil), transport: .car)

        XCTAssertEqual(generator.calls.first?.preferences, TripInterest.allCases.map(\.title))
    }

    func testFailedVariantIsDroppedWhileOthersSucceed() async throws {
        let generator = RecordingRouteGenerator()
        generator.errorsByCall = [2: AppError.noPlacesFound]
        let planner = RouteOptionsPlanner(generator: generator)

        let options = try await planner.options(
            for: TripRequest(city: "Middelburg", interests: [.castlesAndAbbeys, .historicSites], days: nil),
            transport: .car
        )

        XCTAssertEqual(options.map(\.title), ["Balanced", "Relaxed"])
    }

    func testThrowsWhenEveryVariantFails() async {
        let generator = RecordingRouteGenerator()
        generator.errorsByCall = [1: AppError.noPlacesFound, 2: AppError.noPlacesFound, 3: AppError.noPlacesFound]
        let planner = RouteOptionsPlanner(generator: generator)

        do {
            _ = try await planner.options(
                for: TripRequest(city: "Middelburg", interests: [.castlesAndAbbeys, .historicSites], days: nil),
                transport: .car
            )
            XCTFail("Expected the first error when no option could be built")
        } catch AppError.noPlacesFound {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testMissingCityIsReportedBeforeAnyRouteIsBuilt() async {
        let generator = RecordingRouteGenerator()
        let planner = RouteOptionsPlanner(generator: generator)

        do {
            _ = try await planner.options(for: TripRequest(city: nil, interests: [.lakes], days: nil), transport: .car)
            XCTFail("A request without a city must not reach the generator")
        } catch AppError.cityNotFound {
            XCTAssertTrue(generator.calls.isEmpty)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCancellationStopsTheRemainingVariants() async {
        let generator = RecordingRouteGenerator()
        generator.errorsByCall = [1: CancellationError()]
        let planner = RouteOptionsPlanner(generator: generator)

        do {
            _ = try await planner.options(
                for: TripRequest(city: "Middelburg", interests: [.castlesAndAbbeys, .historicSites], days: nil),
                transport: .car
            )
            XCTFail("Cancellation should reach the caller")
        } catch is CancellationError {
            XCTAssertEqual(generator.calls.count, 1, "No further routes should be requested after cancellation")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    /// Async on purpose: a synchronous test that releases a @MainActor test double
    /// crashes inside the Swift runtime's main-actor deinit path (malloc pointer error).
    func testPlannerOffersHistoricCategories() async {
        let viewModel = RoutePlannerViewModel(generator: RecordingRouteGenerator())
        let titles = viewModel.preferences.map(\.title)

        XCTAssertTrue(titles.contains("Castles & Abbeys"))
        XCTAssertTrue(titles.contains("Historic Sites"))
        XCTAssertEqual(titles.count, TripInterest.allCases.count)
    }

    func testEveryInterestMapsBackToItsPlannerCategory() {
        for interest in TripInterest.allCases {
            XCTAssertEqual(TripInterest(title: interest.title), interest)
        }
    }
}

/// Записывает, с какими параметрами его вызвали, и отдаёт маршрут с одной остановкой.
@MainActor
private final class RecordingRouteGenerator: RouteGenerating {

    struct Call: Equatable {
        let city: String
        let days: Int
        let placesPerDay: Int
        let preferences: [String]
        let transport: TransportMode
    }

    private(set) var calls: [Call] = []
    /// Номер вызова (с 1) → ошибка, которую нужно бросить на этом вызове.
    var errorsByCall: [Int: Error] = [:]

    func generateRoute(
        city: String,
        days: Int,
        placesPerDay: Int,
        preferences: [String],
        transport: TransportMode
    ) async throws -> Route {
        calls.append(Call(
            city: city,
            days: days,
            placesPerDay: placesPerDay,
            preferences: preferences,
            transport: transport
        ))
        if let error = errorsByCall[calls.count] {
            throw error
        }
        let stop = Place(name: "Stop \(calls.count)", type: preferences.first ?? "", latitude: 51.5, longitude: 3.6)
        return Route(city: city, days: [RouteDay(dayNumber: 1, places: [stop])], transport: transport)
    }
}

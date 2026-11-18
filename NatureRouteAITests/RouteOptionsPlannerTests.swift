import XCTest
@testable import NatureRouteAI

@MainActor
final class RouteOptionsPlannerTests: XCTestCase {

    func testBuildsShorterStandardAndLongerOptions() async throws {
        let generator = RecordingRouteGenerator()
        let planner = RouteOptionsPlanner(generator: generator)

        let options = try await planner.options(
            for: TripRequest(city: "Middelburg", interests: [.castlesAndAbbeys, .historicSites], days: nil),
            transport: .car
        )

        XCTAssertEqual(options.map(\.title), ["Shorter", "Standard", "Longer"])
        // Standard is built first, so it keeps the best stops and the others skip them.
        XCTAssertEqual(generator.calls.map(\.placesPerDay), [3, 2, 4])
        XCTAssertEqual(generator.calls.map(\.days), [2, 2, 2])
        XCTAssertTrue(generator.calls.allSatisfy { $0.preferences == ["Castles & Abbeys", "Historic Sites"] })
        XCTAssertTrue(generator.calls.allSatisfy { $0.city == "Middelburg" && $0.transport == .car })
    }

    func testSingleInterestStillBuildsThreeOptionsOfThatInterest() async throws {
        let generator = RecordingRouteGenerator()
        let planner = RouteOptionsPlanner(generator: generator)

        let options = try await planner.options(
            for: TripRequest(city: "Innsbruck", interests: [.lakes], days: 1),
            transport: .car
        )

        XCTAssertEqual(options.map(\.title), ["Shorter", "Standard", "Longer"])
        XCTAssertTrue(generator.calls.allSatisfy { $0.days == 1 && $0.preferences == ["Lakes"] })
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

        XCTAssertEqual(options.map(\.title), ["Standard", "Longer"])
    }

    /// A route with fewer stops than asked for would be a "Longer" route with one stop.
    func testOptionWithFewerStopsThanRequestedIsNotOffered() async throws {
        let generator = RecordingRouteGenerator()
        generator.shortRouteCalls = [3]
        let planner = RouteOptionsPlanner(generator: generator)

        let options = try await planner.options(
            for: TripRequest(city: "Middelburg", interests: [.castlesAndAbbeys, .historicSites], days: nil),
            transport: .car
        )

        XCTAssertEqual(options.map(\.title), ["Shorter", "Standard"])
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

    func testLaterOptionsSkipPlacesAlreadyOffered() async throws {
        let generator = RecordingRouteGenerator()
        let planner = RouteOptionsPlanner(generator: generator)

        _ = try await planner.options(
            for: TripRequest(city: "Utrecht", interests: [.castlesAndAbbeys, .historicSites], days: nil),
            transport: .car
        )

        // Standard (2 days × 3 stops) is built first; Shorter (2 × 2) skips its six stops,
        // and Longer (2 × 4) skips the ten stops of the first two.
        XCTAssertEqual(generator.calls[0].excludedNames, [])
        XCTAssertEqual(generator.calls[1].excludedNames, Set((1...6).map { "Stop \($0)" }))
        XCTAssertEqual(generator.calls[2].excludedNames, Set((1...10).map { "Stop \($0)" }))
    }

    func testStalledOptionIsDroppedAfterTheTotalTimeout() async throws {
        let generator = StallingRouteGenerator(stallFromCall: 2)
        let planner = RouteOptionsPlanner(generator: generator, totalTimeout: .milliseconds(300))
        let started = ContinuousClock.now

        let options = try await planner.options(
            for: TripRequest(city: "Utrecht", interests: [.castlesAndAbbeys], days: 1),
            transport: .car
        )

        XCTAssertEqual(options.map(\.title), ["Standard"], "The option that finished in time is kept")
        XCTAssertLessThan(ContinuousClock.now - started, .seconds(5))
    }

    func testThrowsServiceUnavailableWhenNothingFinishesInTime() async {
        let generator = StallingRouteGenerator(stallFromCall: 1)
        let planner = RouteOptionsPlanner(generator: generator, totalTimeout: .milliseconds(300))

        do {
            _ = try await planner.options(
                for: TripRequest(city: "Utrecht", interests: [.castlesAndAbbeys], days: 1),
                transport: .car
            )
            XCTFail("Expected service unavailable when no option finished in time")
        } catch AppError.routeServiceUnavailable {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testVariantBudgetKeepsTheWholeBatchUnderTheMapKitMinuteLimit() {
        // MapKit allows about 50 directions requests a minute. The options are built back to back.
        XCTAssertLessThanOrEqual(RouteOptionsPlanner.requestBudgetPerVariant * 3, 30)
    }

    func testEveryInterestMapsBackToItsPlannerCategory() {
        for interest in TripInterest.allCases {
            XCTAssertEqual(TripInterest(title: interest.title), interest)
        }
    }
}

/// Записывает параметры каждого вызова и отдаёт маршрут с полным числом остановок.
/// Имена остановок уникальны на протяжении всех вызовов.
@MainActor
private final class RecordingRouteGenerator: RouteGenerating {

    struct Call: Equatable {
        let city: String
        let days: Int
        let placesPerDay: Int
        let preferences: [String]
        let transport: TransportMode
        let excludedNames: Set<String>
    }

    private(set) var calls: [Call] = []
    /// Номер вызова (с 1) → ошибка, которую нужно бросить на этом вызове.
    var errorsByCall: [Int: Error] = [:]
    /// Номера вызовов, на которых маршрут возвращается с одной остановкой.
    var shortRouteCalls: Set<Int> = []
    private var stopCounter = 0

    func generateRoute(
        city: String,
        days: Int,
        placesPerDay: Int,
        preferences: [String],
        transport: TransportMode
    ) async throws -> Route {
        try await generateRoute(
            city: city,
            days: days,
            placesPerDay: placesPerDay,
            preferences: preferences,
            transport: transport,
            excludingPlaceNames: []
        )
    }

    func generateRoute(
        city: String,
        days: Int,
        placesPerDay: Int,
        preferences: [String],
        transport: TransportMode,
        excludingPlaceNames: Set<String>
    ) async throws -> Route {
        calls.append(Call(
            city: city,
            days: days,
            placesPerDay: placesPerDay,
            preferences: preferences,
            transport: transport,
            excludedNames: excludingPlaceNames
        ))
        let callNumber = calls.count
        if let error = errorsByCall[callNumber] {
            throw error
        }
        let stopsWanted = shortRouteCalls.contains(callNumber) ? 1 : days * placesPerDay
        var dayRoutes: [RouteDay] = []
        var remaining = stopsWanted
        for dayNumber in 1...max(days, 1) where remaining > 0 {
            var places: [Place] = []
            for _ in 0..<min(placesPerDay, remaining) {
                stopCounter += 1
                places.append(Place(name: "Stop \(stopCounter)", type: preferences.first ?? "", latitude: 51.5, longitude: 3.6))
            }
            remaining -= places.count
            dayRoutes.append(RouteDay(dayNumber: dayNumber, places: places))
        }
        return Route(city: city, days: dayRoutes, transport: transport)
    }
}

/// Answers quickly until `stallFromCall`, then never answers, like a stuck MapKit request.
@MainActor
private final class StallingRouteGenerator: RouteGenerating {
    private(set) var calls = 0
    private let stallFromCall: Int

    init(stallFromCall: Int) {
        self.stallFromCall = stallFromCall
    }

    func generateRoute(
        city: String,
        days: Int,
        placesPerDay: Int,
        preferences: [String],
        transport: TransportMode
    ) async throws -> Route {
        calls += 1
        if calls >= stallFromCall {
            try await Task.sleep(for: .seconds(60))
        }
        let places = (0..<(days * placesPerDay)).map { index in
            Place(name: "Stop \(calls)-\(index)", type: "castles", latitude: 51.5, longitude: 3.6)
        }
        return Route(city: city, days: [RouteDay(dayNumber: 1, places: places)], transport: transport)
    }
}

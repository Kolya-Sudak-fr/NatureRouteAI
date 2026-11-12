import XCTest
@testable import NatureRouteAI

@MainActor
final class HomeTripAssistantViewModelTests: XCTestCase {

    func testEmptyInputDoesNothing() async {
        let viewModel = makeViewModel(parse: TripRequest(city: "Leiden", interests: [.lakes], days: nil))
        viewModel.input = "   "

        await viewModel.submit()

        XCTAssertTrue(isIdle(viewModel.phase))
    }

    func testMessageWithCityGoesStraightToTransportChoice() async {
        let viewModel = makeViewModel(parse: TripRequest(city: "Middelburg", interests: [.castlesAndAbbeys], days: 2))
        viewModel.input = "I'm in Middelburg, castles for 2 days"

        await viewModel.submit()

        guard case .chooseTransport(let request) = viewModel.phase else {
            return XCTFail("Expected transport choice, got \(viewModel.phase)")
        }
        XCTAssertEqual(request.city, "Middelburg")
        XCTAssertEqual(request.days, 2)
    }

    func testMessageWithoutCityAsksOnlyForTheCity() async {
        let viewModel = makeViewModel(parse: TripRequest(city: nil, interests: [.castlesAndAbbeys], days: nil))
        viewModel.input = "хочу замки и аббатства"

        await viewModel.submit()

        guard case .needsCity(let request) = viewModel.phase else {
            return XCTFail("Expected a city question, got \(viewModel.phase)")
        }
        XCTAssertEqual(request.interests, [.castlesAndAbbeys])
    }

    func testAnsweringTheCityMovesOnToTransportChoice() async {
        let viewModel = makeViewModel(parse: TripRequest(city: nil, interests: [.lakes], days: nil))
        viewModel.input = "lakes please"
        await viewModel.submit()

        viewModel.provideCity("  Leiden ")

        guard case .chooseTransport(let request) = viewModel.phase else {
            return XCTFail("Expected transport choice after the city answer")
        }
        XCTAssertEqual(request.city, "Leiden")
    }

    func testBlankCityAnswerKeepsAskingForCity() async {
        let viewModel = makeViewModel(parse: TripRequest(city: nil, interests: [.lakes], days: nil))
        viewModel.input = "lakes please"
        await viewModel.submit()

        viewModel.provideCity("   ")

        guard case .needsCity = viewModel.phase else {
            return XCTFail("A blank city must not move the flow forward")
        }
    }

    func testChoosingCarBuildsAndShowsRouteOptions() async {
        let planner = StubRouteOptionsPlanner(result: .success([
            RouteOption(title: "Balanced", subtitle: "2 days", route: Route(city: "Middelburg", days: [], transport: .car)),
            RouteOption(title: "Relaxed", subtitle: "3 days", route: Route(city: "Middelburg", days: [], transport: .car))
        ]))
        let viewModel = makeViewModel(parse: TripRequest(city: "Middelburg", interests: [.castlesAndAbbeys], days: nil), planner: planner)
        viewModel.input = "castles in Middelburg"
        await viewModel.submit()

        await viewModel.choose(.car)

        guard case .ready(let options) = viewModel.phase else {
            return XCTFail("Expected ready options, got \(viewModel.phase)")
        }
        XCTAssertEqual(options.map(\.title), ["Balanced", "Relaxed"])
        XCTAssertEqual(planner.requestedTransport, .car)
        XCTAssertEqual(planner.requestedCity, "Middelburg")
    }

    func testPlannerFailureShowsItsMessage() async {
        let planner = StubRouteOptionsPlanner(result: .failure(AppError.noPlacesFound))
        let viewModel = makeViewModel(parse: TripRequest(city: "Leiden", interests: [.lakes], days: nil), planner: planner)
        viewModel.input = "lakes in Leiden"
        await viewModel.submit()

        await viewModel.choose(.car)

        guard case .failed(let message) = viewModel.phase else {
            return XCTFail("Expected a failure message, got \(viewModel.phase)")
        }
        XCTAssertEqual(message, AppError.noPlacesFound.userMessage)
    }

    func testChoosingTransportBeforeCityIsIgnored() async {
        let planner = StubRouteOptionsPlanner(result: .success([]))
        let viewModel = makeViewModel(parse: TripRequest(city: nil, interests: [], days: nil), planner: planner)
        viewModel.input = "something"
        await viewModel.submit()

        await viewModel.choose(.car)

        XCTAssertEqual(planner.callCount, 0)
    }

    func testCancelledBuildReturnsToTransportChoice() async {
        let planner = StubRouteOptionsPlanner(result: .success([]))
        planner.waitsUntilCancelled = true
        let viewModel = makeViewModel(parse: TripRequest(city: "Leiden", interests: [.lakes], days: nil), planner: planner)
        viewModel.input = "lakes in Leiden"
        await viewModel.submit()

        let building = Task { await viewModel.choose(.car) }
        while !isBuilding(viewModel.phase) {
            await Task.yield()
        }
        viewModel.cancelBuilding()
        await building.value

        guard case .chooseTransport = viewModel.phase else {
            return XCTFail("Cancelling must go back to the transport choice, got \(viewModel.phase)")
        }
    }

    func testDismissingTransportChoiceKeepsTheText() async {
        let viewModel = makeViewModel(parse: TripRequest(city: "Leiden", interests: [.lakes], days: nil))
        viewModel.input = "lakes in Leiden"
        await viewModel.submit()

        viewModel.dismissTransportChoice()

        XCTAssertTrue(isIdle(viewModel.phase))
        XCTAssertEqual(viewModel.input, "lakes in Leiden")
    }

    func testResetClearsTextAndPhase() async {
        let viewModel = makeViewModel(parse: TripRequest(city: "Leiden", interests: [.lakes], days: nil))
        viewModel.input = "lakes in Leiden"
        await viewModel.submit()

        viewModel.reset()

        XCTAssertTrue(isIdle(viewModel.phase))
        XCTAssertEqual(viewModel.input, "")
    }

    func testRouteTotalsSummarisesStopsDistanceAndTime() {
        let first = Place(name: "Abbey", type: "monasteries", latitude: 51.5, longitude: 3.6)
        first.legDistanceMeters = 12_000
        first.legTravelTime = 1_800
        let second = Place(name: "Castle", type: "castles", latitude: 51.6, longitude: 3.7)
        second.legDistanceMeters = 8_000
        second.legTravelTime = 1_800
        let route = Route(city: "Middelburg", days: [RouteDay(dayNumber: 1, places: [first, second])], transport: .car)

        XCTAssertTrue(RouteOptionsView.totals(for: route).hasPrefix("2 stops · 20 km"))
    }

    // MARK: - Helpers

    private func makeViewModel(
        parse request: TripRequest,
        planner: StubRouteOptionsPlanner? = nil
    ) -> HomeTripAssistantViewModel {
        let planner = planner ?? StubRouteOptionsPlanner(result: .success([]))
        return HomeTripAssistantViewModel(parser: FixedRequestParser(request: request), planner: planner)
    }

    private func isIdle(_ phase: HomeTripAssistantViewModel.Phase) -> Bool {
        if case .idle = phase { return true }
        return false
    }

    private func isBuilding(_ phase: HomeTripAssistantViewModel.Phase) -> Bool {
        if case .building = phase { return true }
        return false
    }
}

private struct FixedRequestParser: TripRequestParsing {
    let request: TripRequest

    func parse(_ text: String) async throws -> TripRequest {
        request
    }
}

@MainActor
private final class StubRouteOptionsPlanner: RouteOptionsPlanning {
    let result: Result<[RouteOption], Error>
    var waitsUntilCancelled = false
    private(set) var callCount = 0
    private(set) var requestedCity: String?
    private(set) var requestedTransport: TransportMode?

    init(result: Result<[RouteOption], Error>) {
        self.result = result
    }

    func options(for request: TripRequest, transport: TransportMode) async throws -> [RouteOption] {
        callCount += 1
        requestedCity = request.city
        requestedTransport = transport
        if waitsUntilCancelled {
            try await Task.sleep(for: .seconds(60))
        }
        return try result.get()
    }
}

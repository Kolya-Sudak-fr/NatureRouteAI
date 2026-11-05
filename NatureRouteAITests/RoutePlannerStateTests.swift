import XCTest
import SwiftData
@testable import NatureRouteAI

@MainActor
final class RoutePlannerStateTests: XCTestCase {
    func testTransportSelectionIsStoredIndependentlyFromViewAnimation() async {
        let generator = StubRouteGenerator(result: .waitForCancellation)
        let viewModel = RoutePlannerViewModel(generator: generator)

        viewModel.transport = .cycling

        XCTAssertEqual(viewModel.transport, .cycling)
    }

    func testSaveStateChangesOnlyAfterPersistenceSucceeds() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Route.self, RouteDay.self, Place.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        let generator = StubRouteGenerator(result: .waitForCancellation)
        let viewModel = RoutePlannerViewModel(generator: generator)
        let route = Route(city: "Utrecht", days: [
            RouteDay(dayNumber: 1, places: [
                Place(name: "Forest", type: "nature_reserves", latitude: 52.1, longitude: 5.1)
            ])
        ])
        viewModel.route = route

        XCTAssertFalse(viewModel.isSaved(in: context))

        viewModel.saveRoute(context: context)

        XCTAssertTrue(viewModel.isSaved(in: context))
        let rereadContext = ModelContext(container)
        XCTAssertEqual(try rereadContext.fetch(FetchDescriptor<Route>()).map(\.id), [route.id])
    }

    func testViewModelSavePersistsRouteAcrossContainerReload() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("Routes.store")
        let schema = Schema([Route.self, RouteDay.self, Place.self])
        let configuration = ModelConfiguration(schema: schema, url: storeURL, allowsSave: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let route = Route(city: "Amsterdam", days: [
            RouteDay(dayNumber: 1, places: [Place(name: "Canal park", type: "water", latitude: 52.1, longitude: 5.1)])
        ])
        let generator = StubRouteGenerator(result: .waitForCancellation)
        let viewModel = RoutePlannerViewModel(generator: generator)
        viewModel.route = route

        viewModel.saveRoute(context: ModelContext(container))

        let reopened = try ModelContainer(for: schema, configurations: [configuration])
        let saved = try XCTUnwrap(ModelContext(reopened).fetch(FetchDescriptor<Route>()).first)
        XCTAssertEqual(saved.id, route.id)
        XCTAssertEqual(saved.days.first?.places.first?.name, "Canal park")
    }

    func testSavingAnotherRouteDoesNotDependOnThePreviousSaveOrDuplicateIt() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Route.self, RouteDay.self, Place.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        let generator = StubRouteGenerator(result: .waitForCancellation)
        let viewModel = RoutePlannerViewModel(generator: generator)
        let cyclingRoute = Route(city: "Amsterdam", days: [
            RouteDay(dayNumber: 1, places: [
                Place(name: "Forest", type: "nature_reserves", latitude: 52.1, longitude: 5.1)
            ])
        ], transport: .cycling)
        let drivingRoute = Route(city: "Amsterdam", days: [
            RouteDay(dayNumber: 1, places: [
                Place(name: "Lake", type: "water", latitude: 52.2, longitude: 5.2)
            ])
        ], transport: .car)

        viewModel.route = cyclingRoute
        viewModel.saveRoute(context: context)
        viewModel.saveRoute(context: context)
        viewModel.route = drivingRoute
        viewModel.saveRoute(context: context)

        let storedRoutes = try ModelContext(container).fetch(FetchDescriptor<Route>())
        XCTAssertEqual(storedRoutes.count, 2)
        XCTAssertEqual(Set(storedRoutes.map(\.id)), [cyclingRoute.id, drivingRoute.id])
        XCTAssertEqual(Set(storedRoutes.compactMap(\.transport)), [TransportMode.cycling.rawValue, TransportMode.car.rawValue])
    }

    func testGenerateRequiresCityAndAtLeastOnePreference() async {
        let generator = StubRouteGenerator(result: .waitForCancellation)
        let viewModel = RoutePlannerViewModel(
            initialCity: "  ",
            generator: generator
        )
        XCTAssertFalse(viewModel.canGenerate)

        viewModel.city = "Amsterdam"
        XCTAssertFalse(viewModel.canGenerate)

        viewModel.setPreferenceSelection(at: 0, isSelected: true)
        XCTAssertTrue(viewModel.canGenerate)
    }

    func testGenerationRejectsReentryAndCancellationKeepsBusyStateUntilTaskStops() async {
        let generator = StubRouteGenerator(result: .waitForCancellation)
        let viewModel = makeReadyViewModel(generator: generator)

        viewModel.generateRoute()
        await waitForGeneratorCall(generator)
        XCTAssertEqual(generator.callCount, 1)

        viewModel.generateRoute()
        await Task.yield()
        XCTAssertEqual(generator.callCount, 1)

        viewModel.cancelGeneration()
        XCTAssertTrue(viewModel.isLoading)
        XCTAssertTrue(viewModel.isCancelling)

        await waitForCompletion(viewModel)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.route)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testCancelledGenerationCannotPublishAfterNewGenerationStarts() async {
        let generator = ContinuationRouteGenerator()
        let viewModel = makeReadyViewModel(generator: generator)
        let oldRoute = Route(city: "Old result", days: [])
        let newRoute = Route(city: "New result", days: [])

        viewModel.generateRoute()
        await waitForGeneratorCallCount(generator, 1)
        viewModel.cancelGeneration()
        viewModel.generateRoute()
        await waitForGeneratorCallCount(generator, 2)

        generator.succeedCall(0, with: oldRoute)
        await Task.yield()
        XCTAssertNil(viewModel.route)
        XCTAssertTrue(viewModel.isLoading)

        generator.succeedCall(1, with: newRoute)
        await waitForCompletion(viewModel)
        XCTAssertEqual(viewModel.route?.city, "New result")
    }

    func testGenerationSuccessAndFailureSetSeparateStates() async {
        let generated = Route(city: "Amsterdam", days: [
            RouteDay(dayNumber: 1, places: [
                Place(name: "Park", type: "nature_reserves", latitude: 52.1, longitude: 5.1)
            ])
        ])
        let successViewModel = makeReadyViewModel(generator: StubRouteGenerator(result: .success(generated)))
        successViewModel.tripDays = 1
        successViewModel.placesPerDay = 1
        successViewModel.generateRoute()
        await waitForCompletion(successViewModel)
        XCTAssertNotNil(successViewModel.route)
        XCTAssertNil(successViewModel.errorMessage)

        let failureViewModel = makeReadyViewModel(generator: StubRouteGenerator(result: .failure(AppError.cityNotFound)))
        failureViewModel.generateRoute()
        await waitForCompletion(failureViewModel)
        XCTAssertNil(failureViewModel.route)
        XCTAssertEqual(failureViewModel.errorMessage, AppError.cityNotFound.userMessage)

        let timeoutViewModel = makeReadyViewModel(generator: StubRouteGenerator(result: .failure(URLError(.timedOut))))
        timeoutViewModel.generateRoute()
        await waitForCompletion(timeoutViewModel)
        XCTAssertNil(timeoutViewModel.route)
        XCTAssertEqual(timeoutViewModel.errorMessage, AppError.noInternetConnection.userMessage)
    }

    func testPartialPublicTransportPlanDoesNotClaimInternalRoutingSucceeded() async {
        let partialRoute = Route(city: "Amsterdam", days: [
            RouteDay(dayNumber: 1, places: [
                Place(name: "Canal park", type: "nature_reserves", latitude: 52.1, longitude: 5.1)
            ]),
            RouteDay(dayNumber: 2, places: [])
        ], transport: .publicTransport)
        let viewModel = makeReadyViewModel(generator: StubRouteGenerator(result: .success(partialRoute)))
        viewModel.transport = .publicTransport
        viewModel.tripDays = 2
        viewModel.placesPerDay = 2

        viewModel.generateRoute()
        await waitForCompletion(viewModel)

        XCTAssertNotNil(viewModel.route)
        XCTAssertTrue(viewModel.errorMessage?.contains("Only 1 unique nature spots") == true)
        XCTAssertFalse(viewModel.errorMessage?.localizedCaseInsensitiveContains("routeable") == true)
    }

    private func makeReadyViewModel(generator: RouteGenerating) -> RoutePlannerViewModel {
        let viewModel = RoutePlannerViewModel(initialCity: "Amsterdam", generator: generator)
        viewModel.setPreferenceSelection(at: 0, isSelected: true)
        return viewModel
    }

    private func waitForCompletion(_ viewModel: RoutePlannerViewModel) async {
        for _ in 0..<100 where viewModel.isLoading {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private func waitForGeneratorCall(_ generator: StubRouteGenerator) async {
        for _ in 0..<100 where generator.callCount == 0 {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    private func waitForGeneratorCallCount(_ generator: ContinuationRouteGenerator, _ count: Int) async {
        for _ in 0..<100 where generator.callCount < count {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertEqual(generator.callCount, count)
    }
}

@MainActor
private final class ContinuationRouteGenerator: RouteGenerating {
    private(set) var callCount = 0
    private var continuations: [Int: CheckedContinuation<Route, Error>] = [:]

    func generateRoute(
        city: String,
        days: Int,
        placesPerDay: Int,
        preferences: [String],
        transport: TransportMode
    ) async throws -> Route {
        let index = callCount
        callCount += 1
        return try await withCheckedThrowingContinuation { continuations[index] = $0 }
    }

    func succeedCall(_ index: Int, with route: Route) {
        continuations.removeValue(forKey: index)?.resume(returning: route)
    }
}

@MainActor
private final class StubRouteGenerator: RouteGenerating {
    enum Result {
        case success(Route)
        case failure(Error)
        case waitForCancellation
    }

    let result: Result
    private(set) var callCount = 0

    init(result: Result) { self.result = result }

    func generateRoute(
        city: String,
        days: Int,
        placesPerDay: Int,
        preferences: [String],
        transport: TransportMode
    ) async throws -> Route {
        callCount += 1
        switch result {
        case .success(let route): return route
        case .failure(let error): throw error
        case .waitForCancellation:
            try await Task.sleep(for: .seconds(10))
            throw CancellationError()
        }
    }
}

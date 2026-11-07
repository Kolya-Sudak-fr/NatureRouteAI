import Foundation
import MapKit
import SwiftData
import XCTest
@testable import NatureRouteAI

@MainActor
struct StubCityGeocoder: CityGeocoding {
    func resolveCity(named name: String) async throws -> ResolvedCity {
        ResolvedCity(name: "Resolved \(name)", latitude: 52, longitude: 5)
    }
}

/// Answers OpenTripMap requests without a network.
nonisolated final class StubOpenTripMapProtocol: URLProtocol {
    nonisolated(unsafe) static var respond: (URLRequest) -> (Int, String) = { _ in (200, places(count: 0)) }
    nonisolated(unsafe) static var requests: [URLRequest] = []

    static func places(count: Int, prefix: String = "Spot") -> String {
        let features = (0..<count).map { index in
            #"{"geometry":{"coordinates":[\#(5 + Double(index) * 0.1),52]},"properties":{"name":"\#(prefix) \#(index)","xid":"\#(prefix)-\#(index)","rate":3}}"#
        }
        return #"{"features":[\#(features.joined(separator: ","))]}"#
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        Self.requests.append(request)
        let (status, body) = Self.respond(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

@MainActor
final class RouteQualityTests: XCTestCase {
    private let metrics = RouteMetrics(distanceMeters: 2_500, expectedTravelTime: 1_800)

    override func setUp() async throws {
        StubOpenTripMapProtocol.requests = []
    }

    // MARK: - Duplicates

    func testSameNameUnderDifferentIDsCloseTogetherIsOnePlace() {
        let unique = RoutePlanningAlgorithm.uniqueCandidates([
            candidate(id: "a", name: "Brekkefossen", longitude: 0.01, preferences: ["Lakes"]),
            candidate(id: "b", name: "BREKKEFOSSEN ", longitude: 0.011, preferences: ["Waterfalls"])
        ])

        XCTAssertEqual(unique.count, 1)
        XCTAssertEqual(unique[0].preferences, ["Lakes", "Waterfalls"])
    }

    func testAccentsDoNotHideADuplicate() {
        let unique = RoutePlanningAlgorithm.uniqueCandidates([
            candidate(id: "a", name: "Årvollåsen", longitude: 0.01),
            candidate(id: "b", name: "Arvollasen", longitude: 0.012)
        ])

        XCTAssertEqual(unique.count, 1)
    }

    func testSameNameFarApartStaysTwoPlaces() {
        let unique = RoutePlanningAlgorithm.uniqueCandidates([
            candidate(id: "a", name: "Hazenberg", longitude: 0.01),
            candidate(id: "b", name: "Hazenberg", longitude: 0.1)
        ])

        XCTAssertEqual(unique.count, 2)
    }

    func testLongerNameAtTheSameSpotIsOnePlace() {
        let unique = RoutePlanningAlgorithm.uniqueCandidates([
            candidate(id: "a", name: "Ekeberg naturreservat", longitude: 0.01),
            candidate(id: "b", name: "Ekeberg", longitude: 0.0105)
        ])

        XCTAssertEqual(unique.count, 1)
    }

    // MARK: - Empty days

    func testDayWhosePreferenceRanOutUsesAnotherSelectedCategory() async throws {
        let result = try await RoutePlanningAlgorithm.distribute(
            candidates: (1...4).map { candidate(id: "f\($0)", name: "Forest \($0)", longitude: Double($0) * 0.01, preferences: ["Forest"]) },
            dayPreferences: ["Forest", "Lakes"],
            placesPerDay: 2,
            transport: .walking,
            originLatitude: 0,
            originLongitude: 0,
            metricsProvider: FixedMetricsProvider(metrics: metrics)
        )

        XCTAssertEqual(result.days.map(\.count), [2, 2])
    }

    func testLastDaysWithoutPlacesAreDroppedFromTheRoute() async throws {
        StubOpenTripMapProtocol.respond = { _ in (200, StubOpenTripMapProtocol.places(count: 2)) }
        let route = try await makeGenerator().generateRoute(
            city: "Testville", days: 3, placesPerDay: 2, preferences: ["Forest"], transport: .walking
        )

        XCTAssertEqual(route.days.map(\.dayNumber), [1])
    }

    // MARK: - City

    func testRouteIsNamedAfterTheResolvedCity() async throws {
        StubOpenTripMapProtocol.respond = { _ in (200, StubOpenTripMapProtocol.places(count: 20)) }
        let route = try await makeGenerator().generateRoute(
            city: "Amster", days: 1, placesPerDay: 1, preferences: ["Forest"], transport: .walking
        )

        XCTAssertEqual(route.city, "Resolved Amster")
        XCTAssertEqual(route.days[0].places[0].city, "Resolved Amster")
    }

    func testGeocoderErrorsMapToUserFacingErrors() {
        XCTAssertEqual(userMessage(MKError(.placemarkNotFound)), AppError.cityNotFound.userMessage)
        XCTAssertEqual(userMessage(MKError(.loadingThrottled)), AppError.routeServiceUnavailable.userMessage)
        XCTAssertEqual(userMessage(URLError(.notConnectedToInternet)), AppError.routeServiceUnavailable.userMessage)
        XCTAssertTrue(MapKitCityGeocoder.appError(for: CancellationError()) is CancellationError)
    }

    // MARK: - Place search

    func testSearchAsksTheServerForRatedPlacesFirst() async throws {
        StubOpenTripMapProtocol.respond = { _ in (200, StubOpenTripMapProtocol.places(count: 16)) }

        let places = try await makeNetwork().fetchPlaces(lat: 52, lon: 5, kinds: "water", preference: "Lakes", count: 16)

        XCTAssertEqual(places.count, 16)
        XCTAssertEqual(StubOpenTripMapProtocol.requests.count, 1)
        XCTAssertTrue(StubOpenTripMapProtocol.requests[0].url?.query?.contains("rate=1") == true)
    }

    func testTooFewRatedPlacesAddsUnratedOnes() async throws {
        StubOpenTripMapProtocol.respond = { request in
            request.url?.query?.contains("rate=1") == true
                ? (200, StubOpenTripMapProtocol.places(count: 2, prefix: "Rated"))
                : (200, StubOpenTripMapProtocol.places(count: 3, prefix: "Unrated"))
        }

        let places = try await makeNetwork().fetchPlaces(lat: 52, lon: 5, kinds: "water", preference: "Lakes", count: 16)

        XCTAssertEqual(places.count, 5)
        XCTAssertEqual(places[0].name, "Rated 0")
        XCTAssertEqual(places[2].sourceOrder, 2)
    }

    func testRatedPlacesSurviveAFailedUnratedSearch() async throws {
        StubOpenTripMapProtocol.respond = { request in
            request.url?.query?.contains("rate=1") == true
                ? (200, StubOpenTripMapProtocol.places(count: 2))
                : (500, "")
        }

        let places = try await makeNetwork().fetchPlaces(lat: 52, lon: 5, kinds: "water", preference: "Lakes", count: 16)

        XCTAssertEqual(places.count, 2)
    }

    func testRateLimitedRequestIsRetriedOnce() async throws {
        var attempts = 0
        StubOpenTripMapProtocol.respond = { _ in
            attempts += 1
            return attempts == 1 ? (429, "") : (200, StubOpenTripMapProtocol.places(count: 16))
        }

        let places = try await makeNetwork().fetchPlaces(lat: 52, lon: 5, kinds: "water", preference: "Lakes", count: 16)

        XCTAssertEqual(places.count, 16)
        XCTAssertEqual(attempts, 2)
    }

    func testPersistentRateLimitIsReported() async {
        StubOpenTripMapProtocol.respond = { _ in (429, "") }

        do {
            _ = try await makeNetwork().fetchPlaces(lat: 52, lon: 5, kinds: "water", preference: "Lakes", count: 16)
            XCTFail("Expected an error")
        } catch let error as AppError {
            XCTAssertTrue(error.userMessage.contains("busy"))
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    // MARK: - Metrics

    func testEveryStopKeepsItsLegMetrics() async throws {
        let result = try await RoutePlanningAlgorithm.distribute(
            candidates: (1...3).map { candidate(id: "s\($0)", name: "Stop \($0)", longitude: Double($0) * 0.01) },
            dayPreferences: ["Nature"],
            placesPerDay: 3,
            transport: .walking,
            originLatitude: 0,
            originLongitude: 0,
            metricsProvider: FixedMetricsProvider(metrics: metrics)
        )

        XCTAssertEqual(result.days[0].map(\.legMetrics), [metrics, metrics, metrics])
    }

    func testPublicTransportHasNoInventedMetrics() async throws {
        StubOpenTripMapProtocol.respond = { _ in (200, StubOpenTripMapProtocol.places(count: 20)) }
        let route = try await makeGenerator().generateRoute(
            city: "Testville", days: 1, placesPerDay: 2, preferences: ["Forest"], transport: .publicTransport
        )

        XCTAssertNil(route.days[0].totalDistanceMeters)
        XCTAssertNil(RouteLegFormatter.summary(distanceMeters: route.days[0].totalDistanceMeters, travelTime: route.days[0].totalTravelTime))
    }

    func testMetricsSurviveSavingAndReopening() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("Metrics.store")
        let schema = Schema([Route.self, RouteDay.self, Place.self])
        func openContainer() throws -> ModelContainer {
            try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: storeURL, allowsSave: true)])
        }

        let place = Place(name: "Stop", type: "water", latitude: 52, longitude: 5)
        place.legDistanceMeters = 2_500
        place.legTravelTime = 1_800
        let viewModel = RoutePlannerViewModel(initialCity: "Metrics", generator: RouteGenerator(metricsProvider: FixedMetricsProvider(metrics: metrics), cityGeocoder: StubCityGeocoder()))
        viewModel.route = Route(city: "Metrics", days: [RouteDay(dayNumber: 1, places: [place])])
        viewModel.saveRoute(context: ModelContext(try openContainer()))
        XCTAssertNil(viewModel.errorMessage)

        let reopened = try XCTUnwrap(ModelContext(try openContainer()).fetch(FetchDescriptor<Route>()).first)
        XCTAssertEqual(reopened.days[0].totalDistanceMeters, 2_500)
        XCTAssertEqual(reopened.days[0].totalTravelTime, 1_800)
    }

    func testLegSummaryNeedsBothValues() {
        XCTAssertNil(RouteLegFormatter.summary(distanceMeters: nil, travelTime: 60))
        XCTAssertNil(RouteLegFormatter.summary(distanceMeters: 100, travelTime: nil))
        XCTAssertNotNil(RouteLegFormatter.summary(distanceMeters: 100, travelTime: 60))
    }

    // MARK: - Helpers

    private func userMessage(_ error: Error) -> String? {
        (MapKitCityGeocoder.appError(for: error) as? AppError)?.userMessage
    }

    private func makeNetwork() -> NetworkService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubOpenTripMapProtocol.self]
        return NetworkService(apiKey: "test", session: URLSession(configuration: configuration), rateLimitRetryDelay: .milliseconds(1))
    }

    private func makeGenerator() -> RouteGenerator {
        RouteGenerator(metricsProvider: FixedMetricsProvider(metrics: metrics), networkService: makeNetwork(), cityGeocoder: StubCityGeocoder())
    }

    private func candidate(id: String?, name: String, longitude: Double, preferences: Set<String> = ["Nature"]) -> RoutePlaceCandidate {
        RoutePlaceCandidate(
            externalID: id,
            name: name,
            type: "natural",
            latitude: 0,
            longitude: longitude,
            preferences: preferences,
            quality: 3,
            sourceOrder: 0
        )
    }
}

@MainActor
private struct FixedMetricsProvider: RouteMetricsProviding {
    let metrics: RouteMetrics

    func metrics(from latitude: Double, longitude: Double, to candidate: RoutePlaceCandidate, transport: TransportMode) async throws -> RouteMetrics {
        metrics
    }
}

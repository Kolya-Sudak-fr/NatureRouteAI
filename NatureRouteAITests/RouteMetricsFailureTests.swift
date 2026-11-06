import Foundation
import MapKit
import XCTest
@testable import NatureRouteAI

@MainActor
final class RouteMetricsFailureTests: XCTestCase {
    // MARK: - Cancellation

    func testCancellingARequestThatNeverAnswersEndsPromptly() async {
        var didCancelRequest = false
        let task = Task { @MainActor () -> Result<Int, Error> in
            do {
                let value: Int = try await withPromptCancellation(
                    start: { _ in },
                    cancel: { didCancelRequest = true }
                )
                return .success(value)
            } catch {
                return .failure(error)
            }
        }
        try? await Task.sleep(for: .milliseconds(20))

        task.cancel()
        let result = await task.value

        guard case .failure(let error) = result else { return XCTFail("Expected cancellation") }
        XCTAssertTrue(error is CancellationError)
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertTrue(didCancelRequest)
    }

    func testAnswerArrivingAfterCancelIsIgnored() async {
        var finishRequest: ((Result<Int, Error>) -> Void)?
        let task = Task { @MainActor () -> Int? in
            try? await withPromptCancellation(start: { finishRequest = $0 }, cancel: {})
        }
        try? await Task.sleep(for: .milliseconds(20))

        task.cancel()
        let value = await task.value
        finishRequest?(.success(1))

        XCTAssertNil(value)
    }

    func testRequestIsNotStartedWhenAlreadyCancelled() async {
        var didStart = false
        let task = Task { @MainActor () -> Int? in
            await Task.yield()
            return try? await withPromptCancellation(start: { _ in didStart = true }, cancel: {})
        }
        task.cancel()

        let value = await task.value

        XCTAssertNil(value)
        XCTAssertFalse(didStart)
    }

    func testAnswerIsDeliveredWithoutCancellation() async throws {
        let value: Int = try await withPromptCancellation(start: { $0(.success(7)) }, cancel: {})
        XCTAssertEqual(value, 7)
    }

    // MARK: - Error classification

    func testMapKitErrorsAreClassified() {
        XCTAssertEqual(classified(MKError(.loadingThrottled)), .throttled)
        XCTAssertEqual(classified(MKError(.serverFailure)), .serviceUnavailable)
        XCTAssertEqual(classified(MKError(.unknown)), .serviceUnavailable)
        XCTAssertEqual(classified(MKError(.directionsNotFound)), .noRoute)
        XCTAssertEqual(classified(URLError(.notConnectedToInternet)), .serviceUnavailable)
    }

    // MARK: - Request budget and throttling

    func testRequestBudgetIsSharedSoEveryStopOfTheLargestPlanGetsChecked() async throws {
        let provider = ScriptedMetricsProvider()
        let result = try await distribute(provider: provider, days: 7, placesPerDay: 5, candidates: 60)

        XCTAssertEqual(result.days.flatMap { $0 }.count, 35)
        XCTAssertLessThanOrEqual(provider.requestCount, RoutePlanningAlgorithm.defaultRequestBudget)
        XCTAssertFalse(result.requestLimitReached)
    }

    func testSmallPlanStillComparesSeveralCandidatesPerStop() async throws {
        let provider = ScriptedMetricsProvider()
        _ = try await distribute(provider: provider, days: 1, placesPerDay: 2, candidates: 20)

        XCTAssertEqual(provider.requestCount, 8)
    }

    func testThrottlingStopsFurtherRequests() async throws {
        let provider = ScriptedMetricsProvider(throwing: .throttled, afterRequests: 5)
        let result = try await distribute(provider: provider, days: 3, placesPerDay: 3, candidates: 30)

        XCTAssertTrue(result.routingInterrupted)
        XCTAssertEqual(provider.requestCount, 6)
        XCTAssertEqual(result.days.count, 3)
    }

    func testUnbrokenServiceFailuresStopFurtherRequests() async throws {
        let provider = ScriptedMetricsProvider(throwing: .serviceUnavailable, afterRequests: 5)
        let result = try await distribute(provider: provider, days: 3, placesPerDay: 3, candidates: 30)

        XCTAssertTrue(result.routingInterrupted)
        XCTAssertEqual(provider.requestCount, 13)
    }

    func testOccasionalServiceFailureDoesNotInterruptPlanning() async throws {
        let provider = ScriptedMetricsProvider(failingEvery: 3)
        let result = try await distribute(provider: provider, days: 3, placesPerDay: 3, candidates: 30)

        XCTAssertFalse(result.routingInterrupted)
        XCTAssertTrue(result.hadServiceFailure)
        XCTAssertEqual(result.days.flatMap { $0 }.count, 9)
    }

    func testRouteCutShortByServiceFailuresIsReportedInsteadOfAPartialRoute() async {
        let generator = makeGenerator(ScriptedMetricsProvider(throwing: .serviceUnavailable, afterRequests: 5))
        await assertGeneration(generator, placesPerDay: 3, throws: .routeServiceUnavailable)
    }

    func testThrottledRouteIsReportedInsteadOfAPartialRoute() async {
        let generator = makeGenerator(ScriptedMetricsProvider(throwing: .throttled, afterRequests: 5))
        await assertGeneration(generator, placesPerDay: 3, throws: .routeServiceUnavailable)
    }

    func testServiceFailureWithoutStopsIsNotReportedAsNoRoute() async {
        let generator = makeGenerator(ScriptedMetricsProvider(throwing: .serviceUnavailable, afterRequests: 0))
        await assertGeneration(generator, placesPerDay: 1, throws: .routeServiceUnavailable)
    }

    func testRealNoRouteIsStillReportedAsNoRoute() async {
        let generator = makeGenerator(ScriptedMetricsProvider(throwing: .noRoute, afterRequests: 0))
        await assertGeneration(generator, placesPerDay: 1, throws: .noRouteablePlaces)
    }

    // MARK: - Helpers

    private func classified(_ error: Error) -> RouteMetricsError? {
        RouteMetricsError.classify(error) as? RouteMetricsError
    }

    private func distribute(
        provider: ScriptedMetricsProvider,
        days: Int,
        placesPerDay: Int,
        candidates count: Int
    ) async throws -> RoutePlanningResult {
        let candidates = (0..<count).map { index in
            RoutePlaceCandidate(
                externalID: "spot-\(index)",
                name: "Spot \(index)",
                type: "natural",
                latitude: 0,
                longitude: Double(index + 1) * 0.01,
                preferences: ["Nature"],
                quality: 3,
                sourceOrder: index
            )
        }
        return try await RoutePlanningAlgorithm.distribute(
            candidates: candidates,
            dayPreferences: Array(repeating: "Nature", count: days),
            placesPerDay: placesPerDay,
            transport: .walking,
            originLatitude: 0,
            originLongitude: 0,
            metricsProvider: provider
        )
    }

    private func makeGenerator(_ provider: ScriptedMetricsProvider) -> RouteGenerator {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubOpenTripMapProtocol.self]
        let network = NetworkService(apiKey: "test", session: URLSession(configuration: configuration))
        return RouteGenerator(metricsProvider: provider, networkService: network)
    }

    private func assertGeneration(
        _ generator: RouteGenerator,
        placesPerDay: Int,
        throws expected: AppError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await generator.generateRoute(
                city: "Testville",
                days: 1,
                placesPerDay: placesPerDay,
                preferences: ["Forest"],
                transport: .walking
            )
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as AppError {
            XCTAssertEqual(error.userMessage, expected.userMessage, file: file, line: line)
        } catch {
            XCTFail("Unexpected error \(error)", file: file, line: line)
        }
    }
}

@MainActor
private final class ScriptedMetricsProvider: RouteMetricsProviding {
    private let failure: RouteMetricsError?
    private let afterRequests: Int
    private let failingEvery: Int?
    private(set) var requestCount = 0

    init(throwing failure: RouteMetricsError? = nil, afterRequests: Int = 0, failingEvery: Int? = nil) {
        self.failure = failure
        self.afterRequests = afterRequests
        self.failingEvery = failingEvery
    }

    func metrics(from latitude: Double, longitude: Double, to candidate: RoutePlaceCandidate, transport: TransportMode) async throws -> RouteMetrics {
        requestCount += 1
        if let failure, requestCount > afterRequests { throw failure }
        if let failingEvery, requestCount % failingEvery == 0 { throw RouteMetricsError.serviceUnavailable }
        return RouteMetrics(distanceMeters: 1_000, expectedTravelTime: 600)
    }
}

private final class StubOpenTripMapProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let features = (0..<20).map { index in
            #"{"geometry":{"coordinates":[\#(5 + Double(index) * 0.01),52]},"properties":{"name":"Spot \#(index)","xid":"x\#(index)","rate":3}}"#
        }
        let body = request.url?.path.hasSuffix("geoname") == true
            ? #"{"lat":52,"lon":5,"status":"OK"}"#
            : #"{"features":[\#(features.joined(separator: ","))]}"#
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

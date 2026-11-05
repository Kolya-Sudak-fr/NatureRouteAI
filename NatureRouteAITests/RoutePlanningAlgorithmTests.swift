import XCTest
@testable import NatureRouteAI

@MainActor
final class RoutePlanningAlgorithmTests: XCTestCase {
    func testDuplicateExternalIDIsNotAssignedAcrossDifferentDays() async throws {
        let samePlaceDayOne = candidate(id: "xid-1", name: "Lake", longitude: 0.01, preferences: ["Lakes"])
        let samePlaceDayTwo = candidate(id: "XID-1", name: "Lake viewpoint", longitude: 0.01, preferences: ["Forest"])

        let result = try await RoutePlanningAlgorithm.distribute(
            candidates: [samePlaceDayOne, samePlaceDayTwo],
            dayPreferences: ["Lakes", "Forest"],
            placesPerDay: 1,
            transport: .walking,
            originLatitude: 0,
            originLongitude: 0,
            metricsProvider: TestRouteMetricsProvider()
        )

        XCTAssertEqual(result.days.flatMap { $0 }.count, 1)
        XCTAssertEqual(result.days[0].map(\.externalID), ["xid-1"])
        XCTAssertTrue(result.days[1].isEmpty)
    }

    func testInsufficientUniquePlacesReturnsPartialRouteWithoutRepeating() async throws {
        let result = try await RoutePlanningAlgorithm.distribute(
            candidates: [candidate(id: "only", name: "One spot", longitude: 0.01, preferences: ["Lake"])],
            dayPreferences: ["Lake", "Lake"],
            placesPerDay: 2,
            transport: .walking,
            originLatitude: 0,
            originLongitude: 0,
            metricsProvider: TestRouteMetricsProvider()
        )

        XCTAssertEqual(result.days.count, 2)
        XCTAssertEqual(result.days.flatMap { $0 }.count, 1)
        XCTAssertEqual(result.days[0].count, 1)
        XCTAssertTrue(result.days[1].isEmpty)
    }

    func testRepeatedPreferenceAcrossDaysUsesDifferentPlaces() async throws {
        let places = (1...4).map {
            candidate(id: "lake-\($0)", name: "Lake \($0)", longitude: Double($0) * 0.01, preferences: ["Lake"])
        }

        let result = try await RoutePlanningAlgorithm.distribute(
            candidates: places,
            dayPreferences: ["Lake", "Lake"],
            placesPerDay: 2,
            transport: .cycling,
            originLatitude: 0,
            originLongitude: 0,
            metricsProvider: TestRouteMetricsProvider()
        )

        XCTAssertEqual(result.days.map(\.count), [2, 2])
        XCTAssertEqual(Set(result.days.flatMap { $0 }.compactMap(\.externalID)).count, 4)
    }

    func testTransportModesHaveTheirConfiguredPreferredRanges() {
        XCTAssertEqual(TransportMode.walking.preferredStopDistanceKilometers, 0.5...2)
        XCTAssertEqual(TransportMode.cycling.preferredStopDistanceKilometers, 2...7)
        XCTAssertEqual(TransportMode.car.preferredStopDistanceKilometers, 3...20)
        XCTAssertEqual(TransportMode.publicTransport.preferredStopDistanceKilometers, 2...15)
    }

    func testTransportModeChangesWhichSpacingCandidateIsPreferred() async throws {
        let expectations: [(TransportMode, Double, Double)] = [
            (.walking, 1, 5),
            (.cycling, 5, 1),
            (.car, 10, 1),
            (.publicTransport, 8, 1)
        ]

        for (mode, preferredDistance, alternativeDistance) in expectations {
            let candidates = [preferredDistance, alternativeDistance].enumerated().map { index, distance in
                candidate(
                    id: "\(mode.rawValue)-\(index)",
                    name: "Spot \(index)",
                    longitude: distance / 111.195,
                    preferences: ["Nature"]
                )
            }

            let provider = TestRouteMetricsProvider(preferredCandidateIDByMode: [mode.rawValue: "\(mode.rawValue)-0"])
            let result = try await RoutePlanningAlgorithm.distribute(
                candidates: candidates,
                dayPreferences: ["Nature"],
                placesPerDay: 1,
                transport: mode,
                originLatitude: 0,
                originLongitude: 0,
                metricsProvider: provider
            )

            XCTAssertEqual(result.days[0].first?.externalID, "\(mode.rawValue)-0", "Unexpected spacing choice for \(mode)")
        }
    }

    func testBestAvailableAttractionOutsidePreferredRangeRemainsEligible() async throws {
        let farSpot = candidate(id: "far", name: "Remote park", longitude: 30.0 / 111.195, preferences: ["Park"], quality: 3)

        let result = try await RoutePlanningAlgorithm.distribute(
            candidates: [farSpot],
            dayPreferences: ["Park"],
            placesPerDay: 1,
            transport: .car,
            originLatitude: 0,
            originLongitude: 0,
            metricsProvider: TestRouteMetricsProvider()
        )

        XCTAssertEqual(result.days[0].map(\.externalID), ["far"])
        XCTAssertGreaterThan(RoutePlanningAlgorithm.distanceMeters(result.days[0][0], candidate(id: "origin", name: "Origin", longitude: 0, preferences: [])) / 1_000, TransportMode.car.preferredStopDistanceKilometers.upperBound)
    }

    func testRequestLimitIsReportedWhenNoRouteCouldBeConfirmed() async throws {
        let result = try await RoutePlanningAlgorithm.distribute(
            candidates: [candidate(id: "limited", name: "Limited spot", longitude: 0.01, preferences: ["Nature"])],
            dayPreferences: ["Nature"],
            placesPerDay: 1,
            transport: .walking,
            originLatitude: 0,
            originLongitude: 0,
            metricsProvider: TestRouteMetricsProvider(requestLimit: 0)
        )

        XCTAssertTrue(result.requestLimitReached)
        XCTAssertTrue(result.days.flatMap { $0 }.isEmpty)
    }

    func testNoRouteableMapKitSegmentsProduceNoStops() async throws {
        let result = try await RoutePlanningAlgorithm.distribute(
            candidates: [
                candidate(id: "unreachable-1", name: "Remote spot 1", longitude: 0.01, preferences: ["Nature"]),
                candidate(id: "unreachable-2", name: "Remote spot 2", longitude: 0.02, preferences: ["Nature"])
            ],
            dayPreferences: ["Nature"],
            placesPerDay: 1,
            transport: .walking,
            originLatitude: 0,
            originLongitude: 0,
            metricsProvider: TestRouteMetricsProvider(unrouteableCandidateIDs: ["unreachable-1", "unreachable-2"])
        )

        XCTAssertTrue(result.days.flatMap { $0 }.isEmpty)
        XCTAssertFalse(result.requestLimitReached)
    }

    func testUnrouteableMapKitSegmentIsSkippedWhenAnotherStopIsReachable() async throws {
        let result = try await RoutePlanningAlgorithm.distribute(
            candidates: [
                candidate(id: "unreachable", name: "Remote spot", longitude: 0.01, preferences: ["Nature"]),
                candidate(id: "reachable", name: "Nearby spot", longitude: 0.02, preferences: ["Nature"])
            ],
            dayPreferences: ["Nature"],
            placesPerDay: 1,
            transport: .walking,
            originLatitude: 0,
            originLongitude: 0,
            metricsProvider: TestRouteMetricsProvider(unrouteableCandidateIDs: ["unreachable"])
        )

        XCTAssertEqual(result.days[0].map(\.externalID), ["reachable"])
        XCTAssertFalse(result.requestLimitReached)
    }

    func testSimilarNamesWithDifferentIDsRemainDistinct() {
        let unique = RoutePlanningAlgorithm.uniqueCandidates([
            candidate(id: "a", name: "Blue Lake", longitude: 0.01, preferences: ["Lake"]),
            candidate(id: "b", name: "Blue Lake View", longitude: 0.02, preferences: ["Lake"])
        ])

        XCTAssertEqual(unique.count, 2)
    }

    func testMissingIDsUseNearIdenticalCoordinatesForDeduplication() {
        let unique = RoutePlanningAlgorithm.uniqueCandidates([
            candidate(id: nil, name: "Unnamed place", longitude: 0.01, preferences: ["Lake"]),
            candidate(id: nil, name: "Different API label", longitude: 0.01001, preferences: ["Forest"]),
            candidate(id: "identified", name: "Nearby identified place", longitude: 0.02, preferences: ["Park"])
        ])

        XCTAssertEqual(unique.count, 2)
        XCTAssertTrue(unique[0].preferences.contains("Forest"))
        XCTAssertEqual(unique[1].externalID, "identified")
    }

    func testIdentifiedAndUnidentifiedDuplicateAreDeduplicatedInEitherOrder() {
        let identified = candidate(id: "spot-1", name: "Lake", longitude: 0.01, preferences: ["Lake"])
        let unidentified = candidate(id: nil, name: "Water feature", longitude: 0.01001, preferences: ["Forest"])

        for input in [[identified, unidentified], [unidentified, identified]] {
            let unique = RoutePlanningAlgorithm.uniqueCandidates(input)
            XCTAssertEqual(unique.count, 1)
            XCTAssertEqual(unique[0].externalID, "spot-1")
            XCTAssertEqual(unique[0].preferences, Set(["Lake", "Forest"]))
        }
    }

    func testNearbyPlacesWithDifferentKnownIDsRemainDistinct() {
        let unique = RoutePlanningAlgorithm.uniqueCandidates([
            candidate(id: "spot-1", name: "First", longitude: 0.01, preferences: ["Lake"]),
            candidate(id: "spot-2", name: "Second", longitude: 0.01001, preferences: ["Forest"])
        ])

        XCTAssertEqual(unique.count, 2)
    }

    private func candidate(
        id: String?,
        name: String,
        longitude: Double,
        preferences: Set<String>,
        quality: Int? = 3
    ) -> RoutePlaceCandidate {
        RoutePlaceCandidate(
            externalID: id,
            name: name,
            type: "natural",
            latitude: 0,
            longitude: longitude,
            preferences: preferences,
            quality: quality,
            sourceOrder: 0
        )
    }
}

@MainActor
private final class TestRouteMetricsProvider: RouteMetricsProviding {
    private let preferredCandidateIDByMode: [String: String]
    private let requestLimit: Int?
    private let unrouteableCandidateIDs: Set<String>
    private var requestCount = 0

    init(
        preferredCandidateIDByMode: [String: String] = [:],
        requestLimit: Int? = nil,
        unrouteableCandidateIDs: Set<String> = []
    ) {
        self.preferredCandidateIDByMode = preferredCandidateIDByMode
        self.requestLimit = requestLimit
        self.unrouteableCandidateIDs = unrouteableCandidateIDs
    }

    func metrics(from latitude: Double, longitude: Double, to candidate: RoutePlaceCandidate, transport: TransportMode) async throws -> RouteMetrics {
        if let externalID = candidate.externalID, unrouteableCandidateIDs.contains(externalID) {
            throw RouteMetricsError.noRoute
        }
        if let requestLimit, requestCount >= requestLimit {
            throw RouteMetricsError.requestLimitReached
        }
        requestCount += 1
        let lat = (candidate.latitude - latitude) * 111_195
        let lon = (candidate.longitude - longitude) * 111_195
        let distance = hypot(lat, lon)
        let speed: Double = switch transport {
        case .walking: 1.2
        case .cycling: 4.0
        case .car: 11.0
        case .publicTransport: throw RouteMetricsError.unsupportedTransport
        }
        let time = preferredCandidateIDByMode[transport.rawValue] == candidate.externalID
            ? 1
            : distance / speed
        return RouteMetrics(distanceMeters: distance, expectedTravelTime: time)
    }
}

import XCTest
@testable import NatureRouteAI

@MainActor
final class RoutePlanningAlgorithmTests: XCTestCase {
    func testDuplicateExternalIDIsNotAssignedAcrossDifferentDays() {
        let samePlaceDayOne = candidate(id: "xid-1", name: "Lake", longitude: 0.01, preferences: ["Lakes"])
        let samePlaceDayTwo = candidate(id: "XID-1", name: "Lake viewpoint", longitude: 0.01, preferences: ["Forest"])

        let days = RoutePlanningAlgorithm.distribute(
            candidates: [samePlaceDayOne, samePlaceDayTwo],
            dayPreferences: ["Lakes", "Forest"],
            placesPerDay: 1,
            transport: .walking,
            originLatitude: 0,
            originLongitude: 0
        )

        XCTAssertEqual(days.flatMap { $0 }.count, 1)
        XCTAssertEqual(days[0].map(\.externalID), ["xid-1"])
        XCTAssertTrue(days[1].isEmpty)
    }

    func testInsufficientUniquePlacesReturnsPartialRouteWithoutRepeating() {
        let days = RoutePlanningAlgorithm.distribute(
            candidates: [candidate(id: "only", name: "One spot", longitude: 0.01, preferences: ["Lake"])],
            dayPreferences: ["Lake", "Lake"],
            placesPerDay: 2,
            transport: .walking,
            originLatitude: 0,
            originLongitude: 0
        )

        XCTAssertEqual(days.count, 2)
        XCTAssertEqual(days.flatMap { $0 }.count, 1)
        XCTAssertEqual(days[0].count, 1)
        XCTAssertTrue(days[1].isEmpty)
    }

    func testRepeatedPreferenceAcrossDaysUsesDifferentPlaces() {
        let places = (1...4).map {
            candidate(id: "lake-\($0)", name: "Lake \($0)", longitude: Double($0) * 0.01, preferences: ["Lake"])
        }

        let days = RoutePlanningAlgorithm.distribute(
            candidates: places,
            dayPreferences: ["Lake", "Lake"],
            placesPerDay: 2,
            transport: .cycling,
            originLatitude: 0,
            originLongitude: 0
        )

        XCTAssertEqual(days.map(\.count), [2, 2])
        XCTAssertEqual(Set(days.flatMap { $0 }.compactMap(\.externalID)).count, 4)
    }

    func testTransportModesHaveTheirConfiguredPreferredRanges() {
        XCTAssertEqual(TransportMode.walking.preferredStopDistanceKilometers, 0.5...2)
        XCTAssertEqual(TransportMode.cycling.preferredStopDistanceKilometers, 2...7)
        XCTAssertEqual(TransportMode.car.preferredStopDistanceKilometers, 3...20)
        XCTAssertEqual(TransportMode.publicTransport.preferredStopDistanceKilometers, 2...15)
    }

    func testTransportModeChangesWhichSpacingCandidateIsPreferred() {
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

            let day = RoutePlanningAlgorithm.distribute(
                candidates: candidates,
                dayPreferences: ["Nature"],
                placesPerDay: 1,
                transport: mode,
                originLatitude: 0,
                originLongitude: 0
            )[0]

            XCTAssertEqual(day.first?.externalID, "\(mode.rawValue)-0", "Unexpected spacing choice for \(mode)")
        }
    }

    func testBestAvailableAttractionOutsidePreferredRangeRemainsEligible() {
        let farSpot = candidate(id: "far", name: "Remote park", longitude: 30.0 / 111.195, preferences: ["Park"], quality: 3)

        let days = RoutePlanningAlgorithm.distribute(
            candidates: [farSpot],
            dayPreferences: ["Park"],
            placesPerDay: 1,
            transport: .car,
            originLatitude: 0,
            originLongitude: 0
        )

        XCTAssertEqual(days[0].map(\.externalID), ["far"])
        XCTAssertGreaterThan(RoutePlanningAlgorithm.distanceMeters(days[0][0], candidate(id: "origin", name: "Origin", longitude: 0, preferences: [])) / 1_000, TransportMode.car.preferredStopDistanceKilometers.upperBound)
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
            candidate(id: "identified", name: "Nearby identified place", longitude: 0.01, preferences: ["Park"])
        ])

        XCTAssertEqual(unique.count, 2)
        XCTAssertTrue(unique[0].preferences.contains("Forest"))
        XCTAssertEqual(unique[1].externalID, "identified")
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

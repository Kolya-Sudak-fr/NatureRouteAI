import XCTest
@testable import NatureRouteAI

@MainActor
final class TripRequestParserTests: XCTestCase {

    // MARK: - Keyword parser

    func testReadsCityInterestsAndDaysFromEnglishMessage() async throws {
        let request = try await KeywordTripRequestParser().parse(
            "I'm in Middelburg, I want castles and historic sites for 2 days"
        )

        XCTAssertEqual(request.city, "Middelburg")
        XCTAssertEqual(request.interests, [.castlesAndAbbeys, .historicSites])
        XCTAssertEqual(request.days, 2)
        XCTAssertFalse(request.needsCity)
    }

    /// The message the user wrote as an example for the assistant.
    func testReadsRussianExampleMessageFromTheUser() async throws {
        let request = try await KeywordTripRequestParser().parse(
            "Привет я сейчас в Мидлбурге, хотел построить что-то историческое, замки, аббатства и тд"
        )

        XCTAssertEqual(request.city, "Мидлбург")
        XCTAssertEqual(request.interests, [.castlesAndAbbeys, .historicSites])
        XCTAssertNil(request.days)
    }

    func testCityIsNilWhenMessageHasNoPlace() async throws {
        let request = try await KeywordTripRequestParser().parse("хочу замки и аббатства")

        XCTAssertNil(request.city)
        XCTAssertTrue(request.needsCity)
        XCTAssertEqual(request.interests, [.castlesAndAbbeys])
    }

    func testLowercaseWordAfterPrepositionIsNotTakenAsCity() async throws {
        let request = try await KeywordTripRequestParser().parse("хочу в замках погулять")

        XCTAssertNil(request.city)
    }

    func testSkipsCityWordBeforeProperName() async throws {
        let request = try await KeywordTripRequestParser().parse("в городе Лейден хочу лес")

        XCTAssertEqual(request.city, "Лейден")
        XCTAssertEqual(request.interests, [.forest])
    }

    func testSkipsEnglishArticleBeforeCity() async throws {
        let request = try await KeywordTripRequestParser().parse("I am in the Hague and want museums")

        XCTAssertEqual(request.city, "Hague")
        XCTAssertEqual(request.interests, [.historicSites])
    }

    func testReadsNatureInterestsAndNearbyCityInEnglish() async throws {
        let request = try await KeywordTripRequestParser().parse(
            "Mountains and lakes near Innsbruck for 3 days"
        )

        XCTAssertEqual(request.city, "Innsbruck")
        XCTAssertEqual(request.interests, [.mountains, .lakes])
        XCTAssertEqual(request.days, 3)
    }

    func testReadsDutchCityAfterBij() async throws {
        let request = try await KeywordTripRequestParser().parse("Ik ben bij Utrecht en wil kastelen zien")

        XCTAssertEqual(request.city, "Utrecht")
        XCTAssertEqual(request.interests, [.castlesAndAbbeys])
    }

    /// Reported by the user: "замок в Утрехте" returned nothing.
    /// "замок" (singular, nominative) must count as a castle, not only "замки".
    func testSingularCastleInRussianFindsCastlesInUtrecht() async throws {
        let request = try await KeywordTripRequestParser().parse("замок в Утрехте")

        XCTAssertEqual(request.city, "Утрехт")
        XCTAssertEqual(request.interests, [.castlesAndAbbeys])
    }

    func testRussianCastleCaseFormsAreRecognised() async throws {
        for phrase in ["замок", "замки", "замка", "замков", "замке"] {
            let request = try await KeywordTripRequestParser().parse("\(phrase) в Утрехте")
            XCTAssertEqual(request.interests, [.castlesAndAbbeys], "phrase: \(phrase)")
        }
    }

    func testRussianDaysAreRead() async throws {
        let request = try await KeywordTripRequestParser().parse("Утрехт, на 3 дня, водопады")

        XCTAssertEqual(request.days, 3)
        XCTAssertEqual(request.interests, [.waterfalls])
    }

    func testDaysOutOfSupportedRangeAreIgnored() async throws {
        let request = try await KeywordTripRequestParser().parse("Amsterdam for 10 days")

        XCTAssertNil(request.days)
    }

    func testEmptyishMessageProducesEmptyRequest() async throws {
        let request = try await KeywordTripRequestParser().parse("привет")

        XCTAssertTrue(request.isEmpty)
        XCTAssertEqual(request.interestsOrDefault, TripInterest.allCases)
    }

    // MARK: - TripRequest rules

    func testBlankCityCountsAsMissing() {
        let request = TripRequest(city: "   ", interests: [], days: nil)

        XCTAssertTrue(request.needsCity)
    }

    func testInterestsOrDefaultKeepsNamedInterests() {
        let request = TripRequest(city: "Leiden", interests: [.lakes], days: nil)

        XCTAssertEqual(request.interestsOrDefault, [.lakes])
    }

    // MARK: - Fallback chain

    func testFallbackParserIsUsedWhenPrimaryThrows() async throws {
        let parser = FallbackTripRequestParser(
            primary: ThrowingParser(error: TripRequestParsingError.modelUnavailable),
            fallback: FixedParser(result: TripRequest(city: "Leiden", interests: [], days: nil))
        )

        let request = try await parser.parse("anything")

        XCTAssertEqual(request.city, "Leiden")
    }

    func testPrimaryAnswerIsUsedWhenItUnderstoodTheRequest() async throws {
        let parser = FallbackTripRequestParser(
            primary: FixedParser(result: TripRequest(city: "Bruges", interests: [.historicSites], days: 2)),
            fallback: FixedParser(result: TripRequest(city: "Other", interests: [], days: nil))
        )

        let request = try await parser.parse("anything")

        XCTAssertEqual(request.city, "Bruges")
        XCTAssertEqual(request.days, 2)
    }

    func testFallbackIsUsedWhenPrimaryFindsNothing() async throws {
        let parser = FallbackTripRequestParser(
            primary: FixedParser(result: TripRequest(city: nil, interests: [], days: nil)),
            fallback: FixedParser(result: TripRequest(city: "Leiden", interests: [], days: nil))
        )

        let request = try await parser.parse("anything")

        XCTAssertEqual(request.city, "Leiden")
    }

    func testCancellationIsNotReplacedByFallback() async {
        let parser = FallbackTripRequestParser(
            primary: ThrowingParser(error: CancellationError()),
            fallback: FixedParser(result: TripRequest(city: "Leiden", interests: [], days: nil))
        )

        do {
            _ = try await parser.parse("anything")
            XCTFail("Cancellation should reach the caller")
        } catch is CancellationError {
            // Expected: the user left, so the keyword parser must not run.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private struct ThrowingParser: TripRequestParsing {
    let error: Error

    func parse(_ text: String) async throws -> TripRequest {
        throw error
    }
}

private struct FixedParser: TripRequestParsing {
    let result: TripRequest

    func parse(_ text: String) async throws -> TripRequest {
        result
    }
}

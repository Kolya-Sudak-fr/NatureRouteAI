import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

enum TripRequestParsingError: Error, Equatable {
    case modelUnavailable
}

/// Разбор свободного текста моделью Apple Intelligence на устройстве.
/// Нужны iOS 26 и iPhone с Apple Intelligence (iPhone 15 Pro и новее).
/// Текст не уходит в сеть, API-ключ не нужен. Если модели нет, бросает
/// TripRequestParsingError.modelUnavailable, и FallbackTripRequestParser берёт правила.
struct AppleIntelligenceTripRequestParser: TripRequestParsing {

    func parse(_ text: String) async throws -> TripRequest {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return try await Self.generate(from: text)
        }
        #endif
        throw TripRequestParsingError.modelUnavailable
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
extension AppleIntelligenceTripRequestParser {

    private static let instructions = """
    You read a short message from a person who is planning a trip and extract the details.
    Do not ask questions. Leave a field empty when the message does not mention it.
    """

    static func generate(from text: String) async throws -> TripRequest {
        guard case .available = SystemLanguageModel.default.availability else {
            throw TripRequestParsingError.modelUnavailable
        }
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: text, generating: GeneratedTripRequest.self)
        return response.content.tripRequest
    }
}

@available(iOS 26.0, *)
@Generable
struct GeneratedTripRequest {
    @Guide(description: "The town or city the person is in or wants to visit, as a proper name. Empty if not mentioned.")
    var city: String?

    @Guide(description: "Only these values, when the message mentions them: mountains, forest, lakes, waterfalls, nationalParks, castlesAndAbbeys, historicSites. Empty if none.")
    var interests: [String]

    @Guide(description: "Trip length in days, from 1 to 7. Empty if not mentioned.")
    var days: Int?

    var tripRequest: TripRequest {
        let trimmedCity = city?.trimmingCharacters(in: .whitespacesAndNewlines)
        return TripRequest(
            city: (trimmedCity?.isEmpty == false) ? trimmedCity : nil,
            interests: TripInterest.allCases.filter { interests.contains($0.rawValue) },
            days: days.flatMap { (1...7).contains($0) ? $0 : nil }
        )
    }
}
#endif

import Foundation

/// Превращает свободный текст пользователя в TripRequest.
protocol TripRequestParsing {
    func parse(_ text: String) async throws -> TripRequest
}

/// Запасной разбор без ИИ и без сети. Понимает простые фразы на английском,
/// русском и нидерландском: город после предлога, названия интересов, «2 days» / «2 дня».
///
/// Город берём только если слово начинается с заглавной буквы. Так «в замках»
/// не станет городом, а «в Мидлбурге» станет.
struct KeywordTripRequestParser: TripRequestParsing {

    func parse(_ text: String) async throws -> TripRequest {
        let words = Self.words(in: text)
        return TripRequest(
            city: Self.city(in: words),
            interests: Self.interests(in: words),
            days: Self.days(in: words)
        )
    }

    private static let cityMarkers: Set<String> = ["in", "near", "around", "в", "во", "около", "bij", "rond"]
    private static let skippedBeforeCity: Set<String> = ["the", "a", "an", "городе", "городке"]

    private static let interestKeywords: [TripInterest: [String]] = [
        .mountains: ["mountain", "горн", "горы", "гора", "горах", "горам"],
        .forest: ["forest", "woods", "лес"],
        .lakes: ["lake", "озер", "meer"],
        .waterfalls: ["waterfall", "водопад"],
        .nationalParks: ["national", "национальн", "nationaal"],
        .castlesAndAbbeys: ["castle", "замк", "kaste", "abbey", "abdij", "аббат", "абатств", "monaster", "монастыр", "klooster"],
        .historicSites: ["histor", "истор", "історич", "monument", "памятник", "памятн", "museum", "музе", "archaeolog", "археолог"]
    ]

    private static let dayUnits = ["day", "dag", "дн", "день", "дня", "дней", "дням", "сутк"]

    static func words(in text: String) -> [String] {
        text.split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    static func city(in words: [String]) -> String? {
        for (index, word) in words.enumerated() where cityMarkers.contains(word.lowercased()) {
            var candidateIndex = index + 1
            while words.indices.contains(candidateIndex),
                  skippedBeforeCity.contains(words[candidateIndex].lowercased()) {
                candidateIndex += 1
            }
            guard words.indices.contains(candidateIndex) else { continue }
            let candidate = words[candidateIndex]
            guard candidate.count >= 3, candidate.first?.isUppercase == true else { continue }
            return normalizedCity(candidate)
        }
        return nil
    }

    static func interests(in words: [String]) -> [TripInterest] {
        let lowercased = words.map { $0.lowercased() }
        return TripInterest.allCases.filter { interest in
            let keywords = interestKeywords[interest] ?? []
            return lowercased.contains { word in keywords.contains { word.hasPrefix($0) } }
        }
    }

    /// Число перед словом «день» или «days». Поддерживаем только 1–7, как и планировщик.
    static func days(in words: [String]) -> Int? {
        for (index, word) in words.enumerated() {
            guard let number = Int(word), words.indices.contains(index + 1) else { continue }
            let unit = words[index + 1].lowercased()
            guard dayUnits.contains(where: { unit.hasPrefix($0) }) || unit == "days" else { continue }
            return (1...7).contains(number) ? number : nil
        }
        return nil
    }

    /// Русский предложный падеж: «в Мидлбурге» → «Мидлбург», «в Утрехте» → «Утрехт».
    /// Это эвристика. Точные формы даёт модель Apple Intelligence.
    private static func normalizedCity(_ word: String) -> String {
        let hasCyrillic = word.range(of: "[А-Яа-яЁё]", options: .regularExpression) != nil
        if hasCyrillic, word.hasSuffix("е"), word.count > 4 {
            return String(word.dropLast())
        }
        return word
    }
}

/// Сначала спрашивает основной парсер, а если он упал или ничего не понял,
/// работает запасной. Отмену не глотаем: пользователь ушёл, и это не ошибка разбора.
struct FallbackTripRequestParser: TripRequestParsing {
    let primary: TripRequestParsing
    let fallback: TripRequestParsing

    func parse(_ text: String) async throws -> TripRequest {
        do {
            let result = try await primary.parse(text)
            if !result.isEmpty { return result }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Модель недоступна или ответила с ошибкой: разбираем правилами.
        }
        return try await fallback.parse(text)
    }
}

enum TripRequestParsers {
    /// Apple Intelligence, если доступна, иначе правила. Ключ API не нужен, текст никуда не уходит.
    static func standard() -> TripRequestParsing {
        FallbackTripRequestParser(
            primary: AppleIntelligenceTripRequestParser(),
            fallback: KeywordTripRequestParser()
        )
    }
}

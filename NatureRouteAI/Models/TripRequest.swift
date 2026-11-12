import Foundation

/// Что пользователь написал в свободной форме, разобранное по полям.
/// Того, что не было в тексте, в запросе нет: city = nil, days = nil, interests пуст.
struct TripRequest: Equatable {
    var city: String?
    var interests: [TripInterest]
    var days: Int?

    /// Город — единственное, без чего маршрут не построить.
    var needsCity: Bool {
        (city?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    /// Если интересы не названы, берём все сразу, чтобы не задавать лишний вопрос.
    var interestsOrDefault: [TripInterest] {
        interests.isEmpty ? TripInterest.allCases : interests
    }

    /// Пустой ответ: ни города, ни интересов, ни дней. Значит, модель ничего не поняла.
    var isEmpty: Bool {
        needsCity && interests.isEmpty && days == nil
    }
}

import Foundation

/// Способ передвижения пользователя.
/// Определяет радиус поиска мест и тип маршрута на карте.
enum TransportMode: String, CaseIterable, Identifiable, Codable {
    case walking
    case cycling
    case car

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .walking: return "Пешком"
        case .cycling: return "Велосипед"
        case .car:     return "Машина"
        }
    }

    var emoji: String {
        switch self {
        case .walking: return "🚶"
        case .cycling: return "🚲"
        case .car:     return "🚗"
        }
    }

    var systemIcon: String {
        switch self {
        case .walking: return "figure.walk"
        case .cycling: return "bicycle"
        case .car:     return "car.fill"
        }
    }
}

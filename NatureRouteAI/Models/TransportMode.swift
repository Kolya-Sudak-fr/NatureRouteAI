import Foundation

/// Способ передвижения пользователя.
/// Определяет радиус поиска мест и тип маршрута на карте.
enum TransportMode: String, CaseIterable, Identifiable, Codable {
    case walking
    case cycling
    case car
    case publicTransport

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .walking: return "Walking"
        case .cycling: return "Cycling"
        case .car:     return "Driving"
        case .publicTransport: return "Public Transport"
        }
    }

    var emoji: String {
        switch self {
        case .walking: return "🚶"
        case .cycling: return "🚲"
        case .car:     return "🚗"
        case .publicTransport: return "🚌"
        }
    }

    var systemIcon: String {
        switch self {
        case .walking: return "figure.walk"
        case .cycling: return "bicycle"
        case .car:     return "car.fill"
        case .publicTransport: return "bus.fill"
        }
    }
}

import Foundation

/// Интерес, который пользователь может назвать в свободном тексте.
/// `title` совпадает с названием категории в планировщике,
/// `openTripMapKinds` — категории OpenTripMap, по которым ищем места.
enum TripInterest: String, CaseIterable, Equatable {
    case mountains
    case forest
    case lakes
    case waterfalls
    case nationalParks
    case castlesAndAbbeys
    case historicSites

    var title: String {
        switch self {
        case .mountains:        return "Mountains"
        case .forest:           return "Forest"
        case .lakes:            return "Lakes"
        case .waterfalls:       return "Waterfalls"
        case .nationalParks:    return "National Parks"
        case .castlesAndAbbeys: return "Castles & Abbeys"
        case .historicSites:    return "Historic Sites"
        }
    }

    var openTripMapKinds: String {
        switch self {
        case .mountains:        return "mountain_peaks"
        case .forest:           return "nature_reserves"
        case .lakes:            return "water"
        case .waterfalls:       return "waterfalls"
        case .nationalParks:    return "national_parks"
        case .castlesAndAbbeys: return "castles,monasteries,fortifications"
        case .historicSites:    return "historic_architecture,monuments,archaeology"
        }
    }

    init?(title: String) {
        guard let match = Self.allCases.first(where: { $0.title == title }) else { return nil }
        self = match
    }
}

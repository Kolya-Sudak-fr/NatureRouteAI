import Foundation

/// A place returned by a category search. OpenTripMap's `xid` is kept while
/// planning so the same real-world place can be recognized across searches.
struct RoutePlaceCandidate: Equatable {
    let externalID: String?
    let name: String
    let type: String
    let latitude: Double
    let longitude: Double
    var preferences: Set<String>
    let quality: Int?
    let sourceOrder: Int
}

enum RoutePlanningAlgorithm {
    private struct Coordinate {
        let latitude: Double
        let longitude: Double
    }

    static func uniqueCandidates(_ candidates: [RoutePlaceCandidate]) -> [RoutePlaceCandidate] {
        var result: [RoutePlaceCandidate] = []
        var indexByExternalID: [String: Int] = [:]

        for candidate in candidates {
            let externalID = candidate.externalID?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if let externalID, !externalID.isEmpty,
               let existingIndex = indexByExternalID[externalID] {
                result[existingIndex].preferences.formUnion(candidate.preferences)
                continue
            }

            // Some API responses omit xid. In that case only near-identical
            // coordinates are treated as the same place; names are never used.
            if externalID == nil || externalID?.isEmpty == true,
               let existingIndex = result.firstIndex(where: {
                   let existingID = $0.externalID?.trimmingCharacters(in: .whitespacesAndNewlines)
                   return (existingID == nil || existingID?.isEmpty == true)
                       && distanceMeters($0, candidate) <= 20
               }) {
                result[existingIndex].preferences.formUnion(candidate.preferences)
                continue
            }

            let newIndex = result.count
            result.append(candidate)
            if let externalID, !externalID.isEmpty {
                indexByExternalID[externalID] = newIndex
            }
        }

        return result
    }

    @MainActor
    static func distribute(
        candidates: [RoutePlaceCandidate],
        dayPreferences: [String],
        placesPerDay: Int,
        transport: TransportMode,
        originLatitude: Double,
        originLongitude: Double,
        metricsProvider: RouteMetricsProviding
    ) async -> [[RoutePlaceCandidate]] {
        guard placesPerDay > 0 else { return Array(repeating: [], count: dayPreferences.count) }

        var remaining = uniqueCandidates(candidates)
        var days: [[RoutePlaceCandidate]] = []

        for preference in dayPreferences {
            var day: [RoutePlaceCandidate] = []
            var current = Coordinate(latitude: originLatitude, longitude: originLongitude)
            while day.count < placesPerDay {
                let eligible = remaining.indices.filter {
                    remaining[$0].preferences.contains(preference)
                }
                guard !eligible.isEmpty else { break }

                let shortlist = eligible.sorted {
                    preliminaryScore(remaining[$0], from: current, transport: transport)
                        < preliminaryScore(remaining[$1], from: current, transport: transport)
                }.prefix(4)

                var ranked: [(index: Int, metrics: RouteMetrics, score: Double)] = []
                if transport == .publicTransport {
                    // Transit remains external; choose spots without pretending that
                    // straight-line distance represents a bus or train journey.
                    let index = eligible.min { qualityScore(remaining[$0]) < qualityScore(remaining[$1]) }
                    if let index {
                        let next = remaining.remove(at: index)
                        day.append(next)
                    }
                    continue
                }
                for index in shortlist {
                    guard let metrics = try? await metricsProvider.metrics(
                        from: current.latitude, longitude: current.longitude,
                        to: remaining[index], transport: transport
                    ), metrics.distanceMeters.isFinite, metrics.expectedTravelTime.isFinite,
                       metrics.distanceMeters > 0, metrics.expectedTravelTime > 0 else { continue }
                    ranked.append((index, metrics, actualScore(remaining[index], metrics: metrics, transport: transport)))
                }
                guard let best = ranked.min(by: { $0.score < $1.score }) else { break }
                let next = remaining.remove(at: best.index)
                current = Coordinate(latitude: next.latitude, longitude: next.longitude)
                day.append(next)
            }

            days.append(day)
        }

        return days
    }

    static func distanceMeters(_ first: RoutePlaceCandidate, _ second: RoutePlaceCandidate) -> Double {
        distanceMeters(
            latitude: first.latitude,
            longitude: first.longitude,
            toLatitude: second.latitude,
            toLongitude: second.longitude
        )
    }

    private static func preliminaryScore(
        _ candidate: RoutePlaceCandidate,
        from current: Coordinate,
        transport: TransportMode
    ) -> Double {
        let distance = distanceMeters(
            latitude: current.latitude,
            longitude: current.longitude,
            toLatitude: candidate.latitude,
            toLongitude: candidate.longitude
        ) / 1_000
        let range = transport.preferredStopDistanceKilometers
        let preferredDistance = (range.lowerBound + range.upperBound) / 2
        let rangePenalty: Double
        if distance < range.lowerBound {
            rangePenalty = (range.lowerBound - distance) * 1.2
        } else if distance > range.upperBound {
            rangePenalty = (distance - range.upperBound) * 0.6
        } else {
            rangePenalty = abs(distance - preferredDistance) * 0.04
        }

        return rangePenalty + qualityScore(candidate) * 0.08 + Double(candidate.sourceOrder) * 0.0001
    }

    private static func actualScore(_ candidate: RoutePlaceCandidate, metrics: RouteMetrics, transport: TransportMode) -> Double {
        let range = transport.preferredStopDistanceKilometers
        let km = metrics.distanceMeters / 1_000
        let rangePenalty = km < range.lowerBound ? (range.lowerBound - km) * 1.2 : km > range.upperBound ? (km - range.upperBound) * 0.6 : 0
        return metrics.expectedTravelTime + rangePenalty * 60 + qualityScore(candidate) * 30
    }

    private static func qualityScore(_ candidate: RoutePlaceCandidate) -> Double {
        Double(max(0, 3 - (candidate.quality ?? 0)))
    }

    private static func distanceMeters(
        latitude: Double,
        longitude: Double,
        toLatitude otherLatitude: Double,
        toLongitude otherLongitude: Double
    ) -> Double {
        let earthRadius = 6_371_000.0
        let lat1 = latitude * .pi / 180
        let lat2 = otherLatitude * .pi / 180
        let deltaLatitude = (otherLatitude - latitude) * .pi / 180
        let deltaLongitude = (otherLongitude - longitude) * .pi / 180
        let a = sin(deltaLatitude / 2) * sin(deltaLatitude / 2)
            + cos(lat1) * cos(lat2) * sin(deltaLongitude / 2) * sin(deltaLongitude / 2)
        return earthRadius * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}

extension TransportMode {
    var preferredStopDistanceKilometers: ClosedRange<Double> {
        switch self {
        case .walking: 0.5...2
        case .cycling: 2...7
        case .car: 3...20
        case .publicTransport: 2...15
        }
    }

}

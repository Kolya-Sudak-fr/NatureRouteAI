import SwiftUI

/// One day of a route. Shared by the planner's result and the saved route details.
struct RouteDayCard: View {
    let day: RouteDay
    var onNavigate: ((Place) -> Void)? = nil

    private let cardBg = Color(red: 0.15, green: 0.18, blue: 0.15)
    private let green = Color(red: 0.2, green: 0.85, blue: 0.4)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Day \(day.dayNumber)")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Spacer()
                if let total = RouteLegFormatter.summary(distanceMeters: day.totalDistanceMeters, travelTime: day.totalTravelTime) {
                    Text(total)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                Image(systemName: "calendar")
                    .font(.subheadline)
                    .foregroundColor(green)
            }

            if day.places.isEmpty {
                Text("No places planned for this day.")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            } else {
                ForEach(Array(day.orderedPlaces.enumerated()), id: \.element.id) { index, place in
                    stopRow(place, index: index)
                }
            }
        }
        .padding(16)
        .background(cardBg)
        .cornerRadius(16)
    }

    private func stopRow(_ place: Place, index: Int) -> some View {
        HStack(spacing: 10) {
            Text("\(index + 1)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.black)
                .frame(width: 22, height: 22)
                .background(Circle().fill(green))

            VStack(alignment: .leading, spacing: 2) {
                Text(place.name)
                    .font(.subheadline)
                    .foregroundColor(.white)
                Text(SavedRouteCardPresentation.readableCategory(place.type))
                    .font(.caption)
                    .foregroundColor(.gray)
                if let leg = RouteLegFormatter.summary(distanceMeters: place.legDistanceMeters, travelTime: place.legTravelTime) {
                    Text(index == 0 ? "\(leg) from the city centre" : "\(leg) from the previous stop")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let onNavigate {
                Button {
                    onNavigate(place)
                } label: {
                    Image(systemName: "arrow.turn.up.right")
                        .foregroundColor(green)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Navigate to \(place.name)")
            }
        }
    }
}

enum RouteLegFormatter {
    /// Formats with the user's locale and units. Nil when MapKit gave no metrics,
    /// so public transport routes never show an invented travel time.
    static func summary(distanceMeters: Double?, travelTime: TimeInterval?) -> String? {
        guard let distanceMeters, let travelTime else { return nil }
        let distance = Measurement(value: distanceMeters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
        let time = Duration.seconds(travelTime)
            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
        return "\(distance) · \(time)"
    }
}

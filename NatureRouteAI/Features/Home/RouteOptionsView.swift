import SwiftUI

/// Список из 2–3 вариантов маршрута. Нажатие открывает обычный экран маршрута.
struct RouteOptionsView: View {
    let options: [RouteOption]

    private let darkBg = Color(red: 0.08, green: 0.10, blue: 0.08)
    private let cardBg = Color(red: 0.15, green: 0.18, blue: 0.15)
    private let green = Color(red: 0.2, green: 0.85, blue: 0.4)

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ForEach(options) { option in
                    NavigationLink {
                        RouteDetailView(route: option.route)
                    } label: {
                        optionCard(option)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
        }
        .background(darkBg.ignoresSafeArea())
        .navigationTitle("Route options")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func optionCard(_ option: RouteOption) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(option.title)
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(green)
                    .accessibilityHidden(true)
            }
            Text(option.subtitle)
                .font(.subheadline)
                .foregroundColor(.gray)
            Text(Self.totals(for: option.route))
                .font(.footnote.weight(.semibold))
                .foregroundColor(green)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBg, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    /// «9 stops · 84 km · 5 h 10 min». Километры и время берём из уже посчитанных ног маршрута.
    static func totals(for route: Route) -> String {
        let stops = route.days.reduce(0) { $0 + $1.places.count }
        var parts = ["\(stops) stops"]
        let meters = route.days.compactMap(\.totalDistanceMeters)
        if !meters.isEmpty {
            let kilometers = Measurement(value: meters.reduce(0, +), unit: UnitLength.meters)
                .converted(to: .kilometers).value
            parts.append("\(Int(kilometers.rounded())) km")
        }
        let seconds = route.days.compactMap(\.totalTravelTime).reduce(0, +)
        if seconds > 0 {
            parts.append(Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .narrow)))
        }
        return parts.joined(separator: " · ")
    }
}

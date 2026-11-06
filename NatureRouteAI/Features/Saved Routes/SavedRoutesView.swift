import SwiftUI
import SwiftData
import UIKit

struct SavedRoutesView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Route.createdAt, order: .reverse) private var routes: [Route]
    @State private var deletionConfirmation = SavedRouteDeletionConfirmation()
    @State private var deletionError: String?
    @State private var removedRouteIDs: Set<UUID> = []

    private var visibleRoutes: [Route] {
        routes.filter { !removedRouteIDs.contains($0.id) }
    }

    private var screenBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.08, green: 0.10, blue: 0.08)
            : Color(red: 0.96, green: 0.97, blue: 0.95)
    }
    private let green = Color(red: 0.2, green: 0.85, blue: 0.4)

    var body: some View {
        ZStack {
            screenBackground.ignoresSafeArea()
            if visibleRoutes.isEmpty {
                ContentUnavailableView {
                    Label("No saved routes", systemImage: "map")
                } description: {
                    Text("Plan a nature trip and save it to build your collection.")
                } actions: {
                    NavigationLink {
                        RoutePlannerView()
                    } label: {
                        Label("Plan a Route", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(green)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(visibleRoutes) { route in
                            HStack(spacing: 10) {
                                NavigationLink {
                                    RouteDetailView(route: route)
                                } label: {
                                    RouteCard(route: route)
                                }
                                .buttonStyle(.plain)

                                Menu {
                                    Button(role: .destructive) {
                                        deletionConfirmation.present(route)
                                    } label: {
                                        Label("Delete Route", systemImage: "trash")
                                    }
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .font(.headline)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }
                                .accessibilityLabel("Actions for \(route.city ?? "route")")
                            }
                            .transition(RouteMotion.transition(reduceMotion: reduceMotion))
                        }
                        recommendations
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Saved Routes")
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    RoutePlannerView()
                } label: {
                    Image(systemName: "plus")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.black)
                        .frame(width: 34, height: 34)
                        .background(green, in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .accessibilityLabel("Create a new route")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(screenBackground, for: .navigationBar)
        .toolbarColorScheme(colorScheme == .dark ? .dark : .light, for: .navigationBar)
        .animation(RouteMotion.animation(RouteMotion.reveal, reduceMotion: reduceMotion), value: visibleRoutes.map(\.id))
        .confirmationDialog(
            "Delete this route?",
            isPresented: $deletionConfirmation.isPresented,
            titleVisibility: .visible,
            presenting: deletionConfirmation.route
        ) { route in
            Button("Delete \(route.city ?? "Route")", role: .destructive) {
                delete(route)
            }
            Button("Cancel", role: .cancel) { deletionConfirmation.cancel() }
        } message: { route in
            Text("\(route.city ?? "This route") and its days and stops will be removed from Saved Routes.")
        }
        .alert("Couldn't Delete Route", isPresented: Binding(
            get: { deletionError != nil },
            set: { if !$0 { deletionError = nil } }
        )) {
            Button("OK", role: .cancel) { deletionError = nil }
        } message: {
            Text(deletionError ?? "Please try again.")
        }
    }

    private func delete(_ route: Route) {
        do {
            try SavedRouteStore.delete(route, from: modelContext)
            deletionConfirmation.cancel()
            withAnimation(RouteMotion.animation(RouteMotion.reveal, reduceMotion: reduceMotion)) {
                _ = removedRouteIDs.insert(route.id)
            }
        } catch {
            deletionError = error.localizedDescription
        }
    }

    @ViewBuilder
    private var recommendations: some View {
        let suggestions = ForYouSuggestion.from(routes: visibleRoutes)
        VStack(alignment: .leading, spacing: 12) {
            Text("For You")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
            Text("Ideas based on the nature in your saved routes.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if suggestions.isEmpty {
                ContentUnavailableView("No recommendations yet", systemImage: "sparkles", description: Text("Save a route to get ideas based on its nature spots."))
                    .frame(minHeight: 140)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(suggestions) { suggestion in
                            NavigationLink {
                                RoutePlannerView(city: suggestion.city, preselectedPreference: suggestion.preference)
                            } label: {
                                ForYouCard(suggestion: suggestion)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 24)
    }
}

struct SavedRouteDeletionConfirmation {
    var route: Route?
    var isPresented = false

    mutating func present(_ route: Route) {
        self.route = route
        isPresented = true
    }

    mutating func cancel() {
        route = nil
        isPresented = false
    }
}

struct ForYouSuggestion: Identifiable {
    let city: String
    let preference: String
    let symbol: String
    var id: String { "\(city.lowercased())-\(preference)" }

    static func from(routes: [Route]) -> [ForYouSuggestion] {
        var seen = Set<String>()
        return routes.flatMap { route -> [ForYouSuggestion] in
            let city = route.city?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !city.isEmpty else { return [] }
            let types = Set(route.days.flatMap(\.places).map(\.type))
            return types.sorted().compactMap { type -> ForYouSuggestion? in
                let value: (String, String)?
                switch type {
                case "mountain_peaks": value = ("Mountains", "mountain.2.fill")
                case "nature_reserves": value = ("Forest", "tree.fill")
                case "water": value = ("Lakes", "water.waves")
                case "waterfalls": value = ("Waterfalls", "water.waves")
                case "national_parks": value = ("National Parks", "leaf.fill")
                default: value = nil
                }
                guard let value else { return nil }
                let key = "\(city.lowercased())-\(value.0)"
                guard seen.insert(key).inserted else { return nil }
                return ForYouSuggestion(city: city, preference: value.0, symbol: value.1)
            }
        }
    }
}

private struct ForYouCard: View {
    let suggestion: ForYouSuggestion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: suggestion.symbol)
                .font(.title2)
                .foregroundStyle(.green)
                .frame(width: 46, height: 46)
                .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
            Text("Explore \(suggestion.preference.lowercased())")
                .font(.headline)
                .foregroundStyle(.primary)
            Text("Inspired by your saved trips in \(suggestion.city)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Label("Plan a trip", systemImage: "arrow.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
        }
        .frame(width: 190, alignment: .leading)
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens route planning with this city and nature preference selected")
    }
}

struct RouteCard: View {
    let route: Route

    private var totalPlaces: Int {
        route.days.reduce(0) { $0 + $1.places.count }
    }

    private var categories: [String] {
        SavedRouteCardPresentation.categories(for: route)
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            cardContent(imageSide: 88, compact: false)
            cardContent(imageSide: 68, compact: true)
        }
    }

    private func cardContent(imageSide: CGFloat, compact: Bool) -> some View {
        HStack(spacing: compact ? 9 : 12) {
            RouteThumbnail(route: route)
                .frame(width: imageSide, height: imageSide)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: compact ? 5 : 7) {
                Text(route.city ?? "Nature Route")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(categories.isEmpty ? "Nature getaway" : categories.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(compact ? 1 : 2)
                    .truncationMode(.tail)

                metadata

                Text(route.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(compact ? 10 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.07), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var dayLabel: some View {
        Label(SavedRouteCardPresentation.dayCount(route.days.count), systemImage: "calendar")
    }

    private var placeLabel: some View {
        Label(SavedRouteCardPresentation.placeCount(totalPlaces), systemImage: "mappin.and.ellipse")
    }

    private var transportLabel: some View {
        Label(route.transportMode.displayName, systemImage: route.transportMode.systemIcon)
    }

    /// One row when everything fits, otherwise two, and one per line at the
    /// largest text sizes, so details wrap instead of turning into "...".
    private var metadata: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 11) { dayLabel; placeLabel; transportLabel }
                .lineLimit(1)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) { dayLabel; placeLabel }
                transportLabel
            }
            .lineLimit(1)
            VStack(alignment: .leading, spacing: 4) { dayLabel; placeLabel; transportLabel }
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
    }

}

enum SavedRouteCardPresentation {
    static func dayCount(_ count: Int) -> String {
        count == 1 ? "1 day" : "\(count) days"
    }

    static func placeCount(_ count: Int) -> String {
        count == 1 ? "1 place" : "\(count) places"
    }

    static func categories(for route: Route) -> [String] {
        Array(Set(route.days.flatMap(\.places).map(\.type))).sorted().prefix(2).map(readableCategory)
    }

    static func imageSymbol(for route: Route) -> String {
        let types = Set(route.days.flatMap(\.places).map(\.type))
        let symbols: [String]
        if types.contains("waterfalls") || types.contains("water") { symbols = ["water.waves", "drop.fill", "humidity.fill"] }
        else if types.contains("mountain_peaks") { symbols = ["mountain.2.fill", "mountain.2", "sun.horizon.fill"] }
        else if types.contains("nature_reserves") || types.contains("national_parks") { symbols = ["tree.fill", "leaf.fill", "tree"] }
        else { symbols = ["leaf.fill", "globe.europe.africa.fill", "sun.max.fill"] }
        let seed = Int(UInt32(String(route.id.uuidString.last ?? "0"), radix: 16) ?? 0)
        return symbols[seed % symbols.count]
    }

    static func gradientColors(for route: Route) -> [Color] {
        let palettes: [[Color]] = [
            [.green.opacity(0.32), .teal.opacity(0.18), .primary.opacity(0.05)],
            [.blue.opacity(0.28), .cyan.opacity(0.17), .primary.opacity(0.05)],
            [.orange.opacity(0.24), .green.opacity(0.18), .primary.opacity(0.05)]
        ]
        let seed = Int(UInt32(String(route.id.uuidString.last ?? "0"), radix: 16) ?? 0)
        return palettes[seed % palettes.count]
    }

    static func readableCategory(_ type: String) -> String {
        switch type {
        case "mountain_peaks": "Mountains"
        case "nature_reserves", "natural": "Nature"
        case "water": "Lakes & water"
        case "waterfalls": "Waterfalls"
        case "national_parks": "National parks"
        default: type.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

private struct RouteThumbnail: View {
    @Environment(\.displayScale) private var displayScale
    let route: Route
    @State private var mapImage: UIImage?

    // Largest size RouteCard uses. Smaller cards scale this image down.
    private let imageSide: CGFloat = 88

    var body: some View {
        ZStack {
            LinearGradient(
                colors: SavedRouteCardPresentation.gradientColors(for: route),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: SavedRouteCardPresentation.imageSymbol(for: route))
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.green)
                .accessibilityHidden(true)

            if let mapImage {
                Image(uiImage: mapImage)
                    .resizable()
                    .scaledToFill()
                    .accessibilityHidden(true)
                    .transition(.opacity)
            }
        }
        .accessibilityLabel("Nature route thumbnail")
        .task(id: route.id) {
            let image = await RouteMapSnapshot.image(for: route, side: imageSide, displayScale: displayScale)
            withAnimation(.easeIn(duration: 0.2)) { mapImage = image }
        }
    }
}

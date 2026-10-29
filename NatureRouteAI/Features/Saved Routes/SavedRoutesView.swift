import SwiftUI
import SwiftData

struct SavedRoutesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Route.createdAt, order: .reverse) private var routes: [Route]
    @State private var routeToDelete: Route?
    @State private var isShowingDeleteConfirmation = false
    @State private var deletionError: String?

    private let darkBg = Color(red: 0.08, green: 0.10, blue: 0.08)
    private let cardBg = Color(red: 0.15, green: 0.18, blue: 0.15)
    private let green = Color(red: 0.2, green: 0.85, blue: 0.4)

    var body: some View {
        ZStack {
            darkBg.ignoresSafeArea()
            if routes.isEmpty {
                ContentUnavailableView {
                    Label("No saved routes", systemImage: "map")
                } description: {
                    Text("Create a nature trip and save it to see it here.")
                } actions: {
                    Button("Back to route planning") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .tint(green)
                }
                .foregroundStyle(.white)
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(routes) { route in
                            HStack(spacing: 10) {
                                NavigationLink {
                                    RouteDetailView(route: route)
                                } label: {
                                    RouteCard(route: route)
                                }
                                .buttonStyle(.plain)

                                Menu {
                                    Button(role: .destructive) {
                                        routeToDelete = route
                                        isShowingDeleteConfirmation = true
                                    } label: {
                                        Label("Delete Route", systemImage: "trash")
                                    }
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .font(.headline)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 36, height: 44)
                                        .contentShape(Rectangle())
                                }
                                .accessibilityLabel("Actions for \(route.city ?? "route")")
                            }
                        }
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
                    .minimumScaleFactor(0.8)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(darkBg, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .confirmationDialog(
            "Delete this route?",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible,
            presenting: routeToDelete
        ) { route in
            Button("Delete \(route.city ?? "Route")", role: .destructive) {
                delete(route)
            }
            Button("Cancel", role: .cancel) { routeToDelete = nil }
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
            try modelContext.transaction {
                modelContext.delete(route)
            }
            routeToDelete = nil
        } catch {
            deletionError = error.localizedDescription
        }
    }
}

struct RouteCard: View {
    let route: Route

    private var totalPlaces: Int {
        route.days.reduce(0) { $0 + $1.places.count }
    }

    private var categories: [String] {
        Array(Set(route.days.flatMap(\.places).map(\.type))).sorted().prefix(2).map(Self.readableCategory)
    }

    var body: some View {
        HStack(spacing: 12) {
            RouteThumbnail(route: route)
                .frame(width: 88, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 7) {
                Text(route.city ?? "Nature Route")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(categories.isEmpty ? "Nature getaway" : categories.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                ViewThatFits(in: .horizontal) {
                    metadata(compact: false)
                    metadata(compact: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.07), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func metadata(compact: Bool) -> some View {
        HStack(spacing: compact ? 7 : 11) {
            Label("\(route.days.count)d", systemImage: "calendar")
            Label("\(totalPlaces)", systemImage: "mappin.and.ellipse")
            Label(route.transportMode.displayName, systemImage: route.transportMode.systemIcon)
                .lineLimit(1)
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(.secondary)
    }

    private static func readableCategory(_ type: String) -> String {
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
    let route: Route

    private var symbol: String {
        let types = Set(route.days.flatMap(\.places).map(\.type))
        if types.contains("waterfalls") || types.contains("water") { return "water.waves" }
        if types.contains("mountain_peaks") { return "mountain.2.fill" }
        if types.contains("nature_reserves") || types.contains("national_parks") { return "tree.fill" }
        return "leaf.fill"
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.green.opacity(0.28), Color.teal.opacity(0.12), Color.primary.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.green)
                .accessibilityHidden(true)
        }
        .accessibilityLabel("Nature route thumbnail")
    }
}

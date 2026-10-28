import SwiftUI
import UIKit

struct RouteNavigationButton: View {
    let route: Route

    @State private var isChoosingProvider = false
    @State private var navigationError: String?
    @State private var stops: [NavigationStop] = []

    private let green = Color(red: 0.2, green: 0.85, blue: 0.4)

    var body: some View {
        Button(action: prepareRoute) {
            Label("Начать навигацию", systemImage: "location.north.line.fill")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(green, in: RoundedRectangle(cornerRadius: 14))
        }
        .confirmationDialog("Открыть навигацию", isPresented: $isChoosingProvider, titleVisibility: .visible) {
            ForEach(NavigationProvider.allCases) { provider in
                Button(provider.title) { open(provider) }
            }
            Button("Отмена", role: .cancel) { }
        } message: {
            Text("Откроется маршрут первого дня в режиме «\(route.transportMode.displayName)».")
        }
        .alert("Не удалось открыть навигатор", isPresented: Binding(
            get: { navigationError != nil },
            set: { if !$0 { navigationError = nil } }
        )) {
            Button("OK", role: .cancel) { navigationError = nil }
        } message: {
            Text(navigationError ?? "Попробуйте ещё раз.")
        }
    }

    private func prepareRoute() {
        guard let firstDay = route.days.sorted(by: { $0.dayNumber < $1.dayNumber })
            .first(where: { !$0.places.isEmpty }) else {
            navigationError = NavigationLinkError.noStops.localizedDescription
            return
        }

        do {
            stops = try firstDay.places.map {
                try NavigationStop(name: $0.name, latitude: $0.latitude, longitude: $0.longitude)
            }
            isChoosingProvider = true
        } catch {
            navigationError = error.localizedDescription
        }
    }

    private func open(_ provider: NavigationProvider) {
        do {
            let url = try RouteNavigationLinks.url(for: provider, stops: stops, transport: route.transportMode)
            Task { @MainActor in
                guard await UIApplication.shared.open(url) else {
                    navigationError = "\(provider.title) is unavailable. Check the link and try again."
                    return
                }
            }
        } catch {
            navigationError = error.localizedDescription
        }
    }
}

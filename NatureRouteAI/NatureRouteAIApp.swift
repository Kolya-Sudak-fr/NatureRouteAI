import SwiftUI
import SwiftData
import Foundation

@main
struct NatureRouteAIApp: App {
    private let modelContainer: ModelContainer

    init() {
        let schema = Schema([Route.self, RouteDay.self, Place.self])
        let isUITesting = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: isUITesting)
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create the app's SwiftData container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(modelContainer)
    }
}

private struct AppRootView: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ContentView()
            .task {
                #if DEBUG
                guard ProcessInfo.processInfo.arguments.contains("--seed-saved-route") else { return }
                let city = "UI Test City"
                let descriptor = FetchDescriptor<Route>(predicate: #Predicate { $0.city == city })
                if (try? modelContext.fetch(descriptor).isEmpty) == false { return }

                let place = Place(
                    name: "UI Test Nature Spot",
                    type: "nature_reserves",
                    city: city,
                    latitude: 52.0,
                    longitude: 5.0
                )
                let route = Route(city: city, days: [RouteDay(dayNumber: 1, places: [place])])
                modelContext.insert(route)
                try? modelContext.save()
                #endif
            }
    }
}

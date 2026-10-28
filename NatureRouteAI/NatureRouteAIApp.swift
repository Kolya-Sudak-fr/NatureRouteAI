import SwiftUI
import SwiftData

@main
struct NatureRouteAIApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
        // Говорим SwiftData какие модели хранить в базе.
        // Все три модели — Route, RouteDay, Place — должны быть здесь.
        // Без этого SwiftData не знает о существовании этих классов.
        .modelContainer(for: [Route.self, RouteDay.self, Place.self])
    }
}

import Foundation
import SwiftData

enum SavedRouteStore {
    static func delete(_ route: Route, from context: ModelContext) throws {
        let deletionContext = ModelContext(context.container)
        let routeID = route.id
        let descriptor = FetchDescriptor<Route>(predicate: #Predicate { $0.id == routeID })
        guard let persistedRoute = try deletionContext.fetch(descriptor).first else { return }

        deletionContext.delete(persistedRoute)
        do {
            try deletionContext.save()
        } catch {
            deletionContext.rollback()
            throw error
        }
    }
}

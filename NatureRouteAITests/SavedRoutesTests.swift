import XCTest
import SwiftData
@testable import NatureRouteAI

@MainActor
final class SavedRoutesTests: XCTestCase {
    func testCardPresentationHandlesMissingOptionalData() throws {
        let route = Route(city: nil, days: [RouteDay(dayNumber: 1, places: [])])
        XCTAssertTrue(SavedRouteCardPresentation.categories(for: route).isEmpty)
        XCTAssertFalse(SavedRouteCardPresentation.imageSymbol(for: route).isEmpty)
    }

    func testCoverSelectionIsStableAndDifferentForRoutesInSameCity() throws {
        let first = Route(city: "Utrecht", days: [RouteDay(dayNumber: 1, places: [place(type: "water")])])
        first.id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let second = Route(city: "Utrecht", days: [RouteDay(dayNumber: 1, places: [place(type: "water")])])
        second.id = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(SavedRouteCardPresentation.imageSymbol(for: first), SavedRouteCardPresentation.imageSymbol(for: first))
        XCTAssertNotEqual(SavedRouteCardPresentation.imageSymbol(for: first), SavedRouteCardPresentation.imageSymbol(for: second))
    }

    func testCoverSelectionSurvivesReadingRouteFromPersistentStore() throws {
        let (container, context) = try makeStore()
        let savedRoute = route(city: "Delft", placeName: "Forest path", type: "nature_reserves")
        context.insert(savedRoute)
        try context.save()
        let originalSymbol = SavedRouteCardPresentation.imageSymbol(for: savedRoute)

        let rereadContext = ModelContext(container)
        let reread = try XCTUnwrap(rereadContext.fetch(FetchDescriptor<Route>()).first)

        XCTAssertEqual(SavedRouteCardPresentation.imageSymbol(for: reread), originalSymbol)
    }

    func testDeletingOneRoutePersistsAndLeavesOtherRouteGraphIntact() throws {
        let (container, context) = try makeStore()
        let removed = route(city: "Same City", placeName: "Remove me")
        let retained = route(city: "Same City", placeName: "Keep me")
        context.insert(removed)
        context.insert(retained)
        try context.save()

        try SavedRouteStore.delete(removed, from: context)

        let rereadContext = ModelContext(container)
        let routes = try rereadContext.fetch(FetchDescriptor<Route>())
        XCTAssertEqual(routes.map(\.id), [retained.id])
        XCTAssertEqual(routes.first?.days.first?.places.first?.name, "Keep me")
        XCTAssertEqual(try rereadContext.fetch(FetchDescriptor<RouteDay>()).count, 1)
        XCTAssertEqual(try rereadContext.fetch(FetchDescriptor<Place>()).map(\.name), ["Keep me"])
    }

    func testNotConfirmingDeletionLeavesRouteInPersistentStore() throws {
        let (container, context) = try makeStore()
        let route = route(city: "Amsterdam", placeName: "Canal park")
        context.insert(route)
        try context.save()

        let rereadContext = ModelContext(container)
        XCTAssertEqual(try rereadContext.fetch(FetchDescriptor<Route>()).map(\.id), [route.id])
    }

    func testForYouSuggestionsUseSavedCategoriesAndNoPopularityClaims() throws {
        let route = route(city: "Leiden", placeName: "Lake", type: "water")
        let suggestions = ForYouSuggestion.from(routes: [route])
        XCTAssertEqual(suggestions.map(\.preference), ["Lakes"])
        XCTAssertFalse(suggestions.contains { $0.preference.localizedCaseInsensitiveContains("popular") })
    }

    private func makeStore() throws -> (ModelContainer, ModelContext) {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Route.self, RouteDay.self, Place.self, configurations: configuration)
        return (container, ModelContext(container))
    }

    private func route(city: String, placeName: String, type: String = "natural") -> Route {
        Route(city: city, days: [RouteDay(dayNumber: 1, places: [place(type: type, name: placeName)])])
    }

    private func place(type: String, name: String = "Nature spot") -> Place {
        Place(name: name, type: type, latitude: 52.0, longitude: 5.0)
    }
}

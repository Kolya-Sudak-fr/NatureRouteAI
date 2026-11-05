import XCTest
@testable import NatureRouteAI

final class RouteNavigationLinksTests: XCTestCase {
    func testAppleMapsPreservesWaypointOrderAndWalkingMode() throws {
        let stops = try [
            NavigationStop(name: "First", latitude: 52.1, longitude: 5.1),
            NavigationStop(name: "Second", latitude: 52.2, longitude: 5.2),
            NavigationStop(name: "Last", latitude: 52.3, longitude: 5.3)
        ]

        let url = try RouteNavigationLinks.url(for: .appleMaps, stops: stops, transport: .walking)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = components.queryItems ?? []

        XCTAssertEqual(components.host, "maps.apple.com")
        XCTAssertEqual(items.first(where: { $0.name == "destination" })?.value, "52.3,5.3")
        XCTAssertEqual(items.filter { $0.name == "waypoint" }.compactMap(\.value), ["52.1,5.1", "52.2,5.2"])
        XCTAssertEqual(items.first(where: { $0.name == "mode" })?.value, "walking")
    }

    func testGoogleMapsUsesBicyclingAndBoundsMobileRouteWaypoints() throws {
        let stops = try (1...6).map { index in
            try NavigationStop(name: "Stop \(index)", latitude: 52 + Double(index) / 100, longitude: 5 + Double(index) / 100)
        }

        let url = try RouteNavigationLinks.url(for: .googleMaps, stops: stops, transport: .cycling)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = components.queryItems ?? []
        let coordinates = items.first(where: { $0.name == "waypoints" })?.value?.components(separatedBy: "|")

        XCTAssertEqual(components.host, "www.google.com")
        XCTAssertEqual(items.first(where: { $0.name == "travelmode" })?.value, "bicycling")
        XCTAssertEqual(coordinates?.count, 3)
        XCTAssertEqual(items.first(where: { $0.name == "destination" })?.value, stops[3].coordinateQuery)
    }

    func testPublicTransportUsesExternalTransitMode() throws {
        let stop = try NavigationStop(name: "Station", latitude: 52.1, longitude: 5.1)
        let url = try RouteNavigationLinks.url(for: .googleMaps, stops: [stop], transport: .publicTransport)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "travelmode" })?.value, "transit")
    }

    func testRejectsEmptyAndInvalidStops() throws {
        XCTAssertThrowsError(try NavigationStop(name: "  ", latitude: 52, longitude: 5))
        XCTAssertThrowsError(try NavigationStop(name: "Outside", latitude: 100, longitude: 5))
        XCTAssertThrowsError(try RouteNavigationLinks.url(for: .appleMaps, stops: [], transport: .car))
    }
}

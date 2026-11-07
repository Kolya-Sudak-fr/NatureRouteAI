import CoreLocation
import MapKit
import UIKit

/// Renders a small map of a route's stops. Each route gets its own picture
/// without a photo service, licensing questions or stored image files.
enum RouteMapSnapshot {
    private nonisolated static let minimumSpan = 0.05
    private nonisolated static let spanPadding = 1.5
    private static let cache = NSCache<NSString, UIImage>()

    /// Nil without any valid coordinate, so callers can keep their placeholder.
    nonisolated static func region(containing coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion? {
        let valid = coordinates.filter(CLLocationCoordinate2DIsValid)
        guard let minLatitude = valid.map(\.latitude).min(),
              let maxLatitude = valid.map(\.latitude).max(),
              let minLongitude = valid.map(\.longitude).min(),
              let maxLongitude = valid.map(\.longitude).max() else {
            return nil
        }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLatitude + maxLatitude) / 2,
                longitude: (minLongitude + maxLongitude) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLatitude - minLatitude) * spanPadding, minimumSpan),
                longitudeDelta: max((maxLongitude - minLongitude) * spanPadding, minimumSpan)
            )
        )
    }

    /// Nil when offline or when MapKit fails. The picture is decoration, so
    /// failing quietly and keeping the placeholder is the right behaviour.
    static func image(for route: Route, side: CGFloat, displayScale: CGFloat) async -> UIImage? {
        let cacheKey = "\(route.id.uuidString)-\(side)-\(displayScale)" as NSString
        if let cached = cache.object(forKey: cacheKey) { return cached }

        let stops = route.days.flatMap(\.places).map(\.coordinate)
        guard let region = region(containing: stops) else { return nil }

        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = CGSize(width: side, height: side)
        options.traitCollection = UITraitCollection { traits in
            traits.userInterfaceStyle = .dark
            traits.displayScale = displayScale
        }
        options.pointOfInterestFilter = .excludingAll
        options.showsBuildings = false
        let snapshotter = MKMapSnapshotter(options: options)

        do {
            let snapshot: MKMapSnapshotter.Snapshot = try await withPromptCancellation(
                start: { finish in
                    snapshotter.start { snapshot, error in
                        if let snapshot {
                            finish(.success(snapshot))
                        } else {
                            finish(.failure(error ?? MKError(.unknown)))
                        }
                    }
                },
                cancel: { snapshotter.cancel() }
            )
            let image = imageWithStops(stops, on: snapshot)
            cache.setObject(image, forKey: cacheKey)
            return image
        } catch {
            return nil
        }
    }

    private static func imageWithStops(_ stops: [CLLocationCoordinate2D], on snapshot: MKMapSnapshotter.Snapshot) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = snapshot.image.scale
        return UIGraphicsImageRenderer(size: snapshot.image.size, format: format).image { _ in
            snapshot.image.draw(at: .zero)
            let radius: CGFloat = 3.5
            for stop in stops where CLLocationCoordinate2DIsValid(stop) {
                let point = snapshot.point(for: stop)
                let dot = UIBezierPath(ovalIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
                UIColor(red: 0.2, green: 0.85, blue: 0.4, alpha: 1).setFill()
                dot.fill()
                UIColor.white.setStroke()
                dot.lineWidth = 1
                dot.stroke()
            }
        }
    }
}

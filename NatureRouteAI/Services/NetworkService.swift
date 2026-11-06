import Foundation
import CoreLocation

class NetworkService {
    
    private let apiKey: String
    private let session: URLSession
    private let rateLimitRetryDelay: Duration
    private let unratedSearchLimit = 200

    init(apiKey: String = Secrets.openTripMapKey, session: URLSession? = nil, rateLimitRetryDelay: Duration = .seconds(1)) {
        self.apiKey = apiKey
        self.rateLimitRetryDelay = rateLimitRetryDelay
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 60
            self.session = URLSession(configuration: configuration)
        }
    }
    
    func fetchPlaces(
        lat: Double,
        lon: Double,
        kinds: String,
        preference: String,
        count: Int,
        radiusMeters: Int = 50_000
    ) async throws -> [RoutePlaceCandidate] {
        
        // Rated places always have names. Unfiltered results are mostly nameless,
        // and the limit applies before those can be dropped, so a small limit could
        // return almost nothing usable.
        var places = try await requestPlaces(lat: lat, lon: lon, kinds: kinds, preference: preference, limit: count, minimumRate: 1, radiusMeters: radiusMeters)

        if places.count < count {
            do {
                let unrated = try await requestPlaces(lat: lat, lon: lon, kinds: kinds, preference: preference, limit: unratedSearchLimit, minimumRate: nil, radiusMeters: radiusMeters)
                let offset = places.count
                places += unrated.map { place in
                    var place = place
                    place.sourceOrder += offset
                    return place
                }
            } catch where !places.isEmpty && !Task.isCancelled {
                // The rated places are still usable.
            }
        }

        guard !places.isEmpty else {
            throw AppError.noPlacesFound
        }

        return places
    }

    private func requestPlaces(
        lat: Double,
        lon: Double,
        kinds: String,
        preference: String,
        limit: Int,
        minimumRate: Int?,
        radiusMeters: Int
    ) async throws -> [RoutePlaceCandidate] {
        var components = URLComponents(string: "https://api.opentripmap.com/0.1/en/places/radius")!
        components.queryItems = [
            URLQueryItem(name: "radius", value: "\(radiusMeters)"),
            URLQueryItem(name: "lon", value: "\(lon)"),
            URLQueryItem(name: "lat", value: "\(lat)"),
            URLQueryItem(name: "kinds", value: kinds),
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "apikey", value: apiKey)
        ]
        if let minimumRate {
            components.queryItems?.append(URLQueryItem(name: "rate", value: "\(minimumRate)"))
        }

        guard let url = components.url else {
            throw AppError.unknown
        }

        let data = try await fetchData(from: url)
        let json = try JSONDecoder().decode(PlacesResponse.self, from: data)

        return json.features.enumerated().compactMap { index, feature -> RoutePlaceCandidate? in
            let name = feature.properties.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let coordinates = feature.geometry.coordinates
            guard !name.isEmpty, coordinates.count >= 2 else { return nil }

            let longitude = coordinates[0]
            let latitude = coordinates[1]
            guard CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: latitude, longitude: longitude)) else {
                return nil
            }

            return RoutePlaceCandidate(
                externalID: feature.properties.xid,
                name: name,
                type: kinds,
                latitude: latitude,
                longitude: longitude,
                preferences: [preference],
                quality: feature.properties.rate,
                sourceOrder: index
            )
        }
    }

    /// OpenTripMap limits requests per second, so one short wait usually clears a 429.
    private func fetchData(from url: URL) async throws -> Data {
        var (data, response) = try await session.data(from: url)
        if (response as? HTTPURLResponse)?.statusCode == 429 {
            try await Task.sleep(for: rateLimitRetryDelay)
            (data, response) = try await session.data(from: url)
        }

        if let httpResponse = response as? HTTPURLResponse {
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw AppError.serverError(httpResponse.statusCode)
            }
        }
        return data
    }

    // MARK: - Response Models
    private struct PlacesResponse: Decodable {
        let features: [Feature]
    }
    
    private struct Feature: Decodable {
        let geometry: Geometry
        let properties: Properties
    }
    
    private struct Geometry: Decodable {
        let coordinates: [Double]
    }
    
    private struct Properties: Decodable {
        let name: String
        let xid: String?
        let rate: Int?
    }
}

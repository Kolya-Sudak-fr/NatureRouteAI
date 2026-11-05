import Foundation
import CoreLocation

class NetworkService {
    
    private let apiKey: String
    private let session: URLSession

    init(apiKey: String = Secrets.openTripMapKey, session: URLSession? = nil) {
        self.apiKey = apiKey
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 60
            self.session = URLSession(configuration: configuration)
        }
    }
    
    func fetchCityCoordinate(city: String) async throws -> (lat: Double, lon: Double) {
        
        var components = URLComponents(string: "https://api.opentripmap.com/0.1/en/places/geoname")!
        components.queryItems = [
            URLQueryItem(name: "name", value: city),
            URLQueryItem(name: "apikey", value: apiKey)
        ]
        
        guard let url = components.url else {
            throw AppError.unknown
        }
        
        let (data, response) = try await session.data(from: url)
        
        if let httpResponse = response as? HTTPURLResponse {
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw AppError.serverError(httpResponse.statusCode)
            }
        }
        
        let json = try JSONDecoder().decode(CityResponse.self, from: data)
        
        guard json.status == "OK" else {
            throw AppError.cityNotFound
        }
        
        guard let lat = json.lat, let lon = json.lon else {
            throw AppError.unknown
        }

        guard CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: lat, longitude: lon)) else {
            throw AppError.unknown
        }
        
        return (lat: lat, lon: lon)
    }
    
    func fetchPlaces(
        lat: Double,
        lon: Double,
        kinds: String,
        preference: String,
        count: Int,
        radiusMeters: Int = 50_000
    ) async throws -> [RoutePlaceCandidate] {
        
        var components = URLComponents(string: "https://api.opentripmap.com/0.1/en/places/radius")!
        components.queryItems = [
            URLQueryItem(name: "radius", value: "\(radiusMeters)"),
            URLQueryItem(name: "lon", value: "\(lon)"),
            URLQueryItem(name: "lat", value: "\(lat)"),
            URLQueryItem(name: "kinds", value: kinds),
            URLQueryItem(name: "limit", value: "\(count)"),
            URLQueryItem(name: "apikey", value: apiKey)
        ]
        
        guard let url = components.url else {
            throw AppError.unknown
        }
        
        let (data, response) = try await session.data(from: url)
        
        if let httpResponse = response as? HTTPURLResponse {
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw AppError.serverError(httpResponse.statusCode)
            }
        }
        
        let json = try JSONDecoder().decode(PlacesResponse.self, from: data)
        
        let validPlaces = json.features.enumerated().compactMap { index, feature -> RoutePlaceCandidate? in
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
        
        guard !validPlaces.isEmpty else {
            throw AppError.noPlacesFound
        }
        
        return validPlaces
    }
    
    // MARK: - Response Models
    private struct CityResponse: Decodable {
        let lat: Double?
        let lon: Double?
        let status: String
        let partial_match: Bool?
    }
    
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

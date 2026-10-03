import Foundation
import CoreLocation

class NetworkService {
    
    private let apiKey = Secrets.openTripMapKey
    
    func fetchCityCoordinate(city: String) async throws -> (lat: Double, lon: Double) {
        
        var components = URLComponents(string: "https://api.opentripmap.com/0.1/en/places/geoname")!
        components.queryItems = [
            URLQueryItem(name: "name", value: city),
            URLQueryItem(name: "apikey", value: apiKey)
        ]
        
        guard let url = components.url else {
            throw AppError.unknown
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        if let httpResponse = response as? HTTPURLResponse {
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw AppError.serverError(httpResponse.statusCode)
            }
        }
        
        #if DEBUG
        print("City API response: \(String(data: data, encoding: .utf8) ?? "nil")")
        #endif
        let json = try JSONDecoder().decode(CityResponse.self, from: data)
        
        guard json.status == "OK" else {
            throw AppError.cityNotFound
        }
        
        guard let lat = json.lat, let lon = json.lon else {
            throw AppError.unknown
        }
        
        return (lat: lat, lon: lon)
    }
    
    func fetchPlaces(lat: Double, lon: Double, kinds: String, count: Int) async throws -> [Place] {
        
        var components = URLComponents(string: "https://api.opentripmap.com/0.1/en/places/radius")!
        components.queryItems = [
            URLQueryItem(name: "radius", value: "50000"),
            URLQueryItem(name: "lon", value: "\(lon)"),
            URLQueryItem(name: "lat", value: "\(lat)"),
            URLQueryItem(name: "kinds", value: kinds),
            URLQueryItem(name: "limit", value: "\(count)"),
            URLQueryItem(name: "apikey", value: apiKey)
        ]
        
        guard let url = components.url else {
            throw AppError.unknown
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        if let httpResponse = response as? HTTPURLResponse {
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw AppError.serverError(httpResponse.statusCode)
            }
        }
        #if DEBUG
        print("Places API response: \(String(data: data, encoding: .utf8) ?? "nil")")
        #endif
        let json = try JSONDecoder().decode(PlacesResponse.self, from: data)
        
        let validPlaces = json.features.filter { !$0.properties.name.isEmpty }
        
        guard !validPlaces.isEmpty else {
            throw AppError.noPlacesFound
        }
        
        return validPlaces.map { feature in
            Place(
                name: feature.properties.name,
                type: kinds,
                city: "",
                coordinate: .init(
                    latitude: feature.geometry.coordinates[1],
                    longitude: feature.geometry.coordinates[0]
                )
            )
        }
    }
    
    // MARK: - Response Models
    // Эти структуры private — используются только внутри NetworkService
    
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
    }
}

import Foundation
import CoreLocation

class NetworkService {
    
    private let apiKey = Secrets.openTripMapKey
    private let baseURL = "https://api.opentripmap.com/0.1/en/places"
    
    // Получаем координаты города по названию
    func fetchCityCoordinate(city: String) async throws -> (lat: Double, lon: Double) {
        
        let urlString = "https://api.opentripmap.com/0.1/en/places/geoname?name=\(city)&apikey=\(apiKey)"
        
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        // Проверяем HTTP статус код — 200-299 это успех
        if let httpResponse = response as? HTTPURLResponse {
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw AppError.serverError(httpResponse.statusCode)
            }
        }
        
        print("City API response: \(String(data: data, encoding: .utf8) ?? "nil")")
        
        let json = try JSONDecoder().decode(CityResponse.self, from: data)
        
        // Если API вернул NOT_FOUND — город не существует
        guard json.status == "OK" else {
            throw AppError.cityNotFound
        }
        
        // Разворачиваем Optional координаты
        guard let lat = json.lat, let lon = json.lon else {
            throw AppError.unknown
        }
        
        return (lat: lat, lon: lon)
    }
    
    // Получаем места рядом с координатами по категории
    func fetchPlaces(lat: Double, lon: Double, kinds: String, count: Int) async throws -> [Place] {
        
        let urlString = "\(baseURL)/radius?radius=50000&lon=\(lon)&lat=\(lat)&kinds=\(kinds)&limit=\(count)&apikey=\(apiKey)"
        
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        // Проверяем HTTP статус код
        if let httpResponse = response as? HTTPURLResponse {
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw AppError.serverError(httpResponse.statusCode)
            }
        }
        
        print("Places API response: \(String(data: data, encoding: .utf8) ?? "nil")")
        
        let json = try JSONDecoder().decode(PlacesResponse.self, from: data)
        
        // Фильтруем места без названия
        let validPlaces = json.features.filter { !$0.properties.name.isEmpty }
        
        // Если мест нет — бросаем ошибку
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
}

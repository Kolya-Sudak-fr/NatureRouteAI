//
//  NetworkService.swift
//  NatureRouteAI
//
//  Created by Kolya Sudak on 03/06/2026.
//5ae2e3f221c38a28845f05b6395bc7aecc6edb35ed8696bd0ee69463

import Foundation
internal import _LocationEssentials

class NetworkService {
    
    private let apiKey = Secrets.openTripMapKey
    private let baseURL = "https://api.opentripmap.com/0.1/en/places"
    
    // Шаг 1 — получаем координаты города по названию
    func fetchCityCoordinate(city: String) async throws -> (lat: Double, lon: Double) {
        

        let urlString = "https://api.opentripmap.com/0.1/en/places/geoname?name=\(city)&apikey=\(apiKey)"
        
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        
        // Временно печатаем сырой ответ от API
        print("City API response: \(String(data: data, encoding: .utf8) ?? "nil")")
        
        let json = try JSONDecoder().decode(CityResponse.self, from: data)
        return (lat: json.lat, lon: json.lon)
    }
    
    // Шаг 2 — получаем места рядом с координатами по категории
    func fetchPlaces(lat: Double, lon: Double, kinds: String, count: Int) async throws -> [Place] {
        
        let urlString = "\(baseURL)/radius?radius=10000&lon=\(lon)&lat=\(lat)&kinds=\(kinds)&limit=\(count)&apikey=\(apiKey)"
        
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let json = try JSONDecoder().decode(PlacesResponse.self, from: data)
        
        return json.features.map { feature in
            Place(
                name: feature.properties.name.isEmpty ? "Unknown Place" : feature.properties.name,
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
    let lat: Double
    let lon: Double
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

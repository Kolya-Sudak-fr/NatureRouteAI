import Foundation

enum AppError: Error {

    case cityNotFound
    case noPlacesFound
    case noRouteablePlaces
    case routePlanningLimitReached
    case routeServiceUnavailable
    case invalidRouteRequest
    case noInternetConnection
    case serverError(Int)
    case unknown
    
    var userMessage: String {
        switch self {
        case .cityNotFound:
            return "City not found. Check the spelling and try again."
        case .noPlacesFound:
            return "No nature spots found in this area. Try a different city or different preferences."
        case .noRouteablePlaces:
            return "Nature spots were found, but Apple Maps couldn't calculate travel routes to them. Try another city or transport mode."
        case .routePlanningLimitReached:
            return "Nature spots were found, but the route-planning request limit was reached before a usable route could be confirmed. Try fewer places or another city."
        case .routeServiceUnavailable:
            return "Apple Maps isn't answering route requests right now. Check your connection, wait about a minute, and try again."
        case .invalidRouteRequest:
            return "Choose at least one nature preference and a valid trip length before generating a route."
        case .noInternetConnection:
            return "No internet connection. Check your connection and try again."
        case .serverError(let code):
            return "Service error (\(code)). Please try again later."
        case .unknown:
            return "Something went wrong. Please try again."
        }
    }
}

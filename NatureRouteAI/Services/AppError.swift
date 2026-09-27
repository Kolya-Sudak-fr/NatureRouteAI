import Foundation

enum AppError: Error {

    case cityNotFound
    case noPlacesFound
    case noInternetConnection
    case serverError(Int)
    case unknown
    
    var userMessage: String {
        switch self {
        case .cityNotFound:
            return "City not found. Check the spelling and try again."
        case .noPlacesFound:
            return "No nature spots found in this area. Try a different city or different preferences."
        case .noInternetConnection:
            return "No internet connection. Check your connection and try again."
        case .serverError(let code):
            return "Service error (\(code)). Please try again later."
        case .unknown:
            return "Something went wrong. Please try again."
        }
    }
}

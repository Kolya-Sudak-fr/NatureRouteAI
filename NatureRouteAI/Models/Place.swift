import Foundation

struct Place: Identifiable {
    
    let id = UUID()
    let name: String
    let type: String
    let city: String
}

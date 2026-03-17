import SwiftUI

struct RoutePlannerView: View {
    
    @State private var preferences: [NaturePreference] = [
        NaturePreference(title: "Mountains", isSelected: false),
        NaturePreference(title: "Forest", isSelected: false),
        NaturePreference(title: "Lakes", isSelected: false),
        NaturePreference(title: "Waterfalls", isSelected: false),
        NaturePreference(title: "National Parks", isSelected: false),
    ]
    
    @State private var city: String = ""
    @State private var tripDays: Int = 3
    @State private var placesPerDay: Int = 3
    @State private var route: Route?
    
    var selectedPreferences: [NaturePreference] {
        preferences.filter { $0.isSelected }
    }
    
    var body: some View {
        
        ScrollView{
            
            VStack(alignment: .leading, spacing: 25){
                
                Text("Plan your trip")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                //City
                VStack(alignment: .leading){
                    
                    Text("City")
                        .font(.headline)
                    
                    TextField("Enter city", text: $city)
                        .textFieldStyle(.roundedBorder)
                    
                }
                
                //Trip days
                
                VStack(alignment: .leading){
                    
                    Text("Trip duration")
                        .font(.headline)
                    
                    Stepper("\(tripDays) days", value: $tripDays, in: 1...14)
                    
                }
                
                //Places per day
                
                VStack(alignment: .leading){
                    Text("Places per day")
                        .font(.headline)
                    
                    Stepper("\(placesPerDay)", value: $placesPerDay, in: 1...10)
                }
                
                //Preferences
                
                Text("Nature preferences")
                    .font(.headline)
                
                ForEach($preferences) { $preference in
                    
                    Toggle(preference.title,
                           isOn: $preference.isSelected)
                }
                
                //Button
                
                Button(action: generateRoute) {
                    Text("Generate route")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(selectedPreferences.isEmpty ? Color.gray : Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .disabled(selectedPreferences.isEmpty)
                if let route = route {
                    
                    VStack(alignment: .leading, spacing: 16) {
                        
                        Text("Your Route")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        ForEach(route.days) { day in
                            
                            VStack(alignment: .leading) {
                                
                                Text("Day \(day.dayNumber)")
                                    .font(.headline)
                                
                                ForEach(day.places, id: \.self) { place in
                                    Text("• \(place)")
                                }
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }
    
        func generateRoute()  {
            
            let selected = preferences
                .filter { $0.isSelected }
                .map { $0.title }
            
            let generator = RouteGenerator()
            
            route = generator.generateRoute(
                city: city,
                days: tripDays,
                placesPerDay: placesPerDay,
                preferences: selected
                )
            }
        }

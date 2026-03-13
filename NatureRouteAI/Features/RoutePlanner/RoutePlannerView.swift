import SwiftUI

struct RoutePlannerView: View {
    
    @State private var preferences: [NaturePreference] = [
        NaturePreference(title: "Mountains", isSelected: false),
        NaturePreference(title: "Forest", isSelected: false),
        NaturePreference(title: "Lakes", isSelected: false),
        NaturePreference(title: "Waterfalls", isSelected: false),
        NaturePreference(title: "National Parks", isSelected: false),
    ]
    
    var selectedPreferences: [NaturePreference] {
        preferences.filter { $0.isSelected }
    }
    
    var body: some View {
        
        VStack(alignment: .leading, spacing: 20){
            
            Text("Choose nature preferences")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            List {
                ForEach($preferences) { $preference in
                    
                    Toggle(preference.title,
                           isOn: $preference.isSelected)
                    
                }
            }
            
            Button(action: generateRoute){
                
                        Text("Generate Route")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(selectedPreferences.isEmpty ? Color.gray : Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                .disabled(selectedPreferences.isEmpty)
                }
                .padding()
        }
        
        func generateRoute() {
            
            let selected = preferences
                .filter { $0.isSelected }
                .map{ $0.title}
            
            print("selected preferences:", selected)
            
        }
    }

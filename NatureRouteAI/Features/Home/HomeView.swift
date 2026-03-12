import SwiftUI

struct HomeView: View {
    
    var body: some View {
        
        NavigationStack {
            
            VStack(alignment: .leading, spacing: 25) {
                
                Text("NatureRoute AI")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Plan nature trips based on your preferences")
                    .foregroundColor(.gray)
                
                
                VStack(spacing: 16) {
                    
                    NavigationLink {
                        RoutePlannerView()
                    } label: {
                        HomeButton(title: "Plan new route",
                                   icon: "map")
                    }
                    
                    
                    NavigationLink {
                        MapView()
                    } label: {
                        HomeButton(title: "Explore map",
                                   icon: "globe.europe.africa")
                    }
                    
                    
                    NavigationLink {
                        Text("Saved Routes Screen")
                    } label: {
                        HomeButton(title: "Saved routes",
                                   icon: "bookmark")
                    }
                    
                }
                
                Spacer()
                
            }
            .padding()
            .navigationTitle("Home")
            
        }
        
    }
}

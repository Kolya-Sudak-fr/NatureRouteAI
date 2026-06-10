import SwiftUI

struct HomeView: View {
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Тёмный фон
                Color(red: 0.08, green: 0.10, blue: 0.08)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        
                        // Header
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("NatureRoute")
                                    .font(.largeTitle)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                + Text(" AI")
                                    .font(.largeTitle)
                                    .fontWeight(.bold)
                                    .foregroundColor(Color(red: 0.2, green: 0.85, blue: 0.4))
                                
                                Text("🌿")
                                    .font(.largeTitle)
                            }
                            
                            Text("Discover real nature around you")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                        .padding(.top, 12)
                        
                        // Main action card
                        NavigationLink {
                            RoutePlannerView()
                        } label: {
                            ZStack(alignment: .bottomLeading) {
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(Color(red: 0.2, green: 0.85, blue: 0.4))
                                    .frame(height: 160)
                                
                                VStack(alignment: .leading, spacing: 6) {
                                    Image(systemName: "map.fill")
                                        .font(.title)
                                        .foregroundColor(.black.opacity(0.7))
                                    
                                    Text("Plan new route")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.black)
                                    
                                    Text("AI builds your perfect nature trip")
                                        .font(.caption)
                                        .foregroundColor(.black.opacity(0.6))
                                }
                                .padding(20)
                            }
                        }
                        
                        // Secondary buttons
                        HStack(spacing: 12) {
                            NavigationLink {
                                MapView()
                            } label: {
                                SecondaryCard(
                                    icon: "globe.europe.africa.fill",
                                    title: "Explore map",
                                    color: Color(red: 0.15, green: 0.18, blue: 0.15)
                                )
                            }
                            
                            NavigationLink {
                                Text("Saved Routes")
                                    .foregroundColor(.white)
                            } label: {
                                SecondaryCard(
                                    icon: "bookmark.fill",
                                    title: "Saved routes",
                                    color: Color(red: 0.15, green: 0.18, blue: 0.15)
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .navigationBarHidden(true)
        }
    }
}

// Отдельный компонент для secondary кнопок
struct SecondaryCard: View {
    let icon: String
    let title: String
    let color: Color
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 16)
                .fill(color)
                .frame(height: 120)
            
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(Color(red: 0.2, green: 0.85, blue: 0.4))
                
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity)
    }
}

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
    @State private var isLoading: Bool = false
    
    private let green = Color(red: 0.2, green: 0.85, blue: 0.4)
    private let darkBg = Color(red: 0.08, green: 0.10, blue: 0.08)
    private let cardBg = Color(red: 0.15, green: 0.18, blue: 0.15)
    
    var selectedPreferences: [NaturePreference] {
        preferences.filter { $0.isSelected }
    }
    
    var body: some View {
        ZStack {
            darkBg.ignoresSafeArea()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    
                    // Header
                    Text("Plan your trip")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.top, 8)
                    
                    // City input
                    VStack(alignment: .leading, spacing: 8) {
                        Label("City", systemImage: "mappin.circle.fill")
                            .font(.headline)
                            .foregroundColor(green)
                        
                        TextField("", text: $city, prompt: Text("Enter city").foregroundColor(.gray))
                            .foregroundColor(.white)
                            .padding()
                            .background(cardBg)
                            .cornerRadius(12)
                    }
                    
                    // Trip duration
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Trip duration", systemImage: "calendar")
                            .font(.headline)
                            .foregroundColor(green)
                        
                        HStack {
                            Text("\(tripDays) days")
                                .foregroundColor(.white)
                                .font(.title3)
                                .fontWeight(.semibold)
                            
                            Spacer()
                            
                            HStack(spacing: 0) {
                                Button {
                                    if tripDays > 1 { tripDays -= 1 }
                                } label: {
                                    Image(systemName: "minus")
                                        .foregroundColor(.white)
                                        .frame(width: 44, height: 44)
                                        .background(cardBg)
                                }
                                
                                Divider()
                                    .frame(height: 44)
                                    .background(.gray)
                                
                                Button {
                                    if tripDays < 14 { tripDays += 1 }
                                } label: {
                                    Image(systemName: "plus")
                                        .foregroundColor(.white)
                                        .frame(width: 44, height: 44)
                                        .background(cardBg)
                                }
                            }
                            .cornerRadius(12)
                        }
                        .padding()
                        .background(cardBg)
                        .cornerRadius(12)
                    }
                    
                    // Places per day
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Places per day", systemImage: "location.fill")
                            .font(.headline)
                            .foregroundColor(green)
                        
                        HStack {
                            Text("\(placesPerDay) places")
                                .foregroundColor(.white)
                                .font(.title3)
                                .fontWeight(.semibold)
                            
                            Spacer()
                            
                            HStack(spacing: 0) {
                                Button {
                                    if placesPerDay > 1 { placesPerDay -= 1 }
                                } label: {
                                    Image(systemName: "minus")
                                        .foregroundColor(.white)
                                        .frame(width: 44, height: 44)
                                        .background(cardBg)
                                }
                                
                                Divider()
                                    .frame(height: 44)
                                    .background(.gray)
                                
                                Button {
                                    if placesPerDay < 10 { placesPerDay += 1 }
                                } label: {
                                    Image(systemName: "plus")
                                        .foregroundColor(.white)
                                        .frame(width: 44, height: 44)
                                        .background(cardBg)
                                }
                            }
                            .cornerRadius(12)
                        }
                        .padding()
                        .background(cardBg)
                        .cornerRadius(12)
                    }
                    
                    // Nature preferences
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Nature preferences", systemImage: "leaf.fill")
                            .font(.headline)
                            .foregroundColor(green)
                        
                        // Chip-стиль вместо Toggle
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 10) {
                            ForEach($preferences) { $pref in
                                Button {
                                    pref.isSelected.toggle()
                                } label: {
                                    HStack {
                                        Image(systemName: pref.isSelected ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(pref.isSelected ? .black : .gray)
                                        Text(pref.title)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundColor(pref.isSelected ? .black : .white)
                                    }
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 14)
                                    .frame(maxWidth: .infinity)
                                    .background(pref.isSelected ? green : cardBg)
                                    .cornerRadius(10)
                                }
                            }
                        }
                    }
                    
                    // Generate button
                    Button(action: generateRoute) {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .tint(.black)
                                Text("Building your route...")
                                    .fontWeight(.semibold)
                                    .foregroundColor(.black)
                            } else {
                                Image(systemName: "sparkles")
                                Text("Generate route")
                                    .fontWeight(.semibold)
                            }
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(selectedPreferences.isEmpty || city.isEmpty ? Color.gray : green)
                        .cornerRadius(14)
                    }
                    .disabled(selectedPreferences.isEmpty || city.isEmpty || isLoading)
                    
                    // Route result
                    if let route = route {
                        VStack(alignment: .leading, spacing: 16) {
                            
                            Text("Your Route")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            
                            ForEach(route.days) { day in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Day \(day.dayNumber)")
                                        .font(.headline)
                                        .foregroundColor(green)
                                    
                                    ForEach(day.places) { place in
                                        HStack {
                                            Circle()
                                                .fill(green)
                                                .frame(width: 8, height: 8)
                                            Text(place.name)
                                                .foregroundColor(.white)
                                                .font(.subheadline)
                                        }
                                    }
                                }
                                .padding()
                                .background(cardBg)
                                .cornerRadius(12)
                            }
                            
                            NavigationLink {
                                MapView(route: route)
                            } label: {
                                HStack {
                                    Image(systemName: "map.fill")
                                    Text("View on Map")
                                        .fontWeight(.semibold)
                                }
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(green)
                                .cornerRadius(14)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(darkBg, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
    
    func generateRoute() {
        let selected = preferences
            .filter { $0.isSelected }
            .map { $0.title }
        
        let generator = RouteGenerator()
        isLoading = true
        
        Task {
            do {
                route = try await generator.generateRoute(
                    city: city,
                    days: tripDays,
                    placesPerDay: placesPerDay,
                    preferences: selected
                )
            } catch {
                print("Error generating route: \(error)")
            }
            isLoading = false
        }
    }
}

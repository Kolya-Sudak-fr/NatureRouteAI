import SwiftUI

struct HomeView: View {
    @StateObject private var assistant = HomeTripAssistantViewModel()

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
                                
                                Image(systemName: "leaf.fill")
                                    .font(.largeTitle)
                                    .foregroundColor(Color(red: 0.2, green: 0.85, blue: 0.4))
                                    .accessibilityHidden(true)
                            }
                            
                            Text("Discover real nature around you")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                        .padding(.top, 12)
                        
                        // Free-text trip assistant
                        TripRequestCard(assistant: assistant)

                        if case .building(_, let mode) = assistant.phase {
                            BuildingRoutesCard(mode: mode) {
                                assistant.cancelBuilding()
                            }
                        }

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
                                    
                                    Text("Builds a nature trip from real places")
                                        .font(.caption)
                                        .foregroundColor(.black.opacity(0.6))
                                }
                                .padding(20)
                            }
                        }
                        
                        // Secondary buttons
                        HStack(spacing: 12) {
                            NavigationLink {
                                MapView(route: nil)
                            } label: {
                                SecondaryCard(
                                    icon: "globe.europe.africa.fill",
                                    title: "Explore map",
                                    color: Color(red: 0.15, green: 0.18, blue: 0.15)
                                )
                            }
                            
                            NavigationLink {
                                SavedRoutesView()
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
            .sheet(isPresented: transportSheetBinding) {
                TransportPickerSheet { mode in
                    Task { await assistant.choose(mode) }
                }
            }
            .navigationDestination(isPresented: resultsBinding) {
                if case .ready(let options) = assistant.phase {
                    RouteOptionsView(options: options)
                }
            }
        }
    }

    /// Шторка выбора транспорта открыта, пока ассистент ждёт выбора.
    private var transportSheetBinding: Binding<Bool> {
        Binding(
            get: {
                if case .chooseTransport = assistant.phase { return true }
                return false
            },
            set: { isPresented in
                if !isPresented { assistant.dismissTransportChoice() }
            }
        )
    }

    /// Экран вариантов открыт, пока есть готовый результат. Возврат назад начинает заново.
    private var resultsBinding: Binding<Bool> {
        Binding(
            get: {
                if case .ready = assistant.phase { return true }
                return false
            },
            set: { isPresented in
                if !isPresented { assistant.reset() }
            }
        )
    }
}

/// Пока строятся варианты, показываем, что происходит, и даём отменить.
private struct BuildingRoutesCard: View {
    let mode: TransportMode
    let onCancel: () -> Void

    private let green = Color(red: 0.2, green: 0.85, blue: 0.4)
    private let cardBg = Color(red: 0.15, green: 0.18, blue: 0.15)

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(green)
            VStack(alignment: .leading, spacing: 2) {
                Text("Building route options")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                Text("By \(mode.displayName.lowercased()), this can take a minute")
                    .font(.footnote)
                    .foregroundColor(.gray)
            }
            Spacer()
            Button("Cancel", action: onCancel)
                .buttonStyle(.bordered)
                .tint(.white)
        }
        .padding(16)
        .background(cardBg, in: RoundedRectangle(cornerRadius: 16))
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


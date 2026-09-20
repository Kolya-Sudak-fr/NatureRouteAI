import SwiftUI

struct RoutePlannerView: View {

    @StateObject private var viewModel = RoutePlannerViewModel()

    private let green = Color(red: 0.2, green: 0.85, blue: 0.4)
    private let darkBg = Color(red: 0.08, green: 0.10, blue: 0.08)
    private let cardBg = Color(red: 0.15, green: 0.18, blue: 0.15)

    var body: some View {
        ZStack {
            darkBg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    Text("Plan your trip")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.top, 8)

                    // MARK: - City input
                    VStack(alignment: .leading, spacing: 8) {
                        Label("City", systemImage: "mappin.circle.fill")
                            .font(.headline)
                            .foregroundColor(green)

                        // $viewModel.city — Binding к ViewModel.
                        // Когда пользователь печатает — viewModel.city обновляется автоматически.
                        TextField("", text: $viewModel.city,
                                  prompt: Text("Enter city").foregroundColor(.gray))
                            .foregroundColor(.white)
                            .padding()
                            .background(cardBg)
                            .cornerRadius(12)
                    }

                    // MARK: - Trip duration
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Trip duration", systemImage: "calendar")
                            .font(.headline)
                            .foregroundColor(green)

                        HStack {
                            Text("\(viewModel.tripDays) days")
                                .foregroundColor(.white)
                                .font(.title3)
                                .fontWeight(.semibold)

                            Spacer()

                            HStack(spacing: 0) {
                                Button {
                                    if viewModel.tripDays > 1 { viewModel.tripDays -= 1 }
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
                                    if viewModel.tripDays < 14 { viewModel.tripDays += 1 }
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

                    // MARK: - Places per day
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Places per day", systemImage: "location.fill")
                            .font(.headline)
                            .foregroundColor(green)

                        HStack {
                            Text("\(viewModel.placesPerDay) places")
                                .foregroundColor(.white)
                                .font(.title3)
                                .fontWeight(.semibold)

                            Spacer()

                            HStack(spacing: 0) {
                                Button {
                                    if viewModel.placesPerDay > 1 { viewModel.placesPerDay -= 1 }
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
                                    if viewModel.placesPerDay < 10 { viewModel.placesPerDay += 1 }
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

                    // MARK: - Nature preferences
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Nature preferences", systemImage: "leaf.fill")
                            .font(.headline)
                            .foregroundColor(green)

                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 10) {
                            // $viewModel.preferences — Binding к массиву в ViewModel.
                            // Изменение pref.isSelected автоматически обновляет ViewModel.
                            ForEach($viewModel.preferences) { $pref in
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

                    // MARK: - Generate button
                    // viewModel.canGenerate — ViewModel решает активна ли кнопка.
                    // View просто спрашивает и отображает результат.
                    Button(action: viewModel.generateRoute) {
                        HStack {
                            if viewModel.isLoading {
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
                        .background(viewModel.canGenerate ? green : Color.gray)
                        .cornerRadius(14)
                    }
                    .disabled(!viewModel.canGenerate)

                    // MARK: - Route result
                    // View просто проверяет viewModel.route и отображает если есть.
                    if let route = viewModel.route {
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
        // Алерт — показывается когда viewModel.errorMessage не nil.
        // View не знает откуда ошибка — просто показывает что ViewModel скажет.
        .alert("Something went wrong", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("Try again") {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}

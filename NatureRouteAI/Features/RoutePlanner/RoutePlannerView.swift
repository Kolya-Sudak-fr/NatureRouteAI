import SwiftUI
import SwiftData
import MapKit

struct RoutePlannerView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = RoutePlannerViewModel()
    @State private var showMapPreview = false
    @FocusState private var cityFocused: Bool

    // Единая палитра приложения
    private let darkBg = Color(red: 0.08, green: 0.10, blue: 0.08)
    private let cardBg = Color(red: 0.15, green: 0.18, blue: 0.15)
    private let green = Color(red: 0.2, green: 0.85, blue: 0.4)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text("Plan a trip")
                                .font(.title)
                                .bold()
                                .foregroundColor(.white)
                            Image(systemName: "leaf.fill")
                                .font(.title3)
                                .foregroundColor(green)
                        }
                        Text("Tell us where — we'll find nature around it")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    .padding(.top, 8)

                    // Destination card
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            Image(systemName: "location.fill")
                                .foregroundColor(green)
                            TextField("Where to? e.g. Amsterdam", text: $viewModel.city)
                                .foregroundColor(.white)
                                .focused($cityFocused)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.words)
                        }
                        .padding(14)
                        .background(Color(red: 0.10, green: 0.13, blue: 0.10))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(viewModel.city.isEmpty ? Color.clear : green.opacity(0.6), lineWidth: 1)
                        )

                        StepperRow(title: "Days of trip",
                                   value: $viewModel.tripDays,
                                   range: 1...14)

                        StepperRow(title: "Places per day",
                                   value: $viewModel.placesPerDay,
                                   range: 1...10)
                    }
                    .padding(16)
                    .background(cardBg)
                    .cornerRadius(18)

                    // Transport card
                    VStack(alignment: .leading, spacing: 10) {
                        Text("How do you travel?")
                            .font(.headline)
                            .foregroundColor(.white)

                        HStack(spacing: 8) {
                            ForEach(TransportMode.allCases) { mode in
                                TransportChip(
                                    mode: mode,
                                    isSelected: viewModel.transport == mode,
                                    green: green
                                ) { viewModel.transport = mode }
                            }
                        }

                        Text(transportHint)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding(16)
                    .background(cardBg)
                    .cornerRadius(18)

                    // Preferences card
                    VStack(alignment: .leading, spacing: 4) {
                        Text("What do you love to see?")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.bottom, 6)

                        ForEach(viewModel.preferences) { preference in
                            PreferenceRow(
                                preference: preference,
                                green: green,
                                onTap: { newValue in
                                    if let index = viewModel.preferences.firstIndex(where: { $0.id == preference.id }) {
                                        viewModel.preferences[index].isSelected = newValue
                                    }
                                }
                            )
                            if preference.id != viewModel.preferences.last?.id {
                                Divider().background(Color.white.opacity(0.08))
                            }
                        }
                    }
                    .padding(16)
                    .background(cardBg)
                    .cornerRadius(18)

                    // Error
                    if let error = viewModel.errorMessage {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.white)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.12))
                        .cornerRadius(12)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .background(darkBg.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) { bottomButtons }
            .navigationTitle("New Route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(darkBg, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .sheet(isPresented: $showMapPreview) {
            if let route = viewModel.route {
                ZStack {
                    MapView(route: route)
                        .environment(\.modelContext, modelContext)
                }
                .overlay(alignment: .topTrailing) {
                    Button {
                        showMapPreview = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Circle().fill(Color.black.opacity(0.65)))
                    }
                    .padding(.trailing, 16)
                    .padding(.top, 60)
                }
                .presentationDragIndicator(.visible)
            }
        }
    }

    // Поиск природных точек не меняется от выбранного транспорта.
    private var transportHint: String {
        "Nature spots are searched within 50 km. Transport changes route directions only."
    }

    // MARK: - Bottom action buttons
    @ViewBuilder
    private var bottomButtons: some View {
        VStack(spacing: 10) {
            if let route = viewModel.route {
                RouteNavigationButton(route: route)

                Button {
                    showMapPreview = true
                } label: {
                    Label("View on Map", systemImage: "map.fill")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(cardBg)
                        .cornerRadius(14)
                }

                if viewModel.isSaved {
                    Label("Route saved — find it in Saved Routes", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(green)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(green.opacity(0.15))
                        .cornerRadius(14)
                } else {
                    Button {
                        viewModel.saveRoute(context: modelContext)
                    } label: {
                        Text("Save Route")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(green)
                            .cornerRadius(14)
                    }
                }
            }

            if viewModel.isLoading {
                HStack(spacing: 12) {
                    ProgressView().tint(.black)
                    Text("Searching for nature...")
                        .font(.headline)
                        .foregroundColor(.black)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(green)
                .cornerRadius(14)
            } else {
                Button {
                    viewModel.generateRoute()
                } label: {
                    Label("Generate Route", systemImage: "sparkles")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(viewModel.canGenerate ? green : Color.white.opacity(0.25))
                        .cornerRadius(14)
                }
                .disabled(!viewModel.canGenerate)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(darkBg.opacity(0.97).ignoresSafeArea())
    }
}

// MARK: - Custom stepper row (dark theme)
struct StepperRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    private let green = Color(red: 0.2, green: 0.85, blue: 0.4)
    private let fieldBg = Color(red: 0.10, green: 0.13, blue: 0.10)

    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.white)
            
            Spacer()

            Button {
                if value > range.lowerBound { value -= 1 }
            } label: {
                Image(systemName: "minus")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(fieldBg))
            }

            Text("\(value)")
                .font(.headline)
                .foregroundColor(green)
                .frame(width: 36)

            Button {
                if value < range.upperBound { value += 1 }
            } label: {
                Image(systemName: "plus")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(fieldBg))
            }
        }
        .padding(14)
        .background(Color(red: 0.10, green: 0.13, blue: 0.10))
        .cornerRadius(12)
    }
}

// MARK: - Transport chip (selection button)
struct TransportChip: View {
    let mode: TransportMode
    let isSelected: Bool
    let green: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: mode.systemIcon)
                    .font(.title3)
                Text(mode.displayName)
                    .font(.caption)
                    .fontWeight(isSelected ? .bold : .regular)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundColor(isSelected ? .black : .white)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? green : Color(red: 0.10, green: 0.13, blue: 0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? green : Color.white.opacity(0.15), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(duration: 0.25), value: isSelected)
    }
}

// MARK: - Preference row with emoji + toggle
struct PreferenceRow: View {
    let preference: NaturePreference
    let green: Color
    let onTap: (Bool) -> Void

    var emoji: String {
        switch preference.title {
        case "Mountains": return "⛰️"
        case "Forest": return "🌲"
        case "Lakes": return "🏞️"
        case "Waterfalls": return "💦"
        case "National Parks": return "🌳"
        default: return "🌿"
        }
    }

    var body: some View {
        HStack {
            Text(emoji)
                .font(.title3)
            Text(preference.title)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            Toggle("", isOn: Binding(
                get: { preference.isSelected },
                set: { onTap($0) }
            ))
            .labelsHidden()
            .tint(green)
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    RoutePlannerView()
}

import SwiftUI
import SwiftData
import MapKit

struct RoutePlannerView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @StateObject private var viewModel = RoutePlannerViewModel()
    @State private var showMapPreview = false
    @FocusState private var cityFocused: Bool

    init(city: String = "", preselectedPreference: String? = nil) {
        _viewModel = StateObject(wrappedValue: RoutePlannerViewModel(
            initialCity: city,
            initialPreference: preselectedPreference
        ))
    }

    private let topAnchor = "planner-top"

    // Единая палитра приложения
    private let darkBg = Color(red: 0.08, green: 0.10, blue: 0.08)
    private let cardBg = Color(red: 0.15, green: 0.18, blue: 0.15)
    private let green = Color(red: 0.2, green: 0.85, blue: 0.4)

    var body: some View {
        NavigationStack {
            ScrollViewReader { scrollProxy in
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
                        .transition(.opacity)
                    }
                    // Result
                    if let route = viewModel.route {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Your route in \(route.city ?? "this area")")
                                .font(.headline)
                                .foregroundColor(.white)
                            ForEach(route.days.sorted { $0.dayNumber < $1.dayNumber }) { day in
                                RouteDayCard(day: day)
                            }
                        }
                        .transition(.opacity)

                        if dynamicTypeSize.isAccessibilitySize {
                            actionButtons
                        }
                    }

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
                                   range: RoutePlannerViewModel.tripDaysRange)

                        StepperRow(title: "Places per day",
                                   value: $viewModel.placesPerDay,
                                   range: RoutePlannerViewModel.placesPerDayRange)
                    }
                    .padding(16)
                    .background(cardBg)
                    .cornerRadius(18)

                    // Transport card
                    VStack(alignment: .leading, spacing: 10) {
                        Text("How do you travel?")
                            .font(.headline)
                            .foregroundColor(.white)

                        // Equal heights even when one label wraps to two lines.
                        HStack(spacing: 8) {
                            ForEach(TransportMode.allCases) { mode in
                                TransportChip(
                                    mode: mode,
                                    isSelected: viewModel.transport == mode,
                                    green: green
                                ) { viewModel.transport = mode }
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)

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
                                        viewModel.setPreferenceSelection(at: index, isSelected: newValue)
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

                    if dynamicTypeSize.isAccessibilitySize, viewModel.route == nil {
                        actionButtons
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
                .id(topAnchor)
            }
            .onChange(of: viewModel.route?.id) { scrollToTop(scrollProxy) }
            .onChange(of: viewModel.errorMessage) { scrollToTop(scrollProxy) }
            .background(darkBg.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                // At accessibility text sizes a pinned panel would cover most of
                // the screen, so the buttons scroll with the content instead.
                if !dynamicTypeSize.isAccessibilitySize {
                    actionButtons
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                        .padding(.bottom, 10)
                        .background(darkBg.ignoresSafeArea())
                }
            }
            .animation(RouteMotion.animation(RouteMotion.reveal, reduceMotion: reduceMotion), value: viewModel.route?.id)
            .animation(RouteMotion.animation(RouteMotion.quick, reduceMotion: reduceMotion), value: viewModel.errorMessage)
            .navigationTitle("New Route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(darkBg, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            }
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

    /// The result and any error appear at the top, which may be scrolled out of view.
    private func scrollToTop(_ proxy: ScrollViewProxy) {
        withAnimation(RouteMotion.animation(RouteMotion.reveal, reduceMotion: reduceMotion)) {
            proxy.scrollTo(topAnchor, anchor: .top)
        }
    }

    // Поиск природных точек не меняется от выбранного транспорта.
    private var transportHint: String {
        if viewModel.transport == .publicTransport {
            return "Nature spots are searched within 50 km. Check public transport directions in an external navigation app."
        }
        return "Nature spots are searched within 50 km. Apple Maps travel distance and time help choose the stop order."
    }

    /// Side by side normally, stacked at accessibility text sizes where two
    /// labels no longer fit in one row.
    private var actionRowLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 10))
            : AnyLayout(HStackLayout(spacing: 10))
    }

    // MARK: - Action buttons
    @ViewBuilder
    private var actionButtons: some View {
        VStack(spacing: 10) {
            if let route = viewModel.route {
                actionRowLayout {
                    RouteNavigationButton(route: route)

                    Button {
                        showMapPreview = true
                    } label: {
                        Label("Map", systemImage: "map.fill")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(cardBg)
                            .cornerRadius(14)
                    }
                }

                actionRowLayout {
                    if viewModel.isSaved(in: modelContext) {
                        Label("Saved", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .foregroundColor(green)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(green.opacity(0.15))
                            .cornerRadius(14)
                            .accessibilityLabel("Route saved. Find it in Saved Routes.")
                            .transition(RouteMotion.transition(reduceMotion: reduceMotion))
                    } else {
                        Button {
                            withAnimation(RouteMotion.animation(RouteMotion.selection, reduceMotion: reduceMotion)) {
                                viewModel.saveRoute(context: modelContext)
                            }
                        } label: {
                            Label("Save Route", systemImage: "bookmark")
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(green)
                                .cornerRadius(14)
                        }
                        .transition(.opacity)
                    }

                    Button {
                        viewModel.generateRoute()
                    } label: {
                        Label("New Route", systemImage: "sparkles")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(cardBg)
                            .cornerRadius(14)
                    }
                    .disabled(!viewModel.canGenerate)
                }
            }

            if viewModel.isLoading {
                HStack(spacing: 12) {
                    ProgressView().tint(.black)
                    Text(viewModel.isCancelling ? "Stopping route search..." : "Searching for nature...")
                        .font(.headline)
                        .foregroundColor(.black)
                        .contentTransition(.opacity)
                    Spacer(minLength: 0)
                    Button(viewModel.isCancelling ? "Stopping" : "Cancel") { viewModel.cancelGeneration() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.black)
                        .disabled(viewModel.isCancelling)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .background(green)
                .cornerRadius(14)
                .transition(.opacity)
            } else if viewModel.route == nil {
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
                .transition(.opacity)
            }
        }
        .animation(RouteMotion.animation(RouteMotion.quick, reduceMotion: reduceMotion), value: viewModel.isLoading)
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
            .accessibilityLabel("Decrease \(title.lowercased())")

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
            .accessibilityLabel("Increase \(title.lowercased())")
        }
        .padding(14)
        .background(Color(red: 0.10, green: 0.13, blue: 0.10))
        .cornerRadius(12)
    }
}

// MARK: - Transport chip (selection button)
struct TransportChip: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .animation(RouteMotion.animation(RouteMotion.selection, reduceMotion: reduceMotion), value: isSelected)
    }
}

// MARK: - Preference row with emoji + toggle
struct PreferenceRow: View {
    let preference: NaturePreference
    let green: Color
    let onTap: (Bool) -> Void

    var symbol: String {
        switch preference.title {
        case "Mountains": return "mountain.2.fill"
        case "Forest": return "tree.fill"
        case "Lakes": return "water.waves"
        case "Waterfalls": return "drop.fill"
        case "National Parks": return "leaf.fill"
        default: return "leaf"
        }
    }

    var body: some View {
        HStack {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundColor(green)
                .frame(width: 32)
                .accessibilityHidden(true)
            Text(preference.title)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            Toggle(preference.title, isOn: Binding(
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

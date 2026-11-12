import SwiftUI

/// Поле, в которое пользователь пишет свободным текстом, куда и что хочет увидеть.
struct TripRequestCard: View {
    @ObservedObject var assistant: HomeTripAssistantViewModel
    @State private var cityDraft = ""
    @FocusState private var inputFocused: Bool

    private let green = Color(red: 0.2, green: 0.85, blue: 0.4)
    private let cardBg = Color(red: 0.15, green: 0.18, blue: 0.15)

    private var canSend: Bool {
        !assistant.isBusy && !assistant.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Describe your trip", systemImage: "sparkles")
                .font(.headline)
                .foregroundColor(.white)

            Text("Say where you are and what you want to see, for example: \"I'm in Middelburg, castles and abbeys for 2 days\".")
                .font(.footnote)
                .foregroundColor(.gray)

            HStack(alignment: .bottom, spacing: 10) {
                TextField("Where are you, and what do you like?", text: $assistant.input, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                    .focused($inputFocused)
                    .submitLabel(.send)
                    .onSubmit(send)

                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title)
                        .foregroundColor(canSend ? green : .gray)
                }
                .disabled(!canSend)
                .accessibilityLabel("Send trip description")
            }

            statusView
        }
        .padding(16)
        .background(cardBg, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var statusView: some View {
        switch assistant.phase {
        case .parsing:
            ProgressView("Reading your request")
                .font(.footnote)
                .foregroundColor(.white)
        case .needsCity:
            cityQuestion
        case .failed(let message):
            Text(message)
                .font(.footnote)
                .foregroundColor(.orange)
        default:
            EmptyView()
        }
    }

    /// Единственный вопрос, который мы задаём: без города маршрут не построить.
    private var cityQuestion: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Which city are you in?")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
            HStack(spacing: 10) {
                TextField("City", text: $cityDraft)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.continue)
                    .onSubmit(answerCity)
                Button("Continue", action: answerCity)
                    .buttonStyle(.borderedProminent)
                    .tint(green)
                    .disabled(cityDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func send() {
        guard canSend else { return }
        inputFocused = false
        Task { await assistant.submit() }
    }

    private func answerCity() {
        assistant.provideCity(cityDraft)
        cityDraft = ""
    }
}

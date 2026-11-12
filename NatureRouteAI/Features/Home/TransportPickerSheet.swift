import SwiftUI

/// Всплывающий выбор транспорта. Одно нажатие на вид транспорта запускает построение вариантов,
/// без дополнительных вопросов.
struct TransportPickerSheet: View {
    let onChoose: (TransportMode) -> Void

    private let darkBg = Color(red: 0.08, green: 0.10, blue: 0.08)
    private let green = Color(red: 0.2, green: 0.85, blue: 0.4)

    var body: some View {
        VStack(spacing: 14) {
            Text("How will you travel?")
                .font(.headline)
                .foregroundColor(.white)
                .padding(.top, 8)

            Button { onChoose(.car) } label: {
                Label("Driving", systemImage: TransportMode.car.systemIcon)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(green)
            .controlSize(.large)

            HStack(spacing: 10) {
                otherModeButton(.cycling)
                otherModeButton(.walking)
                otherModeButton(.publicTransport)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(darkBg.ignoresSafeArea())
        .presentationDetents([.height(260)])
        .presentationDragIndicator(.visible)
    }

    private func otherModeButton(_ mode: TransportMode) -> some View {
        Button { onChoose(mode) } label: {
            VStack(spacing: 6) {
                Image(systemName: mode.systemIcon)
                    .font(.title3)
                Text(mode.displayName)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.bordered)
        .tint(.white)
    }
}

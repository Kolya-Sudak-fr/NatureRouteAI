import Foundation
import Combine

/// Логика ассистента на главном экране: текст → уточнение города → выбор транспорта → варианты маршрутов.
/// Вопросов задаём не больше одного, и только если не назван город.
@MainActor
final class HomeTripAssistantViewModel: ObservableObject {

    enum Phase {
        case idle
        case parsing
        case needsCity(TripRequest)
        case chooseTransport(TripRequest)
        case building(TripRequest, TransportMode)
        case ready([RouteOption])
        case failed(String)
    }

    @Published var input: String = ""
    @Published private(set) var phase: Phase = .idle

    private let parser: TripRequestParsing
    private let planner: RouteOptionsPlanning
    private var buildTask: Task<[RouteOption], Error>?
    private var buildGeneration = 0

    init(parser: TripRequestParsing = TripRequestParsers.standard(), planner: RouteOptionsPlanning? = nil) {
        self.parser = parser
        self.planner = planner ?? RouteOptionsPlanner(generator: RouteGenerator())
    }

    var isBusy: Bool {
        switch phase {
        case .parsing, .building: return true
        default: return false
        }
    }

    /// Пустой текст ничего не запускает.
    func submit() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isBusy else { return }
        phase = .parsing
        do {
            let request = try await parser.parse(text)
            phase = request.needsCity ? .needsCity(request) : .chooseTransport(request)
        } catch is CancellationError {
            phase = .idle
        } catch {
            phase = .failed(Self.message(for: error))
        }
    }

    /// Ответ на единственный вопрос: в каком городе вы находитесь.
    func provideCity(_ city: String) {
        guard case .needsCity(var request) = phase else { return }
        let trimmed = city.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        request.city = trimmed
        phase = .chooseTransport(request)
    }

    /// Одна кнопка транспорта запускает построение всех вариантов сразу.
    func choose(_ transport: TransportMode) async {
        guard case .chooseTransport(let request) = phase else { return }
        buildGeneration += 1
        let generation = buildGeneration
        phase = .building(request, transport)

        let planner = self.planner
        let task = Task { try await planner.options(for: request, transport: transport) }
        buildTask = task
        do {
            let options = try await task.value
            // Результат от отменённого или заменённого построения не показываем.
            guard generation == buildGeneration else { return }
            phase = .ready(options)
        } catch is CancellationError {
            guard generation == buildGeneration else { return }
            phase = .chooseTransport(request)
        } catch {
            guard generation == buildGeneration else { return }
            phase = .failed(Self.message(for: error))
        }
    }

    /// Отмена из интерфейса во время построения.
    func cancelBuilding() {
        guard case .building(let request, _) = phase else { return }
        buildGeneration += 1
        buildTask?.cancel()
        buildTask = nil
        phase = .chooseTransport(request)
    }

    /// Выбор транспорта закрыли смахиванием: возвращаемся к вводу, текст сохраняем.
    func dismissTransportChoice() {
        guard case .chooseTransport = phase else { return }
        phase = .idle
    }

    func reset() {
        input = ""
        phase = .idle
    }

    static func message(for error: Error) -> String {
        if let appError = error as? AppError {
            return appError.userMessage
        }
        if let urlError = error as? URLError, urlError.code == .notConnectedToInternet {
            return AppError.noInternetConnection.userMessage
        }
        return AppError.unknown.userMessage
    }
}

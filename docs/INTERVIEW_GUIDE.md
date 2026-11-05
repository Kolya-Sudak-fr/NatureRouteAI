# NatureRouteAI: конспект для объяснения проекта

Этот файл помогает объяснить устройство приложения и решения в коде на техническом интервью. Описания сверены с текущей реализацией; если код изменится, обнови и конспект.

## Короткий рассказ о приложении

NatureRouteAI — iOS-приложение для планирования многодневных поездок на природу. Пользователь задаёт город, число дней, тип транспорта и предпочтения. Приложение получает координаты города и природные точки из OpenTripMap, оценивает доступность сегментов через MapKit, распределяет уникальные точки по дням и позволяет сохранить маршрут в SwiftData.

Генерация детерминирована: приложение не использует LLM и не обещает «идеальный» маршрут. Public Transport открывает внешнюю навигацию, потому что приложение не рассчитывает расписания или маршруты общественного транспорта.

## Архитектура и поток данных

```text
SwiftUI View
  └─ RoutePlannerViewModel (@MainActor, ObservableObject)
       └─ RouteGenerating
            └─ RouteGenerator
                 ├─ NetworkService → OpenTripMap
                 └─ RoutePlanningAlgorithm → RouteMetricsProviding
                      └─ MapKitRouteMetricsService → MKDirections

RoutePlannerViewModel → SwiftData (Route → RouteDay → Place)
SavedRoutesView / MapView → отображают сохранённый или построенный маршрут
```

- **View** отвечает за отображение состояния и передачу пользовательских действий.
- **ViewModel** владеет состоянием планировщика: введённым городом, транспортом, ходом генерации, результатом и ошибкой.
- **Протоколы `RouteGenerating` и `RouteMetricsProviding`** отделяют алгоритм от конкретной сети и MapKit. В production используются настоящие сервисы; в тестах — управляемые заглушки.
- **`RouteGenerator`** координирует поиск города, запросы точек и алгоритм распределения.
- **`RoutePlanningAlgorithm`** убирает дубликаты, выбирает доступные точки и учитывает расстояние и время поездки.
- **SwiftData** хранит маршрут и связанные с ним дни и точки. Отношения настроены с каскадным удалением.

Файлы: [RoutePlannerView.swift](../NatureRouteAI/Features/RoutePlanner/RoutePlannerView.swift), [RoutePlannerViewModel.swift](../NatureRouteAI/Features/RoutePlanner/RoutePlannerViewModel.swift), [RouteGenerator.swift](../NatureRouteAI/Services/RouteGenerator.swift), [RoutePlanningAlgorithm.swift](../NatureRouteAI/Services/RoutePlanningAlgorithm.swift), [RouteMetricsService.swift](../NatureRouteAI/Services/RouteMetricsService.swift), [Route.swift](../NatureRouteAI/Models/Route.swift).

## 60-секундное представление проекта

### English

> “NatureRouteAI is an iOS app for planning multi-day nature trips. Users choose a city, trip length, transport mode, and the kinds of places they want to visit. The app fetches real places from OpenTripMap and uses MapKit directions to select reachable stops and estimate travel between them. I built the app with SwiftUI and a ViewModel that manages asynchronous generation, cancellation, and UI state. Routes are stored locally with SwiftData. I also wrote XCTest coverage for cancellation races, place deduplication, MapKit failures, and persistence. It is an MVP, so public transport directions are handed off to external navigation apps.”

### Русский смысл

> «NatureRouteAI — iOS-приложение для планирования многодневных поездок на природу. Пользователь выбирает город, длительность поездки, транспорт и типы мест. Приложение получает реальные точки из OpenTripMap, а MapKit помогает выбрать достижимые остановки и оценить перемещения между ними. Я использовал SwiftUI и ViewModel для асинхронной генерации, отмены запросов и состояния интерфейса. Маршруты хранятся локально в SwiftData. В XCTest проверяются гонки отмены, дедупликация мест, ошибки MapKit и сохранение. Это MVP: маршруты общественного транспорта открываются во внешнем приложении».

Это заготовка, а не текст для заучивания. На интервью полезно рассказать один конкретный технический вызов и решение — например, как тестом воспроизводится гонка отмены.

## Черновик записи о проекте для CV

**NatureRouteAI — iOS project** · Swift, SwiftUI, SwiftData, MapKit, XCTest

- Built a SwiftUI route-planning app with a ViewModel and service-based architecture.
- Integrated OpenTripMap place search and MapKit Directions to select reachable nature stops for walking, cycling, and driving.
- Implemented cancellation-safe async generation and guarded the UI against stale task results.
- Persisted routes and related stops with SwiftData; covered route persistence, scoped deletion, deduplication, and concurrency cases with XCTest.

Перед отправкой CV адаптируй формулировки под вакансию и будь готов объяснить любой пункт примером из кода. Не заявляй backend key protection или расчёт общественного транспорта: этих функций в MVP нет.

## Как объяснить асинхронную генерацию

1. ViewModel запоминает параметры текущего запроса, чтобы значения формы не меняли уже начавшуюся генерацию.
2. Каждому запуску назначается свой `generationID`, а сам запрос выполняется в `Task`.
3. При отмене вызывается `Task.cancel()`. Сетевая и MapKit части сотрудничают с отменой через `Task.checkCancellation()`; `MKDirections` также получает `cancel()`.
4. После `await` ViewModel проверяет и отмену, и ID запуска. `Task.checkCancellation()` отвечает на вопрос «отменили ли именно эту Swift-задачу?» и прерывает её, если сигнал отмены уже выставлен. Проверка `generationID == currentGenerationID` отвечает на другой вопрос: «эта задача всё ещё владеет актуальным состоянием экрана?». Она не позволяет старому запуску менять результат, ошибку или индикатор загрузки, даже если старая операция завершилась поздно. Это дополняющие проверки: отмена — про жизненный цикл задачи, ID — про актуальность результата.
5. `defer` снимает индикатор загрузки только у актуального запуска.

Это **кооперативная отмена**: задача проверяет сигнал отмены в контрольных точках. Одного вызова `cancel()` недостаточно, чтобы безопасно остановить произвольный код или автоматически отменить любой сетевой запрос.

## Как объяснить тесты

Обычно тест строится по схеме **Arrange → Act → Assert**:

1. Arrange — подготовить объект и исходные данные.
2. Act — выполнить проверяемое действие.
3. Assert — проверить наблюдаемый результат.

### Гонка старой и новой генерации

В [RoutePlannerStateTests.swift](../NatureRouteAITests/RoutePlannerStateTests.swift) `ContinuationRouteGenerator` удерживает завершение запросов. Тест запускает старую генерацию, отменяет её, начинает новую и намеренно завершает старую первой. Он проверяет, что старый маршрут не появился, а затем убеждается, что принят результат новой генерации.

Это **детерминированный тест гонки**: порядок завершений задан тестом, поэтому проверка не зависит от случайного интернета или скорости устройства. `StubRouteGenerator` также позволяет проверить успех, ошибку, таймаут и отмену без реального API.

### Недоступные сегменты MapKit

В [RoutePlanningAlgorithmTests.swift](../NatureRouteAITests/RoutePlanningAlgorithmTests.swift) `TestRouteMetricsProvider` подменяет MapKit. Он может вернуть метрики, исчерпать лимит или сообщить, что маршрут до конкретной точки недоступен. Так проверяется, что недоступная точка пропускается, если есть другая достижимая, а при полном отказе алгоритм не возвращает точки как готовый маршрут.

### Постоянное хранение и отмена удаления

В [SavedRoutesTests.swift](../NatureRouteAITests/SavedRoutesTests.swift) тесты сохраняют данные в SwiftData и перечитывают их из нового контекста или контейнера. Это сильнее, чем проверить только текст кнопки: проверяется именно сохранённое состояние. Отдельный тест проверяет отмену подтверждения и наличие маршрута вместе с его днями и точками после отмены.

Удаление выполняется в [SavedRouteStore.swift](../NatureRouteAI/Services/SavedRouteStore.swift) поиском по UUID конкретного маршрута, а не по городу: в одном городе могут храниться разные маршруты. После удаления создаётся отдельный `ModelContext` и изменения сохраняются. В модели `Route → RouteDay → Place` включено каскадное удаление, поэтому при удалении маршрута SwiftData удаляет его дни и точки. Тест с двумя маршрутами одного города перечитывает сохранённые данные и проверяет, что остался ровно второй маршрут с его графом. Вариант с временным файлом и новым `ModelContainer` проверяет, что удаление действительно переживает закрытие и повторное открытие хранилища.

На интервью это можно сформулировать так: «Маршрут удаляется по стабильному UUID, потому что название города не уникально. Я проверяю не только количество записей `Route`, но и связанные `RouteDay` и `Place`, затем повторно открываю persistent container. Так тест ловит и ошибку выбора маршрута, и ошибку каскадного удаления».

### UI-тест отмены удаления

В [SavedRoutesUITests.swift](../NatureRouteAIUITests/SavedRoutesUITests.swift) используется `XCUIApplication`: тест запускает настоящее приложение в симуляторе, открывает список сохранённых маршрутов, выбирает тестовую карточку, открывает меню и диалог удаления, затем отменяет диалог нажатием вне него. После этого проверяется, что карточка всё ещё видна.

Чтобы сценарий был изолирован от личных данных и сети, приложение запускается с аргументами `--ui-testing` и `--seed-saved-route`. Первый включает временное хранилище SwiftData в памяти, второй добавляет предсказуемый тестовый маршрут. Это тестовый входной путь; обычный запуск использует постоянное SwiftData-хранилище. UI-тест медленнее unit-теста, зато проверяет сквозное взаимодействие SwiftUI-экранов и системного диалога.

Короткий ответ на интервью: «Я использовал unit-тест для проверки неизменности состояния модели, а UI-тест — чтобы проверить сам пользовательский путь отмены удаления. UI-тест запускает приложение с изолированными тестовыми данными и обращается к элементам по accessibility labels, а не по координатам, кроме жеста отмены системного диалога».

### Что означает текущий зелёный прогон

На 30 октября 2026 года в Xcode прошли **34 unit-теста (0 failures)** и отдельно **1 UI-тест (0 failures)**. Generic iOS build также завершился `Build Succeeded` в Xcode. Это подтверждает компиляцию приложения и перечисленное тестами поведение; сценарии реальной сети, все режимы генерации и внешних приложений в сквозном прогоне не проверялись.

## Пример ответа на интервью

> «Для проверки отмены генерации я внедрил протокол генератора в ViewModel. В production подставляется реальный сервис, а тест использует управляемую заглушку. Она позволяет завершать старые и новые запросы в заданном порядке. Так я проверил race condition: отменённая задача не меняет опубликованный результат. Для сохранения я перечитываю SwiftData после открытия нового контекста, поэтому тест проверяет постоянное хранилище, а не только состояние ViewModel».

## Темы для дальнейшего изучения

- `async/await`, `Task`, cooperative cancellation и изоляция через `@MainActor`.
- Dependency injection и test doubles: stub, fake, mock.
- SwiftData: модели, relationships, `ModelContext`, транзакции и миграции.
- XCTest: асинхронные тесты, тестирование ошибок и отличие unit-тестов от UI/e2e.
- Практическое ограничение MVP: API-ключ внутри iOS-бинарника можно извлечь; для публичного релиза нужен серверный proxy.

## Подготовка к Junior iOS вакансиям в Нидерландах

Сверка с вакансиями от 30 октября 2026 года — объявления меняются, перед откликом проверь их статус:

- [Junior iOS Mobile Developer op de Zuidas, CareerValue](https://www.careervalue.nl/vacatures/mobile-development/vacature-in-amsterdam-junior-ios-mobile-developer-op-de-zuidas/) описывает годичную программу для недавно окончивших релевантный HBO/WO. Swift указан как преимущество, но не обязательное условие; обучение включает работу с опытными разработчиками. Страница указывает диапазон €2,600–€3,400 и отклик с CV и короткой мотивацией.
- [Junior/Medior iOS Developer, NPO Start](https://magnet.me/nl-NL/vacature/1097284/junior-medior-ios-developer-npo-start--m-v-x-) принимает кандидатов с 0–5 годами опыта и перечисляет Swift, SwiftUI, Swift 6 Concurrency, Swift Testing, MVVM и Clean Architecture. В объявлении также указаны HBO-уровень и свободный нидерландский и английский.
- [Startende/Junior iOS developer, Sterksen](https://nl.linkedin.com/jobs/view/startendejunior-ios-developer-at-sterksen-4442893572) предлагает стартовую программу с наставничеством; среди требований указана завершённая техническая магистратура, поэтому это подойдёт только при совпадении образования.

NatureRouteAI уже даёт проверяемые примеры SwiftUI, ViewModel, `async/await`, отмены задач, XCTest, внешнего API, MapKit и локального хранения. При этом проект сейчас настроен на Swift language mode 5.0 и использует XCTest, а не Swift Testing. Значит, не следует писать в CV «Swift 6» или «Swift Testing» как уже применённый опыт. Полезный следующий учебный шаг — разобраться в различиях XCTest и Swift Testing и собрать небольшой учебный пример на `@Test`/`#expect`, затем отдельно проверить concurrency warnings в режиме Swift 6.

Например, существующую проверку дедупликации можно выразить синтаксисом Swift Testing так:

```swift
import Testing
@testable import NatureRouteAI

struct RoutePlaceDeduplicationTests {
    @Test("Merges a nearby result when one copy has no external ID")
    func identifiedAndUnidentifiedDuplicateAreMerged() {
        let identified = RoutePlaceCandidate(
            externalID: "spot-1", name: "Lake", type: "water",
            latitude: 52.0, longitude: 5.0,
            preferences: ["Lake"], quality: 3, sourceOrder: 0
        )
        let unidentified = RoutePlaceCandidate(
            externalID: nil, name: "Water feature", type: "water",
            latitude: 52.00001, longitude: 5.0,
            preferences: ["Forest"], quality: 3, sourceOrder: 1
        )

        let result = RoutePlanningAlgorithm.uniqueCandidates([identified, unidentified])

        #expect(result.count == 1)
        #expect(result.first?.externalID == "spot-1")
        #expect(result.first?.preferences == Set(["Lake", "Forest"]))
    }
}
```

Это учебный пример, а не добавленный или запущенный тест. По смыслу он соответствует Arrange → Act → Assert: создаём две записи одного места, вызываем функцию дедупликации и проверяем количество результатов, сохранённый ID и объединённые категории. В Swift Testing `@Test` регистрирует тест, а `#expect` выражает проверку; в XCTest аналогичная проверка обычно записывается через `func test...()` и `XCTAssert...`.

Для CareerValue сначала проверь формальное условие — недавнее окончание релевантного HBO/WO. Для NPO проверь HBO werk- en denkniveau и нидерландский язык, для Sterksen — требование к магистратуре. В резюме описывай только то, что можешь показать в коде или объяснить на примере.

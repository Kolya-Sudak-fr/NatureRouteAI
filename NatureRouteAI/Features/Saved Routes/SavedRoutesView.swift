import SwiftUI
import SwiftData

struct SavedRoutesView: View {
    
    // @Query — SwiftData автоматически загружает все сохранённые маршруты из базы.
    // Сортируем по дате создания — новые сверху.
    // Когда база меняется — View обновляется автоматически.
    @Query(sort: \Route.createdAt, order: .reverse) private var routes: [Route]
    
    private let darkBg = Color(red: 0.08, green: 0.10, blue: 0.08)
    private let cardBg = Color(red: 0.15, green: 0.18, blue: 0.15)
    private let green = Color(red: 0.2, green: 0.85, blue: 0.4)
    
    var body: some View {
        ZStack {
            darkBg.ignoresSafeArea()
            
            if routes.isEmpty {
                // Пустое состояние — когда маршрутов ещё нет
                VStack(spacing: 16) {
                    Image(systemName: "bookmark.slash")
                        .font(.system(size: 48))
                        .foregroundColor(.gray)
                    Text("No saved routes yet")
                        .font(.title3)
                        .foregroundColor(.gray)
                    Text("Generate a route and tap Save")
                        .font(.subheadline)
                        .foregroundColor(.gray.opacity(0.7))
                }
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(routes) { route in
                            // Карточка одного маршрута
                            NavigationLink {
                                RouteDetailView(route: route)
                            } label: {
                                RouteCard(route: route, green: green, cardBg: cardBg)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
            }
        }
        .navigationTitle("Saved Routes")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(darkBg, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

// Отдельный компонент карточки маршрута —
// чтобы не перегружать основной View
struct RouteCard: View {
    let route: Route
    let green: Color
    let cardBg: Color
    
    // Общее количество мест во всех днях
    var totalPlaces: Int {
        route.days.reduce(0) { $0 + $1.places.count }
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Миниатюра города (детерминированное фото по названию города)
            CityThumb(city: route.city ?? "Unknown City")
                .frame(width: 56, height: 56)
                .cornerRadius(12)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(green.opacity(0.4), lineWidth: 1)
                )
            
            // Информация о маршруте
            VStack(alignment: .leading, spacing: 4) {
                // Здесь мы используем опциональную развертку (??)
                // Это гарантирует, что ошибка 'Optional type' исчезнет
                Text(route.city ?? "Unknown City")
                    .font(.headline)
                    .foregroundColor(.white)
                
                HStack(spacing: 12) {
                    // Количество дней
                    Label("\(route.days.count) days", systemImage: "calendar")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    // Количество мест
                    Label("\(totalPlaces) places", systemImage: "mappin")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                // Дата сохранения
                Text(route.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(cardBg)
        .cornerRadius(15)
    }
}

// Миниатюра города: детерминированное фото (seed = название города),
// если нет сети — зелёный плейсхолдер с листом
struct CityThumb: View {
    let city: String

    private let green = Color(red: 0.2, green: 0.85, blue: 0.4)

    var url: URL? {
        var components = URLComponents(string: "https://picsum.photos/seed/")
        components?.path = "/seed/\(city.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? city)/120/120"
        return components?.url
    }

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            default:
                ZStack {
                    Color(red: 0.15, green: 0.18, blue: 0.15)
                    Image(systemName: "leaf.fill")
                        .font(.title3)
                        .foregroundColor(green)
                }
            }
        }
    }
}

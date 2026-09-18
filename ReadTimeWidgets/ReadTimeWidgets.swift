import WidgetKit
import SwiftUI

// MARK: - Data

struct ReadTimeEntry: TimelineEntry {
    let date: Date
    let book: Book?
    let cover: UIImage?
    let minutesToday: Int
    let dailyGoal: Int
    let streak: Int
    /// Minutes read on each day of the current week, Monday first.
    let week: [(day: Date, minutes: Int)]

    static let placeholder = ReadTimeEntry(
        date: .now,
        book: Book(id: UUID(), title: "Atomic Habits", author: "James Clear", genre: "Self-help",
                   totalPages: 320, currentPage: 96, status: .reading),
        cover: nil,
        minutesToday: 12,
        dailyGoal: 20,
        streak: 3,
        week: []
    )
}

struct ReadTimeProvider: TimelineProvider {
    func placeholder(in context: Context) -> ReadTimeEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (ReadTimeEntry) -> Void) {
        Task { completion(await entry()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ReadTimeEntry>) -> Void) {
        Task {
            let entry = await entry()
            // Refresh on the hour; the app also reloads the widgets whenever data changes.
            let nextHour = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now.addingTimeInterval(3600)
            completion(Timeline(entries: [entry], policy: .after(nextHour)))
        }
    }

    private func entry() async -> ReadTimeEntry {
        guard let snapshot = LocalStore.load() else {
            return ReadTimeEntry(date: .now, book: nil, cover: nil, minutesToday: 0, dailyGoal: 20, streak: 0, week: [])
        }
        let calendar = Calendar.current
        let book = snapshot.books.first { $0.id == snapshot.selectedBookID }
            ?? snapshot.books.first { $0.status == .reading }
            ?? snapshot.books.first { $0.status == .wantToRead }

        func minutes(on day: Date) -> Int {
            snapshot.activities
                .filter { calendar.isDate($0.date, inSameDayAs: day) }
                .reduce(0) { $0 + $1.minutes }
        }

        var weekCalendar = calendar
        weekCalendar.firstWeekday = 2
        let monday = weekCalendar.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        let week = (0..<7).compactMap { weekCalendar.date(byAdding: .day, value: $0, to: monday) }
            .map { (day: $0, minutes: minutes(on: $0)) }

        return ReadTimeEntry(
            date: .now,
            book: book,
            cover: await cover(for: book),
            minutesToday: minutes(on: .now),
            dailyGoal: snapshot.dailyGoal,
            streak: streak(in: snapshot, calendar: calendar),
            week: week
        )
    }

    private func cover(for book: Book?) async -> UIImage? {
        guard let book else { return nil }
        if let name = book.coverName,
           let url = Bundle.main.url(forResource: name, withExtension: "png") {
            return UIImage(contentsOfFile: url.path)
        }
        guard let coverURL = book.coverURL, let url = URL(string: coverURL) else { return nil }
        return await CoverCache.image(for: url, persist: true)
    }

    /// Days in a row up to today (or yesterday, if today hasn't started yet) with a reading session.
    private func streak(in snapshot: ReadingSnapshot, calendar: Calendar) -> Int {
        let days = Set(snapshot.activities.filter { $0.minutes > 0 }.map { calendar.startOfDay(for: $0.date) })
        var day = calendar.startOfDay(for: .now)
        if !days.contains(day) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var count = 0
        while days.contains(day) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }
}

// MARK: - Current book

struct CurrentBookWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CurrentBookWidget", provider: ReadTimeProvider()) { entry in
            CurrentBookView(entry: entry)
                .widgetBackground(Color.readTimeCardBackground)
        }
        .configurationDisplayName("Current Book")
        .description("The book you're reading and how far you've got.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct CurrentBookView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ReadTimeEntry

    var body: some View {
        if let book = entry.book {
            if family == .systemSmall {
                VStack(alignment: .leading, spacing: 8) {
                    WidgetCover(image: entry.cover, width: 46, height: 69)
                    Text(book.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    ProgressLine(progress: book.progress)
                    Text("\(Int(book.progress * 100))% · \(book.currentPage)/\(book.totalPages)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 14) {
                    WidgetCover(image: entry.cover, width: 76, height: 114)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(book.title)
                            .font(.headline)
                            .lineLimit(2)
                        Text(book.author)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        ProgressLine(progress: book.progress)
                        HStack {
                            Text("Page \(book.currentPage) of \(book.totalPages)")
                            Spacer()
                            Text("\(Int(book.progress * 100))%")
                                .foregroundStyle(Color.readTimeGreen)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        } else {
            WidgetEmptyState(message: "Add a book to start reading")
        }
    }
}

// MARK: - Daily goal

struct DailyGoalWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DailyGoalWidget", provider: ReadTimeProvider()) { entry in
            DailyGoalView(entry: entry)
                .widgetBackground(Color.readTimeCardBackground)
        }
        .configurationDisplayName("Daily Goal")
        .description("Today's reading against your goal, and your streak.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

struct DailyGoalView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ReadTimeEntry

    private var progress: Double {
        guard entry.dailyGoal > 0 else { return 0 }
        return min(Double(entry.minutesToday) / Double(entry.dailyGoal), 1)
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: progress) {
                Image(systemName: "book.fill")
            } currentValueLabel: {
                Text("\(entry.minutesToday)")
            }
            .gaugeStyle(.accessoryCircularCapacity)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("\(entry.minutesToday) of \(entry.dailyGoal) min")
                    .font(.headline)
                ProgressView(value: progress)
                if entry.streak > 0 {
                    Text("\(entry.streak) day streak")
                        .font(.caption)
                }
            }
        case .systemMedium:
            HStack(spacing: 18) {
                GoalRing(progress: progress, minutes: entry.minutesToday, goal: entry.dailyGoal)
                    .frame(width: 92, height: 92)
                VStack(alignment: .leading, spacing: 10) {
                    if entry.streak > 0 {
                        Label("\(entry.streak) day streak", systemImage: "flame.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.orange)
                    } else {
                        Text("Read today to start a streak")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    WeekDots(week: entry.week, goal: entry.dailyGoal)
                }
            }
        default:
            VStack(spacing: 8) {
                GoalRing(progress: progress, minutes: entry.minutesToday, goal: entry.dailyGoal)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if entry.streak > 0 {
                    Label("\(entry.streak)", systemImage: "flame.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}

// MARK: - Pieces

struct GoalRing: View {
    let progress: Double
    let minutes: Int
    let goal: Int

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.readTimePurple.opacity(0.18), lineWidth: 10)
            Circle()
                .trim(from: 0, to: max(progress, 0.001))
                .stroke(Color.readTimePurple, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(minutes)")
                    .font(.title3.weight(.bold))
                    .minimumScaleFactor(0.6)
                Text("of \(goal) min")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct WeekDots: View {
    let week: [(day: Date, minutes: Int)]
    let goal: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(week, id: \.day) { day in
                VStack(spacing: 4) {
                    Text(day.day.formatted(.dateTime.weekday(.narrow)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Circle()
                        .fill(day.minutes >= goal && goal > 0 ? Color.readTimeGreen : Color.readTimePurple.opacity(day.minutes > 0 ? 0.55 : 0.15))
                        .frame(width: 10, height: 10)
                }
            }
        }
    }
}

struct ProgressLine: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.readTimePurple.opacity(0.18))
                Capsule().fill(Color.readTimeGreen)
                    .frame(width: proxy.size.width * progress)
            }
        }
        .frame(height: 6)
    }
}

struct WidgetCover: View {
    let image: UIImage?
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "book.closed.fill")
                    .font(.title3)
                    .foregroundStyle(Color.readTimePurple)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.readTimePurple.opacity(0.12))
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct WidgetEmptyState: View {
    let message: LocalizedStringKey

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "book.closed")
                .font(.title2)
                .foregroundStyle(Color.readTimePurple)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension View {
    /// `containerBackground` is iOS 17 and later; older systems draw the background themselves.
    @ViewBuilder
    func widgetBackground(_ color: Color) -> some View {
        if #available(iOS 17.0, *) {
            containerBackground(color, for: .widget)
        } else {
            background(color)
        }
    }
}

@main
struct ReadTimeWidgets: WidgetBundle {
    var body: some Widget {
        CurrentBookWidget()
        DailyGoalWidget()
    }
}

import SwiftUI
import Combine
import CryptoKit
import Charts
import UserNotifications
import UIKit
import StoreKit
import PhotosUI
import GoogleMobileAds
import UserMessagingPlatform
import AppTrackingTransparency

@main
struct ReadTimeApp: App {
    @StateObject private var store = ReadingStore()
    @StateObject private var purchases = PurchaseManager()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppearanceMode.storageKey) private var appearance = AppearanceMode.system
    @AppStorage(CloudBackup.syncEnabledKey) private var iCloudSyncEnabled = false
    /// Set when the app goes to the background; the next `.active` counts as "returning to the app".
    @State private var wasInBackground = false

    init() {
        // Shown on ReadTime's page in the Settings app (see Settings.bundle).
        UserDefaults.standard.set(AppInfo.version, forKey: "settings_app_version")
    }

    var body: some Scene {
        WindowGroup {
            ReadTimeTabView()
                .environmentObject(store)
                .environmentObject(purchases)
                .tint(.readTimePurple)
                .preferredColorScheme(appearance.colorScheme)
                .onAppear { KeyboardDismissal.install() }
                .onChange(of: appearance) { mode in mode.apply() }
                .task { await purchases.load() }
                // Consent and tracking prompts wait until onboarding is done.
                .task(id: store.needsOnboarding) {
                    if !store.needsOnboarding { AdManager.shared.start() }
                }
        }
        .onChange(of: scenePhase) { phase in
            // Returning from the background (not just a system alert, which only makes the app
            // inactive) shows an app open ad. iOS goes background → inactive → active.
            if phase == .active, wasInBackground {
                wasInBackground = false
                if !store.needsOnboarding { AdManager.shared.showAppOpenAdIfAvailable() }
            }
            guard phase == .background else { return }
            wasInBackground = true
            store.save()
            // Keep the iCloud copy current whenever the user leaves the app.
            if iCloudSyncEnabled {
                try? CloudBackup.backUp(store)
            }
        }
    }
}

// MARK: - Models

enum BookStatus: String, CaseIterable, Identifiable, Codable {
    case reading = "Reading"
    case wantToRead = "Want to Read"
    case finished = "Finished"

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .reading: "Reading"
        case .wantToRead: "Want to Read"
        case .finished: "Finished"
        }
    }

    var color: Color {
        switch self {
        case .reading: .readTimePurple
        case .wantToRead: .readTimeAmber
        case .finished: .readTimeGreen
        }
    }
}

struct Book: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var author: String
    var genre: String
    var totalPages: Int
    var currentPage: Int
    var status: BookStatus
    var coverName: String?
    /// Cover found through online book search; cached on the device by `CoverCache`.
    var coverURL: String?
    /// Marks the sample library so it can be cleared without touching the user's own books.
    var isDemo: Bool?

    var progress: Double {
        guard totalPages > 0 else { return 0 }
        return min(Double(currentPage) / Double(totalPages), 1)
    }
}

struct ReadingActivity: Identifiable, Codable {
    var id = UUID()
    let date: Date
    let minutes: Int
    var bookTitle: String
    var coverName: String?
    var coverURL: String?
    var isDemo: Bool?
    /// Pages moved forward in the session; nil for sessions saved before this was tracked.
    var pagesRead: Int?

    var label: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return String(localized: "Today") }
        if calendar.isDateInYesterday(date) { return String(localized: "Yesterday") }
        return date.formatted(.dateTime.weekday(.abbreviated).day())
    }
}

struct JournalEntry: Identifiable, Codable {
    var id = UUID()
    var date: Date
    /// Empty when the entry isn't about a particular book.
    var bookTitle: String
    var text: String
    var isDemo: Bool?
}

/// The sample library shown on first launch, and loaded or cleared from Settings.
enum DemoContent {
    static var books: [Book] {
        [
            Book(id: UUID(), title: "I Owe You One", author: "Sophie Kinsella", genre: "Romance", totalPages: 400, currentPage: 240, status: .reading, coverName: "i-owe-you-one", isDemo: true),
            Book(id: UUID(), title: "This Is Going To Hurt", author: "Adam Kay", genre: "Memoir", totalPages: 248, currentPage: 156, status: .reading, coverName: "this-is-going-to-hurt", isDemo: true),
            Book(id: UUID(), title: "Steal Like an Artist", author: "Austin Kleon", genre: "Creativity", totalPages: 160, currentPage: 160, status: .finished, coverName: "steal-like-an-artist", isDemo: true),
            Book(id: UUID(), title: "High Output Management", author: "Andrew S. Grove", genre: "Business", totalPages: 272, currentPage: 0, status: .wantToRead, coverName: "high-output-management", isDemo: true)
        ]
    }

    static var activities: [ReadingActivity] {
        [
            ReadingActivity(date: .now, minutes: 35, bookTitle: "Steal Like an Artist", coverName: "steal-like-an-artist", isDemo: true, pagesRead: 30),
            ReadingActivity(date: .now.addingTimeInterval(-86_400), minutes: 32, bookTitle: "I Owe You One", coverName: "i-owe-you-one", isDemo: true, pagesRead: 28),
            ReadingActivity(date: .now.addingTimeInterval(-2 * 86_400), minutes: 18, bookTitle: "This Is Going To Hurt", coverName: "this-is-going-to-hurt", isDemo: true, pagesRead: 16),
            ReadingActivity(date: .now.addingTimeInterval(-3 * 86_400), minutes: 15, bookTitle: "High Output Management", coverName: "high-output-management", isDemo: true, pagesRead: 14),
            ReadingActivity(date: .now.addingTimeInterval(-4 * 86_400), minutes: 42, bookTitle: "I Owe You One", coverName: "i-owe-you-one", isDemo: true, pagesRead: 38),
            ReadingActivity(date: .now.addingTimeInterval(-5 * 86_400), minutes: 22, bookTitle: "This Is Going To Hurt", coverName: "this-is-going-to-hurt", isDemo: true, pagesRead: 19),
            ReadingActivity(date: .now.addingTimeInterval(-6 * 86_400), minutes: 34, bookTitle: "Steal Like an Artist", coverName: "steal-like-an-artist", isDemo: true, pagesRead: 30)
        ]
    }

    static var journalEntries: [JournalEntry] {
        [
            JournalEntry(date: .now.addingTimeInterval(-86_400), bookTitle: "Steal Like an Artist", text: "Make things for yourself first. The work becomes clearer when I stop trying to impress everyone.", isDemo: true)
        ]
    }

    /// Data saved before demo items were flagged: recognise the sample items by their content.
    @MainActor
    static func markLegacyItems(in store: ReadingStore) {
        let sampleBooks = books, sampleActivities = activities, sampleJournal = journalEntries
        for index in store.books.indices where store.books[index].isDemo == nil {
            store.books[index].isDemo = sampleBooks.contains { $0.title == store.books[index].title && $0.coverName == store.books[index].coverName }
        }
        for index in store.activities.indices where store.activities[index].isDemo == nil {
            store.activities[index].isDemo = sampleActivities.contains { $0.bookTitle == store.activities[index].bookTitle && $0.minutes == store.activities[index].minutes }
        }
        for index in store.journalEntries.indices where store.journalEntries[index].isDemo == nil {
            store.journalEntries[index].isDemo = sampleJournal.contains { $0.text == store.journalEntries[index].text }
        }
    }
}

@MainActor
final class ReadingStore: ObservableObject {
    @Published var books: [Book] = []
    @Published var activities: [ReadingActivity] = []
    @Published var journalEntries: [JournalEntry] = []

    @Published var dailyGoal = 30
    /// Which days and for how long the daily goal applies. Nil means every day with no end date.
    @Published var routine: ReadingRoutine?
    @Published var yearlyBookGoal = 24
    @Published var reminderEnabled = false
    @Published var reminderTime = Calendar.current.date(from: DateComponents(hour: 20, minute: 0)) ?? .now
    @Published var selectedBookID: UUID?

    /// True until the user picks demo content or a fresh start on first launch.
    @Published private(set) var needsOnboarding = false

    private var autosave: AnyCancellable?

    /// Loads the data saved on this device (starting empty on first launch) and
    /// saves again shortly after anything changes.
    init() {
        if let saved = LocalStore.load() {
            restore(from: saved)
            reminderEnabled = saved.reminderEnabled ?? reminderEnabled
            reminderTime = saved.reminderTime ?? reminderTime
            selectedBookID = saved.selectedBookID
            DemoContent.markLegacyItems(in: self)
        } else {
            needsOnboarding = true
        }
        autosave = objectWillChange
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.save() }
    }

    func save() {
        // Nothing is written until onboarding finishes, so quitting halfway shows it again next launch.
        guard !needsOnboarding else { return }
        LocalStore.save(snapshot)
    }

    func finishOnboarding(withDemoContent: Bool) {
        if withDemoContent { loadDemoContent() }
        needsOnboarding = false
        // Save right away so a fresh start with no changes isn't asked again next launch.
        save()
    }

    var hasDemoContent: Bool {
        books.contains { $0.isDemo == true }
            || activities.contains { $0.isDemo == true }
            || journalEntries.contains { $0.isDemo == true }
    }

    /// Adds the sample library alongside the user's own data.
    func loadDemoContent() {
        clearDemoContent()
        books.append(contentsOf: DemoContent.books)
        activities = (activities + DemoContent.activities).sorted { $0.date > $1.date }
        journalEntries = (journalEntries + DemoContent.journalEntries).sorted { $0.date > $1.date }
    }

    /// Removes only the sample library, keeping everything the user added.
    func clearDemoContent() {
        guard hasDemoContent else { return }
        books.removeAll { $0.isDemo == true }
        activities.removeAll { $0.isDemo == true }
        journalEntries.removeAll { $0.isDemo == true }
        if let selectedBookID, book(with: selectedBookID) == nil {
            self.selectedBookID = nil
        }
    }

    var activeBook: Book? {
        if let selectedBookID, let selected = book(with: selectedBookID) {
            return selected
        }
        // Fall back to a book on the to-read list, e.g. the first book added during onboarding.
        return books.first(where: { $0.status == .reading })
            ?? books.first(where: { $0.status == .wantToRead })
    }

    var minutesToday: Int {
        minutesRead(on: .now)
    }

    func minutesRead(on day: Date) -> Int {
        activities
            .filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
            .reduce(0) { $0 + $1.minutes }
    }

    /// Monday to Sunday of the current week.
    var currentWeekDays: [Date] {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        guard let monday = calendar.dateInterval(of: .weekOfYear, for: .now)?.start else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
    }

    /// Whether the daily goal applies on this day.
    func isScheduled(_ day: Date) -> Bool {
        routine?.includes(day) ?? true
    }

    var routineHasEnded: Bool {
        guard let routine else { return false }
        return Date.now >= routine.endDate
    }

    var routineDaysLabel: String {
        routine?.daysLabel ?? String(localized: "Every day")
    }

    /// Saves a goal created in `CreateGoalFlow` and schedules its reminders.
    func applyGoal(minutes: Int, routine: ReadingRoutine, remind: Bool) {
        dailyGoal = minutes
        self.routine = routine
        reminderEnabled = remind
        if remind {
            ReminderManager.schedule(at: reminderTime, weekdays: routine.weekdays)
        } else {
            ReminderManager.cancel()
        }
    }

    var currentWeekMinutes: Int {
        currentWeekDays.reduce(0) { $0 + minutesRead(on: $1) }
    }

    var finishedBooks: Int {
        books.filter { $0.status == .finished }.count
    }

    struct GenreShare: Identifiable {
        let genre: String
        let percent: Int
        var id: String { genre }
    }

    /// Top genres by time spent reading, or by books in the library before any sessions are logged.
    var favouriteGenres: (shares: [GenreShare], byReadingTime: Bool) {
        func genre(of book: Book) -> String {
            let trimmed = book.genre.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? String(localized: "Other") : trimmed
        }

        var totals: [String: Int] = [:]
        for activity in activities {
            if let book = books.first(where: { $0.title == activity.bookTitle }) {
                totals[genre(of: book), default: 0] += activity.minutes
            }
        }
        let byReadingTime = totals.values.reduce(0, +) > 0
        if !byReadingTime {
            totals = [:]
            for book in books { totals[genre(of: book), default: 0] += 1 }
        }

        let total = totals.values.reduce(0, +)
        guard total > 0 else { return ([], byReadingTime) }
        let shares = totals
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(5)
            .map { GenreShare(genre: $0.key, percent: Int((Double($0.value) / Double(total) * 100).rounded())) }
        return (Array(shares), byReadingTime)
    }

    /// Pages per minute over the last seven sessions that recorded pages read.
    var readingSpeed: (pagesPerMinute: Double, sessions: Int)? {
        let sessions = activities
            .filter { ($0.pagesRead ?? 0) > 0 && $0.minutes > 0 }
            .sorted { $0.date > $1.date }
            .prefix(7)
        let minutes = sessions.reduce(0) { $0 + $1.minutes }
        guard minutes > 0 else { return nil }
        let pages = sessions.reduce(0) { $0 + ($1.pagesRead ?? 0) }
        return (Double(pages) / Double(minutes), sessions.count)
    }

    func book(with id: UUID) -> Book? {
        books.first(where: { $0.id == id })
    }

    var snapshot: ReadingSnapshot {
        ReadingSnapshot(
            books: books,
            activities: activities,
            journalEntries: journalEntries,
            dailyGoal: dailyGoal,
            yearlyBookGoal: yearlyBookGoal,
            routine: routine,
            reminderEnabled: reminderEnabled,
            reminderTime: reminderTime,
            selectedBookID: selectedBookID,
            savedAt: .now
        )
    }

    func restore(from snapshot: ReadingSnapshot) {
        books = snapshot.books
        activities = snapshot.activities
        journalEntries = snapshot.journalEntries
        dailyGoal = snapshot.dailyGoal
        yearlyBookGoal = snapshot.yearlyBookGoal
        routine = snapshot.routine
        selectedBookID = nil
    }

    /// Adds a new entry or replaces the existing one with the same id, keeping newest first.
    func saveJournalEntry(_ entry: JournalEntry) {
        if let index = journalEntries.firstIndex(where: { $0.id == entry.id }) {
            journalEntries[index] = entry
        } else {
            journalEntries.append(entry)
        }
        journalEntries.sort { $0.date > $1.date }
    }

    func deleteJournalEntry(id: UUID) {
        journalEntries.removeAll { $0.id == id }
    }

    func addBook(_ book: Book) {
        books.insert(book, at: 0)
    }

    /// Saves edits to a book. Sessions and journal entries refer to books by title, so a rename
    /// and a new cover carry over to them.
    func updateBook(_ book: Book) {
        guard let index = books.firstIndex(where: { $0.id == book.id }) else { return }
        let oldTitle = books[index].title
        books[index] = book
        for i in activities.indices where activities[i].bookTitle == oldTitle {
            activities[i].bookTitle = book.title
            activities[i].coverName = book.coverName
            activities[i].coverURL = book.coverURL
        }
        for i in journalEntries.indices where journalEntries[i].bookTitle == oldTitle {
            journalEntries[i].bookTitle = book.title
        }
    }

    /// Removes a book from the library. Its past sessions and journal entries stay.
    func deleteBook(id: UUID) {
        books.removeAll { $0.id == id }
        if selectedBookID == id { selectedBookID = nil }
    }

    func completeSession(for bookID: UUID, seconds: TimeInterval, page: Int, journal: String) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else { return }

        let roundedMinutes = max(1, Int((seconds / 60).rounded()))
        let previousPage = books[index].currentPage
        books[index].currentPage = min(page, books[index].totalPages)
        books[index].status = books[index].currentPage >= books[index].totalPages ? .finished : .reading

        let completedBook = books[index]
        activities.insert(
            ReadingActivity(
                date: .now,
                minutes: roundedMinutes,
                bookTitle: completedBook.title,
                coverName: completedBook.coverName,
                coverURL: completedBook.coverURL,
                pagesRead: max(0, completedBook.currentPage - previousPage)
            ),
            at: 0
        )

        let trimmedJournal = journal.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedJournal.isEmpty {
            journalEntries.insert(
                JournalEntry(date: .now, bookTitle: completedBook.title, text: trimmedJournal),
                at: 0
            )
        }
    }
}

// MARK: - App shell

struct ReadTimeTabView: View {
    @EnvironmentObject private var store: ReadingStore
    @State private var showingBookPicker = false
    @State private var showingSession = false

    private var onboardingBinding: Binding<Bool> {
        Binding(get: { store.needsOnboarding }, set: { _ in })
    }

    var body: some View {
        TabView {
            NavigationStack {
                HomeView(showingBookPicker: $showingBookPicker)
            }
            .tabItem { Label("Home", systemImage: "house") }

            NavigationStack {
                GoalsView()
            }
            .tabItem { Label("Goals", systemImage: "target") }

            NavigationStack {
                LibraryView()
            }
            .tabItem { Label("Library", systemImage: "books.vertical") }

            NavigationStack {
                StatsView()
            }
            .tabItem { Label("Stats", systemImage: "chart.bar.xaxis") }
        }
        .sheet(isPresented: $showingBookPicker) {
            BookPickerView { book in
                store.selectedBookID = book.id
                showingSession = true
            }
            .environmentObject(store)
            .presentationDetents([.medium, .large])
        }
        .fullScreenCover(isPresented: onboardingBinding) {
            OnboardingView()
                .environmentObject(store)
        }
        .fullScreenCover(isPresented: $showingSession) {
            if let book = store.activeBook {
                ReadingSessionView(bookID: book.id)
                    .environmentObject(store)
            }
        }
    }
}

// MARK: - Home

struct HomeView: View {
    @EnvironmentObject private var store: ReadingStore
    @EnvironmentObject private var purchases: PurchaseManager
    @Binding var showingBookPicker: Bool
    @State private var showingSettings = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                // Sits right under the large navigation title; collapses to nothing until an ad loads.
                AdBanner()

                SectionHeader(title: "Recent Goals", systemImage: "target") {
                    // The Goals tab is the dedicated edit surface.
                }

                VStack(spacing: 14) {
                    DailyGoalCard()
                    if let book = store.activeBook {
                        ActiveBookGoalCard(book: book)
                    }
                }

                SectionHeader(title: "Recent Activities", systemImage: "arrow.triangle.2.circlepath")

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(store.activities.prefix(3)) { activity in
                            ActivityCard(activity: activity)
                        }
                    }
                }

                AdBanner()

                NavigationLink {
                    JournalView()
                } label: {
                    JournalPreview(entry: store.journalEntries.first, count: store.journalEntries.count)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(Color.readTimeBackground.ignoresSafeArea())
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingSettings = true } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(store)
                .environmentObject(purchases)
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button {
                    showingBookPicker = true
                } label: {
                    Label("Read Now", systemImage: "play.fill")
                        .font(.headline)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 15)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(.readTimePurple)
                .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
    }
}

struct DailyGoalCard: View {
    @EnvironmentObject private var store: ReadingStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("\(store.dailyGoal) min", systemImage: "alarm")
                    .font(.headline)
                    .foregroundStyle(Color.readTimePurple)
                Spacer()
                GoalBadge(text: store.routineDaysLabel)
            }

            Group {
                if store.routineHasEnded {
                    Text("Your routine has ended. Create a new goal in the Goals tab.")
                } else if store.isScheduled(.now) {
                    Text("Today: \(store.minutesToday) of \(store.dailyGoal) minutes")
                } else {
                    if store.minutesToday >= store.dailyGoal {
                        Text("Rest day, but you still read \(store.minutesToday) minutes. Nice!")
                    } else {
                        Text("Rest day today. You've read \(store.minutesToday) minutes.")
                    }
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            ProgressView(value: Double(store.minutesToday), total: Double(store.dailyGoal))
                .tint(.readTimeGreen)

            WeekTracker()
        }
        .padding(16)
        .readTimeCard()
    }
}

/// Monday to Sunday of this week, with a check on each day the daily goal was met.
struct WeekTracker: View {
    @EnvironmentObject private var store: ReadingStore
    /// Colour for today's column.
    var todayColor: Color = .readTimePurple
    /// Give every day its own tile, as on the session summary.
    var tiled = false

    var body: some View {
        HStack(spacing: tiled ? 6 : 5) {
            ForEach(store.currentWeekDays, id: \.self) { day in
                let isToday = Calendar.current.isDateInToday(day)
                let scheduled = store.isScheduled(day)
                let goalMet = store.minutesRead(on: day) >= store.dailyGoal
                let color = isToday ? todayColor : Color.readTimePurple
                VStack(spacing: 5) {
                    Text(day.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(isToday ? todayColor : Color.primary)
                    Text(day.formatted(.dateTime.day()))
                        .font(.caption)
                        .foregroundStyle(isToday ? AnyShapeStyle(todayColor) : AnyShapeStyle(.secondary))
                    Group {
                        // Reading the goal amount counts even on a day outside the routine.
                        if scheduled || goalMet {
                            Image(systemName: goalMet ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(color.opacity(day > .now && !isToday ? 0.4 : 1))
                        } else {
                            // Not part of the routine: a quiet dot instead of a goal circle.
                            Circle()
                                .fill(Color.secondary.opacity(0.25))
                                .frame(width: 18, height: 18)
                        }
                    }
                    .frame(height: 26)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, tiled ? 9 : 7)
                .background(
                    isToday ? todayColor.opacity(tiled ? 0.12 : 0.07) : (tiled ? Color.readTimeBackground : .clear),
                    in: RoundedRectangle(cornerRadius: 10)
                )
                .overlay {
                    if isToday {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(todayColor, lineWidth: 1)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityValue(goalMet ? Text("Goal met") : (scheduled ? Text("Goal not met") : Text("Rest day")))
            }
        }
    }
}

struct ActiveBookGoalCard: View {
    let book: Book

    var body: some View {
        HStack(spacing: 14) {
            BookCover(book: book, width: 50, height: 75)
            VStack(alignment: .leading, spacing: 7) {
                Text(book.title)
                    .font(.headline)
                    .lineLimit(1)
                Text("Page \(book.currentPage) of \(book.totalPages)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ProgressView(value: book.progress)
                    .tint(.readTimeGreen)
            }
            Spacer(minLength: 4)
            Text("\(Int(book.progress * 100))%")
                .font(.headline)
                .foregroundStyle(Color.readTimeGreen)
                .padding(12)
                .background(Color.readTimeGreen.opacity(0.10), in: Circle())
        }
        .padding(16)
        .readTimeCard()
    }
}

struct ActivityCard: View {
    let activity: ReadingActivity

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(activity.label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Label("\(activity.minutes) mins", systemImage: "clock")
                .font(.headline)
            // 2:3, the usual book cover shape.
            CoverImage(coverName: activity.coverName, coverURL: activity.coverURL)
                .frame(width: 120, height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                .frame(maxWidth: .infinity)
            Text(activity.bookTitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 170, alignment: .leading)
        .padding(12)
        .readTimeCard()
    }
}

struct JournalPreview: View {
    let entry: JournalEntry?
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Reading journal", systemImage: "pencil.and.outline")
                    .font(.headline)
                    .foregroundStyle(Color.readTimeText)
                Spacer()
                if count > 0 {
                    Text("\(count) entries")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            if let entry {
                Text(entry.text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                if !entry.bookTitle.isEmpty {
                    Text(entry.bookTitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.readTimePurple)
                }
            } else {
                Text("Capture your thoughts about what you're reading.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .readTimeCard()
        .contentShape(Rectangle())
    }
}

struct JournalView: View {
    @EnvironmentObject private var store: ReadingStore
    @State private var editingEntry: JournalEntry?

    var body: some View {
        Group {
            if store.journalEntries.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "book.and.wrench")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.readTimePurple.opacity(0.6))
                    Text("No journal entries yet")
                        .font(.title3.bold())
                    Text("Write down quotes, ideas, and feelings from your reading. Entries also appear when you finish a reading session.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button {
                        editingEntry = newEntry()
                    } label: {
                        Label("New Entry", systemImage: "square.and.pencil")
                            .font(.headline)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .tint(.readTimePurple)
                    .padding(.top, 6)
                }
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(store.journalEntries) { entry in
                        Button {
                            editingEntry = entry
                        } label: {
                            JournalEntryRow(entry: entry)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.readTimeCardBackground)
                        .swipeActions {
                            Button(role: .destructive) {
                                store.deleteJournalEntry(id: entry.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .tint(.red)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(Color.readTimeBackground.ignoresSafeArea())
        .navigationTitle("Reading Journal")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editingEntry = newEntry()
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("New Entry")
            }
        }
        .sheet(item: $editingEntry) { entry in
            JournalEntryEditor(entry: entry, isNew: !store.journalEntries.contains { $0.id == entry.id })
                .environmentObject(store)
        }
    }

    private func newEntry() -> JournalEntry {
        JournalEntry(date: .now, bookTitle: store.activeBook?.title ?? "", text: "")
    }
}

struct JournalEntryRow: View {
    let entry: JournalEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if !entry.bookTitle.isEmpty {
                    Text(entry.bookTitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.readTimePurple)
                        .lineLimit(1)
                }
            }
            Text(entry.text)
                .font(.body)
                .foregroundStyle(Color.readTimeText)
                .lineLimit(4)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

struct JournalEntryEditor: View {
    @EnvironmentObject private var store: ReadingStore
    @Environment(\.dismiss) private var dismiss
    @State private var entry: JournalEntry
    @State private var confirmingDelete = false
    let isNew: Bool

    init(entry: JournalEntry, isNew: Bool) {
        _entry = State(initialValue: entry)
        self.isNew = isNew
    }

    private var bookTitles: [String] {
        var titles = store.books.map(\.title)
        // Keep the entry's book selectable even if it was removed from the library.
        if !entry.bookTitle.isEmpty, !titles.contains(entry.bookTitle) {
            titles.insert(entry.bookTitle, at: 0)
        }
        return titles
    }

    private var canSave: Bool {
        !entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Book", selection: $entry.bookTitle) {
                        Text("None").tag("")
                        ForEach(bookTitles, id: \.self) { title in
                            Text(title).tag(title)
                        }
                    }
                    DatePicker("Date", selection: $entry.date)
                }

                Section("Entry") {
                    TextEditor(text: $entry.text)
                        .frame(minHeight: 220)
                        .accessibilityLabel("Journal entry")
                }

                if !isNew {
                    Section {
                        Button("Delete Entry", role: .destructive) {
                            confirmingDelete = true
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.readTimeBackground.ignoresSafeArea())
            .navigationTitle(isNew ? "New Entry" : "Edit Entry")
            .keyboardDoneButton()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        entry.text = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
                        store.saveJournalEntry(entry)
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(!canSave)
                    .accessibilityLabel("Save")
                }
            }
            .confirmationDialog("Delete this entry?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete Entry", role: .destructive) {
                    store.deleteJournalEntry(id: entry.id)
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Goals

struct GoalsView: View {
    @EnvironmentObject private var store: ReadingStore
    @State private var creating: GoalKind?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                AdBanner()

                Text("Make time for the books that matter.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                RoutineGoalCard { creating = $0 }

                GoalSummaryCard(
                    title: "Daily reading",
                    subtitle: "\(store.minutesToday) of \(store.dailyGoal) minutes today",
                    systemImage: "timer",
                    progress: Double(store.minutesToday) / Double(max(store.dailyGoal, 1)),
                    value: "\(store.dailyGoal) min"
                )

                GoalSummaryCard(
                    title: "Yearly book goal",
                    subtitle: "\(store.finishedBooks) of \(store.yearlyBookGoal) books finished",
                    systemImage: "books.vertical.fill",
                    progress: Double(store.finishedBooks) / Double(max(store.yearlyBookGoal, 1)),
                    value: "\(store.yearlyBookGoal) books"
                )

                VStack(alignment: .leading, spacing: 12) {
                    Label("Set your goals", systemImage: "slider.horizontal.3")
                        .font(.headline)
                    Stepper("Daily goal: \(store.dailyGoal) minutes", value: $store.dailyGoal, in: 5...600, step: 5)
                    Stepper("Yearly goal: \(store.yearlyBookGoal) books", value: $store.yearlyBookGoal, in: 1...100)
                }
                .padding(16)
                .readTimeCard()

                ReminderCard()
            }
            .padding(20)
        }
        .background(Color.readTimeBackground.ignoresSafeArea())
        .navigationTitle("Goals")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NewGoalMenu { creating = $0 } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New Goal")
            }
        }
        .sheet(item: $creating) { kind in
            CreateGoalFlow(kind: kind)
                .environmentObject(store)
        }
    }
}

struct NewGoalMenu<Label: View>: View {
    let onSelect: (GoalKind) -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Menu {
            Button { onSelect(.daily) } label: {
                SwiftUI.Label("Daily Goal", systemImage: "sun.max")
            }
            Button { onSelect(.custom) } label: {
                SwiftUI.Label("Custom Goal", systemImage: "calendar.badge.plus")
            }
        } label: {
            label()
        }
    }
}

struct GoalBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(Color.readTimePurple)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .overlay(Capsule().stroke(Color.readTimePurple.opacity(0.35)))
    }
}

/// The current reading routine on the Goals tab, or a prompt to create one.
struct RoutineGoalCard: View {
    @EnvironmentObject private var store: ReadingStore
    let onCreate: (GoalKind) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let routine = store.routine {
                HStack {
                    Label("\(store.dailyGoal) min/day", systemImage: "alarm")
                        .font(.headline)
                        .foregroundStyle(Color.readTimePurple)
                    Spacer()
                    GoalBadge(text: routine.daysLabel)
                }
                Group {
                    if store.routineHasEnded {
                        Text("Ended \(routine.lastDay.formatted(date: .abbreviated, time: .omitted))")
                    } else {
                        Text("\(GoalFormat.startLabel(routine.startDate)) – \(routine.lastDay.formatted(date: .abbreviated, time: .omitted)) · \(GoalFormat.durationLabel(weeks: routine.weeks))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                WeekTracker()

                NewGoalMenu(onSelect: onCreate) {
                    Label("New Goal", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                }
                .padding(.top, 2)
            } else {
                Label("Build a reading habit", systemImage: "target")
                    .font(.headline)
                Text("Choose how long to read, on which days, and how many weeks to keep it up.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button { onCreate(.daily) } label: {
                        Text("Daily Goal").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    Button { onCreate(.custom) } label: {
                        Text("Custom Goal").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .buttonBorderShape(.capsule)
                .tint(.readTimePurple)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .readTimeCard()
    }
}

struct GoalSummaryCard: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let systemImage: String
    let progress: Double
    let value: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(Color.readTimePurple)
                    .frame(width: 48, height: 48)
                    .background(Color.readTimePurple.opacity(0.10), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.readTimePurple)
            }
            ProgressView(value: min(progress, 1))
                .tint(.readTimePurple)
        }
        .padding(16)
        .readTimeCard()
    }
}

struct ReminderCard: View {
    @EnvironmentObject private var store: ReadingStore

    private var reminderBinding: Binding<Bool> {
        Binding(
            get: { store.reminderEnabled },
            set: { enabled in
                store.reminderEnabled = enabled
                if enabled {
                    ReminderManager.schedule(at: store.reminderTime, weekdays: store.routine?.weekdays ?? Array(1...7))
                } else {
                    ReminderManager.cancel()
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Gentle reminder", systemImage: "bell.badge")
                .font(.headline)
            Text("Choose a quiet moment to return to your book.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Toggle("Daily reading reminder", isOn: reminderBinding)
            if store.reminderEnabled {
                DatePicker("Remind me at", selection: $store.reminderTime, displayedComponents: .hourAndMinute)
                    .onChange(of: store.reminderTime) { newTime in
                        ReminderManager.schedule(at: newTime, weekdays: store.routine?.weekdays ?? Array(1...7))
                    }
            }
        }
        .padding(16)
        .readTimeCard()
    }
}

enum ReminderManager {
    private static let dailyIdentifier = "readtime.daily-reminder"
    private static let allIdentifiers = [dailyIdentifier] + (1...7).map { "\(dailyIdentifier).\($0)" }

    /// Repeats at `date`'s time on the given `Calendar` weekdays (every day by default).
    static func schedule(at date: Date, weekdays: [Int] = Array(1...7)) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = String(localized: "A little reading time")
            content.body = String(localized: "Your book is waiting for the next chapter.")
            content.sound = .default

            center.removePendingNotificationRequests(withIdentifiers: allIdentifiers)
            let time = Calendar.current.dateComponents([.hour, .minute], from: date)
            if Set(weekdays).count == 7 {
                let trigger = UNCalendarNotificationTrigger(dateMatching: time, repeats: true)
                center.add(UNNotificationRequest(identifier: dailyIdentifier, content: content, trigger: trigger))
            } else {
                for weekday in Set(weekdays) {
                    var components = time
                    components.weekday = weekday
                    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                    center.add(UNNotificationRequest(identifier: "\(dailyIdentifier).\(weekday)", content: content, trigger: trigger))
                }
            }
        }
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: allIdentifiers)
    }
}

// MARK: - Goal creation

struct ReadingRoutine: Codable, Equatable {
    /// `Calendar` weekday numbers: 1 is Sunday, 2 is Monday, and so on.
    var weekdays: [Int]
    var startDate: Date
    var weeks: Int

    /// The first day after the routine (exclusive end).
    var endDate: Date {
        let calendar = Calendar.current
        return calendar.date(byAdding: .day, value: weeks * 7, to: calendar.startOfDay(for: startDate)) ?? startDate
    }

    var lastDay: Date {
        Calendar.current.date(byAdding: .day, value: -1, to: endDate) ?? endDate
    }

    func includes(_ day: Date) -> Bool {
        let calendar = Calendar.current
        let date = calendar.startOfDay(for: day)
        return date >= calendar.startOfDay(for: startDate)
            && date < endDate
            && weekdays.contains(calendar.component(.weekday, from: date))
    }

    var daysLabel: String {
        GoalFormat.daysLabel(Set(weekdays))
    }
}

enum GoalKind: String, Identifiable {
    case daily, custom
    var id: String { rawValue }
}

enum GoalFormat {
    /// Monday-first `Calendar` weekday numbers, the order the app shows a week in.
    static let mondayFirstWeekdays = [2, 3, 4, 5, 6, 7, 1]

    static func weekdayName(_ weekday: Int) -> String {
        Calendar.current.shortStandaloneWeekdaySymbols[weekday - 1]
    }

    static func daysLabel(_ weekdays: Set<Int>) -> String {
        if weekdays.count == 7 { return String(localized: "Every day") }
        return mondayFirstWeekdays.filter(weekdays.contains).map(weekdayName).joined(separator: ", ")
    }

    static func minutesLabel(_ minutes: Int) -> String {
        if minutes >= 60, minutes % 60 == 0 {
            return String(localized: "\(minutes / 60) hours")
        }
        return String(localized: "\(minutes) min")
    }

    static func durationLabel(weeks: Int) -> String {
        weeks == 4 ? String(localized: "1 month") : String(localized: "\(weeks) weeks")
    }

    static func startLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return String(localized: "Today") }
        if calendar.isDateInTomorrow(date) { return String(localized: "Tomorrow") }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

struct GoalDraft {
    var minutes = 15
    var weekdays: Set<Int> = Set(1...7)
    var weeks = 4
    var startDate = Calendar.current.startOfDay(for: .now)
    var remind = true

    var routine: ReadingRoutine {
        ReadingRoutine(
            weekdays: GoalFormat.mondayFirstWeekdays.filter(weekdays.contains),
            startDate: startDate,
            weeks: weeks
        )
    }
}

/// Daily goal: reading time and routine, then a preview.
/// Custom goal: days and reading time, then routine, then a preview.
struct CreateGoalFlow: View {
    private enum Step { case dailySpec, customDays, routine, preview }

    let kind: GoalKind
    @EnvironmentObject private var store: ReadingStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: GoalDraft
    @State private var stepIndex = 0

    init(kind: GoalKind) {
        self.kind = kind
        var draft = GoalDraft()
        if kind == .custom { draft.weekdays = [] }
        _draft = State(initialValue: draft)
    }

    private var steps: [Step] {
        kind == .daily ? [.dailySpec, .preview] : [.customDays, .routine, .preview]
    }

    private var step: Step { steps[stepIndex] }

    private var title: LocalizedStringKey {
        switch step {
        case .dailySpec: "Create Daily Goal"
        case .customDays, .routine: "Custom Read Goal"
        case .preview: "Goal Preview"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    switch step {
                    case .dailySpec:
                        ReadPerDaySection(minutes: $draft.minutes)
                        RoutineSection(draft: $draft)
                    case .customDays:
                        WeekdaysSection(weekdays: $draft.weekdays)
                        ReadPerDaySection(minutes: $draft.minutes)
                    case .routine:
                        RoutineSection(draft: $draft)
                    case .preview:
                        GoalPreview(draft: draft)
                    }
                }
                .padding(20)
            }
            .background(Color.readTimeBackground.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Cancel")
                }
            }
            .safeAreaInset(edge: .bottom) { buttons }
        }
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            if step == .preview {
                Button {
                    store.applyGoal(minutes: draft.minutes, routine: draft.routine, remind: draft.remind)
                    dismiss()
                } label: {
                    Text("Create Goal").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    if stepIndex == 0 {
                        dismiss()
                    } else {
                        withAnimation { stepIndex -= 1 }
                    }
                } label: {
                    Text("Back").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    withAnimation { stepIndex += 1 }
                } label: {
                    Text("Next").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(step == .customDays && draft.weekdays.isEmpty)
            }
        }
        .font(.headline)
        .controlSize(.large)
        .buttonBorderShape(.capsule)
        .tint(.readTimePurple)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color.readTimeBackground)
    }
}

private struct GoalSection<Content: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(Color.readTimeText)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .readTimeCard()
    }
}

struct ChoiceChip: View {
    let title: String
    let isSelected: Bool
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(.subheadline.weight(isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? Color.readTimePurple : Color.readTimeText)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? Color.readTimePurple.opacity(0.1) : .clear, in: Capsule())
            .overlay(Capsule().stroke(isSelected ? Color.readTimePurple : Color.secondary.opacity(0.3)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Lays chips out left to right, wrapping onto new rows.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, usedWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            usedWidth = max(usedWidth, x - spacing)
        }
        return CGSize(width: proposal.width ?? usedWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

struct ReadPerDaySection: View {
    @Binding var minutes: Int
    @State private var askingCustom = false
    @State private var customText = ""

    private let presets = [15, 30, 60, 120]

    var body: some View {
        GoalSection(title: "Read Per Day", systemImage: "clock") {
            FlowLayout {
                ForEach(presets, id: \.self) { preset in
                    ChoiceChip(title: GoalFormat.minutesLabel(preset), isSelected: minutes == preset) {
                        minutes = preset
                    }
                }
                let isCustom = !presets.contains(minutes)
                ChoiceChip(
                    title: isCustom ? String(localized: "Custom: \(GoalFormat.minutesLabel(minutes))") : String(localized: "Custom"),
                    isSelected: isCustom,
                    systemImage: "slider.horizontal.3"
                ) {
                    customText = isCustom ? "\(minutes)" : ""
                    askingCustom = true
                }
            }
        }
        .alert("Minutes per day", isPresented: $askingCustom) {
            TextField("Minutes", text: $customText)
                .keyboardType(.numberPad)
            Button("Cancel", role: .cancel) {}
            Button("Set") {
                if let value = Int(customText) { minutes = min(max(value, 5), 600) }
            }
        } message: {
            Text("Enter between 5 and 600 minutes.")
        }
    }
}

struct WeekdaysSection: View {
    @Binding var weekdays: Set<Int>

    var body: some View {
        GoalSection(title: "Selected Days Per Week", systemImage: "calendar") {
            FlowLayout {
                ForEach(GoalFormat.mondayFirstWeekdays, id: \.self) { weekday in
                    ChoiceChip(title: GoalFormat.weekdayName(weekday), isSelected: weekdays.contains(weekday)) {
                        if weekdays.contains(weekday) {
                            weekdays.remove(weekday)
                        } else {
                            weekdays.insert(weekday)
                        }
                    }
                }
            }
            if weekdays.isEmpty {
                Text("Choose at least one day.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct RoutineSection: View {
    @EnvironmentObject private var store: ReadingStore
    @Binding var draft: GoalDraft
    @State private var askingCustom = false
    @State private var customText = ""
    @State private var choosingStart = false

    private let presets = [1, 2, 4]

    var body: some View {
        GoalSection(title: "Maintain Routine For", systemImage: "calendar.badge.clock") {
            FlowLayout {
                ForEach(presets, id: \.self) { weeks in
                    ChoiceChip(title: GoalFormat.durationLabel(weeks: weeks), isSelected: draft.weeks == weeks) {
                        draft.weeks = weeks
                    }
                }
                let isCustom = !presets.contains(draft.weeks)
                ChoiceChip(
                    title: isCustom ? String(localized: "Custom: \(GoalFormat.durationLabel(weeks: draft.weeks))") : String(localized: "Custom"),
                    isSelected: isCustom,
                    systemImage: "slider.horizontal.3"
                ) {
                    customText = isCustom ? "\(draft.weeks)" : ""
                    askingCustom = true
                }
            }

            HStack {
                Label("Date Start", systemImage: "flag")
                    .foregroundStyle(Color.readTimeText)
                Spacer()
                Button {
                    choosingStart = true
                } label: {
                    Label(GoalFormat.startLabel(draft.startDate), systemImage: "calendar")
                        .font(.subheadline)
                        .foregroundStyle(Color.readTimeText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.3)))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 6)

            Toggle(isOn: $draft.remind) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Remind me", systemImage: "bell")
                        .foregroundStyle(Color.readTimeText)
                    Text("At \(store.reminderTime.formatted(date: .omitted, time: .shortened)) on routine days")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.readTimePurple)
        }
        .alert("Number of weeks", isPresented: $askingCustom) {
            TextField("Weeks", text: $customText)
                .keyboardType(.numberPad)
            Button("Cancel", role: .cancel) {}
            Button("Set") {
                if let value = Int(customText) { draft.weeks = min(max(value, 1), 52) }
            }
        } message: {
            Text("Enter between 1 and 52 weeks.")
        }
        .sheet(isPresented: $choosingStart) {
            ChooseStartDaySheet(date: $draft.startDate)
                .presentationDetents([.large])
        }
    }
}

struct ChooseStartDaySheet: View {
    @Binding var date: Date
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Date

    init(date: Binding<Date>) {
        _date = date
        _selection = State(initialValue: date.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                DatePicker("Start date", selection: $selection, in: Calendar.current.startOfDay(for: .now)..., displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding(12)
                    .readTimeCard()
                Spacer()
            }
            .padding(20)
            .background(Color.readTimeBackground.ignoresSafeArea())
            .navigationTitle("Choose Start Day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Cancel")
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    date = Calendar.current.startOfDay(for: selection)
                    dismiss()
                } label: {
                    Text("Select Date").font(.headline).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .tint(.readTimePurple)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }
        }
    }
}

struct GoalPreview: View {
    let draft: GoalDraft

    /// The week (Monday first) the routine starts in.
    private var firstWeek: [Date] {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        guard let monday = calendar.dateInterval(of: .weekOfYear, for: draft.startDate)?.start else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
    }

    var body: some View {
        let routine = draft.routine
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 8) {
                PreviewFact(title: "Type", systemImage: "square.grid.2x2", value: String(localized: "Habit Build"), highlighted: true)
                PreviewFact(title: "Duration", systemImage: "calendar", value: GoalFormat.durationLabel(weeks: draft.weeks))
                PreviewFact(title: "Start", systemImage: "flag", value: GoalFormat.startLabel(draft.startDate))
            }
            .padding(14)
            .readTimeCard()

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("\(draft.minutes) min/day", systemImage: "alarm")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.readTimePurple)
                    Spacer()
                    GoalBadge(text: routine.daysLabel)
                }
                Text("Until \(routine.lastDay.formatted(date: .numeric, time: .omitted))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    ForEach(firstWeek, id: \.self) { day in
                        let active = routine.includes(day)
                        VStack(spacing: 5) {
                            Text(day.formatted(.dateTime.weekday(.abbreviated)))
                                .font(.caption.weight(.medium))
                            Text(day.formatted(.dateTime.day()))
                                .font(.caption)
                            if active {
                                Image(systemName: "circle")
                                    .font(.title3)
                                    .frame(height: 26)
                            } else {
                                Circle()
                                    .fill(Color.secondary.opacity(0.25))
                                    .frame(width: 18, height: 18)
                                    .frame(height: 26)
                            }
                        }
                        .foregroundStyle(active ? AnyShapeStyle(Color.readTimeGreen) : AnyShapeStyle(.secondary))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(active ? Color.readTimeGreen.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 10))
                        .overlay {
                            if active {
                                RoundedRectangle(cornerRadius: 10).stroke(Color.readTimeGreen, lineWidth: 1)
                            }
                        }
                    }
                }

                if draft.remind {
                    Label("Reminders on", systemImage: "bell.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .readTimeCard()
        }
    }
}

private struct PreviewFact: View {
    let title: LocalizedStringKey
    let systemImage: String
    let value: String
    var highlighted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(highlighted ? Color.readTimePurple : Color.readTimeText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Library

struct LibraryView: View {
    @EnvironmentObject private var store: ReadingStore
    @State private var selection: BookStatus? = nil
    @State private var showingAddBook = false
    @State private var editingBook: Book?
    @State private var deletingBook: Book?

    private var books: [Book] {
        guard let selection else { return store.books }
        return store.books.filter { $0.status == selection }
    }

    var body: some View {
        // A List (not a ScrollView) so rows support swipe actions.
        List {
            AdBanner()
                .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            Picker("Book status", selection: $selection) {
                Text("All").tag(BookStatus?.none)
                ForEach(BookStatus.allCases) { status in
                    Text(status.title).tag(Optional(status))
                }
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 10, trailing: 20))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            ForEach(books) { book in
                BookLibraryCard(book: book)
                    .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            deletingBook = book
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .tint(.red)

                        Button {
                            editingBook = book
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.readTimePurple)
                    }
                    .contextMenu {
                        Button { editingBook = book } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(role: .destructive) { deletingBook = book } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.readTimeBackground.ignoresSafeArea())
        .navigationTitle("Library")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddBook = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add a book")
            }
        }
        .sheet(isPresented: $showingAddBook) {
            AddBookView()
                .environmentObject(store)
        }
        .sheet(item: $editingBook) { book in
            AddBookView(editing: book)
                .environmentObject(store)
        }
        .confirmationDialog(
            "Delete this book?",
            isPresented: Binding(get: { deletingBook != nil }, set: { if !$0 { deletingBook = nil } }),
            titleVisibility: .visible,
            presenting: deletingBook
        ) { book in
            Button("Delete Book", role: .destructive) {
                store.deleteBook(id: book.id)
            }
        } message: { book in
            Text("“\(book.title)” will be removed from your library. Your reading history and journal stay.")
        }
    }
}

struct BookLibraryCard: View {
    let book: Book

    var body: some View {
        HStack(spacing: 14) {
            BookCover(book: book, width: 64, height: 96)
            VStack(alignment: .leading, spacing: 6) {
                Text(book.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(book.author)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(book.genre)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if book.status == .reading {
                    ProgressView(value: book.progress)
                        .tint(.readTimePurple)
                    Text("Page \(book.currentPage) of \(book.totalPages)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            Text(book.status.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(book.status.color)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(book.status.color.opacity(0.10), in: Capsule())
        }
        .padding(14)
        .readTimeCard()
    }
}

struct AddBookView: View {
    @EnvironmentObject private var store: ReadingStore
    @Environment(\.dismiss) private var dismiss
    /// The book being edited, or nil when adding a new one.
    private let editing: Book?
    @State private var title: String
    @State private var author: String
    @State private var genre: String
    @State private var pageCount: Int
    @State private var currentPage: Int
    @State private var status: BookStatus
    @State private var coverName: String?
    @State private var coverURL: String?
    @State private var confirmingDelete = false
    @State private var photoItem: PhotosPickerItem?
    @State private var isLoadingPhoto = false
    @State private var photoError: String?

    @State private var query = ""
    @State private var results: [BookSearchResult] = []
    @State private var isSearching = false
    @State private var searchMessage: String?
    @FocusState private var searchFocused: Bool

    init(editing: Book? = nil) {
        self.editing = editing
        _title = State(initialValue: editing?.title ?? "")
        _author = State(initialValue: editing?.author ?? "")
        _genre = State(initialValue: editing?.genre ?? String(localized: "General"))
        _pageCount = State(initialValue: editing?.totalPages ?? 250)
        _currentPage = State(initialValue: editing?.currentPage ?? 0)
        _status = State(initialValue: editing?.status ?? .wantToRead)
        _coverName = State(initialValue: editing?.coverName)
        _coverURL = State(initialValue: editing?.coverURL)
    }

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && !author.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var hasCover: Bool { coverName != nil || coverURL != nil }

    private func save() {
        var book = editing ?? Book(id: UUID(), title: "", author: "", genre: "", totalPages: pageCount, currentPage: 0, status: status)
        book.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        book.author = author.trimmingCharacters(in: .whitespacesAndNewlines)
        book.genre = genre.trimmingCharacters(in: .whitespacesAndNewlines)
        book.totalPages = pageCount
        book.currentPage = min(currentPage, pageCount)
        book.status = status
        book.coverName = coverName
        book.coverURL = coverURL
        if editing == nil {
            store.addBook(book)
        } else {
            store.updateBook(book)
        }
        dismiss()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Title, author, or ISBN", text: $query)
                            .autocorrectionDisabled()
                            .submitLabel(.search)
                            .focused($searchFocused)
                        if isSearching {
                            ProgressView()
                        } else if !query.isEmpty {
                            Button {
                                query = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Clear search")
                        }
                    }

                    if let searchMessage {
                        Text(searchMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(results) { result in
                        Button {
                            select(result)
                        } label: {
                            BookSearchResultRow(result: result)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Find a book")
                } footer: {
                    if query.isEmpty {
                        Text("Search online to fill in the details and cover automatically, or enter them yourself below.")
                    }
                }

                Section("Book details") {
                    HStack(spacing: 14) {
                        ZStack {
                            CoverImage(coverName: coverName, coverURL: coverURL)
                            if isLoadingPhoto { ProgressView() }
                        }
                        .frame(width: 60, height: 90)
                        .clipShape(RoundedRectangle(cornerRadius: 5))

                        VStack(alignment: .leading, spacing: 10) {
                            PhotosPicker(selection: $photoItem, matching: .images) {
                                Label(hasCover ? "Change Cover" : "Upload Cover", systemImage: "photo.on.rectangle")
                            }
                            if hasCover {
                                Button("Remove Cover", role: .destructive) {
                                    coverName = nil
                                    coverURL = nil
                                    photoItem = nil
                                }
                            }
                            if let photoError {
                                Text(photoError)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                    .onChange(of: photoItem) { item in
                        guard let item else { return }
                        Task { await loadCover(from: item) }
                    }
                    TextField("Title", text: $title)
                    TextField("Author", text: $author)
                    TextField("Genre", text: $genre)
                    Stepper("Pages: \(pageCount)", value: $pageCount, in: 1...5_000)
                    if editing != nil {
                        Stepper("Current page: \(currentPage)", value: $currentPage, in: 0...pageCount)
                    }
                }
                Section("Shelf") {
                    Picker("Status", selection: $status) {
                        ForEach(BookStatus.allCases) { status in
                            Text(status.title).tag(status)
                        }
                    }
                }

                if editing != nil {
                    Section {
                        Button("Delete Book", role: .destructive) {
                            confirmingDelete = true
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle(editing == nil ? "New Book" : "Edit Book")
            .keyboardDoneButton()
            .confirmationDialog("Delete this book?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete Book", role: .destructive) {
                    if let editing { store.deleteBook(id: editing.id) }
                    dismiss()
                }
            } message: {
                Text("“\(title)” will be removed from your library. Your reading history and journal stay.")
            }
            .task(id: query) { await search() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) {
                        Image(systemName: "checkmark")
                    }
                    .accessibilityLabel("Save")
                    .disabled(!isValid)
                }
            }
        }
    }

    /// Runs whenever the query changes, after a short pause so typing doesn't fire a request per key.
    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            results = []
            searchMessage = nil
            isSearching = false
            return
        }
        try? await Task.sleep(nanoseconds: 450_000_000)
        guard !Task.isCancelled else { return }

        isSearching = true
        do {
            let found = try await BookSearch.search(trimmed)
            guard !Task.isCancelled else { return }
            results = found
            searchMessage = found.isEmpty ? String(localized: "No books found. You can still add it manually below.") : nil
        } catch {
            guard !Task.isCancelled else { return }
            results = []
            searchMessage = String(localized: "Couldn't search right now. Check your connection, or add the book manually below.")
        }
        isSearching = false
    }

    private func loadCover(from item: PhotosPickerItem) async {
        isLoadingPhoto = true
        photoError = nil
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { throw CocoaError(.fileReadNoSuchFile) }
            coverURL = try CoverCache.saveUploadedCover(data)
            coverName = nil
        } catch {
            photoError = String(localized: "Couldn't use that photo. Try another one.")
        }
        isLoadingPhoto = false
    }

    private func select(_ result: BookSearchResult) {
        title = result.title
        author = result.authors.joined(separator: ", ")
        if let resultGenre = result.genre { genre = resultGenre }
        if let pages = result.pageCount { pageCount = min(max(pages, 1), 5_000) }
        coverURL = result.coverURL?.absoluteString
        if coverURL != nil { coverName = nil }
        searchFocused = false
        query = ""
    }
}

struct BookSearchResultRow: View {
    let result: BookSearchResult

    private var details: String {
        var parts: [String] = []
        if !result.authors.isEmpty { parts.append(result.authors.joined(separator: ", ")) }
        if let year = result.year { parts.append(year) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            CoverImage(coverName: nil, coverURL: result.thumbnailURL?.absoluteString, persist: false)
                .frame(width: 40, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            VStack(alignment: .leading, spacing: 3) {
                Text(result.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.readTimeText)
                    .lineLimit(2)
                if !details.isEmpty {
                    Text(details)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let pages = result.pageCount {
                    Text("\(pages) pages")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "plus.circle.fill")
                .font(.title3)
                .foregroundStyle(Color.readTimePurple)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Book search

struct BookSearchResult: Identifiable, Hashable {
    let id: String
    let title: String
    let authors: [String]
    let genre: String?
    let pageCount: Int?
    let year: String?
    /// Small image for the result list; `coverURL` is the larger one saved with the book.
    let thumbnailURL: URL?
    let coverURL: URL?
}

/// Looks books up on Google Books, falling back to Open Library when Google has
/// nothing or is unavailable (for example when the keyless daily quota runs out).
enum BookSearch {
    /// Optional. Set `GOOGLE_BOOKS_API_KEY` in ReadTime/Config/Secrets.xcconfig; the build copies it
    /// into Info.plist. Without a key Google Books still works, but with a lower shared quota.
    static let googleBooksAPIKey: String = {
        let value = (Bundle.main.object(forInfoDictionaryKey: "GoogleBooksAPIKey") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // An unset build setting can leave the literal "$(GOOGLE_BOOKS_API_KEY)" behind.
        return value.hasPrefix("$(") ? "" : value
    }()

    static func search(_ query: String) async throws -> [BookSearchResult] {
        do {
            let results = try await searchGoogleBooks(query)
            if !results.isEmpty { return results }
        } catch {
            try Task.checkCancellation()
        }
        return try await searchOpenLibrary(query)
    }

    private static func searchGoogleBooks(_ query: String) async throws -> [BookSearchResult] {
        var components = URLComponents(string: "https://www.googleapis.com/books/v1/volumes")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "printType", value: "books"),
            URLQueryItem(name: "maxResults", value: "20")
        ]
        if !googleBooksAPIKey.isEmpty {
            components.queryItems?.append(URLQueryItem(name: "key", value: googleBooksAPIKey))
        }
        let response: GoogleBooksResponse = try await fetch(components.url!)
        return (response.items ?? []).compactMap { item in
            let info = item.volumeInfo
            guard let title = info.title, !title.isEmpty else { return nil }
            // Google returns http thumbnails with a page-curl effect; ask for the plain https image.
            let thumbnail = (info.imageLinks?.thumbnail ?? info.imageLinks?.smallThumbnail)?
                .replacingOccurrences(of: "http://", with: "https://")
                .replacingOccurrences(of: "&edge=curl", with: "")
            return BookSearchResult(
                id: "google-\(item.id)",
                title: [title, info.subtitle].compactMap { $0 }.joined(separator: ": "),
                authors: info.authors ?? [],
                genre: info.categories?.first?.components(separatedBy: " / ").first,
                pageCount: info.pageCount.flatMap { $0 > 0 ? $0 : nil },
                year: info.publishedDate.map { String($0.prefix(4)) },
                thumbnailURL: thumbnail.flatMap(URL.init(string:)),
                coverURL: thumbnail.flatMap(URL.init(string:))
            )
        }
    }

    private static func searchOpenLibrary(_ query: String) async throws -> [BookSearchResult] {
        var components = URLComponents(string: "https://openlibrary.org/search.json")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "20"),
            URLQueryItem(name: "fields", value: "key,title,author_name,first_publish_year,number_of_pages_median,cover_i,subject")
        ]
        let response: OpenLibraryResponse = try await fetch(components.url!)
        return response.docs.compactMap { doc in
            guard let title = doc.title, !title.isEmpty else { return nil }
            return BookSearchResult(
                id: "openlibrary-\(doc.key)",
                title: title,
                authors: doc.author_name ?? [],
                genre: doc.subject?.first,
                pageCount: doc.number_of_pages_median,
                year: doc.first_publish_year.map(String.init),
                // `default=false` returns 404 instead of a blank image when there's no cover.
                thumbnailURL: doc.cover_i.flatMap { URL(string: "https://covers.openlibrary.org/b/id/\($0)-M.jpg?default=false") },
                coverURL: doc.cover_i.flatMap { URL(string: "https://covers.openlibrary.org/b/id/\($0)-L.jpg?default=false") }
            )
        }
    }

    private static func fetch<Response: Decodable>(_ url: URL) async throws -> Response {
        var request = URLRequest(url: url)
        request.setValue("ReadTime/\(AppInfo.version) (\(AppInfo.supportEmail))", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private struct GoogleBooksResponse: Decodable {
        let items: [Item]?

        struct Item: Decodable {
            let id: String
            let volumeInfo: VolumeInfo
        }

        struct VolumeInfo: Decodable {
            let title: String?
            let subtitle: String?
            let authors: [String]?
            let publishedDate: String?
            let pageCount: Int?
            let categories: [String]?
            let imageLinks: ImageLinks?
        }

        struct ImageLinks: Decodable {
            let thumbnail: String?
            let smallThumbnail: String?
        }
    }

    private struct OpenLibraryResponse: Decodable {
        let docs: [Doc]

        struct Doc: Decodable {
            let key: String
            let title: String?
            let author_name: [String]?
            let first_publish_year: Int?
            let number_of_pages_median: Int?
            let cover_i: Int?
            let subject: [String]?
        }
    }
}

// MARK: - Stats

struct StatsView: View {
    @EnvironmentObject private var store: ReadingStore

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                AdBanner()

                HStack(spacing: 12) {
                    StatTile(value: "\(store.currentWeekMinutes)", label: "minutes this week", systemImage: "clock.fill")
                    StatTile(value: "\(store.finishedBooks)", label: "books completed", systemImage: "checkmark.seal.fill")
                }

                VStack(alignment: .leading, spacing: 14) {
                    Label("Weekly reading", systemImage: "chart.bar.fill")
                        .font(.headline)
                    Chart(store.currentWeekDays, id: \.self) { day in
                        BarMark(
                            x: .value("Day", day.formatted(.dateTime.weekday(.abbreviated))),
                            y: .value("Minutes", store.minutesRead(on: day))
                        )
                        .foregroundStyle(Color.readTimePurple.gradient)
                        .cornerRadius(5)
                    }
                    .chartYAxisLabel("Minutes")
                    .frame(height: 190)
                }
                .padding(16)
                .readTimeCard()

                favouriteGenresCard

                readingSpeedCard
            }
            .padding(20)
        }
        .background(Color.readTimeBackground.ignoresSafeArea())
        .navigationTitle("Stats")
    }

    private var favouriteGenresCard: some View {
        let favourites = store.favouriteGenres
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Label("Favourite genres", systemImage: "heart.text.square")
                    .font(.headline)
                if !favourites.shares.isEmpty {
                    Text(favourites.byReadingTime ? "By time spent reading" : "By books in your library")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if favourites.shares.isEmpty {
                Text("Add books to your library to see your favourite genres.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Chart(favourites.shares) { share in
                    BarMark(
                        x: .value("Share", share.percent),
                        y: .value("Genre", share.genre)
                    )
                    .foregroundStyle(Color.readTimePurple.opacity(0.78))
                    .cornerRadius(4)
                    .annotation(position: .trailing) {
                        Text("\(share.percent)%")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .chartXScale(domain: 0...115)
                .chartXAxis(.hidden)
                .frame(height: CGFloat(favourites.shares.count) * 42 + 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .readTimeCard()
    }

    private var readingSpeedCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("Average reading speed", systemImage: "gauge.with.dots.needle.50percent")
                .font(.headline)
            if let speed = store.readingSpeed {
                Text("\(speed.pagesPerMinute.formatted(.number.precision(.fractionLength(1)))) pages/min")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color.readTimePurple)
                Text("Based on your last \(speed.sessions) sessions")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Finish a reading session and save your page to see your reading speed.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .readTimeCard()
    }
}

struct StatTile: View {
    let value: String
    let label: LocalizedStringKey
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.readTimePurple)
            Text(value)
                .font(.title2.weight(.bold))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .readTimeCard()
    }
}

// MARK: - Reading flow

struct BookPickerView: View {
    @EnvironmentObject private var store: ReadingStore
    @Environment(\.dismiss) private var dismiss
    let onSelect: (Book) -> Void

    private var readableBooks: [Book] {
        store.books.filter { $0.status != .finished }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(readableBooks) { book in
                        Button {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                onSelect(book)
                            }
                        } label: {
                            HStack(spacing: 14) {
                                BookCover(book: book, width: 54, height: 81)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(book.title)
                                        .font(.headline)
                                        .foregroundStyle(Color.readTimeText)
                                    Text(book.author)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Text("\(book.totalPages) pages · \(Text(book.status.title))")
                                        .font(.caption)
                                        .foregroundStyle(book.status.color)
                                }
                                Spacer()
                                Image(systemName: "play.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(Color.readTimePurple)
                            }
                            .padding(14)
                            .readTimeCard()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
            .background(Color.readTimeBackground.ignoresSafeArea())
            .navigationTitle("Choose a book")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
            }
        }
    }
}

struct ReadingSessionView: View {
    @EnvironmentObject private var store: ReadingStore
    @Environment(\.dismiss) private var dismiss
    let bookID: UUID
    @State private var startedAt = Date()
    @State private var showingFinish = false

    private var book: Book? { store.book(with: bookID) }

    var body: some View {
        NavigationStack {
            Group {
                if let book {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let seconds = context.date.timeIntervalSince(startedAt)
                        ScrollView {
                            VStack(spacing: 26) {
                                VStack(spacing: 14) {
                                    BookCover(book: book, width: 170, height: 255)
                                        .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
                                    Text(book.title)
                                        .font(.title3.weight(.medium))
                                        .multilineTextAlignment(.center)
                                    Label("\(book.author) · \(book.totalPages) pages", systemImage: "book.closed")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Text(timeString(seconds))
                                        .font(.system(size: 52, weight: .bold, design: .rounded))
                                        .monospacedDigit()
                                        .foregroundStyle(Color.readTimePurple)
                                        .padding(.top, 18)
                                    Button {
                                        showingFinish = true
                                    } label: {
                                        Label("End Session", systemImage: "stop.circle.fill")
                                            .font(.headline)
                                            .padding(.horizontal, 22)
                                            .padding(.vertical, 14)
                                    }
                                    .buttonStyle(.bordered)
                                    .buttonBorderShape(.capsule)
                                    .tint(.readTimePurple)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(22)
                                .background(.background, in: RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.readTimePurple, lineWidth: 1))

                                Divider()

                                VStack(alignment: .leading, spacing: 14) {
                                    Label("Related goals", systemImage: "target")
                                        .font(.headline)
                                    GoalSummaryCard(
                                        title: "Finish \(book.title)",
                                        subtitle: "Page \(book.currentPage) of \(book.totalPages)",
                                        systemImage: "book.closed.fill",
                                        progress: book.progress,
                                        value: "\(Int(book.progress * 100))%"
                                    )
                                }
                            }
                            .padding(20)
                        }
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "book.closed")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("Book unavailable")
                            .font(.title2.bold())
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Color.readTimeBackground.ignoresSafeArea())
            .navigationTitle("Reading Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "chevron.left") }
                }
            }
            .sheet(isPresented: $showingFinish) {
                FinishSessionView(bookID: bookID, seconds: Date().timeIntervalSince(startedAt)) {
                    dismiss()
                }
                .environmentObject(store)
                .presentationDetents([.large])
            }
        }
    }

    private func timeString(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }
}

struct FinishSessionView: View {
    @EnvironmentObject private var store: ReadingStore
    @Environment(\.dismiss) private var dismiss
    let bookID: UUID
    let seconds: TimeInterval
    let onFinished: () -> Void
    @State private var currentPage = 1
    @State private var journal = ""
    @State private var showingSummary = false

    private var book: Book? { store.book(with: bookID) }

    var body: some View {
        NavigationStack {
            if showingSummary {
                GoalsUpdatedView(bookID: bookID) {
                    dismiss()
                    onFinished()
                }
                .transition(.opacity)
            } else {
                sessionForm
            }
        }
        // The session is already saved once the summary shows; leave only through Confirm.
        .interactiveDismissDisabled(showingSummary)
    }

    private var sessionForm: some View {
            ScrollView {
                if let book {
                    VStack(alignment: .leading, spacing: 14) {
                        Image(systemName: "checkmark")
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(Color.readTimePurple)
                            .frame(width: 88, height: 88)
                            .background(Color.readTimePurple.opacity(0.08), in: Circle())
                            .padding(.top, 8)

                        Text("Finish Session")
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(Color.readTimePurple)

                        HStack(spacing: 14) {
                            BookCover(book: book, width: 64, height: 96)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(book.title).font(.headline)
                                Text(book.author).font(.subheadline).foregroundStyle(.secondary)
                                Text("\(max(1, Int((seconds / 60).rounded()))) min")
                                    .font(.title2.weight(.medium))
                                    .foregroundStyle(Color.readTimePurple)
                            }
                            Spacer()
                        }
                        .padding(16)
                        .readTimeCard()

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Save your current page")
                                .font(.headline)
                            Text("Keep your progress accurate for next time.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Stepper("Page \(currentPage) of \(book.totalPages)", value: $currentPage, in: 1...book.totalPages)
                        }
                        .padding(16)
                        .readTimeCard()

                        VStack(alignment: .leading, spacing: 10) {
                            Label("Journal your thoughts", systemImage: "pencil.and.outline")
                                .font(.headline)
                            TextEditor(text: $journal)
                                .frame(minHeight: 150)
                                .padding(10)
                                .scrollContentBackground(.hidden)
                                .background(Color.readTimeBackground, in: RoundedRectangle(cornerRadius: 12))
                                .accessibilityLabel("Reading journal")
                            Text("Anything you want to remember? Keep it short and clean.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(16)
                        .readTimeCard()

                        Button {
                            store.completeSession(for: bookID, seconds: seconds, page: currentPage, journal: journal)
                            // The session is saved first; the ad (if one is ready) plays before the summary.
                            AdManager.shared.showInterstitial {
                                withAnimation { showingSummary = true }
                            }
                        } label: {
                            Label("Finish Session", systemImage: "checkmark")
                                .frame(maxWidth: .infinity)
                                .font(.headline)
                                .padding(.vertical, 16)
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .tint(.readTimePurple)
                        .padding(.top, 6)
                    }
                    .padding(20)
                    .onAppear {
                        currentPage = min(max(book.currentPage + 1, 1), book.totalPages)
                    }
                }
            }
            .background(Color.readTimeBackground.ignoresSafeArea())
            .keyboardDoneButton()
    }
}

/// Shown after a session is saved: how today's reading moved the daily, book, and yearly goals.
struct GoalsUpdatedView: View {
    @EnvironmentObject private var store: ReadingStore
    let bookID: UUID
    let onConfirm: () -> Void

    private var dailyGoalMet: Bool { store.minutesToday >= store.dailyGoal }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(Color.readTimeGreen)
                        .frame(width: 112, height: 112)
                        .background(Color.readTimeGreen.opacity(0.15), in: Circle())
                    Text("Goals Updated")
                        .font(.largeTitle.bold())
                        .foregroundStyle(Color.readTimeGreen)
                    Text(dailyGoalMet ? "You have made good progress on your goals!" : "Every session counts. Keep going!")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 24)
                .padding(.bottom, 8)

                VStack(alignment: .leading, spacing: 12) {
                    Label("Routine", systemImage: "calendar")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        ForEach(store.currentWeekDays, id: \.self) { day in
                            let scheduled = store.routine.map { $0.weekdays.contains(Calendar.current.component(.weekday, from: day)) } ?? true
                            Text(day.formatted(.dateTime.weekday(.abbreviated)))
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .foregroundStyle(scheduled ? Color.readTimePurple : Color.secondary.opacity(0.6))
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity)
                                .overlay(Capsule().stroke(scheduled ? Color.readTimePurple.opacity(0.35) : Color.secondary.opacity(0.2)))
                        }
                    }

                    Label("Weekly Tracking", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    WeekTracker(todayColor: .readTimeGreen, tiled: true)
                }
                .padding(16)
                .readTimeCard()

                if let book = store.book(with: bookID) {
                    ActiveBookGoalCard(book: book)
                }

                HStack(spacing: 12) {
                    GoalRingCard(
                        progress: Double(store.minutesToday) / Double(max(store.dailyGoal, 1)),
                        ringLabel: "\(store.minutesToday)/\(store.dailyGoal)",
                        title: "\(store.dailyGoal) min",
                        caption: "Read today"
                    )
                    GoalRingCard(
                        progress: Double(store.finishedBooks) / Double(max(store.yearlyBookGoal, 1)),
                        ringLabel: "\(store.finishedBooks)/\(store.yearlyBookGoal)",
                        title: "\(store.yearlyBookGoal) books",
                        caption: "Yearly goal"
                    )
                }
            }
            .padding(20)
        }
        .background(Color.readTimeBackground.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            Button(action: onConfirm) {
                Text("Confirm")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(.readTimePurple)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

struct GoalRingCard: View {
    let progress: Double
    let ringLabel: String
    let title: LocalizedStringKey
    let caption: LocalizedStringKey

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: min(max(progress, 0), 1))
                    .stroke(Color.readTimeGreen, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(ringLabel)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.readTimeGreen)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .padding(6)
            }
            .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .readTimeCard()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Settings

struct ReadingSnapshot: Codable {
    var books: [Book]
    var activities: [ReadingActivity]
    var journalEntries: [JournalEntry]
    var dailyGoal: Int
    var yearlyBookGoal: Int
    var routine: ReadingRoutine?
    // Device-level preferences, only applied when loading this device's own data.
    var reminderEnabled: Bool?
    var reminderTime: Date?
    var selectedBookID: UUID?
    var savedAt: Date
}

/// Saves the reading data as JSON in Application Support so it survives relaunches.
enum LocalStore {
    private static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ReadTime.json")
    }

    static func load() -> ReadingSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        do {
            return try JSONDecoder().decode(ReadingSnapshot.self, from: data)
        } catch {
            print("ReadTime: couldn't read saved data: \(error)")
            return nil
        }
    }

    static func save(_ snapshot: ReadingSnapshot) {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(snapshot).write(to: fileURL, options: .atomic)
        } catch {
            print("ReadTime: couldn't save data: \(error)")
        }
    }
}

/// Stores a single backup of the reading data in iCloud key-value storage, which
/// syncs across the user's devices signed in to the same Apple ID (1 MB limit).
enum CloudBackup {
    static let syncEnabledKey = "iCloudSyncEnabled"
    private static let backupKey = "readtime.backup"

    enum BackupError: LocalizedError {
        case iCloudUnavailable
        case noBackup

        var errorDescription: String? {
            switch self {
            case .iCloudUnavailable: String(localized: "Sign in to iCloud in the Settings app to back up your reading.")
            case .noBackup: String(localized: "No iCloud backup was found.")
            }
        }
    }

    static var isAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    static var lastBackupDate: Date? {
        try? latestSnapshot().savedAt
    }

    @MainActor
    static func backUp(_ store: ReadingStore) throws {
        guard isAvailable else { throw BackupError.iCloudUnavailable }
        let data = try JSONEncoder().encode(store.snapshot)
        NSUbiquitousKeyValueStore.default.set(data, forKey: backupKey)
        NSUbiquitousKeyValueStore.default.synchronize()
    }

    @MainActor
    static func restore(into store: ReadingStore) throws {
        guard isAvailable else { throw BackupError.iCloudUnavailable }
        NSUbiquitousKeyValueStore.default.synchronize()
        store.restore(from: try latestSnapshot())
    }

    private static func latestSnapshot() throws -> ReadingSnapshot {
        guard let data = NSUbiquitousKeyValueStore.default.data(forKey: backupKey) else {
            throw BackupError.noBackup
        }
        return try JSONDecoder().decode(ReadingSnapshot.self, from: data)
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    static let storageKey = "appearanceMode"

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    /// Also applied at the window level so switching back to System takes effect
    /// immediately, including in sheets that are already on screen.
    func apply() {
        let style: UIUserInterfaceStyle = switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .forEach { $0.overrideUserInterfaceStyle = style }
    }
}

@MainActor
final class PurchaseManager: ObservableObject {
    // TODO: Replace with the product ID configured in App Store Connect.
    static let premiumProductID = "com.fatties.readtime.premium"

    @Published private(set) var premiumProduct: Product?
    @Published private(set) var isPremium = false {
        didSet { AdManager.shared.isAdFree = isPremium }
    }
    @Published private(set) var isWorking = false
    @Published var message: String?

    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await self?.refreshEntitlements()
                }
            }
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    func load() async {
        premiumProduct = try? await Product.products(for: [Self.premiumProductID]).first
        await refreshEntitlements()
    }

    func refreshEntitlements() async {
        var owned = false
        for await result in StoreKit.Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.premiumProductID,
               transaction.revocationDate == nil {
                owned = true
            }
        }
        isPremium = owned
    }

    func buyPremium() async {
        if premiumProduct == nil { await load() }
        guard let premiumProduct else {
            message = String(localized: "Premium isn't available right now. Please try again later.")
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            switch try await premiumProduct.purchase() {
            case .success(.verified(let transaction)):
                await transaction.finish()
                isPremium = true
                message = String(localized: "Welcome to ReadTime Premium!")
            case .success(.unverified):
                message = String(localized: "The purchase couldn't be verified.")
            case .pending:
                message = String(localized: "Your purchase is pending approval.")
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            message = error.localizedDescription
        }
    }

    func restorePurchases() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            message = isPremium
                ? String(localized: "Your purchases have been restored.")
                : String(localized: "No previous purchases were found.")
        } catch {
            message = error.localizedDescription
        }
    }
}

enum AppInfo {
    // TODO: Replace with the real support address.
    static let supportEmail = "support@readtime.app"

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    static var contactURL: URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = supportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: String(localized: "ReadTime Support")),
            URLQueryItem(name: "body", value: "\n\n---\nApp version: \(version)\niOS \(UIDevice.current.systemVersion)")
        ]
        return components.url
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: ReadingStore
    @EnvironmentObject private var purchases: PurchaseManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage(AppearanceMode.storageKey) private var appearance = AppearanceMode.system
    @AppStorage(CloudBackup.syncEnabledKey) private var iCloudSyncEnabled = false
    @State private var lastBackup = CloudBackup.lastBackupDate
    @State private var confirmingRestore = false
    @State private var backupMessage: String?
    @State private var confirmingClearDemo = false

    /// The language ReadTime is currently shown in, written in that language.
    private var currentLanguage: String {
        let code = Bundle.main.preferredLocalizations.first ?? "en"
        let locale = Locale(identifier: code)
        return locale.localizedString(forIdentifier: code)?.capitalized(with: locale) ?? code
    }

    var body: some View {
        NavigationStack {
            Form {
                premiumSection
                iCloudSection

                Section("Appearance") {
                    Picker("Theme", selection: $appearance) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    } label: {
                        HStack {
                            Label("Language", systemImage: "globe")
                                .foregroundStyle(Color.readTimeText)
                            Spacer()
                            Text(currentLanguage)
                                .foregroundStyle(.secondary)
                            Image(systemName: "arrow.up.forward.app")
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("ReadTime follows the language chosen for it in the Settings app.")
                }

                demoSection

                Section("Support") {
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("About", systemImage: "info.circle")
                    }
                    Button {
                        if let url = AppInfo.contactURL { openURL(url) }
                    } label: {
                        Label("Contact Us", systemImage: "envelope")
                            .foregroundStyle(Color.readTimeText)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.readTimeBackground.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Restore from iCloud?", isPresented: $confirmingRestore, titleVisibility: .visible) {
                Button("Replace Data on This iPhone", role: .destructive) {
                    run { try CloudBackup.restore(into: store) }
                    if backupMessage == nil { backupMessage = String(localized: "Your reading data was restored.") }
                }
            } message: {
                Text("Your books, goals, and journal on this device will be replaced with the iCloud backup.")
            }
            .alert("iCloud", isPresented: messageBinding(for: $backupMessage)) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(backupMessage ?? "")
            }
            .alert("Premium", isPresented: messageBinding(for: $purchases.message)) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(purchases.message ?? "")
            }
        }
    }

    private var demoSection: some View {
        Section {
            Button {
                store.loadDemoContent()
            } label: {
                Label("Load Demo Content", systemImage: "books.vertical")
                    .foregroundStyle(store.hasDemoContent ? Color.secondary : Color.readTimePurple)
            }
            .disabled(store.hasDemoContent)

            Button(role: .destructive) {
                confirmingClearDemo = true
            } label: {
                Label("Clear Demo Content", systemImage: "trash")
                    .foregroundStyle(store.hasDemoContent ? Color.red : Color.secondary)
            }
            .disabled(!store.hasDemoContent)
            .confirmationDialog("Clear demo content?", isPresented: $confirmingClearDemo, titleVisibility: .visible) {
                Button("Clear Demo Content", role: .destructive) {
                    store.clearDemoContent()
                }
            } message: {
                Text("The sample books, activity, and journal entry will be removed. Your own books and reading stay.")
            }
        } header: {
            Text("Demo Content")
        } footer: {
            Text("Sample books and reading activity to explore ReadTime with. Clearing them never removes your own data.")
        }
    }

    private var premiumSection: some View {
        Section {
            if purchases.isPremium {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ReadTime Premium").font(.headline)
                        Text("Thank you for your support!").font(.subheadline).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "crown.fill").foregroundStyle(Color.readTimeAmber)
                }
            } else {
                Button {
                    Task { await purchases.buyPremium() }
                } label: {
                    HStack {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Upgrade to Premium").font(.headline)
                                Text("Unlock every ReadTime feature").font(.subheadline).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "crown.fill").foregroundStyle(Color.readTimeAmber)
                        }
                        .foregroundStyle(Color.readTimeText)
                        Spacer()
                        if purchases.isWorking {
                            ProgressView()
                        } else if let product = purchases.premiumProduct {
                            Text(product.displayPrice)
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.readTimePurple, in: Capsule())
                                .foregroundStyle(.white)
                        }
                    }
                }
                .disabled(purchases.isWorking)
            }

            Button {
                Task { await purchases.restorePurchases() }
            } label: {
                Label("Restore Purchases", systemImage: "arrow.clockwise")
            }
            .disabled(purchases.isWorking)
        }
    }

    private var iCloudSection: some View {
        Section {
            Toggle(isOn: $iCloudSyncEnabled) {
                Label("Sync with iCloud", systemImage: "icloud")
            }
            .onChange(of: iCloudSyncEnabled) { enabled in
                if enabled { run { try CloudBackup.backUp(store) } }
            }
            Button {
                run { try CloudBackup.backUp(store) }
                if backupMessage == nil { backupMessage = String(localized: "Your reading data was backed up.") }
            } label: {
                Label("Back Up Now", systemImage: "icloud.and.arrow.up")
            }
            Button {
                confirmingRestore = true
            } label: {
                Label("Restore from iCloud", systemImage: "icloud.and.arrow.down")
            }
        } header: {
            Text("iCloud")
        } footer: {
            if !CloudBackup.isAvailable {
                Text("Sign in to iCloud in the Settings app to back up and sync your reading.")
            } else if let lastBackup {
                Text("Last backup: \(lastBackup.formatted(date: .abbreviated, time: .shortened))")
            } else {
                Text("No backup yet. With sync on, ReadTime backs up whenever you leave the app.")
            }
        }
    }

    private func run(_ action: () throws -> Void) {
        do {
            try action()
            lastBackup = CloudBackup.lastBackupDate
        } catch {
            backupMessage = error.localizedDescription
            if error as? CloudBackup.BackupError == .iCloudUnavailable {
                iCloudSyncEnabled = false
            }
        }
    }

    private func messageBinding(for message: Binding<String?>) -> Binding<Bool> {
        Binding(
            get: { message.wrappedValue != nil },
            set: { if !$0 { message.wrappedValue = nil } }
        )
    }
}

struct AboutView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    AppIconView(size: 88)
                    Text("ReadTime")
                        .font(.title2.bold())
                    Text("Version \(AppInfo.version)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            Section {
                Text("ReadTime helps you build a gentle reading habit with daily goals, timed reading sessions, a reading journal, and simple stats.")
                    .foregroundStyle(Color.readTimeText)
            }

            Section {
                Button("Rate ReadTime") {
                    if let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
                        SKStoreReviewController.requestReview(in: scene)
                    }
                }
                Button("Contact Us") {
                    if let url = AppInfo.contactURL { openURL(url) }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.readTimeBackground.ignoresSafeArea())
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Onboarding

struct OnboardingView: View {
    private enum Step { case welcome, goal, firstBook }

    @EnvironmentObject private var store: ReadingStore
    @State private var step = Step.welcome

    var body: some View {
        Group {
            switch step {
            case .welcome:
                OnboardingWelcomeStep(
                    onDemo: { store.finishOnboarding(withDemoContent: true) },
                    onStartFresh: { withAnimation { step = .goal } }
                )
            case .goal:
                OnboardingGoalStep(
                    onBack: { withAnimation { step = .welcome } },
                    onContinue: { withAnimation { step = .firstBook } }
                )
            case .firstBook:
                OnboardingFirstBookStep(
                    onBack: { withAnimation { step = .goal } },
                    onFinish: { store.finishOnboarding(withDemoContent: false) }
                )
            }
        }
        .transition(.opacity)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.readTimeBackground.ignoresSafeArea())
        .interactiveDismissDisabled()
    }
}

private struct OnboardingWelcomeStep: View {
    let onDemo: () -> Void
    let onStartFresh: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 18) {
                AppIconView(size: 112)
                Text("Welcome to ReadTime")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text("Build a gentle reading habit with daily goals, timed sessions, and a reading journal.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 12) {
                Text("How would you like to start?")
                    .font(.headline)
                    .foregroundStyle(Color.readTimeText)

                Button(action: onStartFresh) {
                    VStack(spacing: 2) {
                        Text("Start Fresh")
                            .font(.headline)
                        Text("Set a goal and add your first book")
                            .font(.caption)
                            .opacity(0.85)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)

                Button(action: onDemo) {
                    VStack(spacing: 2) {
                        Text("Explore with Demo Content")
                            .font(.headline)
                        Text("Sample books, goals, and activity")
                            .font(.caption)
                            .opacity(0.85)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)

                Text("You can load or clear demo content anytime in Settings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
            .buttonBorderShape(.capsule)
            .tint(.readTimePurple)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }
}

/// Shared layout for the onboarding steps after the welcome screen.
private struct OnboardingStepLayout<Content: View, Actions: View>: View {
    let progress: Int
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let onBack: () -> Void
    @ViewBuilder let content: () -> Content
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Back")
                Spacer()
                HStack(spacing: 6) {
                    ForEach(1...2, id: \.self) { index in
                        Capsule()
                            .fill(index <= progress ? Color.readTimePurple : Color.secondary.opacity(0.25))
                            .frame(width: index == progress ? 24 : 8, height: 8)
                    }
                }
                .accessibilityElement()
                .accessibilityLabel(Text("Step \(progress) of 2"))
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            .tint(.readTimePurple)
            .padding(.horizontal, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title)
                            .font(.largeTitle.bold())
                        Text(subtitle)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    content()
                }
                .padding(24)
            }

            VStack(spacing: 10) {
                actions()
            }
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(.readTimePurple)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }
}

private struct OnboardingGoalStep: View {
    private enum Choice { case minutesPerDay, booksPerYear }

    @EnvironmentObject private var store: ReadingStore
    let onBack: () -> Void
    let onContinue: () -> Void

    @State private var choice = Choice.minutesPerDay
    @State private var minutes = 20
    @State private var books = 12

    var body: some View {
        OnboardingStepLayout(
            progress: 1,
            title: "Choose your goal",
            subtitle: "Start small. You can change it anytime in Goals.",
            onBack: onBack
        ) {
            VStack(spacing: 14) {
                GoalChoiceCard(
                    systemImage: "clock.fill",
                    title: "Read \(minutes) minutes a day",
                    subtitle: "Build a daily reading habit",
                    isSelected: choice == .minutesPerDay,
                    onSelect: { choice = .minutesPerDay }
                ) {
                    Stepper("Minutes per day", value: $minutes, in: 5...180, step: 5)
                        .labelsHidden()
                        .onChange(of: minutes) { _ in choice = .minutesPerDay }
                }

                GoalChoiceCard(
                    systemImage: "books.vertical.fill",
                    title: "Read \(books) books a year",
                    subtitle: "Finish more of the books you want to read",
                    isSelected: choice == .booksPerYear,
                    onSelect: { choice = .booksPerYear }
                ) {
                    Stepper("Books per year", value: $books, in: 1...100)
                        .labelsHidden()
                        .onChange(of: books) { _ in choice = .booksPerYear }
                }
            }
        } actions: {
            Button {
                switch choice {
                case .minutesPerDay:
                    store.dailyGoal = minutes
                    store.routine = nil
                case .booksPerYear:
                    store.yearlyBookGoal = books
                }
                onContinue()
            } label: {
                Text("Continue").font(.headline).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

private struct GoalChoiceCard<Accessory: View>: View {
    let systemImage: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let isSelected: Bool
    let onSelect: () -> Void
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(Color.readTimePurple)
                    .frame(width: 48, height: 48)
                    .background(Color.readTimePurple.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Color.readTimeText)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? Color.readTimePurple : Color.secondary.opacity(0.5))
            }
            HStack {
                Spacer()
                accessory()
            }
        }
        .padding(16)
        .readTimeCard()
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isSelected ? Color.readTimePurple : .clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct OnboardingFirstBookStep: View {
    @EnvironmentObject private var store: ReadingStore
    let onBack: () -> Void
    let onFinish: () -> Void
    @State private var addingBook = false

    var body: some View {
        OnboardingStepLayout(
            progress: 2,
            title: "Add your first book",
            subtitle: "What are you reading now, or what's next on your list?",
            onBack: onBack
        ) {
            if let book = store.books.first {
                VStack(alignment: .leading, spacing: 12) {
                    BookLibraryCard(book: book)
                    Button {
                        addingBook = true
                    } label: {
                        Label("Add Another Book", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                    }
                    .tint(.readTimePurple)
                }
            } else {
                Button {
                    addingBook = true
                } label: {
                    VStack(spacing: 12) {
                        Image(systemName: "book.closed.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.readTimePurple)
                            .frame(width: 88, height: 88)
                            .background(Color.readTimePurple.opacity(0.12), in: Circle())
                        Text("Search or add a book")
                            .font(.headline)
                            .foregroundStyle(Color.readTimeText)
                        Text("Find it online to fill in the cover and details automatically.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(24)
                    .readTimeCard()
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color.readTimePurple.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                    )
                }
                .buttonStyle(.plain)
            }
        } actions: {
            Button(action: onFinish) {
                Text(store.books.isEmpty ? "Skip for Now" : "Start Reading")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(false)
        }
        .sheet(isPresented: $addingBook) {
            AddBookView()
                .environmentObject(store)
        }
    }
}

// MARK: - Ads

/// Google AdMob interstitials, shown when a reading session ends.
/// IDs come from Info.plist (set in ReadTime/Config/ReadTime.xcconfig); they default to Google's test IDs.
@MainActor
final class AdManager: NSObject, ObservableObject, FullScreenContentDelegate {
    static let shared = AdManager()

    /// Premium users never see ads.
    @Published var isAdFree = false

    private var interstitial: InterstitialAd?
    private var isLoading = false

    private var appOpenAd: AppOpenAd?
    private var appOpenLoadedAt: Date?
    private var isLoadingAppOpen = false
    private var lastAppOpenShownAt: Date?
    private var isShowingAd = false
    private let launchedAt = Date()
    private var onDismiss: (() -> Void)?
    private var started = false

    private var interstitialUnitID: String? {
        let value = (Bundle.main.object(forInfoDictionaryKey: "AdMobInterstitialUnitID") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty || value.hasPrefix("$(") ? nil : value
    }

    /// Asks for consent where the law requires it (EEA, UK, and similar), then starts the SDK
    /// and preloads the first ad.
    func start() {
        guard !started else { return }
        started = true
        Task { await prepare() }
    }

    /// Google's consent form first (where required), then Apple's tracking prompt, then the SDK.
    private func prepare() async {
        // Returning users who already answered the tracking prompt can start without waiting.
        if ATTrackingManager.trackingAuthorizationStatus != .notDetermined {
            startSDKIfAllowed()
        }

        await withCheckedContinuation { continuation in
            ConsentInformation.shared.requestConsentInfoUpdate(with: RequestParameters()) { _ in
                continuation.resume()
            }
        }
        if let root = Self.topViewController() {
            try? await ConsentForm.loadAndPresentIfRequired(from: root)
        }

        await requestTrackingAuthorizationIfNeeded()
        startSDKIfAllowed()
    }

    private func requestTrackingAuthorizationIfNeeded() async {
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else { return }
        // iOS ignores the request unless the app is active, e.g. right after launch.
        for _ in 0..<20 where UIApplication.shared.applicationState != .active {
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        _ = await ATTrackingManager.requestTrackingAuthorization()
    }

    /// True once consent allows ads and the SDK has started; banners wait for this.
    @Published private(set) var sdkStarted = false

    var bannerUnitID: String? {
        let value = (Bundle.main.object(forInfoDictionaryKey: "AdMobBannerUnitID") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty || value.hasPrefix("$(") ? nil : value
    }

    private func startSDKIfAllowed() {
        guard ConsentInformation.shared.canRequestAds, !sdkStarted else { return }
        sdkStarted = true
        MobileAds.shared.start { [weak self] _ in
            Task { @MainActor in
                self?.loadInterstitial()
                self?.loadAppOpenAd()
            }
        }
    }

    private func loadInterstitial() {
        guard !isAdFree, sdkStarted, interstitial == nil, !isLoading, let unitID = interstitialUnitID else { return }
        isLoading = true
        InterstitialAd.load(with: unitID, request: Request()) { [weak self] ad, _ in
            Task { @MainActor in
                guard let self else { return }
                self.isLoading = false
                self.interstitial = ad
                ad?.fullScreenContentDelegate = self
            }
        }
    }

    private var appOpenUnitID: String? {
        let value = (Bundle.main.object(forInfoDictionaryKey: "AdMobAppOpenUnitID") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty || value.hasPrefix("$(") ? nil : value
    }

    /// App open ads expire after four hours, per Google's guidance.
    private var hasFreshAppOpenAd: Bool {
        guard appOpenAd != nil, let appOpenLoadedAt else { return false }
        return Date.now.timeIntervalSince(appOpenLoadedAt) < 4 * 3600
    }

    private func loadAppOpenAd() {
        guard !isAdFree, sdkStarted, !isLoadingAppOpen, !hasFreshAppOpenAd, let unitID = appOpenUnitID else { return }
        isLoadingAppOpen = true
        AppOpenAd.load(with: unitID, request: Request()) { [weak self] ad, _ in
            Task { @MainActor in
                guard let self else { return }
                self.isLoadingAppOpen = false
                self.appOpenAd = ad
                self.appOpenLoadedAt = ad == nil ? nil : .now
                ad?.fullScreenContentDelegate = self
                // Cold start: show it only if it arrived within a few seconds of launch,
                // so it never pops up in the middle of using the app.
                if ad != nil, Date.now.timeIntervalSince(self.launchedAt) < 5 {
                    self.showAppOpenAdIfAvailable()
                }
            }
        }
    }

    /// Shows an app open ad when the app opens or returns to the foreground.
    func showAppOpenAdIfAvailable() {
        guard !isAdFree, !isShowingAd else { return }
        // Don't show them back to back when someone quickly switches apps.
        if let lastAppOpenShownAt, Date.now.timeIntervalSince(lastAppOpenShownAt) < 60 { return }
        guard hasFreshAppOpenAd, let appOpenAd, let root = Self.topViewController(), !(root is UIAlertController) else {
            loadAppOpenAd()
            return
        }
        isShowingAd = true
        lastAppOpenShownAt = .now
        appOpenAd.present(from: root)
    }

    /// Shows an interstitial if one is loaded, then calls `completion` once it closes.
    /// Calls `completion` right away when there's no ad (Premium, no consent, still loading, offline).
    func showInterstitial(then completion: @escaping () -> Void) {
        guard !isAdFree, let interstitial, let root = Self.topViewController() else {
            completion()
            loadInterstitial()
            return
        }
        onDismiss = completion
        isShowingAd = true
        interstitial.present(from: root)
    }

    nonisolated func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        let adID = ObjectIdentifier(ad)
        Task { @MainActor in self.finishPresentation(of: adID) }
    }

    nonisolated func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        let adID = ObjectIdentifier(ad)
        Task { @MainActor in self.finishPresentation(of: adID) }
    }

    private func finishPresentation(of adID: ObjectIdentifier) {
        isShowingAd = false
        if let appOpenAd, ObjectIdentifier(appOpenAd) == adID {
            self.appOpenAd = nil
            appOpenLoadedAt = nil
            loadAppOpenAd()
            return
        }
        interstitial = nil
        let completion = onDismiss
        onDismiss = nil
        completion?()
        loadInterstitial()
    }

    static func topViewController() -> UIViewController? {
        let root = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
        var top = root
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}

/// An adaptive AdMob banner that takes no space until an ad has loaded, and none at all for Premium users.
struct AdBanner: View {
    @ObservedObject private var ads = AdManager.shared
    @State private var width: CGFloat = 0
    @State private var loadedHeight: CGFloat = 0

    var body: some View {
        if !ads.isAdFree, ads.sdkStarted, let unitID = ads.bannerUnitID {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: loadedHeight)
                .background(GeometryReader { proxy in
                    Color.clear
                        .onAppear { width = proxy.size.width }
                        .onChange(of: proxy.size.width) { width = $0 }
                })
                .overlay(alignment: .top) {
                    if width >= 320 {
                        // The banner always gets its full ad size (AdMob rejects a zero-height view);
                        // the container stays collapsed and clips it until an ad has loaded.
                        BannerAdView(unitID: unitID, width: width) { loadedHeight = $0 }
                            .frame(width: width, height: currentOrientationAnchoredAdaptiveBanner(width: width).size.height)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .animation(.easeOut(duration: 0.2), value: loadedHeight)
        }
    }
}

private struct BannerAdView: UIViewRepresentable {
    let unitID: String
    let width: CGFloat
    let onHeightChange: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onHeightChange: onHeightChange) }

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: currentOrientationAnchoredAdaptiveBanner(width: width))
        banner.adUnitID = unitID
        banner.delegate = context.coordinator
        banner.rootViewController = AdManager.topViewController()
        banner.load(Request())
        context.coordinator.loadedWidth = width
        return banner
    }

    func updateUIView(_ banner: BannerView, context: Context) {
        // Reload at the new width after rotation or a layout change.
        guard width > 0, abs(width - context.coordinator.loadedWidth) > 1 else { return }
        context.coordinator.loadedWidth = width
        banner.adSize = currentOrientationAnchoredAdaptiveBanner(width: width)
        banner.load(Request())
    }

    final class Coordinator: NSObject, BannerViewDelegate {
        let onHeightChange: (CGFloat) -> Void
        var loadedWidth: CGFloat = 0

        init(onHeightChange: @escaping (CGFloat) -> Void) {
            self.onHeightChange = onHeightChange
        }

        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            onHeightChange(bannerView.adSize.size.height)
        }

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            onHeightChange(0)
        }
    }
}

// MARK: - Keyboard

extension View {
    /// Adds a Done button above the keyboard and lets scrolling push the keyboard away.
    /// Use inside a NavigationStack on screens with text input.
    func keyboardDoneButton() -> some View {
        self
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { KeyboardDismissal.dismiss() }
                        .fontWeight(.semibold)
                }
            }
    }
}

/// Hides the keyboard when the user taps anywhere that isn't a text field, across the whole
/// app (sheets included), without swallowing taps meant for buttons.
enum KeyboardDismissal {
    private static let handler = TapHandler()

    static func dismiss() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    static func install() {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        for window in windows where !(window.gestureRecognizers ?? []).contains(where: { $0 is DismissTap }) {
            let tap = DismissTap(target: handler, action: #selector(TapHandler.handleTap(_:)))
            tap.cancelsTouchesInView = false
            tap.delegate = handler
            window.addGestureRecognizer(tap)
        }
    }

    private final class DismissTap: UITapGestureRecognizer {}

    private final class TapHandler: NSObject, UIGestureRecognizerDelegate {
        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            recognizer.view?.endEditing(true)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            // Let taps on text inputs through so moving between fields keeps the keyboard up.
            var view = touch.view
            while let current = view {
                if current is UITextField || current is UITextView { return false }
                view = current.superview
            }
            return true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

// MARK: - Reusable views

/// The app icon artwork, also used for the home screen icon in Assets.xcassets.
struct AppIconView: View {
    let size: CGFloat

    var body: some View {
        Image(systemName: "book.pages.fill")
            .font(.system(size: size * 0.5))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color.readTimePurple, in: RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct SectionHeader<Action: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    @ViewBuilder let action: () -> Action

    init(title: LocalizedStringKey, systemImage: String, @ViewBuilder action: @escaping () -> Action = { EmptyView() }) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        HStack {
            Label(title, systemImage: systemImage)
                .font(.title3.weight(.medium))
                .foregroundStyle(Color.readTimeText)
            Spacer()
            action()
        }
    }
}

struct BookCover: View {
    let book: Book
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        CoverImage(coverName: book.coverName, coverURL: book.coverURL)
            .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .accessibilityLabel("Cover of \(book.title)")
    }
}

/// Loads the cover exports from the app bundle. The Figma source assets are PNG
/// resources instead of Xcode asset-catalog entries, so SwiftUI's `Image(name:)`
/// lookup is not sufficient here.
struct FigmaImage: View {
    let name: String

    private var image: UIImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png") else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    var body: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            CoverPlaceholder()
        }
    }
}

struct CoverPlaceholder: View {
    var body: some View {
        Image(systemName: "book.closed.fill")
            .font(.title2)
            .foregroundStyle(Color.readTimePurple)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.readTimePurple.opacity(0.10))
    }
}

/// A book cover from the app bundle (sample books) or from an online search result.
struct CoverImage: View {
    let coverName: String?
    let coverURL: String?
    /// Keep the downloaded image on disk. Search result thumbnails only stay in memory.
    var persist = true
    @State private var remoteImage: UIImage?

    var body: some View {
        Group {
            if let coverName {
                FigmaImage(name: coverName)
            } else if let remoteImage {
                Image(uiImage: remoteImage)
                    .resizable()
                    .scaledToFill()
            } else {
                CoverPlaceholder()
            }
        }
        .task(id: coverURL) {
            guard coverName == nil, let coverURL, let url = URL(string: coverURL) else {
                remoteImage = nil
                return
            }
            remoteImage = await CoverCache.image(for: url, persist: persist)
        }
    }
}

/// Downloads book covers once and keeps them in Application Support so saved books
/// still show their cover offline.
enum CoverCache {
    private static let memory = NSCache<NSURL, NSData>()

    private static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Covers", isDirectory: true)
    }

    private static func fileURL(for url: URL) -> URL {
        let hash = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(hash).appendingPathExtension("jpg")
    }

    /// Covers the user picked from Photos, stored by file name so the path survives app updates.
    private static let uploadScheme = "readtime-cover"

    static func saveUploadedCover(_ data: Data) throws -> String {
        guard let image = UIImage(data: data) else { throw CocoaError(.fileReadCorruptFile) }
        // Covers show at most ~170pt wide, so keep them small.
        let maxSide: CGFloat = 900
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let jpeg = resized.jpegData(compressionQuality: 0.85) else { throw CocoaError(.fileWriteUnknown) }

        let name = "\(UUID().uuidString).jpg"
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try jpeg.write(to: directory.appendingPathComponent(name), options: .atomic)
        return "\(uploadScheme):\(name)"
    }

    static func image(for url: URL, persist: Bool) async -> UIImage? {
        if url.scheme == uploadScheme {
            let file = directory.appendingPathComponent(String(url.absoluteString.dropFirst(uploadScheme.count + 1)))
            return UIImage(contentsOfFile: file.path)
        }
        let file = fileURL(for: url)
        if let data = try? Data(contentsOf: file), let image = UIImage(data: data) {
            return image
        }

        var data = memory.object(forKey: url as NSURL) as Data?
        if data == nil {
            guard let (downloaded, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            data = downloaded
        }
        guard let data, let image = UIImage(data: data) else { return nil }

        memory.setObject(data as NSData, forKey: url as NSURL)
        if persist {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
        }
        return image
    }
}

extension View {
    func readTimeCard() -> some View {
        background(Color.readTimeCardBackground, in: RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
    }
}

extension Color {
    static let readTimePurple = Color(light: (0.412, 0.255, 0.776), dark: (0.604, 0.482, 0.918))
    static let readTimeBackground = Color(light: (0.945, 0.961, 0.976), dark: (0.043, 0.047, 0.063))
    static let readTimeCardBackground = Color(light: (1.0, 1.0, 1.0), dark: (0.110, 0.114, 0.137))
    static let readTimeText = Color(light: (0.200, 0.255, 0.345), dark: (0.855, 0.878, 0.918))
    static let readTimeGreen = Color(red: 0.012, green: 0.706, blue: 0.012)
    static let readTimeAmber = Color(red: 0.890, green: 0.490, blue: 0.075)
}

private extension Color {
    init(light: (Double, Double, Double), dark: (Double, Double, Double)) {
        self.init(uiColor: UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }
}

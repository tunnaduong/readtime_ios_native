import SwiftUI
import Combine
import CryptoKit
import UserNotifications
import UIKit
import UniformTypeIdentifiers
#if !SKIP
// Frameworks with no Skip/Android equivalent: Skip transpiles this file to
// Kotlin/Compose, so these are compiled only for the Darwin (iOS) target. Each
// type that depends on one of these has an `#else` branch below with an
// Android-side stand-in (CloudKit Web Services over HTTP, Play Billing, AdMob
// Android SDK, Android Photo Picker) that still needs its real implementation
// wired up — see README.md "Android TODOs".
import Charts
import StoreKit
import PhotosUI
import GoogleMobileAds
import UserMessagingPlatform
import AppTrackingTransparency
import WidgetKit
import CloudKit
#else
import Foundation
#endif

#if SKIP
/// Talks to Apple's CloudKit **Web Services** REST API — the only way to reach
/// the existing `iCloud.com.fatties.readtime` public database from Android,
/// since there is no CloudKit SDK outside Apple platforms. Needs a CloudKit
/// Console "Server-to-Server Key" (private key + Key ID); see README.md
/// "CloudKit on Android". Docs: https://developer.apple.com/documentation/cloudkitjs/cloudkit_javascript_reference/web_services_reference
enum CloudKitWebService {
    struct Config {
        let containerID: String
        let environment: String // "development" or "production"
        let keyID: String
        let privateKeyPEM: String
    }

    enum ServiceError: LocalizedError {
        case notConfigured
        case badResponse(Int)

        var errorDescription: String? {
            switch self {
            case .notConfigured: "CloudKit isn't configured for Android yet."
            case .badResponse(let code): "CloudKit request failed (\(code))."
            }
        }
    }

    /// Read from Info.plist keys `CloudKitServerKeyID` / `CloudKitServerPrivateKey`
    /// (wire these up the same way the AdMob unit IDs are configured), so the raw
    /// key never sits directly in source.
    static var config: Config? {
        guard
            let keyID = Bundle.main.object(forInfoDictionaryKey: "CloudKitServerKeyID") as? String, !keyID.isEmpty,
            let pem = Bundle.main.object(forInfoDictionaryKey: "CloudKitServerPrivateKey") as? String, !pem.isEmpty
        else { return nil }
        return Config(
            containerID: RoadmapStore.containerIdentifier,
            environment: AppInfo.isDebugBuild ? "development" : "production",
            keyID: keyID,
            privateKeyPEM: pem
        )
    }

    /// Stands in for the signed-in Apple ID CloudKit normally uses, so one
    /// install can't vote twice — mirrors the `vote-<feature>-<user>` record
    /// naming the iOS `RoadmapStore` already relies on.
    static var installID: String {
        let key = "cloudkit.installID"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }

    static func request(path: String, body: [String: Any]) async throws -> [String: Any] {
        guard let config else { throw ServiceError.notConfigured }
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let subpath = "/database/1/\(config.containerID)/\(config.environment)/public/\(path)"
        let date = ISO8601DateFormatter().string(from: Date())
        let bodyHash = Data(SHA256.hash(data: bodyData)).base64EncodedString()
        let message = "\(date):\(bodyHash):\(subpath)"
        let signature = try sign(message: message, privateKeyPEM: config.privateKeyPEM)

        var request = URLRequest(url: URL(string: "https://api.apple-cloudkit.com\(subpath)")!)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        request.setValue(config.keyID, forHTTPHeaderField: "X-Apple-CloudKit-Request-KeyID")
        request.setValue(date, forHTTPHeaderField: "X-Apple-CloudKit-Request-ISO8601Date")
        request.setValue(signature, forHTTPHeaderField: "X-Apple-CloudKit-Request-SignatureV1")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ServiceError.badResponse((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    /// ECDSA P-256/SHA-256 signature over `message`, base64-encoded, per CloudKit
    /// Web Services' server-to-server auth scheme.
    /// Unverified — no Swift/Skip toolchain available here to confirm either
    /// branch actually compiles. Two independent attempts, gated so whichever
    /// works can be kept: CryptoKit (in case Skip's crypto shim covers P256
    /// signing) and, if not, a direct `java.security` call using the
    /// fully-qualified-Kotlin-call pattern Skip Fuse documents.
    private static func sign(message: String, privateKeyPEM: String) throws -> String {
        #if !SKIP
        let key = try P256.Signing.PrivateKey(pemRepresentation: privateKeyPEM)
        let signature = try key.signature(for: Data(message.utf8))
        return signature.derRepresentation.base64EncodedString()
        #else
        // TODO(android): confirm this transpiles — untested. Strips the PEM's
        // header/footer/newlines, decodes the base64 body to a PKCS#8 key, and
        // signs with the JDK's own ECDSA implementation (no extra Gradle
        // dependency needed; java.security is part of the Android runtime).
        let base64Body = privateKeyPEM
            .replacingOccurrences(of: "-----BEGIN PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let keyBytes = Data(base64Encoded: base64Body) else {
            throw ServiceError.notConfigured
        }
        let keySpec = java.security.spec.PKCS8EncodedKeySpec(keyBytes.kotlin())
        let keyFactory = java.security.KeyFactory.getInstance("EC")
        let privateKey = keyFactory.generatePrivate(keySpec)
        let signer = java.security.Signature.getInstance("SHA256withECDSA")
        signer.initSign(privateKey)
        signer.update(Data(message.utf8).kotlin())
        let signatureBytes = signer.sign()
        return Data(platformValue: signatureBytes).base64EncodedString()
        #endif
    }
}
#endif

@main
struct ReadTimeApp: App {
    @StateObject var store = ReadingStore()
    @StateObject var purchases = PurchaseManager()
    @Environment(\.scenePhase) var scenePhase
    @AppStorage(AppearanceMode.storageKey) var appearance = AppearanceMode.system
    @AppStorage(CloudBackup.syncEnabledKey) var iCloudSyncEnabled = false
    /// Set when the app goes to the background; the next `.active` counts as "returning to the app".
    @State var wasInBackground = false

    init() {
        // Shown on ReadTime's page in the Settings app (see Settings.bundle).
        UserDefaults.standard.set(AppInfo.version, forKey: "settings_app_version")
    }

    var body: some Scene {
        WindowGroup {
            ReadTimeTabView()
                .task {
                    #if DEBUG
                    // Screenshot runs start from a known library instead of the welcome screen.
                    if UserDefaults.standard.bool(forKey: "demoContent"), store.needsOnboarding {
                        store.finishOnboarding(withDemoContent: true)
                    }
                    #endif
                }
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
                try? CloudBackup.backUp(JSONEncoder().encode(store.snapshot))
            }
        }
    }
}

#if DEBUG
/// Opens a chosen screen straight away, for capturing App Store screenshots in every language:
/// `simctl launch <device> com.fatties.readtime -screen stats -disableAds YES`.
enum ScreenshotMode {
    static var screen: String? { UserDefaults.standard.string(forKey: "screen") }
}
#endif

// MARK: - Models

/// Represents a saved reading session state for app restoration.
struct ActiveSessionState: Codable {
    let bookID: UUID
    let startedAt: Date
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
    /// The ID of the book currently being read (session in progress).
    @Published var activeSessionBookID: UUID?
    /// The timestamp when the current reading session started.
    @Published var activeSessionStartedAt: Date?

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
        // Restore active session if one was in progress
        if let sessionData = UserDefaults.standard.data(forKey: "activeSession"),
           let session = try? JSONDecoder().decode(ActiveSessionState.self, from: sessionData) {
            activeSessionBookID = session.bookID
            activeSessionStartedAt = session.startedAt
        }
        autosave = objectWillChange
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.save() }
    }

    func save() {
        // Nothing is written until onboarding finishes, so quitting halfway shows it again next launch.
        guard !needsOnboarding else { return }
        LocalStore.save(snapshot)
        #if !SKIP
        WidgetCenter.shared.reloadAllTimelines()
        #endif
        // No Android home-screen widgets yet — WidgetKit has no Android equivalent
        // (Glance would be the native route); out of scope for this port, see README.md.
        // Save active session state
        if let bookID = activeSessionBookID, let startedAt = activeSessionStartedAt {
            let session = ActiveSessionState(bookID: bookID, startedAt: startedAt)
            if let encoded = try? JSONEncoder().encode(session) {
                UserDefaults.standard.set(encoded, forKey: "activeSession")
            }
        } else {
            UserDefaults.standard.removeObject(forKey: "activeSession")
        }
    }

    func startSession(for bookID: UUID) {
        activeSessionBookID = bookID
        activeSessionStartedAt = Date()
        save()
    }

    func clearSession() {
        activeSessionBookID = nil
        activeSessionStartedAt = nil
        UserDefaults.standard.removeObject(forKey: "activeSession")
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

    // MARK: Stats

    func activities(in interval: DateInterval) -> [ReadingActivity] {
        activities.filter { $0.date >= interval.start && $0.date < interval.end }
    }

    func booksFinished(in interval: DateInterval) -> Int {
        books.filter { book in
            guard let finishedAt = book.finishedAt else { return false }
            return finishedAt >= interval.start && finishedAt < interval.end
        }.count
    }

    /// The book read longest on a day, for the calendar cover.
    func topActivity(on day: Date) -> ReadingActivity? {
        let sessions = activities.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
        let minutesByTitle = Dictionary(grouping: sessions, by: \.bookTitle).mapValues { $0.reduce(0) { $0 + $1.minutes } }
        guard let title = minutesByTitle.max(by: { $0.value < $1.value })?.key else { return nil }
        return sessions.first { $0.bookTitle == title }
    }

    /// Most consecutive days with at least one reading session.
    var longestStreak: Int {
        let calendar = Calendar.current
        let days = Set(activities.filter { $0.minutes > 0 }.map { calendar.startOfDay(for: $0.date) }).sorted()
        var best = 0, run = 0
        var previous: Date?
        for day in days {
            if let previous, calendar.dateComponents([.day], from: previous, to: day).day == 1 {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            previous = day
        }
        return best
    }

    var pagesPerHour: Int? {
        readingSpeed.map { Int(($0.pagesPerMinute * 60).rounded()) }
    }

    var averageRating: Double? {
        let ratings = books.compactMap { $0.status == .finished ? $0.rating : nil }
        guard !ratings.isEmpty else { return nil }
        return Double(ratings.reduce(0, +)) / Double(ratings.count)
    }

    var averageFinishedLength: Int? {
        let finished = books.filter { $0.status == .finished }
        guard !finished.isEmpty else { return nil }
        return finished.reduce(0) { $0 + $1.totalPages } / finished.count
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

    /// Adds books that aren't already in the library (same title and author). Returns how many were added.
    @discardableResult
    func importBooks(_ imported: [Book]) -> Int {
        func key(_ book: Book) -> String {
            "\(book.title.lowercased().trimmingCharacters(in: .whitespaces))|\(book.author.lowercased().trimmingCharacters(in: .whitespaces))"
        }
        var existing = Set(books.map(key))
        var added = 0
        for book in imported where !existing.contains(key(book)) {
            books.append(book)
            existing.insert(key(book))
            added += 1
        }
        return added
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
        var book = book
        if book.status == .finished { book.finishedAt = book.finishedAt ?? .now }
        books.insert(book, at: 0)
    }

    /// Saves edits to a book. Sessions and journal entries refer to books by title, so a rename
    /// and a new cover carry over to them.
    func updateBook(_ book: Book) {
        guard let index = books.firstIndex(where: { $0.id == book.id }) else { return }
        let oldTitle = books[index].title
        var book = book
        if book.status == .finished {
            book.finishedAt = book.finishedAt ?? .now
        } else {
            book.finishedAt = nil
            book.rating = nil
        }
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
        if books[index].status == .finished, books[index].finishedAt == nil {
            books[index].finishedAt = .now
        }

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
    @EnvironmentObject var store: ReadingStore
    @EnvironmentObject var purchases: PurchaseManager
    @State var showingPaywall = false
    @State var showingBookPicker = false
    @State var showingSession = false
    @State var selectedTab = 0
    @State var showingJournal = false

    private var onboardingBinding: Binding<Bool> {
        Binding(get: { store.needsOnboarding }, set: { _ in })
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeView(showingBookPicker: $showingBookPicker, showingSession: $showingSession, showingJournal: $showingJournal)
            }
            .tabItem { Label("Home", systemImage: "house") }
            .tag(0)

            NavigationStack {
                GoalsView()
            }
            .tabItem { Label("Goals", systemImage: "target") }
            .tag(1)

            NavigationStack {
                LibraryView()
            }
            .tabItem { Label("Library", systemImage: "books.vertical") }
            .tag(2)

            NavigationStack {
                StatsView()
            }
            .tabItem { Label("Stats", systemImage: "chart.bar.xaxis") }
            .tag(3)
        }
        .task { openScreenshotScreen() }
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
        // Offer Premium once, right after onboarding.
        .onChange(of: store.needsOnboarding) { needsOnboarding in
            guard !needsOnboarding, !purchases.isPremium else { return }
            Task {
                try? await Task.sleep(nanoseconds: 700_000_000)
                showingPaywall = true
            }
        }
        .fullScreenCover(isPresented: $showingPaywall) {
            PremiumPaywallView()
                .environmentObject(purchases)
        }
        .fullScreenCover(isPresented: $showingSession) {
            if let book = store.activeBook {
                ReadingSessionView(bookID: book.id)
                    .environmentObject(store)
            }
        }
    }

    private func openScreenshotScreen() {
        #if DEBUG
        switch ScreenshotMode.screen {
        case "goals": selectedTab = 1
        case "library": selectedTab = 2
        case "stats", "trends": selectedTab = 3
        case "journal": showingJournal = true
        case "session": showingSession = true
        case "premium": showingPaywall = true
        default: break
        }
        #endif
    }
}

// MARK: - Home

struct HomeView: View {
    @EnvironmentObject var store: ReadingStore
    @EnvironmentObject var purchases: PurchaseManager
    @Binding var showingBookPicker: Bool
    @Binding var showingSession: Bool
    @Binding var showingJournal: Bool
    @State var showingSettings = false

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
                .navigationDestination(isPresented: $showingJournal) { JournalView() }
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
                if let activeBook = store.activeBook, store.activeSessionBookID == activeBook.id {
                    Button {
                        showingSession = true
                    } label: {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Resume")
                                    .font(.caption.weight(.medium))
                                Text(activeBook.title)
                                    .font(.caption)
                                    .lineLimit(1)
                                Text("Page \(activeBook.currentPage) of \(activeBook.totalPages)")
                                    .font(.caption2)
                                    .opacity(0.7)
                            }
                            Spacer()
                            Text("\(Int(activeBook.progress * 100))%")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background {
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(Color.readTimePurple.opacity(0.55))
                                GeometryReader { proxy in
                                    Rectangle()
                                        .fill(Color.readTimePurple)
                                        .frame(width: proxy.size.width * activeBook.progress)
                                }
                            }
                        }
                        .clipShape(Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                    .animation(.snappy, value: activeBook.progress)
                } else {
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
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
    }
}

struct DailyGoalCard: View {
    @EnvironmentObject var store: ReadingStore

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
    @EnvironmentObject var store: ReadingStore
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
    @EnvironmentObject var store: ReadingStore
    @State var editingEntry: JournalEntry?

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
    @EnvironmentObject var store: ReadingStore
    @Environment(\.dismiss) var dismiss
    @State var entry: JournalEntry
    @State var confirmingDelete = false
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
    @EnvironmentObject var store: ReadingStore
    @State var creating: GoalKind?

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
    @EnvironmentObject var store: ReadingStore
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
    @EnvironmentObject var store: ReadingStore

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

extension ReadingRoutine {
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
    @EnvironmentObject var store: ReadingStore
    @Environment(\.dismiss) var dismiss
    @State var draft: GoalDraft
    @State var stepIndex = 0

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

struct GoalSection<Content: View>: View {
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
    @State var askingCustom = false
    @State var customText = ""

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
    @EnvironmentObject var store: ReadingStore
    @Binding var draft: GoalDraft
    @State var askingCustom = false
    @State var customText = ""
    @State var choosingStart = false

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
    @Environment(\.dismiss) var dismiss
    @State var selection: Date

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

struct PreviewFact: View {
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
    @EnvironmentObject var store: ReadingStore
    @State var selection: BookStatus? = nil
    @State var showingAddBook = false
    @State var editingBook: Book?
    @State var deletingBook: Book?

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
    @EnvironmentObject var store: ReadingStore
    @Environment(\.dismiss) var dismiss
    /// The book being edited, or nil when adding a new one.
    private let editing: Book?
    @State var title: String
    @State var author: String
    @State var genre: String
    @State var pageCount: Int
    @State var currentPage: Int
    @State var status: BookStatus
    @State var rating: Int
    @State var coverName: String?
    @State var coverURL: String?
    @State var confirmingDelete = false
    #if !SKIP
    @State var photoItem: PhotosPickerItem?
    #endif
    @State var isLoadingPhoto = false
    @State var photoError: String?

    @State var query = ""
    @State var results: [BookSearchResult] = []
    @State var isSearching = false
    @State var searchMessage: String?
    @FocusState var searchFocused: Bool

    init(editing: Book? = nil) {
        self.editing = editing
        _title = State(initialValue: editing?.title ?? "")
        _author = State(initialValue: editing?.author ?? "")
        _genre = State(initialValue: editing?.genre ?? String(localized: "General"))
        _pageCount = State(initialValue: editing?.totalPages ?? 250)
        _currentPage = State(initialValue: editing?.currentPage ?? 0)
        _status = State(initialValue: editing?.status ?? .wantToRead)
        _rating = State(initialValue: editing?.rating ?? 0)
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
        book.rating = status == .finished && rating > 0 ? rating : nil
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
                            #if !SKIP
                            PhotosPicker(selection: $photoItem, matching: .images) {
                                Label(hasCover ? "Change Cover" : "Upload Cover", systemImage: "photo.on.rectangle")
                            }
                            #else
                            // TODO(android): launch Android's Photo Picker via
                            // ActivityResultContracts.PickVisualMedia (Skip Kotlin interop),
                            // then call CoverCache.saveUploadedCover(_:) with the bytes.
                            Button {
                                photoError = String(localized: "Photo upload isn't set up on Android yet.")
                            } label: {
                                Label(hasCover ? "Change Cover" : "Upload Cover", systemImage: "photo.on.rectangle")
                            }
                            #endif
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
                    #if !SKIP
                    .onChange(of: photoItem) { item in
                        guard let item else { return }
                        Task { await loadCover(from: item) }
                    }
                    #endif
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
                    if status == .finished {
                        StarRatingPicker(rating: $rating)
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

    #if !SKIP
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
    #endif

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
    @EnvironmentObject var store: ReadingStore

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                AdBanner()

                HStack(spacing: 12) {
                    StatTile(value: "\(store.currentWeekMinutes)", label: "minutes this week", systemImage: "clock.fill")
                    StatTile(value: "\(store.finishedBooks)", label: "books completed", systemImage: "checkmark.seal.fill")
                }

                ReadingCalendarCard()

                TrendsSection()
                    .id("trends")

                Text("All Time")
                    .font(.title2.bold())
                    .padding(.top, 8)

                InsightsCard()

                favouriteGenresCard
            }
            .padding(20)
        }
        .background(Color.readTimeBackground.ignoresSafeArea())
        .navigationTitle("Stats")
        .task {
            #if DEBUG
            if ScreenshotMode.screen == "trends" {
                try? await Task.sleep(nanoseconds: 400_000_000)
                proxy.scrollTo("trends", anchor: .top)
            }
            #endif
        }
        }
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
                #if !SKIP
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
                #else
                // TODO(android): Swift Charts doesn't transpile through Skip; this plain
                // bar list stands in for it. Swap for a Compose chart via Kotlin interop if
                // richer visuals are needed later.
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(favourites.shares) { share in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(share.genre) — \(share.percent)%")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            GeometryReader { proxy in
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.readTimePurple.opacity(0.78))
                                    .frame(width: proxy.size.width * CGFloat(share.percent) / 100)
                            }
                            .frame(height: 10)
                        }
                    }
                }
                #endif
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .readTimeCard()
    }
}

struct StarRatingPicker: View {
    @Binding var rating: Int

    var body: some View {
        HStack {
            Text("Rating")
            Spacer()
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        rating = rating == star ? 0 : star
                    } label: {
                        Image(systemName: star <= rating ? "star.fill" : "star")
                            .foregroundStyle(star <= rating ? Color.yellow : Color.secondary)
                            .font(.title3)
                    }
                    // Plain style so each star gets its own tap inside a Form row.
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("\(star) stars"))
                }
            }
        }
    }
}

/// A month grid where each day shows the cover of the book read most that day.
struct ReadingCalendarCard: View {
    @EnvironmentObject var store: ReadingStore
    @State var monthOffset = 0

    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar
    }

    private var month: Date {
        let start = calendar.dateInterval(of: .month, for: .now)?.start ?? .now
        return calendar.date(byAdding: .month, value: -monthOffset, to: start) ?? start
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }

    /// Nil entries pad the first week so day 1 lands under its weekday.
    private var days: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let leading = (calendar.component(.weekday, from: month) - calendar.firstWeekday + 7) % 7
        let dates = range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: month) }
        return Array(repeating: nil, count: leading) + dates
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .font(.headline)
                Spacer()
                Button { monthOffset += 1 } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Previous month")
                Button { monthOffset -= 1 } label: { Image(systemName: "chevron.right") }
                    .disabled(monthOffset == 0)
                    .accessibilityLabel("Next month")
                    .padding(.leading, 12)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.readTimePurple)

            let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)
            LazyVGrid(columns: columns, spacing: 5) {
                ForEach(weekdaySymbols.indices, id: \.self) { index in
                    Text(weekdaySymbols[index])
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                ForEach(days.indices, id: \.self) { index in
                    if let day = days[index] {
                        dayCell(day)
                    } else {
                        Color.clear.aspectRatio(2 / 3, contentMode: .fit)
                    }
                }
            }
        }
        .padding(16)
        .readTimeCard()
    }

    private func dayCell(_ day: Date) -> some View {
        let minutes = store.minutesRead(on: day)
        let top = minutes > 0 ? store.topActivity(on: day) : nil
        let isToday = calendar.isDateInToday(day)
        return RoundedRectangle(cornerRadius: 6)
            .fill(minutes > 0 ? Color.readTimePurple.opacity(0.35) : Color.secondary.opacity(0.08))
            .aspectRatio(2 / 3, contentMode: .fit)
            .overlay {
                if let top, top.coverName != nil || top.coverURL != nil {
                    CoverImage(coverName: top.coverName, coverURL: top.coverURL)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                }
            }
            .overlay(alignment: .topLeading) {
                Text(day.formatted(.dateTime.day()))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(top == nil ? Color.secondary : Color.white)
                    .shadow(color: top == nil ? .clear : .black.opacity(0.7), radius: 2)
                    .padding(3)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                if isToday {
                    RoundedRectangle(cornerRadius: 6).stroke(Color.readTimePurple, lineWidth: 2)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(day.formatted(date: .long, time: .omitted)), \(minutes) min"))
    }
}

enum TrendPeriod: String, CaseIterable, Identifiable {
    case week, month, year

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .week: "7 Days"
        case .month: "30 Days"
        case .year: "12 Months"
        }
    }

    /// `offset` 0 is the period ending today; 1 is the one before it, and so on.
    func interval(offset: Int, calendar: Calendar = .current) -> DateInterval {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now)) ?? .now
        switch self {
        case .week, .month:
            let length = self == .week ? 7 : 30
            let end = calendar.date(byAdding: .day, value: -length * offset, to: tomorrow) ?? tomorrow
            let start = calendar.date(byAdding: .day, value: -length, to: end) ?? end
            return DateInterval(start: start, end: end)
        case .year:
            let thisMonth = calendar.dateInterval(of: .month, for: .now)?.start ?? .now
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: thisMonth) ?? tomorrow
            let end = calendar.date(byAdding: .month, value: -12 * offset, to: nextMonth) ?? nextMonth
            let start = calendar.date(byAdding: .month, value: -12, to: end) ?? end
            return DateInterval(start: start, end: end)
        }
    }

    var bucketUnit: Calendar.Component { self == .year ? .month : .day }

    func buckets(in interval: DateInterval, calendar: Calendar = .current) -> [Date] {
        var dates: [Date] = []
        var date = interval.start
        while date < interval.end {
            dates.append(date)
            guard let next = calendar.date(byAdding: bucketUnit, value: 1, to: date) else { break }
            date = next
        }
        return dates
    }

    func rangeLabel(for interval: DateInterval) -> String {
        let last = interval.end.addingTimeInterval(-1)
        if self == .year {
            return "\(interval.start.formatted(.dateTime.month(.abbreviated).year())) – \(last.formatted(.dateTime.month(.abbreviated).year()))"
        }
        return "\(interval.start.formatted(.dateTime.day().month(.abbreviated))) – \(last.formatted(.dateTime.day().month(.abbreviated)))"
    }
}

/// Pages, time and finished books for a chosen period, compared with the period before it.
struct TrendsSection: View {
    @EnvironmentObject var store: ReadingStore
    @State var period = TrendPeriod.week
    @State var offset = 0

    var body: some View {
        let current = period.interval(offset: offset)
        let previous = period.interval(offset: offset + 1)
        let buckets = period.buckets(in: current)

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Trends")
                    .font(.title2.bold())
                Spacer()
                Menu {
                    Picker("Period", selection: $period) {
                        ForEach(TrendPeriod.allCases) { Text($0.title).tag($0) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(period.title)
                        Image(systemName: "chevron.down").font(.caption.weight(.bold))
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.readTimeCardBackground, in: Capsule())
                }
            }
            .onChange(of: period) { _ in offset = 0 }

            HStack {
                Text(period.rangeLabel(for: current))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button { offset += 1 } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Previous period")
                Button { offset -= 1 } label: { Image(systemName: "chevron.right") }
                    .disabled(offset == 0)
                    .accessibilityLabel("Next period")
                    .padding(.leading, 12)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.readTimePurple)

            TrendCard(
                title: "Pages read",
                systemImage: "doc.text.fill",
                color: .blue,
                current: pages(in: current),
                previous: pages(in: previous),
                format: { Text("\($0) pages") },
                series: buckets.map { ($0, pages(in: bucket($0))) },
                unit: period.bucketUnit
            )
            TrendCard(
                title: "Time read",
                systemImage: "clock.fill",
                color: .readTimePurple,
                current: minutes(in: current),
                previous: minutes(in: previous),
                format: { Text(Self.duration($0)) },
                series: buckets.map { ($0, minutes(in: bucket($0))) },
                unit: period.bucketUnit
            )
            TrendCard(
                title: "Books finished",
                systemImage: "checkmark.seal.fill",
                color: .readTimeGreen,
                current: store.booksFinished(in: current),
                previous: store.booksFinished(in: previous),
                format: { Text("\($0) books") },
                series: buckets.map { ($0, store.booksFinished(in: bucket($0))) },
                unit: period.bucketUnit
            )
        }
    }

    private func bucket(_ start: Date) -> DateInterval {
        let end = Calendar.current.date(byAdding: period.bucketUnit, value: 1, to: start) ?? start
        return DateInterval(start: start, end: end)
    }

    private func pages(in interval: DateInterval) -> Int {
        store.activities(in: interval).reduce(0) { $0 + ($1.pagesRead ?? 0) }
    }

    private func minutes(in interval: DateInterval) -> Int {
        store.activities(in: interval).reduce(0) { $0 + $1.minutes }
    }

    static func duration(_ minutes: Int) -> String {
        Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}

struct TrendCard: View {
    let title: LocalizedStringKey
    let systemImage: String
    let color: Color
    let current: Int
    let previous: Int
    let format: (Int) -> Text
    let series: [(date: Date, value: Int)]
    let unit: Calendar.Component
    @State var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.snappy) { expanded.toggle() }
            } label: {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(title, systemImage: systemImage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        format(current)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(color)
                        delta
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                        .padding(.top, 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                #if !SKIP
                Chart(series, id: \.date) { point in
                    BarMark(
                        x: .value("Date", point.date, unit: unit),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(color.gradient)
                    .cornerRadius(3)
                }
                .frame(height: 150)
                .transition(.opacity)
                #else
                // TODO(android): Swift Charts doesn't transpile through Skip; this plain
                // bar row stands in for it. Swap for a Compose chart via Kotlin interop if
                // richer visuals are needed later.
                let maxValue = max(series.map(\.value).max() ?? 0, 1)
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(series, id: \.date) { point in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(color.gradient)
                            .frame(height: max(2, 130 * CGFloat(point.value / maxValue)))
                    }
                }
                .frame(height: 150, alignment: .bottom)
                .transition(.opacity)
                #endif
            }
        }
        .padding(16)
        .readTimeCard()
    }

    @ViewBuilder private var delta: some View {
        let change = current - previous
        HStack(spacing: 4) {
            Image(systemName: change > 0 ? "arrow.up.right" : change < 0 ? "arrow.down.right" : "equal")
            format(abs(change))
            Text("vs. previous period")
                .foregroundStyle(.secondary)
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(change > 0 ? Color.readTimeGreen : change < 0 ? Color.red : Color.secondary)
    }
}

struct InsightsCard: View {
    @EnvironmentObject var store: ReadingStore

    var body: some View {
        VStack(spacing: 0) {
            row("Top genre", systemImage: "books.vertical.fill", color: .orange,
                value: store.favouriteGenres.shares.first.map { Text($0.genre) })
            Divider().padding(.leading, 52)
            row("Longest streak", systemImage: "flame.fill", color: .red,
                value: store.longestStreak > 0 ? Text("\(store.longestStreak) days") : nil)
            Divider().padding(.leading, 52)
            row("Average reading speed", systemImage: "gauge.with.dots.needle.50percent", color: .teal,
                value: store.pagesPerHour.map { Text("\($0) pages/hour") })
            Divider().padding(.leading, 52)
            row("Average rating", systemImage: "star.fill", color: .yellow,
                value: store.averageRating.map { Text("\($0.formatted(.number.precision(.fractionLength(1)))) stars") })
            Divider().padding(.leading, 52)
            row("Average book length", systemImage: "book.closed.fill", color: .gray,
                value: store.averageFinishedLength.map { Text("\($0) pages") })
        }
        .padding(.vertical, 4)
        .readTimeCard()
    }

    private func row(_ title: LocalizedStringKey, systemImage: String, color: Color, value: Text?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
                .frame(width: 28)
            Text(title)
            Spacer()
            (value ?? Text(verbatim: "—"))
                .fontWeight(.semibold)
                .foregroundStyle(value == nil ? Color.secondary : color)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 13)
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
    @EnvironmentObject var store: ReadingStore
    @Environment(\.dismiss) var dismiss
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
                            store.startSession(for: book.id)
                            onSelect(book)
                            dismiss()
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
    @EnvironmentObject var store: ReadingStore
    @Environment(\.dismiss) var dismiss
    let bookID: UUID
    @State var startedAt = Date()
    @State var showingFinish = false

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
            .onAppear {
                // Use the stored start time if resuming a session
                if let sessionStart = store.activeSessionStartedAt, store.activeSessionBookID == bookID {
                    startedAt = sessionStart
                } else {
                    startedAt = Date()
                }
            }
        }
    }

    private func timeString(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }
}

struct FinishSessionView: View {
    @EnvironmentObject var store: ReadingStore
    @Environment(\.dismiss) var dismiss
    let bookID: UUID
    let seconds: TimeInterval
    let onFinished: () -> Void
    @State var currentPage = 1
    @State var journal = ""
    @State var showingSummary = false

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
                            store.clearSession()
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
    @EnvironmentObject var store: ReadingStore
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

/// Stores a single backup of the reading data in iCloud key-value storage, which
/// syncs across the user's devices signed in to the same Apple ID (1 MB limit).
#if !SKIP
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
        try? JSONDecoder().decode(ReadingSnapshot.self, from: latestData()).savedAt
    }

    /// Takes/returns raw JSON `Data` rather than `ReadingSnapshot` directly —
    /// Skip's Android bridging couldn't handle `ReadingSnapshot` crossing this
    /// function boundary ("does not appear to be a bridged type"); callers
    /// encode/decode the snapshot themselves.
    static func backUp(_ data: Data) throws {
        guard isAvailable else { throw BackupError.iCloudUnavailable }
        NSUbiquitousKeyValueStore.default.set(data, forKey: backupKey)
        NSUbiquitousKeyValueStore.default.synchronize()
    }

    static func restore() throws -> Data {
        guard isAvailable else { throw BackupError.iCloudUnavailable }
        NSUbiquitousKeyValueStore.default.synchronize()
        return try latestData()
    }

    private static func latestData() throws -> Data {
        guard let data = NSUbiquitousKeyValueStore.default.data(forKey: backupKey) else {
            throw BackupError.noBackup
        }
        return data
    }
}
#else
/// Android has no iCloud KVS equivalent. This stand-in keeps the same API but only
/// backs up locally for now.
/// TODO(android): CloudKit Web Services can reach the CloudKit **private** database
/// (per-user, needed here — the public database used by `RoadmapStore`/`ReferralReport`
/// below isn't right for personal backups), but only via a Web Auth Token from a
/// "Sign in with Apple" flow, not the server-to-server key. That's a bigger feature
/// (OAuth-style sign-in screen + token exchange) — worth doing once the read-only
/// public-database calls below are confirmed working.
enum CloudBackup {
    static let syncEnabledKey = "iCloudSyncEnabled"
    private static let backupKey = "readtime.backup"

    enum BackupError: LocalizedError {
        case iCloudUnavailable
        case noBackup

        var errorDescription: String? {
            switch self {
            case .iCloudUnavailable: String(localized: "Cloud backup isn't set up yet on Android.")
            case .noBackup: String(localized: "No backup was found.")
            }
        }
    }

    static var isAvailable: Bool { true }

    static var lastBackupDate: Date? {
        try? JSONDecoder().decode(ReadingSnapshot.self, from: latestData()).savedAt
    }

    static func backUp(_ data: Data) throws {
        UserDefaults.standard.set(data, forKey: backupKey)
    }

    static func restore() throws -> Data {
        try latestData()
    }

    private static func latestData() throws -> Data {
        guard let data = UserDefaults.standard.data(forKey: backupKey) else {
            throw BackupError.noBackup
        }
        return data
    }
}
#endif

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
        #if !SKIP
        let style: UIUserInterfaceStyle = switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .forEach { $0.overrideUserInterfaceStyle = style }
        #endif
        // On Android, `.preferredColorScheme(appearance.colorScheme)` in
        // ReadTimeApp's body is enough on its own; there's no UIKit-style
        // window override to also update for sheets already on screen.
    }
}

#if !SKIP
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

    /// Length of the free trial, when the product is a subscription with one.
    var freeTrialDescription: String? {
        guard let offer = premiumProduct?.subscription?.introductoryOffer, offer.paymentMode == .freeTrial else { return nil }
        return Self.describe(offer.period)
    }

    func isEligibleForFreeTrial() async -> Bool {
        guard freeTrialDescription != nil, let subscription = premiumProduct?.subscription else { return false }
        return await subscription.isEligibleForIntroOffer
    }

    /// "29,000 ₫/year" for subscriptions, or the plain price for a one-time purchase.
    var priceDescription: String? {
        guard let product = premiumProduct else { return nil }
        guard let period = product.subscription?.subscriptionPeriod else { return product.displayPrice }
        return "\(product.displayPrice)/\(Self.describe(period, unitOnly: period.value == 1))"
    }

    private static func describe(_ period: Product.SubscriptionPeriod, unitOnly: Bool = false) -> String {
        let components: DateComponents
        switch period.unit {
        case .day: components = DateComponents(day: period.value)
        case .week: components = DateComponents(day: period.value * 7)
        case .month: components = DateComponents(month: period.value)
        case .year: components = DateComponents(year: period.value)
        @unknown default: components = DateComponents(day: period.value)
        }
        if unitOnly {
            switch period.unit {
            case .week: return String(localized: "week")
            case .month: return String(localized: "month")
            case .year: return String(localized: "year")
            default: return String(localized: "day")
            }
        }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 1
        return formatter.string(from: components) ?? ""
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
#else
/// TODO(android): wire this to Google Play Billing so it fulfills the same
/// product ID / entitlement contract as the iOS StoreKit version above.
/// `skip-revenue` (RevenueCat) would avoid hand-rolling the Play Billing
/// Kotlin API, but its manifest currently requires Swift tools-version 6.1,
/// which the toolchain resolving this package couldn't satisfy ("'skip-revenue'
/// contains incompatible tools version (6.1.0)") — re-add it once that's no
/// longer a blocker, or fall back to Play Billing directly via Skip's Kotlin
/// interop otherwise.
@MainActor
final class PurchaseManager: ObservableObject {
    static let premiumProductID = "com.fatties.readtime.premium"

    @Published private(set) var premiumProduct: String? = nil
    @Published private(set) var isPremium = false {
        didSet { AdManager.shared.isAdFree = isPremium }
    }
    @Published private(set) var isWorking = false
    @Published var message: String?

    func load() async {
        // TODO(android): query Play Billing for `premiumProductID` and current entitlements.
    }

    var freeTrialDescription: String? { nil }

    func isEligibleForFreeTrial() async -> Bool { false }

    var priceDescription: String? { nil }

    func refreshEntitlements() async {
        // TODO(android): re-query Play Billing's purchase history.
    }

    func buyPremium() async {
        message = String(localized: "Premium isn't available on Android yet.")
    }

    func restorePurchases() async {
        message = String(localized: "No previous purchases were found.")
    }
}
#endif

enum AppInfo {
#if DEBUG
    static let isDebugBuild = true
#else
    static let isDebugBuild = false
#endif
    // TODO: Replace with the real support address.
    static let supportEmail = "support@tunnaduong.com"
    // TODO: Set the numeric App Store ID once the app is live, for share links and "Write a Review".
    static let appStoreID: String? = nil
    /// Apple's standard licence agreement, which applies unless the app ships its own terms.
    static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    static var appStoreURL: URL? {
        appStoreID.flatMap { URL(string: "https://apps.apple.com/app/id\($0)") }
    }

    static var writeReviewURL: URL? {
        appStoreID.flatMap { URL(string: "https://apps.apple.com/app/id\($0)?action=write-review") }
    }

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
    @EnvironmentObject var store: ReadingStore
    @EnvironmentObject var purchases: PurchaseManager
    @Environment(\.dismiss) var dismiss
    @Environment(\.openURL) var openURL
    @AppStorage(AppearanceMode.storageKey) var appearance = AppearanceMode.system
    @AppStorage(CloudBackup.syncEnabledKey) var iCloudSyncEnabled = false
    @State var lastBackup = CloudBackup.lastBackupDate
    @State var confirmingRestore = false
    @State var backupMessage: String?
    @State var confirmingClearDemo = false
    @State var showingPaywall = false

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
                        #if !SKIP
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                        #else
                        // TODO(android): open the per-app language settings screen
                        // instead (Settings.ACTION_APP_LOCALE_SETTINGS on API 33+).
                        #endif
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

                Section {
                    #if !SKIP
                    NavigationLink {
                        AppIconPickerView()
                    } label: {
                        Label("App Icon", systemImage: "square.grid.2x2")
                    }
                    #endif
                    // No alternate app icon support on Android — there's no
                    // UIApplication.setAlternateIconName equivalent without a
                    // bigger activity-alias setup, so this entry is iOS-only.
                    NavigationLink {
                        ImportExportView()
                            .environmentObject(store)
                    } label: {
                        Label("Import & Export", systemImage: "arrow.up.arrow.down")
                    }
                }

                demoSection

                Section {
                    NavigationLink {
                        RoadmapView()
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Roadmap")
                                Text("Suggest, vote on, and discuss the features you'd like to see next!")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "map")
                        }
                    }
                }

                Section("Support") {
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("About", systemImage: "info.circle")
                    }
                    Button {
                        if let url = AppInfo.writeReviewURL {
                            openURL(url)
                        }
                        #if !SKIP
                        else if let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
                            SKStoreReviewController.requestReview(in: scene)
                        }
                        #endif
                        // TODO(android): fall back to the Play In-App Review API here.
                    } label: {
                        Label("Leave a Review", systemImage: "star")
                            .foregroundStyle(Color.readTimeText)
                    }
                    Button {
                        if let url = AppInfo.contactURL { openURL(url) }
                    } label: {
                        Label("Send Feedback", systemImage: "envelope")
                            .foregroundStyle(Color.readTimeText)
                    }
                }

                Section {
                    if let url = AppInfo.appStoreURL {
                        ShareLink(item: url, message: Text("I'm building a reading habit with ReadTime.")) {
                            Label("Share ReadTime", systemImage: "square.and.arrow.up")
                                .foregroundStyle(Color.readTimeText)
                        }
                    } else {
                        ShareLink(item: String(localized: "I'm building a reading habit with ReadTime.")) {
                            Label("Share ReadTime", systemImage: "square.and.arrow.up")
                                .foregroundStyle(Color.readTimeText)
                        }
                    }
                    Link(destination: AppInfo.termsURL) {
                        Label("Terms of Use", systemImage: "doc.text")
                            .foregroundStyle(Color.readTimeText)
                    }
                } footer: {
                    Text("App version: \(AppInfo.version)")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
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
                    run { store.restore(from: try JSONDecoder().decode(ReadingSnapshot.self, from: try CloudBackup.restore())) }
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
            // The paywall shows its own alert while it's open.
            .alert("Premium", isPresented: Binding(
                get: { purchases.message != nil && !showingPaywall },
                set: { if !$0 { purchases.message = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(purchases.message ?? "")
            }
            .fullScreenCover(isPresented: $showingPaywall) {
                PremiumPaywallView()
                    .environmentObject(purchases)
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
                    showingPaywall = true
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
                if enabled { run { try CloudBackup.backUp(JSONEncoder().encode(store.snapshot)) } }
            }
            Button {
                run { try CloudBackup.backUp(JSONEncoder().encode(store.snapshot)) }
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

#if !SKIP
/// Sends the onboarding answer to the CloudKit public database, once per device.
/// Only the chosen option and the app version are stored — nothing about the reader.
enum ReferralReport {
    private static let sentKey = "onboarding_referral_sent"

    static func send(source: String) async {
        guard !UserDefaults.standard.bool(forKey: sentKey) else { return }
        let record = CKRecord(recordType: "ReferralAnswer")
        record["source"] = source
        record["appVersion"] = AppInfo.version
        do {
            try await CKContainer(identifier: RoadmapStore.containerIdentifier).publicCloudDatabase.save(record)
            UserDefaults.standard.set(true, forKey: sentKey)
        } catch {
            // Not worth interrupting onboarding; the answer stays on the device.
        }
    }
}
#else
/// Writes to the same CloudKit public database as iOS, over CloudKit Web
/// Services (see `CloudKitWebService` above).
enum ReferralReport {
    private static let sentKey = "onboarding_referral_sent"

    static func send(source: String) async {
        guard !UserDefaults.standard.bool(forKey: sentKey) else { return }
        do {
            _ = try await CloudKitWebService.request(path: "records/modify", body: [
                "operations": [[
                    "operationType": "create",
                    "record": [
                        "recordType": "ReferralAnswer",
                        "fields": [
                            "source": ["value": source],
                            "appVersion": ["value": AppInfo.version],
                        ],
                    ],
                ]]
            ])
            UserDefaults.standard.set(true, forKey: sentKey)
        } catch {
            // Not worth interrupting onboarding; the answer stays on the device.
        }
    }
}
#endif

// MARK: - Premium paywall

struct PremiumPaywallView: View {
    @EnvironmentObject var purchases: PurchaseManager
    @Environment(\.dismiss) var dismiss
    @State var eligibleForTrial = false

    private struct Benefit: Identifiable {
        let title: LocalizedStringKey
        let detail: LocalizedStringKey
        let systemImage: String
        var id: String { systemImage }
    }

    private let benefits = [
        Benefit(title: "No Ads", detail: "Read without banners, full-screen ads, or ads when you open the app.", systemImage: "eye.slash.fill"),
        Benefit(title: "Support an Independent Developer", detail: "Your purchase keeps ReadTime growing and improving.", systemImage: "heart.fill"),
        Benefit(title: "Everything Else Stays Free", detail: "Goals, reading sessions, stats, journal, and iCloud backup are yours either way.", systemImage: "checkmark.seal.fill")
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Close")
                    .padding(.leading, -10)

                    Text("Why readers go Premium")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)

                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(benefits) { benefit in
                            HStack(alignment: .top, spacing: 16) {
                                Image(systemName: benefit.systemImage)
                                    .font(.title3)
                                    .foregroundStyle(.white)
                                    .frame(width: 48, height: 48)
                                    .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(benefit.title)
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                    Text(benefit.detail)
                                        .font(.subheadline)
                                        .foregroundStyle(.white.opacity(0.8))
                                }
                            }
                        }
                    }
                }
                .padding(24)
            }

            VStack(spacing: 10) {
                Button {
                    Task { await purchases.buyPremium() }
                } label: {
                    Group {
                        if purchases.isWorking {
                            ProgressView().tint(Color.readTimePurple)
                        } else if eligibleForTrial, let trial = purchases.freeTrialDescription {
                            Text("Try \(trial) Free")
                        } else {
                            Text("Get Premium")
                        }
                    }
                    .font(.headline)
                    .foregroundStyle(Color.readTimePurple)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(.white, in: Capsule())
                }
                .disabled(purchases.isWorking)

                if let price = purchases.priceDescription {
                    Group {
                        if eligibleForTrial {
                            Text("Then \(price). Cancel anytime.")
                        } else {
                            Text(price)
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.8))
                }

                Button("Restore Purchases") {
                    Task { await purchases.restorePurchases() }
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 8)
        }
        .background(
            LinearGradient(
                colors: [Color(red: 0.36, green: 0.22, blue: 0.72), Color(red: 0.62, green: 0.40, blue: 0.95)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .task {
            if purchases.premiumProduct == nil { await purchases.load() }
            eligibleForTrial = await purchases.isEligibleForFreeTrial()
        }
        .onChange(of: purchases.isPremium) { isPremium in
            if isPremium { dismiss() }
        }
        .alert("Premium", isPresented: Binding(get: { purchases.message != nil }, set: { if !$0 { purchases.message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(purchases.message ?? "")
        }
    }
}

// MARK: - Roadmap

/// A feature on the public roadmap, stored in the CloudKit public database.
///
/// CloudKit setup (container `iCloud.com.fatties.readtime`, CloudKit Console):
/// - `FeatureRequest`: title (String), details (String), status (String), listed (Int64, Queryable).
///   Only records with `listed = 1` appear, so set it after reviewing a suggestion.
/// - `Vote`: featureName (String, Queryable). One record per user and feature.
/// Deploy the schema to Production before release.
// Kept top-level rather than nested inside FeatureRequest (as `Status`):
// Skip's bridging couldn't resolve nested-type member references like
// `FeatureRequest.Status.inReview` ("unable to determine the owning type"),
// and separately couldn't bridge `[FeatureRequest]`/`FeatureRequest`
// themselves in RoadmapStore's Android branch below ("does not appear to
// be a bridged type") — unverified whether de-nesting alone resolves both.
enum FeatureRequestStatus: String, CaseIterable, Identifiable, Codable {
    case inReview, planned, inProgress, completed

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .inReview: "In Review"
        case .planned: "Planned"
        case .inProgress: "In Progress"
        case .completed: "Completed"
        }
    }

    var color: Color {
        switch self {
        case .inReview: .blue
        case .planned: .readTimePurple
        case .inProgress: .orange
        case .completed: .readTimeGreen
        }
    }
}

struct FeatureRequest: Identifiable, Hashable, Codable {
    let id: String
    var title: String
    var details: String
    var status: FeatureRequestStatus
    var votes: Int
    var hasVoted: Bool
}

#if !SKIP
@MainActor
final class RoadmapStore: ObservableObject {
    static let containerIdentifier = "iCloud.com.fatties.readtime"

    @Published private(set) var requests: [FeatureRequest] = []
    @Published private(set) var isLoading = false
    @Published private(set) var loadFailed = false
    /// False when there's no iCloud account on the device, which blocks the public database too.
    @Published private(set) var isSignedIn = true
    @Published var message: String?

    private let container = CKContainer(identifier: RoadmapStore.containerIdentifier)
    private var database: CKDatabase { container.publicCloudDatabase }
    private var userID: CKRecord.ID?

    func load() async {
        isLoading = true
        loadFailed = false
        defer { isLoading = false }
        isSignedIn = (try? await container.accountStatus()) == .available
        userID = try? await container.userRecordID()
        do {
            // Fetch everything and hide only what's explicitly unlisted, so a record created
            // without `listed` still shows up.
            let features = try await fetchAll(CKQuery(recordType: "FeatureRequest", predicate: NSPredicate(value: true)))
                .filter { ($0["listed"] as? Int64) != 0 }
            let names = features.map(\.recordID.recordName)
            let votes = names.isEmpty ? [] : try await fetchAll(CKQuery(recordType: "Vote", predicate: NSPredicate(format: "featureName IN %@", names)))

            var counts: [String: Int] = [:]
            var mine: Set<String> = []
            for vote in votes {
                guard let name = vote["featureName"] as? String else { continue }
                counts[name, default: 0] += 1
                if let userID, vote.creatorUserRecordID?.recordName == userID.recordName
                    || vote.creatorUserRecordID?.recordName == CKCurrentUserDefaultName {
                    mine.insert(name)
                }
            }

            requests = features.map { record in
                let name = record.recordID.recordName
                return FeatureRequest(
                    id: name,
                    title: record["title"] as? String ?? "",
                    details: record["details"] as? String ?? "",
                    status: FeatureRequestStatus(rawValue: record["status"] as? String ?? "") ?? .inReview,
                    votes: counts[name] ?? 0,
                    hasVoted: mine.contains(name)
                )
            }
            .sorted { $0.votes == $1.votes ? $0.title < $1.title : $0.votes > $1.votes }
        } catch let error as CKError where error.code == .unknownItem {
            // The record types don't exist until the first record is saved.
            requests = []
        } catch {
            loadFailed = true
        }
    }

    func toggleVote(for request: FeatureRequest) async {
        guard let userID else {
            message = String(localized: "Sign in to iCloud in the Settings app to vote.")
            return
        }
        guard let index = requests.firstIndex(where: { $0.id == request.id }) else { return }
        let recordID = CKRecord.ID(recordName: "vote-\(request.id)-\(userID.recordName)")
        let wasVoted = requests[index].hasVoted
        requests[index].hasVoted.toggle()
        requests[index].votes += wasVoted ? -1 : 1

        do {
            if wasVoted {
                try await database.deleteRecord(withID: recordID)
            } else {
                let vote = CKRecord(recordType: "Vote", recordID: recordID)
                vote["featureName"] = request.id
                try await database.save(vote)
            }
        } catch let error as CKError where error.code == .serverRecordChanged || error.code == .unknownItem {
            // Already voted (or already removed) on another device; the local state is now correct.
        } catch {
            if let index = requests.firstIndex(where: { $0.id == request.id }) {
                requests[index].hasVoted = wasVoted
                requests[index].votes += wasVoted ? 1 : -1
            }
            message = error.localizedDescription
        }
    }

    func suggest(title: String, details: String) async -> Bool {
        guard userID != nil else {
            message = String(localized: "Sign in to iCloud in the Settings app to suggest a feature.")
            return false
        }
        let record = CKRecord(recordType: "FeatureRequest")
        record["title"] = title
        record["details"] = details
        record["status"] = FeatureRequestStatus.inReview.rawValue
        record["listed"] = 0 as Int64
        do {
            try await database.save(record)
            message = String(localized: "Thanks! Your suggestion will appear on the roadmap once it's been reviewed.")
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    private func fetchAll(_ query: CKQuery) async throws -> [CKRecord] {
        var records: [CKRecord] = []
        var (results, cursor) = try await database.records(matching: query)
        records += results.compactMap { try? $0.1.get() }
        while let next = cursor {
            (results, cursor) = try await database.records(continuingMatchFrom: next)
            records += results.compactMap { try? $0.1.get() }
        }
        return records
    }
}
#else
/// Reads/writes the same CloudKit public database as iOS, over CloudKit Web
/// Services (see `CloudKitWebService` above). `CloudKitWebService.installID`
/// stands in for the signed-in Apple ID iOS uses to key each `Vote` record.
@MainActor
final class RoadmapStore: ObservableObject {
    static let containerIdentifier = "iCloud.com.fatties.readtime"

    // Not private(set): unlike the private(set) Bool/String properties below,
    // Skip's bridging couldn't handle `[FeatureRequest]` with a private
    // setter ("does not appear to be a bridged type") -- `@Published var books:
    // [Book]` elsewhere in this file (no private(set)) bridges fine, so trying
    // this next. Unverified.
    @Published var requests: [FeatureRequest] = []
    @Published private(set) var isLoading = false
    @Published private(set) var loadFailed = false
    /// Always true on Android: there's no per-device Apple ID sign-in gate here,
    /// only the app-wide server-to-server key.
    @Published private(set) var isSignedIn = true
    @Published var message: String?

    func load() async {
        isLoading = true
        loadFailed = false
        defer { isLoading = false }
        do {
            let featureResult = try await CloudKitWebService.request(path: "records/query", body: [
                "query": ["recordType": "FeatureRequest"]
            ])
            let featureRecords = (featureResult["records"] as? [[String: Any]]) ?? []
            let listed = featureRecords.filter { record in
                let fields = record["fields"] as? [String: Any]
                let listedValue = (fields?["listed"] as? [String: Any])?["value"] as? Int ?? 1
                return listedValue != 0
            }
            let names = listed.compactMap { $0["recordName"] as? String }

            var votesByFeature: [String: Int] = [:]
            var myVotes: Set<String> = []
            if !names.isEmpty {
                let voteResult = try await CloudKitWebService.request(path: "records/query", body: [
                    "query": [
                        "recordType": "Vote",
                        "filterBy": [[
                            "fieldName": "featureName",
                            "comparator": "IN",
                            "fieldValue": ["value": names, "type": "STRING_LIST"],
                        ]],
                    ]
                ])
                let voteRecords = (voteResult["records"] as? [[String: Any]]) ?? []
                for vote in voteRecords {
                    guard let fields = vote["fields"] as? [String: Any],
                          let name = (fields["featureName"] as? [String: Any])?["value"] as? String
                    else { continue }
                    votesByFeature[name, default: 0] += 1
                    if let recordName = vote["recordName"] as? String,
                       recordName == "vote-\(name)-\(CloudKitWebService.installID)" {
                        myVotes.insert(name)
                    }
                }
            }

            requests = listed.compactMap { record -> FeatureRequest? in
                guard let name = record["recordName"] as? String,
                      let fields = record["fields"] as? [String: Any] else { return nil }
                return FeatureRequest(
                    id: name,
                    title: (fields["title"] as? [String: Any])?["value"] as? String ?? "",
                    details: (fields["details"] as? [String: Any])?["value"] as? String ?? "",
                    status: FeatureRequestStatus(rawValue: (fields["status"] as? [String: Any])?["value"] as? String ?? "") ?? .inReview,
                    votes: votesByFeature[name] ?? 0,
                    hasVoted: myVotes.contains(name)
                )
            }
            .sorted { $0.votes == $1.votes ? $0.title < $1.title : $0.votes > $1.votes }
        } catch {
            loadFailed = true
        }
    }

    func toggleVote(for request: FeatureRequest) async {
        guard let index = requests.firstIndex(where: { $0.id == request.id }) else { return }
        let recordName = "vote-\(request.id)-\(CloudKitWebService.installID)"
        let wasVoted = requests[index].hasVoted
        requests[index].hasVoted.toggle()
        requests[index].votes += wasVoted ? -1 : 1

        do {
            if wasVoted {
                _ = try await CloudKitWebService.request(path: "records/modify", body: [
                    "operations": [[
                        "operationType": "forceDelete",
                        "record": ["recordName": recordName],
                    ]]
                ])
            } else {
                _ = try await CloudKitWebService.request(path: "records/modify", body: [
                    "operations": [[
                        "operationType": "create",
                        "record": [
                            "recordName": recordName,
                            "recordType": "Vote",
                            "fields": ["featureName": ["value": request.id]],
                        ],
                    ]]
                ])
            }
        } catch {
            if let index = requests.firstIndex(where: { $0.id == request.id }) {
                requests[index].hasVoted = wasVoted
                requests[index].votes += wasVoted ? 1 : -1
            }
            message = error.localizedDescription
        }
    }

    func suggest(title: String, details: String) async -> Bool {
        do {
            _ = try await CloudKitWebService.request(path: "records/modify", body: [
                "operations": [[
                    "operationType": "create",
                    "record": [
                        "recordType": "FeatureRequest",
                        "fields": [
                            "title": ["value": title],
                            "details": ["value": details],
                            "status": ["value": FeatureRequestStatus.inReview.rawValue],
                            "listed": ["value": 0],
                        ],
                    ],
                ]]
            ])
            message = String(localized: "Thanks! Your suggestion will appear on the roadmap once it's been reviewed.")
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }
}
#endif

struct RoadmapView: View {
    @StateObject var roadmap = RoadmapStore()
    @State var filter: FeatureRequestStatus?
    @State var suggesting = false

    private var visible: [FeatureRequest] {
        guard let filter else { return roadmap.requests }
        return roadmap.requests.filter { $0.status == filter }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Menu {
                    Picker("Filter", selection: $filter) {
                        Text("All (\(roadmap.requests.count))").tag(FeatureRequestStatus?.none)
                        ForEach(FeatureRequestStatus.allCases) { status in
                            Text("\(Text(status.title)) (\(roadmap.requests.filter { $0.status == status }.count))")
                                .tag(Optional(status))
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        if let filter {
                            Text("\(Text(filter.title)) (\(visible.count))")
                        } else {
                            Text("All (\(roadmap.requests.count))")
                        }
                        Image(systemName: "chevron.up.chevron.down").font(.caption.weight(.semibold))
                    }
                    .font(.headline)
                    .foregroundStyle(Color.readTimeText)
                }
                .padding(.bottom, 4)

                if roadmap.isLoading && roadmap.requests.isEmpty {
                    ProgressView().padding(.top, 40)
                } else if roadmap.loadFailed && roadmap.requests.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "icloud.slash")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary)
                        Text(roadmap.isSignedIn ? "Couldn't load the roadmap" : "Sign in to iCloud")
                            .font(.headline)
                        Text(roadmap.isSignedIn
                             ? "Check your internet connection, then pull to refresh."
                             : "The roadmap is shared through iCloud. Sign in to iCloud in the Settings app to see and vote on features.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Try Again") { Task { await roadmap.load() } }
                            .tint(.readTimePurple)
                            .padding(.top, 4)
                    }
                    .padding(.top, 40)
                } else if visible.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "map")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary)
                        Text("No features here yet")
                            .font(.headline)
                        Text("Tap + to suggest something you'd like to see in ReadTime.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 40)
                } else {
                    ForEach(visible) { request in
                        NavigationLink {
                            FeatureRequestDetailView(request: request, roadmap: roadmap)
                        } label: {
                            FeatureRequestRow(request: request) {
                                Task { await roadmap.toggleVote(for: request) }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(20)
            .padding(.bottom, 70)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.readTimeBackground.ignoresSafeArea(edges: .all))
        .navigationTitle("Roadmap")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await roadmap.load() }
        .task { await roadmap.load() }
        .overlay(alignment: .bottomTrailing) {
            Button {
                suggesting = true
            } label: {
                Image(systemName: "plus")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 60, height: 60)
                    .background(Color.readTimePurple, in: Circle())
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
            }
            .accessibilityLabel("Suggest a Feature")
            .padding(20)
        }
        .sheet(isPresented: $suggesting) {
            SuggestFeatureView(roadmap: roadmap)
        }
        .alert("Roadmap", isPresented: Binding(get: { roadmap.message != nil }, set: { if !$0 { roadmap.message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(roadmap.message ?? "")
        }
    }
}

struct FeatureRequestRow: View {
    let request: FeatureRequest
    let onVote: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VoteButton(votes: request.votes, hasVoted: request.hasVoted, action: onVote)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(request.title)
                        .font(.headline)
                        .foregroundStyle(Color.readTimeText)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    StatusBadge(status: request.status)
                }
                if !request.details.isEmpty {
                    Text(request.details)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .readTimeCard()
    }
}

struct VoteButton: View {
    let votes: Int
    let hasVoted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: hasVoted ? "arrowtriangle.up.fill" : "arrowtriangle.up")
                    .font(.subheadline)
                Text("\(votes)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(hasVoted ? Color.readTimePurple : Color.secondary)
            .frame(width: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(hasVoted ? Text("Remove vote, \(votes) votes") : Text("Vote, \(votes) votes"))
    }
}

struct StatusBadge: View {
    let status: FeatureRequestStatus

    var body: some View {
        Text(status.title)
            .textCase(.uppercase)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(status.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(status.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
            .fixedSize(horizontal: true, vertical: false)
    }
}

struct FeatureRequestDetailView: View {
    let request: FeatureRequest
    @ObservedObject var roadmap: RoadmapStore

    private var current: FeatureRequest {
        roadmap.requests.first { $0.id == request.id } ?? request
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                StatusBadge(status: current.status)
                Text(current.title)
                    .font(.title2.bold())
                if !current.details.isEmpty {
                    Text(current.details)
                        .foregroundStyle(Color.readTimeText)
                }
                Button {
                    Task { await roadmap.toggleVote(for: current) }
                } label: {
                    Label(current.hasVoted ? "Voted · \(current.votes)" : "Vote · \(current.votes)",
                          systemImage: current.hasVoted ? "arrowtriangle.up.fill" : "arrowtriangle.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(current.hasVoted ? .secondary : .readTimePurple)
                .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .background(Color.readTimeBackground.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SuggestFeatureView: View {
    @ObservedObject var roadmap: RoadmapStore
    @Environment(\.dismiss) var dismiss
    @State var title = ""
    @State var details = ""
    @State var isSending = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Feature name", text: $title)
                    TextField("What should it do, and why would it help you?", text: $details, axis: .vertical)
                        .lineLimit(4...10)
                } footer: {
                    Text("Suggestions are reviewed before they appear on the roadmap for everyone to vote on.")
                }
            }
            .navigationTitle("Suggest a Feature")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSending {
                        ProgressView()
                    } else {
                        Button("Send") {
                            isSending = true
                            Task {
                                let sent = await roadmap.suggest(
                                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                    details: details.trimmingCharacters(in: .whitespacesAndNewlines)
                                )
                                isSending = false
                                if sent { dismiss() }
                            }
                        }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }
}

// MARK: - App icon

#if !SKIP
enum AlternateIcon: String, CaseIterable, Identifiable {
    case standard = "Default", midnight = "Midnight", paper = "Paper", sunset = "Sunset", forest = "Forest", ocean = "Ocean"

    var id: String { rawValue }

    /// Nil selects the primary icon.
    var iconName: String? { self == .standard ? nil : "AppIcon-\(rawValue)" }

    var title: LocalizedStringKey {
        switch self {
        case .standard: "Default"
        case .midnight: "Midnight"
        case .paper: "Paper"
        case .sunset: "Sunset"
        case .forest: "Forest"
        case .ocean: "Ocean"
        }
    }

    static var current: AlternateIcon {
        let name = UIApplication.shared.alternateIconName
        return allCases.first { $0.iconName == name } ?? .standard
    }
}

struct AppIconPickerView: View {
    @State var selection = AlternateIcon.current
    @State var errorMessage: String?

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 18)], spacing: 22) {
                ForEach(AlternateIcon.allCases) { icon in
                    Button {
                        choose(icon)
                    } label: {
                        VStack(spacing: 8) {
                            Image("AppIconPreview-\(icon.rawValue)")
                                .resizable()
                                .frame(width: 76, height: 76)
                                .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                                )
                                .padding(4)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 21, style: .continuous)
                                        .stroke(selection == icon ? Color.readTimePurple : .clear, lineWidth: 3)
                                )
                            Text(icon.title)
                                .font(.subheadline.weight(selection == icon ? .semibold : .regular))
                                .foregroundStyle(selection == icon ? Color.readTimePurple : Color.readTimeText)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == icon ? .isSelected : [])
                }
            }
            .padding(24)
        }
        .background(Color.readTimeBackground.ignoresSafeArea())
        .navigationTitle("App Icon")
        .navigationBarTitleDisplayMode(.inline)
        .alert("App Icon", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func choose(_ icon: AlternateIcon) {
        guard icon != selection, UIApplication.shared.supportsAlternateIcons else { return }
        let previous = selection
        selection = icon
        Task {
            do {
                try await setIcon(icon, retries: 2)
            } catch {
                selection = previous
                errorMessage = error.localizedDescription
            }
        }
    }

    /// iOS sometimes answers EAGAIN ("Resource temporarily unavailable") while it's still busy,
    /// occasionally even after the icon did change, so check the icon in use and try again.
    private func setIcon(_ icon: AlternateIcon, retries: Int) async throws {
        do {
            try await UIApplication.shared.setAlternateIconName(icon.iconName)
        } catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == Int(EAGAIN) {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if UIApplication.shared.alternateIconName == icon.iconName { return }
            guard retries > 0 else { throw error }
            try await setIcon(icon, retries: retries - 1)
        }
    }
}
#endif

// MARK: - Import & export

enum LibraryTransfer {
    enum TransferError: LocalizedError {
        case noBooksFound

        var errorDescription: String? {
            String(localized: "No books were found in this file. Export your library as CSV from Goodreads or StoryGraph and try again.")
        }
    }

    private static func temporaryFile(named name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(name)
    }

    private static var dateStamp: String {
        Date.now.formatted(.iso8601.year().month().day())
    }

    @MainActor
    static func backupFile(for store: ReadingStore) throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let url = temporaryFile(named: "ReadTime Backup \(dateStamp).json")
        try encoder.encode(store.snapshot).write(to: url, options: .atomic)
        return url
    }

    @MainActor
    static func booksCSVFile(for store: ReadingStore) throws -> URL {
        var rows = [["Title", "Author", "Genre", "Pages", "Current Page", "Status", "Rating", "Date Finished"]]
        for book in store.books {
            rows.append([
                book.title, book.author, book.genre, String(book.totalPages), String(book.currentPage),
                book.status.rawValue, book.rating.map(String.init) ?? "",
                book.finishedAt.map { $0.formatted(.iso8601.year().month().day()) } ?? ""
            ])
        }
        let csv = rows.map { $0.map(escape).joined(separator: ",") }.joined(separator: "\n")
        let url = temporaryFile(named: "ReadTime Books \(dateStamp).csv")
        try csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Reads files picked with `fileImporter`, which live outside the app's sandbox.
    private static func contents(of url: URL) throws -> Data {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        return try Data(contentsOf: url)
    }

    static func readBackup(from url: URL) throws -> ReadingSnapshot {
        try JSONDecoder().decode(ReadingSnapshot.self, from: contents(of: url))
    }

    /// Understands Goodreads and StoryGraph exports, and ReadTime's own CSV.
    static func books(fromCSV url: URL) throws -> [Book] {
        let text = String(decoding: try contents(of: url), as: UTF8.self)
        let rows = parseCSV(text)
        guard let header = rows.first else { throw TransferError.noBooksFound }
        let columns = header.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        func column(_ names: String...) -> Int? { names.lazy.compactMap { columns.firstIndex(of: $0) }.first }

        guard let titleColumn = column("title") else { throw TransferError.noBooksFound }
        let authorColumn = column("author", "authors", "author l-f")
        let pagesColumn = column("number of pages", "pages", "page count")
        let currentPageColumn = column("current page")
        let statusColumn = column("exclusive shelf", "read status", "status")
        let ratingColumn = column("my rating", "star rating", "rating")
        let dateColumn = column("date read", "last date read", "date finished")
        let genreColumn = column("genre", "genres")

        let dateFormats = ["yyyy/MM/dd", "yyyy-MM-dd", "MM/dd/yyyy"]
        func parseDate(_ value: String) -> Date? {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            for format in dateFormats {
                formatter.dateFormat = format
                if let date = formatter.date(from: value) { return date }
            }
            return nil
        }

        let books: [Book] = rows.dropFirst().compactMap { row in
            func value(_ index: Int?) -> String {
                guard let index, index < row.count else { return "" }
                return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let title = value(titleColumn)
            guard !title.isEmpty else { return nil }

            let pages = Int(value(pagesColumn)) ?? 0
            let totalPages = pages > 0 ? pages : 250
            let status: BookStatus
            switch value(statusColumn).lowercased() {
            case "read", "finished": status = .finished
            case "currently-reading", "reading": status = .reading
            default: status = .wantToRead
            }
            let rating = Double(value(ratingColumn)).map { Int($0.rounded()) }.flatMap { (1...5).contains($0) ? $0 : nil }
            let genre = value(genreColumn).components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? ""
            let author = value(authorColumn).components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? ""

            return Book(
                id: UUID(),
                title: title,
                author: author.isEmpty ? String(localized: "Unknown Author") : author,
                genre: genre.isEmpty ? String(localized: "General") : genre,
                totalPages: totalPages,
                currentPage: status == .finished ? totalPages : min(Int(value(currentPageColumn)) ?? 0, totalPages),
                status: status,
                finishedAt: status == .finished ? (parseDate(value(dateColumn)) ?? .now) : nil,
                rating: status == .finished ? rating : nil
            )
        }
        guard !books.isEmpty else { throw TransferError.noBooksFound }
        return books
    }

    private static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// RFC 4180: quoted fields may contain commas, doubled quotes, and line breaks.
    static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = text.makeIterator()
        var pending: Character?

        while let char = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                if char == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" { field.append("\"") } else { inQuotes = false; pending = next }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(char)
                }
            } else {
                switch char {
                case "\"": inQuotes = true
                case ",": row.append(field); field = ""
                case "\n", "\r\n", "\r":
                    row.append(field); field = ""
                    if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
                    row = []
                default: field.append(char)
                }
            }
        }
        row.append(field)
        if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
        // Byte-order mark some spreadsheet apps add to the first header.
        if let first = rows.first?.first, first.hasPrefix("\u{FEFF}") {
            rows[0][0] = String(first.dropFirst())
        }
        return rows
    }
}

struct ImportExportView: View {
    private enum Picking { case csv, backup }

    @EnvironmentObject var store: ReadingStore
    @State var backupURL: URL?
    @State var csvURL: URL?
    @State var picking: Picking?
    @State var pendingBackup: ReadingSnapshot?
    @State var message: String?

    var body: some View {
        Form {
            Section {
                if let backupURL {
                    ShareLink(item: backupURL) {
                        Label("Export Backup (JSON)", systemImage: "externaldrive.badge.checkmark")
                    }
                }
                if let csvURL {
                    ShareLink(item: csvURL) {
                        Label("Export Books (CSV)", systemImage: "tablecells")
                    }
                }
            } header: {
                Text("Export")
            } footer: {
                Text("A backup has everything: books, sessions, journal, and goals. The CSV lists your books for spreadsheets and other reading apps.")
            }

            Section {
                Button {
                    picking = .csv
                } label: {
                    Label("Import from Goodreads or StoryGraph", systemImage: "square.and.arrow.down")
                }
                Button {
                    picking = .backup
                } label: {
                    Label("Restore from Backup File", systemImage: "clock.arrow.circlepath")
                }
            } header: {
                Text("Import")
            } footer: {
                Text("In Goodreads, go to My Books → Import and export → Export Library. In StoryGraph, go to Manage Account → Export StoryGraph Library. Books already in your library are skipped.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.readTimeBackground.ignoresSafeArea())
        .navigationTitle("Import & Export")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            backupURL = try? LibraryTransfer.backupFile(for: store)
            csvURL = try? LibraryTransfer.booksCSVFile(for: store)
        }
        .fileImporter(
            isPresented: Binding(get: { picking != nil }, set: { if !$0 { picking = nil } }),
            allowedContentTypes: picking == .backup ? [.json] : [.commaSeparatedText, .plainText]
        ) { result in
            let kind = picking
            picking = nil
            switch result {
            case .success(let url):
                handlePicked(url, kind: kind)
            case .failure(let error):
                message = error.localizedDescription
            }
        }
        .confirmationDialog("Restore this backup?", isPresented: Binding(get: { pendingBackup != nil }, set: { if !$0 { pendingBackup = nil } }), titleVisibility: .visible) {
            Button("Replace Data on This iPhone", role: .destructive) {
                if let pendingBackup {
                    store.restore(from: pendingBackup)
                    message = String(localized: "Your reading data was restored.")
                }
                pendingBackup = nil
            }
        } message: {
            Text("Your books, goals, and journal on this device will be replaced with the backup.")
        }
        .alert("Import & Export", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    private func handlePicked(_ url: URL, kind: Picking?) {
        do {
            if kind == .backup {
                pendingBackup = try LibraryTransfer.readBackup(from: url)
            } else {
                let books = try LibraryTransfer.books(fromCSV: url)
                let added = store.importBooks(books)
                message = String(localized: "Imported \(added) books. \(books.count - added) were already in your library.")
            }
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? String(localized: "This file couldn't be read.")
        }
    }
}

struct AboutView: View {
    @Environment(\.openURL) var openURL

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
                    #if !SKIP
                    if let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
                        SKStoreReviewController.requestReview(in: scene)
                    }
                    #endif
                    // TODO(android): fall back to the Play In-App Review API here.
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
    private enum Step { case welcome, source, goal, importBooks, firstBook }

    @EnvironmentObject var store: ReadingStore
    @State var step = Step.welcome

    var body: some View {
        Group {
            switch step {
            case .welcome:
                OnboardingWelcomeStep(
                    onDemo: { store.finishOnboarding(withDemoContent: true) },
                    onStartFresh: { withAnimation { step = .source } }
                )
            case .source:
                OnboardingSourceStep(
                    onBack: { withAnimation { step = .welcome } },
                    onContinue: { withAnimation { step = .goal } }
                )
            case .goal:
                OnboardingGoalStep(
                    onBack: { withAnimation { step = .source } },
                    onContinue: { withAnimation { step = .importBooks } }
                )
            case .importBooks:
                OnboardingImportStep(
                    onBack: { withAnimation { step = .goal } },
                    onContinue: { withAnimation { step = .firstBook } }
                )
            case .firstBook:
                OnboardingFirstBookStep(
                    onBack: { withAnimation { step = .importBooks } },
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

struct OnboardingWelcomeStep: View {
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
struct OnboardingStepLayout<Content: View, Actions: View>: View {
    let progress: Int
    var total = 4
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
                    ForEach(1...total, id: \.self) { index in
                        Capsule()
                            .fill(index <= progress ? Color.readTimePurple : Color.secondary.opacity(0.25))
                            .frame(width: index == progress ? 24 : 8, height: 8)
                    }
                }
                .accessibilityElement()
                .accessibilityLabel(Text("Step \(progress) of \(total)"))
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

struct OnboardingSourceStep: View {
    enum Source: String, CaseIterable, Identifiable {
        case appStore, search, social, video, friends, other

        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .appStore: "App Store"
            case .search: "Google Search"
            case .social: "Facebook/Instagram/Threads"
            case .video: "TikTok/YouTube"
            case .friends: "Friends/family"
            case .other: "Other"
            }
        }

        var systemImage: String {
            switch self {
            case .appStore: "bag.fill"
            case .search: "magnifyingglass"
            case .social: "bubble.left.and.bubble.right.fill"
            case .video: "play.rectangle.fill"
            case .friends: "person.2.fill"
            case .other: "ellipsis"
            }
        }
    }

    @AppStorage("onboarding_referral_source") var storedSource = ""
    @State var selection: Source?
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        OnboardingStepLayout(
            progress: 1,
            title: "Where did you hear about ReadTime?",
            subtitle: "It helps us know how readers find the app. Your answer is sent anonymously.",
            onBack: onBack
        ) {
            VStack(spacing: 12) {
                ForEach(Source.allCases) { source in
                    Button {
                        selection = source
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: source.systemImage)
                                .font(.title3)
                                .foregroundStyle(Color.readTimePurple)
                                .frame(width: 32)
                            Text(source.title)
                                .font(.headline)
                                .foregroundStyle(Color.readTimeText)
                            Spacer()
                            Image(systemName: selection == source ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(selection == source ? Color.readTimePurple : Color.secondary.opacity(0.5))
                        }
                        .padding(16)
                        .readTimeCard()
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(selection == source ? Color.readTimePurple : .clear, lineWidth: 2)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == source ? .isSelected : [])
                }
            }
        } actions: {
            Button {
                if let selection {
                    storedSource = selection.rawValue
                    Task { await ReferralReport.send(source: selection.rawValue) }
                }
                onContinue()
            } label: {
                Text("Continue").font(.headline).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selection == nil)

            Button("Skip", action: onContinue)
                .font(.subheadline)
        }
        .onAppear { selection = Source(rawValue: storedSource) }
    }
}

struct OnboardingImportStep: View {
    @EnvironmentObject var store: ReadingStore
    let onBack: () -> Void
    let onContinue: () -> Void
    @State var picking = false
    @State var importedCount: Int?
    @State var errorMessage: String?

    var body: some View {
        OnboardingStepLayout(
            progress: 3,
            title: "Bringing some books with you?",
            subtitle: "Import your library from another reading app. You can also do this later in Settings.",
            onBack: onBack
        ) {
            VStack(alignment: .leading, spacing: 12) {
                importCard(title: "Import from Goodreads", systemImage: "g.circle.fill",
                           hint: "My Books → Import and export → Export Library")
                importCard(title: "Import from StoryGraph", systemImage: "chart.bar.xaxis",
                           hint: "Manage Account → Export StoryGraph Library")

                if let importedCount {
                    Label("Imported \(importedCount) books", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.readTimeGreen)
                        .padding(.top, 4)
                }
            }
        } actions: {
            Button(action: onContinue) {
                Text(importedCount == nil ? "Skip" : "Continue").font(.headline).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
            do {
                let books = try LibraryTransfer.books(fromCSV: result.get())
                importedCount = (importedCount ?? 0) + store.importBooks(books)
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
        .alert("Import", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func importCard(title: LocalizedStringKey, systemImage: String, hint: LocalizedStringKey) -> some View {
        Button {
            picking = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(Color.readTimePurple)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Color.readTimeText)
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "square.and.arrow.down")
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .readTimeCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct OnboardingGoalStep: View {
    private enum Choice { case minutesPerDay, booksPerYear }

    @EnvironmentObject var store: ReadingStore
    let onBack: () -> Void
    let onContinue: () -> Void

    @State var choice = Choice.minutesPerDay
    @State var minutes = 20
    @State var books = 12

    var body: some View {
        OnboardingStepLayout(
            progress: 2,
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

struct GoalChoiceCard<Accessory: View>: View {
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

struct OnboardingFirstBookStep: View {
    @EnvironmentObject var store: ReadingStore
    let onBack: () -> Void
    let onFinish: () -> Void
    @State var addingBook = false

    var body: some View {
        OnboardingStepLayout(
            progress: 4,
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

#if !SKIP
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
        #if DEBUG
        // Used when capturing App Store screenshots: `simctl launch … -disableAds YES`.
        if UserDefaults.standard.bool(forKey: "disableAds") {
            isAdFree = true
            return
        }
        #endif
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
#else
/// TODO(android): wire this to the AdMob Android SDK + Google UMP Android SDK
/// (both are separate native libraries from the iOS ones, but a near-identical
/// API) via Skip's Kotlin interop. There's no Android equivalent of
/// AppTrackingTransparency — consent is handled by UMP alone.
@MainActor
final class AdManager: NSObject, ObservableObject {
    static let shared = AdManager()

    @Published var isAdFree = false
    @Published private(set) var sdkStarted = false

    var bannerUnitID: String? { nil }

    func start() {
        // TODO(android): request UMP consent, then start the AdMob Android SDK.
    }

    func showAppOpenAdIfAvailable() {}

    func showInterstitial(then completion: @escaping () -> Void) {
        completion()
    }
}
#endif

#if !SKIP
/// An adaptive AdMob banner that takes no space until an ad has loaded, and none at all for Premium users.
struct AdBanner: View {
    @ObservedObject private var ads = AdManager.shared
    @State var width: CGFloat = 0
    @State var loadedHeight: CGFloat = 0

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
#else
/// TODO(android): render a Compose `AdView` from the AdMob Android SDK here via
/// Skip's Kotlin interop, matching the adaptive-banner behavior above. Until then
/// `AdManager.bannerUnitID` returns nil, so this renders nothing.
struct AdBanner: View {
    var body: some View {
        EmptyView()
    }
}
#endif

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
#if !SKIP
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
#else
/// TODO(android): Compose dismisses the keyboard differently (e.g. LocalFocusManager
/// / `.scrollDismissesKeyboard`, already used elsewhere in this app); tap-outside-to-dismiss
/// across the whole app isn't wired up here yet.
enum KeyboardDismissal {
    static func dismiss() {}
    static func install() {}
}
#endif

// MARK: - Reusable views

/// The app icon artwork, also used for the home screen icon in Assets.xcassets.
struct AppIconView: View {
    let size: CGFloat

    var body: some View {
        // The real icon artwork, so this always matches what's on the Home Screen.
        Image("AppIconPreview-Default")
            .resizable()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
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

extension View {
    func readTimeCard() -> some View {
        background(Color.readTimeCardBackground, in: RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
    }
}

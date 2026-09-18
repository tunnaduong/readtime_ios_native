import SwiftUI
import CryptoKit
#if canImport(UIKit)
import UIKit
#endif

// Models, storage, and colours shared by the app and its widgets.

/// The app group both targets use, so the widgets can read the same saved data and covers.
enum AppGroup {
    static let identifier = "group.com.fatties.readtime"

    /// The shared container, or the app's own Application Support folder if the group isn't available.
    static var containerURL: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    /// Where the data lived before widgets existed; still read once so nothing is lost.
    static var legacyContainerURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }
}

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
    /// When the book was marked finished; nil for books finished before this was tracked.
    var finishedAt: Date?
    /// 1–5 stars, set once the book is finished.
    var rating: Int?

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
}

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

/// Saves the reading data as JSON in the shared container so it survives relaunches
/// and the widgets can read it.
enum LocalStore {
    private static let fileName = "ReadTime.json"

    private static var fileURL: URL {
        AppGroup.containerURL.appendingPathComponent(fileName)
    }

    private static var legacyFileURL: URL {
        AppGroup.legacyContainerURL.appendingPathComponent(fileName)
    }

    static func load() -> ReadingSnapshot? {
        migrateIfNeeded()
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

    /// Moves data saved by versions that stored it in the app's own container.
    private static func migrateIfNeeded() {
        let manager = FileManager.default
        guard !manager.fileExists(atPath: fileURL.path), manager.fileExists(atPath: legacyFileURL.path) else { return }
        try? manager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? manager.copyItem(at: legacyFileURL, to: fileURL)
        let legacyCovers = AppGroup.legacyContainerURL.appendingPathComponent("Covers", isDirectory: true)
        let covers = AppGroup.containerURL.appendingPathComponent("Covers", isDirectory: true)
        if manager.fileExists(atPath: legacyCovers.path), !manager.fileExists(atPath: covers.path) {
            try? manager.copyItem(at: legacyCovers, to: covers)
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

    #if !SKIP
    private var image: UIImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png") else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
    #endif

    var body: some View {
        #if !SKIP
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            CoverPlaceholder()
        }
        #else
        // TODO(android): render the bundled Figma PNG art here too — needs
        // Skip's cross-platform image type in place of UIImage.
        CoverPlaceholder()
        #endif
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
    #if !SKIP
    @State var remoteImage: UIImage?
    #endif

    var body: some View {
        Group {
            if let coverName {
                FigmaImage(name: coverName)
            }
            #if !SKIP
            else if let remoteImage {
                Image(uiImage: remoteImage)
                    .resizable()
                    .scaledToFill()
            }
            #endif
            else {
                CoverPlaceholder()
            }
        }
        #if !SKIP
        .task(id: coverURL) {
            guard coverName == nil, let coverURL, let url = URL(string: coverURL) else {
                remoteImage = nil
                return
            }
            remoteImage = await CoverCache.image(for: url, persist: persist)
        }
        #endif
        // TODO(android): CoverCache (below) is iOS-only for now, so remote/
        // online-search covers always fall back to CoverPlaceholder here.
    }
}

/// Downloads book covers once and keeps them in Application Support so saved books
/// still show their cover offline.
/// TODO(android): reimplement using a cross-platform image type once this is
/// actually wired up on Android (its only call sites are gated to iOS for now).
#if !SKIP
enum CoverCache {
    private static let memory = NSCache<NSURL, NSData>()

    private static var directory: URL {
        AppGroup.containerURL.appendingPathComponent("Covers", isDirectory: true)
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
#endif

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
        #if !SKIP
        self.init(uiColor: UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
        #else
        // TODO(android): this always renders the light variant — there's no
        // UIColor-style dynamic-provider equivalent without Named/asset-catalog
        // colors (which do adapt cross-platform) or reading the environment
        // color scheme at each call site instead of at initialization time.
        self.init(red: light.0, green: light.1, blue: light.2, opacity: 1)
        #endif
    }
}

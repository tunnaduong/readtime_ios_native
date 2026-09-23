package com.fatties.readtime.data

import java.time.LocalDate
import java.time.temporal.ChronoUnit
import kotlin.math.roundToInt

/** An immutable snapshot of everything the screens read. */
data class ReadingState(
    val books: List<Book> = emptyList(),
    val activities: List<ReadingActivity> = emptyList(),
    val journalEntries: List<JournalEntry> = emptyList(),
    val dailyGoal: Int = 30,
    /** Which days and for how long the daily goal applies. Null means every day with no end date. */
    val routine: ReadingRoutine? = null,
    val yearlyBookGoal: Int = 24,
    val reminderEnabled: Boolean = false,
    val reminderTime: AppleDate = AppleDate.now(),
    val selectedBookID: String? = null,
    /** The book currently being read (session in progress). */
    val activeSessionBookID: String? = null,
    val activeSessionStartedAt: AppleDate? = null,
    /** True until the reader picks demo content or a fresh start on first launch. */
    val needsOnboarding: Boolean = false,
) {
    val activeBook: Book?
        get() = books.firstOrNull { it.id == selectedBookID }
        // Fall back to a book on the to-read list, e.g. the first book added during onboarding.
            ?: books.firstOrNull { it.status == BookStatus.READING }
            ?: books.firstOrNull { it.status == BookStatus.WANT_TO_READ }

    fun book(id: String?): Book? = id?.let { wanted -> books.firstOrNull { it.id == wanted } }

    // MARK: Days and goals

    val minutesToday: Int get() = minutesRead(LocalDate.now())

    fun minutesRead(day: LocalDate): Int =
        activities.filter { it.date.localDate() == day }.sumOf { it.minutes }

    /** Monday to Sunday of the current week. */
    val currentWeekDays: List<LocalDate>
        get() {
            val today = LocalDate.now()
            val monday = today.minusDays((today.iosWeekday + 5) % 7L)
            return (0..6).map { monday.plusDays(it.toLong()) }
        }

    /** Whether the daily goal applies on this day. */
    fun isScheduled(day: LocalDate): Boolean = routine?.includes(day) ?: true

    val routineHasEnded: Boolean
        get() = routine?.let { !LocalDate.now().isBefore(it.endDate) } ?: false

    val currentWeekMinutes: Int get() = currentWeekDays.sumOf { minutesRead(it) }

    val finishedBooks: Int get() = books.count { it.status == BookStatus.FINISHED }

    // MARK: Stats

    data class GenreShare(val genre: String, val percent: Int)

    /** Top genres by time spent reading, or by books in the library before any sessions are logged. */
    fun favouriteGenres(otherLabel: String): Pair<List<GenreShare>, Boolean> {
        fun genreOf(book: Book): String = book.genre.trim().ifEmpty { otherLabel }

        var totals = mutableMapOf<String, Int>()
        for (activity in activities) {
            val book = books.firstOrNull { it.title == activity.bookTitle } ?: continue
            totals[genreOf(book)] = (totals[genreOf(book)] ?: 0) + activity.minutes
        }
        val byReadingTime = totals.values.sum() > 0
        if (!byReadingTime) {
            totals = mutableMapOf()
            for (book in books) totals[genreOf(book)] = (totals[genreOf(book)] ?: 0) + 1
        }

        val total = totals.values.sum()
        if (total == 0) return emptyList<GenreShare>() to byReadingTime
        val shares = totals.entries
            .sortedWith(compareByDescending<Map.Entry<String, Int>> { it.value }.thenBy { it.key })
            .take(5)
            .map { GenreShare(it.key, (it.value.toDouble() / total * 100).roundToInt()) }
        return shares to byReadingTime
    }

    /** Pages per minute over the last seven sessions that recorded pages read. */
    val readingSpeed: Pair<Double, Int>?
        get() {
            val sessions = activities
                .filter { (it.pagesRead ?: 0) > 0 && it.minutes > 0 }
                .sortedByDescending { it.date.value }
                .take(7)
            val minutes = sessions.sumOf { it.minutes }
            if (minutes == 0) return null
            val pages = sessions.sumOf { it.pagesRead ?: 0 }
            return (pages.toDouble() / minutes) to sessions.size
        }

    val pagesPerHour: Int? get() = readingSpeed?.let { (it.first * 60).roundToInt() }

    val averageRating: Double?
        get() {
            val ratings = books.mapNotNull { if (it.status == BookStatus.FINISHED) it.rating else null }
            if (ratings.isEmpty()) return null
            return ratings.sum().toDouble() / ratings.size
        }

    val averageFinishedLength: Int?
        get() {
            val finished = books.filter { it.status == BookStatus.FINISHED }
            if (finished.isEmpty()) return null
            return finished.sumOf { it.totalPages } / finished.size
        }

    /** Most consecutive days with at least one reading session. */
    val longestStreak: Int
        get() {
            val days = activities.filter { it.minutes > 0 }.map { it.date.localDate() }.distinct().sorted()
            var best = 0
            var run = 0
            var previous: LocalDate? = null
            for (day in days) {
                run = if (previous != null && ChronoUnit.DAYS.between(previous, day) == 1L) run + 1 else 1
                best = maxOf(best, run)
                previous = day
            }
            return best
        }

    fun activitiesIn(start: LocalDate, endExclusive: LocalDate): List<ReadingActivity> =
        activities.filter { val day = it.date.localDate(); !day.isBefore(start) && day.isBefore(endExclusive) }

    fun booksFinishedIn(start: LocalDate, endExclusive: LocalDate): Int =
        books.count {
            val day = it.finishedAt?.localDate() ?: return@count false
            !day.isBefore(start) && day.isBefore(endExclusive)
        }

    /** The book read longest on a day, for the calendar cover. */
    fun topActivity(day: LocalDate): ReadingActivity? {
        val sessions = activities.filter { it.date.localDate() == day }
        val minutesByTitle = mutableMapOf<String, Int>()
        for (session in sessions) minutesByTitle[session.bookTitle] = (minutesByTitle[session.bookTitle] ?: 0) + session.minutes
        val title = minutesByTitle.maxByOrNull { it.value }?.key ?: return null
        return sessions.firstOrNull { it.bookTitle == title }
    }
}

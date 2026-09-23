package com.fatties.readtime.data

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID
import kotlin.math.min

/**
 * The models are serialised with the same field names and value shapes as the iOS app's
 * `Codable` types, so a backup exported on iOS restores here and vice versa: dates are
 * seconds since Apple's reference date (2001-01-01 UTC) and ids are uppercase UUID strings.
 */

/** Seconds between the Unix epoch and Apple's reference date. */
private const val APPLE_EPOCH_OFFSET = 978_307_200.0

/** A moment in time, stored the way Swift's `JSONEncoder` writes a `Date`. */
@JvmInline
@Serializable
value class AppleDate(val value: Double) : Comparable<AppleDate> {
    val epochMillis: Long get() = ((value + APPLE_EPOCH_OFFSET) * 1000).toLong()
    val instant: Instant get() = Instant.ofEpochMilli(epochMillis)
    fun localDate(zone: ZoneId = ZoneId.systemDefault()): LocalDate = instant.atZone(zone).toLocalDate()

    override fun compareTo(other: AppleDate): Int = value.compareTo(other.value)

    operator fun plus(seconds: Double) = AppleDate(value + seconds)
    operator fun minus(other: AppleDate): Double = value - other.value

    companion object {
        fun now() = AppleDate(System.currentTimeMillis() / 1000.0 - APPLE_EPOCH_OFFSET)
        fun of(instant: Instant) = AppleDate(instant.toEpochMilli() / 1000.0 - APPLE_EPOCH_OFFSET)
        fun of(date: LocalDate, zone: ZoneId = ZoneId.systemDefault()): AppleDate =
            of(date.atStartOfDay(zone).toInstant())
    }
}

fun newID(): String = UUID.randomUUID().toString().uppercase()

@Serializable
enum class BookStatus(val rawValue: String) {
    @SerialName("Reading")
    READING("Reading"),

    @SerialName("Want to Read")
    WANT_TO_READ("Want to Read"),

    @SerialName("Finished")
    FINISHED("Finished");

    companion object {
        fun fromRaw(raw: String?): BookStatus? = entries.firstOrNull { it.rawValue == raw }
    }
}

@Serializable
data class Book(
    val id: String = newID(),
    val title: String = "",
    val author: String = "",
    val genre: String = "",
    val totalPages: Int = 0,
    val currentPage: Int = 0,
    val status: BookStatus = BookStatus.WANT_TO_READ,
    /** A cover bundled with the app (the sample library). */
    val coverName: String? = null,
    /** A cover found through book search, or a photo the reader picked; cached by [CoverCache]. */
    val coverURL: String? = null,
    /** Marks the sample library so it can be cleared without touching the reader's own books. */
    val isDemo: Boolean? = null,
    val finishedAt: AppleDate? = null,
    /** 1–5 stars, set once the book is finished. */
    val rating: Int? = null,
) {
    val progress: Float
        get() = if (totalPages <= 0) 0f else min(currentPage.toFloat() / totalPages, 1f)
}

@Serializable
data class ReadingActivity(
    val id: String = newID(),
    val date: AppleDate = AppleDate.now(),
    val minutes: Int = 0,
    val bookTitle: String = "",
    val coverName: String? = null,
    val coverURL: String? = null,
    val isDemo: Boolean? = null,
    /** Pages moved forward in the session; null for sessions saved before this was tracked. */
    val pagesRead: Int? = null,
)

@Serializable
data class JournalEntry(
    val id: String = newID(),
    val date: AppleDate = AppleDate.now(),
    /** Empty when the entry isn't about a particular book. */
    val bookTitle: String = "",
    val text: String = "",
    val isDemo: Boolean? = null,
)

@Serializable
data class ReadingRoutine(
    /** `Calendar` weekday numbers, matching iOS: 1 is Sunday, 2 is Monday, and so on. */
    val weekdays: List<Int> = (1..7).toList(),
    val startDate: AppleDate = AppleDate.now(),
    val weeks: Int = 4,
) {
    /** The first day after the routine (exclusive end). */
    val endDate: LocalDate get() = startDate.localDate().plusDays(weeks * 7L)

    val lastDay: LocalDate get() = endDate.minusDays(1)

    fun includes(day: LocalDate): Boolean =
        !day.isBefore(startDate.localDate()) && day.isBefore(endDate) && weekdays.contains(day.iosWeekday)
}

@Serializable
data class ReadingSnapshot(
    val books: List<Book> = emptyList(),
    val activities: List<ReadingActivity> = emptyList(),
    val journalEntries: List<JournalEntry> = emptyList(),
    val dailyGoal: Int = 30,
    val yearlyBookGoal: Int = 24,
    val routine: ReadingRoutine? = null,
    // Device-level preferences, only applied when loading this device's own data.
    val reminderEnabled: Boolean? = null,
    val reminderTime: AppleDate? = null,
    val selectedBookID: String? = null,
    val savedAt: AppleDate = AppleDate.now(),
)

/** The reading session that was in progress when the app was last closed. */
@Serializable
data class ActiveSessionState(
    val bookID: String,
    val startedAt: AppleDate,
)

/** `Calendar.component(.weekday)` on iOS: Sunday is 1 … Saturday is 7. */
val LocalDate.iosWeekday: Int
    get() = when (dayOfWeek) {
        DayOfWeek.SUNDAY -> 1
        DayOfWeek.MONDAY -> 2
        DayOfWeek.TUESDAY -> 3
        DayOfWeek.WEDNESDAY -> 4
        DayOfWeek.THURSDAY -> 5
        DayOfWeek.FRIDAY -> 6
        DayOfWeek.SATURDAY -> 7
    }

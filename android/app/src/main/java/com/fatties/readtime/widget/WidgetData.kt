package com.fatties.readtime.widget

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import com.fatties.readtime.data.Book
import com.fatties.readtime.data.BookStatus
import com.fatties.readtime.data.LocalStore
import com.fatties.readtime.data.iosWeekday
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.time.LocalDate

/** What both widgets show, the counterpart of the iOS `ReadTimeEntry`. */
data class WidgetEntry(
    val book: Book? = null,
    val cover: Bitmap? = null,
    val minutesToday: Int = 0,
    val dailyGoal: Int = 20,
    val streak: Int = 0,
    /** Minutes read on each day of the current week, Monday first. */
    val week: List<Pair<LocalDate, Int>> = emptyList(),
) {
    val progress: Float get() = if (dailyGoal <= 0) 0f else minOf(minutesToday.toFloat() / dailyGoal, 1f)
}

object WidgetData {
    suspend fun load(context: Context): WidgetEntry = withContext(Dispatchers.IO) {
        val snapshot = LocalStore.load(context) ?: return@withContext WidgetEntry()

        val book = snapshot.books.firstOrNull { it.id == snapshot.selectedBookID }
            ?: snapshot.books.firstOrNull { it.status == BookStatus.READING }
            ?: snapshot.books.firstOrNull { it.status == BookStatus.WANT_TO_READ }

        fun minutes(day: LocalDate) =
            snapshot.activities.filter { it.date.localDate() == day }.sumOf { it.minutes }

        val today = LocalDate.now()
        val monday = today.minusDays((today.iosWeekday + 5) % 7L)
        val week = (0..6).map { offset ->
            val day = monday.plusDays(offset.toLong())
            day to minutes(day)
        }

        WidgetEntry(
            book = book,
            cover = cover(context, book),
            minutesToday = minutes(today),
            dailyGoal = snapshot.dailyGoal,
            streak = streak(snapshot.activities.filter { it.minutes > 0 }.map { it.date.localDate() }.toSet()),
            week = week,
        )
    }

    /** Days in a row up to today (or yesterday, if today hasn't started yet) with a reading session. */
    private fun streak(days: Set<LocalDate>): Int {
        var day = LocalDate.now()
        if (!days.contains(day)) day = day.minusDays(1)
        var count = 0
        while (days.contains(day)) {
            count += 1
            day = day.minusDays(1)
        }
        return count
    }

    private fun cover(context: Context, book: Book?): Bitmap? {
        if (book == null) return null
        book.coverName?.let { name ->
            val id = context.resources.getIdentifier(name.replace('-', '_'), "drawable", context.packageName)
            if (id != 0) return BitmapFactory.decodeResource(context.resources, id)
        }
        val url = book.coverURL ?: return null
        if (url.startsWith("readtime-cover:")) {
            val file = File(File(context.filesDir, "Covers"), url.removePrefix("readtime-cover:"))
            return if (file.exists()) BitmapFactory.decodeFile(file.path) else null
        }
        return downloadedCover(context, url)
    }

    /**
     * Widgets can't read Coil's cache, so remote covers get their own small copy on disk,
     * downloaded once per URL.
     */
    private fun downloadedCover(context: Context, url: String): Bitmap? {
        val directory = File(context.filesDir, "WidgetCovers").apply { mkdirs() }
        val digest = MessageDigest.getInstance("SHA-256").digest(url.toByteArray())
        val file = File(directory, digest.joinToString("") { "%02x".format(it) } + ".jpg")
        if (!file.exists()) {
            runCatching {
                val connection = (URL(url).openConnection() as HttpURLConnection).apply {
                    connectTimeout = 10_000
                    readTimeout = 15_000
                }
                try {
                    if (connection.responseCode in 200..299) {
                        connection.inputStream.use { input -> file.outputStream().use { input.copyTo(it) } }
                    }
                } finally {
                    connection.disconnect()
                }
            }
        }
        return if (file.exists()) BitmapFactory.decodeFile(file.path) else null
    }
}

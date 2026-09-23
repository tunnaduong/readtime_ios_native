package com.fatties.readtime.data

import android.content.Context
import android.util.Log
import kotlinx.serialization.json.Json
import java.io.File

/** Saves the reading data as JSON in the app's files directory, in the iOS app's format. */
object LocalStore {
    private const val FILE_NAME = "ReadTime.json"

    val json = Json {
        ignoreUnknownKeys = true
        explicitNulls = false
        encodeDefaults = true
        prettyPrint = false
    }

    private fun file(context: Context) = File(context.filesDir, FILE_NAME)

    fun load(context: Context): ReadingSnapshot? {
        val file = file(context)
        if (!file.exists()) return null
        return try {
            json.decodeFromString<ReadingSnapshot>(file.readText())
        } catch (error: Exception) {
            Log.e("ReadTime", "couldn't read saved data", error)
            null
        }
    }

    fun save(context: Context, snapshot: ReadingSnapshot) {
        try {
            val target = file(context)
            val temporary = File(target.parentFile, "$FILE_NAME.tmp")
            temporary.writeText(json.encodeToString(ReadingSnapshot.serializer(), snapshot))
            temporary.renameTo(target)
        } catch (error: Exception) {
            Log.e("ReadTime", "couldn't save data", error)
        }
    }
}

/** The sample library shown on first launch, and loaded or cleared from Settings. */
object DemoContent {
    val books: List<Book>
        get() = listOf(
            Book(title = "I Owe You One", author = "Sophie Kinsella", genre = "Romance", totalPages = 400, currentPage = 240, status = BookStatus.READING, coverName = "i-owe-you-one", isDemo = true),
            Book(title = "This Is Going To Hurt", author = "Adam Kay", genre = "Memoir", totalPages = 248, currentPage = 156, status = BookStatus.READING, coverName = "this-is-going-to-hurt", isDemo = true),
            Book(title = "Steal Like an Artist", author = "Austin Kleon", genre = "Creativity", totalPages = 160, currentPage = 160, status = BookStatus.FINISHED, coverName = "steal-like-an-artist", isDemo = true),
            Book(title = "High Output Management", author = "Andrew S. Grove", genre = "Business", totalPages = 272, currentPage = 0, status = BookStatus.WANT_TO_READ, coverName = "high-output-management", isDemo = true),
        )

    val activities: List<ReadingActivity>
        get() {
            val now = AppleDate.now()
            fun daysAgo(days: Int) = AppleDate(now.value - days * 86_400.0)
            return listOf(
                ReadingActivity(date = now, minutes = 35, bookTitle = "Steal Like an Artist", coverName = "steal-like-an-artist", isDemo = true, pagesRead = 30),
                ReadingActivity(date = daysAgo(1), minutes = 32, bookTitle = "I Owe You One", coverName = "i-owe-you-one", isDemo = true, pagesRead = 28),
                ReadingActivity(date = daysAgo(2), minutes = 18, bookTitle = "This Is Going To Hurt", coverName = "this-is-going-to-hurt", isDemo = true, pagesRead = 16),
                ReadingActivity(date = daysAgo(3), minutes = 15, bookTitle = "High Output Management", coverName = "high-output-management", isDemo = true, pagesRead = 14),
                ReadingActivity(date = daysAgo(4), minutes = 42, bookTitle = "I Owe You One", coverName = "i-owe-you-one", isDemo = true, pagesRead = 38),
                ReadingActivity(date = daysAgo(5), minutes = 22, bookTitle = "This Is Going To Hurt", coverName = "this-is-going-to-hurt", isDemo = true, pagesRead = 19),
                ReadingActivity(date = daysAgo(6), minutes = 34, bookTitle = "Steal Like an Artist", coverName = "steal-like-an-artist", isDemo = true, pagesRead = 30),
            )
        }

    val journalEntries: List<JournalEntry>
        get() = listOf(
            JournalEntry(
                date = AppleDate(AppleDate.now().value - 86_400.0),
                bookTitle = "Steal Like an Artist",
                text = "Make things for yourself first. The work becomes clearer when I stop trying to impress everyone.",
                isDemo = true,
            )
        )
}

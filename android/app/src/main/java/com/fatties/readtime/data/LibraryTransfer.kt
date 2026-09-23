package com.fatties.readtime.data

import android.content.Context
import android.net.Uri
import androidx.core.content.FileProvider
import java.io.File
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.roundToInt

/** Backups and CSV import/export, in the same shapes the iOS app reads and writes. */
object LibraryTransfer {
    class NoBooksFound : Exception()

    private val dateStamp: String get() = LocalDate.now().format(DateTimeFormatter.ISO_LOCAL_DATE)

    private fun shareDirectory(context: Context) = File(context.cacheDir, "share").apply { mkdirs() }

    private fun shareUri(context: Context, file: File): Uri =
        FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)

    fun backupFile(context: Context, snapshot: ReadingSnapshot): Uri {
        val pretty = kotlinx.serialization.json.Json(LocalStore.json) { prettyPrint = true }
        val file = File(shareDirectory(context), "ReadTime Backup $dateStamp.json")
        file.writeText(pretty.encodeToString(ReadingSnapshot.serializer(), snapshot))
        return shareUri(context, file)
    }

    fun booksCSVFile(context: Context, books: List<Book>): Uri {
        val rows = mutableListOf(
            listOf("Title", "Author", "Genre", "Pages", "Current Page", "Status", "Rating", "Date Finished")
        )
        for (book in books) {
            rows.add(
                listOf(
                    book.title,
                    book.author,
                    book.genre,
                    book.totalPages.toString(),
                    book.currentPage.toString(),
                    book.status.rawValue,
                    book.rating?.toString() ?: "",
                    book.finishedAt?.localDate()?.format(DateTimeFormatter.ISO_LOCAL_DATE) ?: "",
                )
            )
        }
        val csv = rows.joinToString("\n") { row -> row.joinToString(",") { escape(it) } }
        val file = File(shareDirectory(context), "ReadTime Books $dateStamp.csv")
        file.writeText(csv)
        return shareUri(context, file)
    }

    fun readBackup(context: Context, uri: Uri): ReadingSnapshot =
        LocalStore.json.decodeFromString(read(context, uri))

    /** Understands Goodreads and StoryGraph exports, and ReadTime's own CSV. */
    fun booksFromCSV(context: Context, uri: Uri): List<Book> {
        val rows = parseCSV(read(context, uri))
        val header = rows.firstOrNull() ?: throw NoBooksFound()
        val columns = header.map { it.trim().lowercase() }
        fun column(vararg names: String): Int? = names.firstNotNullOfOrNull { name ->
            columns.indexOf(name).takeIf { it >= 0 }
        }

        val titleColumn = column("title") ?: throw NoBooksFound()
        val authorColumn = column("author", "authors", "author l-f")
        val pagesColumn = column("number of pages", "pages", "page count")
        val currentPageColumn = column("current page")
        val statusColumn = column("exclusive shelf", "read status", "status")
        val ratingColumn = column("my rating", "star rating", "rating")
        val dateColumn = column("date read", "last date read", "date finished")
        val genreColumn = column("genre", "genres")

        val books = rows.drop(1).mapNotNull { row ->
            fun value(index: Int?): String =
                if (index == null || index >= row.size) "" else row[index].trim()

            val title = value(titleColumn)
            if (title.isEmpty()) return@mapNotNull null

            val pages = value(pagesColumn).toIntOrNull() ?: 0
            val totalPages = if (pages > 0) pages else 250
            val status = when (value(statusColumn).lowercase()) {
                "read", "finished" -> BookStatus.FINISHED
                "currently-reading", "reading" -> BookStatus.READING
                else -> BookStatus.WANT_TO_READ
            }
            val rating = value(ratingColumn).toDoubleOrNull()?.roundToInt()?.takeIf { it in 1..5 }
            val genre = value(genreColumn).split(",").firstOrNull()?.trim().orEmpty()
            val author = value(authorColumn).split(",").firstOrNull()?.trim().orEmpty()

            Book(
                title = title,
                author = author.ifEmpty { context.getString(com.fatties.readtime.R.string.s_unknown_author) },
                genre = genre.ifEmpty { context.getString(com.fatties.readtime.R.string.s_general) },
                totalPages = totalPages,
                currentPage = if (status == BookStatus.FINISHED) totalPages
                else minOf(value(currentPageColumn).toIntOrNull() ?: 0, totalPages),
                status = status,
                finishedAt = if (status == BookStatus.FINISHED) {
                    parseDate(value(dateColumn))?.let { AppleDate.of(it) } ?: AppleDate.now()
                } else {
                    null
                },
                rating = if (status == BookStatus.FINISHED) rating else null,
            )
        }
        if (books.isEmpty()) throw NoBooksFound()
        return books
    }

    private fun read(context: Context, uri: Uri): String =
        context.contentResolver.openInputStream(uri)?.bufferedReader()?.use { it.readText() }
            ?: throw NoBooksFound()

    private fun parseDate(value: String): LocalDate? {
        for (format in listOf("yyyy/MM/dd", "yyyy-MM-dd", "MM/dd/yyyy")) {
            runCatching {
                return LocalDate.parse(value, DateTimeFormatter.ofPattern(format, Locale.US))
            }
        }
        return null
    }

    private fun escape(field: String): String {
        if (field.none { it == ',' || it == '"' || it == '\n' || it == '\r' }) return field
        return "\"" + field.replace("\"", "\"\"") + "\""
    }

    /** RFC 4180: quoted fields may contain commas, doubled quotes, and line breaks. */
    fun parseCSV(text: String): List<List<String>> {
        val rows = mutableListOf<List<String>>()
        var row = mutableListOf<String>()
        val field = StringBuilder()
        var inQuotes = false
        var index = 0

        fun endRow() {
            row.add(field.toString())
            field.clear()
            if (row.any { it.isNotEmpty() }) rows.add(row)
            row = mutableListOf()
        }

        while (index < text.length) {
            val char = text[index]
            index += 1
            if (inQuotes) {
                if (char == '"') {
                    val next = text.getOrNull(index)
                    if (next == '"') {
                        field.append('"')
                        index += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(char)
                }
            } else {
                when (char) {
                    '"' -> inQuotes = true
                    ',' -> {
                        row.add(field.toString())
                        field.clear()
                    }

                    '\n' -> endRow()
                    '\r' -> {
                        if (text.getOrNull(index) == '\n') index += 1
                        endRow()
                    }

                    else -> field.append(char)
                }
            }
        }
        row.add(field.toString())
        if (row.any { it.isNotEmpty() }) rows.add(row)

        // Byte-order mark some spreadsheet apps add to the first header.
        val first = rows.firstOrNull()?.firstOrNull()
        if (first != null && first.startsWith("﻿")) {
            rows[0] = rows[0].toMutableList().also { it[0] = first.removePrefix("﻿") }
        }
        return rows
    }
}

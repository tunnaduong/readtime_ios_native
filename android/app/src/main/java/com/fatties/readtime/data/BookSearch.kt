package com.fatties.readtime.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

data class BookSearchResult(
    val id: String,
    val title: String,
    val authors: List<String>,
    val genre: String?,
    val pageCount: Int?,
    val year: String?,
    /** Small image for the result list; [coverURL] is the larger one saved with the book. */
    val thumbnailURL: String?,
    val coverURL: String?,
)

/**
 * Looks books up on Google Books, falling back to Open Library when Google has nothing or is
 * unavailable (for example when the keyless daily quota runs out).
 */
object BookSearch {
    private const val USER_AGENT = "ReadTime/1.0 (hello@readtime.app)"

    suspend fun search(query: String): List<BookSearchResult> {
        val google = runCatching { searchGoogleBooks(query) }.getOrDefault(emptyList())
        if (google.isNotEmpty()) return google
        return searchOpenLibrary(query)
    }

    private suspend fun searchGoogleBooks(query: String): List<BookSearchResult> {
        val url = "https://www.googleapis.com/books/v1/volumes" +
            "?q=${query.encoded()}&printType=books&maxResults=20"
        val response = LocalStore.json.decodeFromString<GoogleBooksResponse>(fetch(url))
        return (response.items ?: emptyList()).mapNotNull { item ->
            val info = item.volumeInfo
            val title = info.title?.takeIf { it.isNotEmpty() } ?: return@mapNotNull null
            // Google returns http thumbnails with a page-curl effect; ask for the plain https image.
            val thumbnail = (info.imageLinks?.thumbnail ?: info.imageLinks?.smallThumbnail)
                ?.replace("http://", "https://")
                ?.replace("&edge=curl", "")
            BookSearchResult(
                id = "google-${item.id}",
                title = listOfNotNull(title, info.subtitle).joinToString(": "),
                authors = info.authors ?: emptyList(),
                genre = info.categories?.firstOrNull()?.split(" / ")?.firstOrNull(),
                pageCount = info.pageCount?.takeIf { it > 0 },
                year = info.publishedDate?.take(4),
                thumbnailURL = thumbnail,
                coverURL = thumbnail,
            )
        }
    }

    private suspend fun searchOpenLibrary(query: String): List<BookSearchResult> {
        val url = "https://openlibrary.org/search.json?q=${query.encoded()}&limit=20" +
            "&fields=key,title,author_name,first_publish_year,number_of_pages_median,cover_i,subject"
        val response = LocalStore.json.decodeFromString<OpenLibraryResponse>(fetch(url))
        return response.docs.mapNotNull { doc ->
            val title = doc.title?.takeIf { it.isNotEmpty() } ?: return@mapNotNull null
            BookSearchResult(
                id = "openlibrary-${doc.key}",
                title = title,
                authors = doc.author_name ?: emptyList(),
                genre = doc.subject?.firstOrNull(),
                pageCount = doc.number_of_pages_median,
                year = doc.first_publish_year?.toString(),
                // `default=false` returns 404 instead of a blank image when there's no cover.
                thumbnailURL = doc.cover_i?.let { "https://covers.openlibrary.org/b/id/$it-M.jpg?default=false" },
                coverURL = doc.cover_i?.let { "https://covers.openlibrary.org/b/id/$it-L.jpg?default=false" },
            )
        }
    }

    private suspend fun fetch(url: String): String = withContext(Dispatchers.IO) {
        val connection = (URL(url).openConnection() as HttpURLConnection).apply {
            setRequestProperty("User-Agent", USER_AGENT)
            connectTimeout = 10_000
            readTimeout = 15_000
        }
        try {
            if (connection.responseCode !in 200..299) throw IllegalStateException("HTTP ${connection.responseCode}")
            connection.inputStream.bufferedReader().use { it.readText() }
        } finally {
            connection.disconnect()
        }
    }

    private fun String.encoded(): String = URLEncoder.encode(this, "UTF-8")

    @Serializable
    private data class GoogleBooksResponse(val items: List<Item>? = null) {
        @Serializable
        data class Item(val id: String, val volumeInfo: VolumeInfo)

        @Serializable
        data class VolumeInfo(
            val title: String? = null,
            val subtitle: String? = null,
            val authors: List<String>? = null,
            val publishedDate: String? = null,
            val pageCount: Int? = null,
            val categories: List<String>? = null,
            val imageLinks: ImageLinks? = null,
        )

        @Serializable
        data class ImageLinks(val thumbnail: String? = null, val smallThumbnail: String? = null)
    }

    @Serializable
    private data class OpenLibraryResponse(val docs: List<Doc>) {
        @Serializable
        data class Doc(
            val key: String,
            val title: String? = null,
            val author_name: List<String>? = null,
            val first_publish_year: Int? = null,
            val number_of_pages_median: Int? = null,
            val cover_i: Int? = null,
            val subject: List<String>? = null,
        )
    }
}

package com.fatties.readtime.data

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import java.io.File
import kotlin.math.max
import kotlin.math.min

/**
 * Covers the reader picked from their photos, stored by file name so the path survives app
 * updates. Downloaded covers are left to Coil's own disk cache.
 */
object CoverCache {
    /** The iOS app's marker for a cover that lives in the app's own storage. */
    private const val UPLOAD_SCHEME = "readtime-cover"

    private fun directory(context: Context) = File(context.filesDir, "Covers").apply { mkdirs() }

    /** What Coil should load for a stored cover reference: a local file or a remote URL. */
    fun request(context: Context, coverURL: String): Any =
        if (coverURL.startsWith("$UPLOAD_SCHEME:")) {
            File(directory(context), coverURL.removePrefix("$UPLOAD_SCHEME:"))
        } else {
            coverURL
        }

    /** Saves a picked photo, scaled down, and returns the reference to store on the book. */
    fun saveUploadedCover(context: Context, uri: Uri): String {
        val bitmap = context.contentResolver.openInputStream(uri).use { input ->
            BitmapFactory.decodeStream(input)
        } ?: throw IllegalArgumentException("Could not read the picked image")

        // Covers show at most ~170dp wide, so keep them small.
        val maxSide = 900f
        val scale = min(1f, maxSide / max(bitmap.width, bitmap.height).toFloat())
        val resized = if (scale < 1f) {
            Bitmap.createScaledBitmap(bitmap, (bitmap.width * scale).toInt(), (bitmap.height * scale).toInt(), true)
        } else {
            bitmap
        }

        val name = "${newID()}.jpg"
        File(directory(context), name).outputStream().use { output ->
            resized.compress(Bitmap.CompressFormat.JPEG, 85, output)
        }
        return "$UPLOAD_SCHEME:$name"
    }
}

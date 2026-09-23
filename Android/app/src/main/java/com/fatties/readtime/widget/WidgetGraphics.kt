package com.fatties.readtime.widget

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import androidx.core.graphics.ColorUtils

/**
 * Glance has no canvas, and its progress bar ignores tint colours before Android 12, so the
 * ring and the progress line are drawn as small bitmaps instead.
 */
object WidgetGraphics {
    private const val PURPLE = 0xFF6941C6.toInt()
    private const val GREEN = 0xFF03B403.toInt()

    /** The daily-goal ring: a faint full circle with the progress arc on top. */
    fun ring(sizePx: Int, progress: Float): Bitmap {
        val bitmap = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val stroke = sizePx * 0.11f
        val bounds = RectF(stroke / 2, stroke / 2, sizePx - stroke / 2, sizePx - stroke / 2)

        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = stroke
            strokeCap = Paint.Cap.ROUND
        }
        paint.color = ColorUtils.setAlphaComponent(PURPLE, 46)
        canvas.drawOval(bounds, paint)

        paint.color = PURPLE
        canvas.drawArc(bounds, -90f, 360f * progress.coerceIn(0.001f, 1f), false, paint)
        return bitmap
    }

    /** The book-progress line: a rounded track filled to `progress`, stretched by the widget. */
    fun progressLine(widthPx: Int, heightPx: Int, progress: Float): Bitmap {
        val bitmap = Bitmap.createBitmap(widthPx, heightPx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val radius = heightPx / 2f
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)

        paint.color = ColorUtils.setAlphaComponent(PURPLE, 46)
        canvas.drawRoundRect(RectF(0f, 0f, widthPx.toFloat(), heightPx.toFloat()), radius, radius, paint)

        val filled = widthPx * progress.coerceIn(0f, 1f)
        if (filled > 0f) {
            paint.color = GREEN
            canvas.drawRoundRect(RectF(0f, 0f, maxOf(filled, heightPx.toFloat()), heightPx.toFloat()), radius, radius, paint)
        }
        return bitmap
    }
}

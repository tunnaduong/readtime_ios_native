package com.fatties.readtime.ui

import android.content.Context
import android.text.format.DateFormat
import com.fatties.readtime.R
import com.fatties.readtime.data.AppleDate
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale

/** Localised dates and durations, matching what the iOS app shows. */
object Dates {
    /** Formats with a skeleton such as "EEE", "d", "MMMMy" — the system picks the local order. */
    fun pattern(context: Context, skeleton: String, date: LocalDate): String {
        val locale = Locale.getDefault()
        val best = DateFormat.getBestDateTimePattern(locale, skeleton)
        return date.format(DateTimeFormatter.ofPattern(best, locale))
    }

    fun abbreviated(date: LocalDate): String =
        date.format(DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).withLocale(Locale.getDefault()))

    fun abbreviatedWithTime(moment: LocalDateTime): String =
        moment.format(DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT).withLocale(Locale.getDefault()))

    fun time(moment: LocalDateTime): String =
        moment.format(DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).withLocale(Locale.getDefault()))

    fun iso(date: LocalDate): String = date.format(DateTimeFormatter.ISO_LOCAL_DATE)

    fun local(date: AppleDate): LocalDateTime = LocalDateTime.ofInstant(date.instant, ZoneId.systemDefault())

    /** "Today", "Yesterday", or a short weekday and day, as on the activity cards. */
    fun activityLabel(context: Context, date: AppleDate): String {
        val day = date.localDate()
        val today = LocalDate.now()
        return when (day) {
            today -> context.getString(R.string.s_today)
            today.minusDays(1) -> context.getString(R.string.s_yesterday)
            else -> pattern(context, "EEEd", day)
        }
    }

    /** "Today", "Tomorrow", or a medium date — the label on a goal's start day. */
    fun startLabel(context: Context, date: LocalDate): String {
        val today = LocalDate.now()
        return when (date) {
            today -> context.getString(R.string.s_today)
            today.plusDays(1) -> context.getString(R.string.s_tomorrow)
            else -> abbreviated(date)
        }
    }

    /** Short standalone weekday names, Sunday first, matching iOS weekday numbering. */
    fun shortWeekdays(): List<String> {
        val locale = Locale.getDefault()
        val formatter = DateTimeFormatter.ofPattern("EEE", locale)
        // 2024-01-07 was a Sunday.
        val sunday = LocalDate.of(2024, 1, 7)
        return (0..6).map { sunday.plusDays(it.toLong()).format(formatter) }
    }

    /** One or two letter weekday names, Sunday first. */
    fun narrowWeekdays(): List<String> {
        val locale = Locale.getDefault()
        val formatter = DateTimeFormatter.ofPattern("EEEEE", locale)
        val sunday = LocalDate.of(2024, 1, 7)
        return (0..6).map { sunday.plusDays(it.toLong()).format(formatter) }
    }
}

object Durations {
    /** "45 min", "2 hours", or "2 hours 5 min" — the totals the stats screens show. */
    fun readable(context: Context, minutes: Int): String {
        val hours = minutes / 60
        val rest = minutes % 60
        val hoursText = context.resources.getQuantityString(R.plurals.s_n_hours, hours, hours)
        val minutesText = context.getString(R.string.s_n_min, rest)
        return when {
            hours == 0 -> minutesText
            rest == 0 -> hoursText
            else -> "$hoursText $minutesText"
        }
    }

    /** mm:ss, or h:mm:ss once a session passes an hour. */
    fun clock(seconds: Long): String {
        val hours = seconds / 3600
        val minutes = (seconds % 3600) / 60
        val secs = seconds % 60
        return if (hours > 0) {
            String.format(Locale.getDefault(), "%d:%02d:%02d", hours, minutes, secs)
        } else {
            String.format(Locale.getDefault(), "%d:%02d", minutes, secs)
        }
    }
}

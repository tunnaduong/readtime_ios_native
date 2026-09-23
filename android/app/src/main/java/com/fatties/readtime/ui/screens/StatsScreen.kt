package com.fatties.readtime.ui.screens

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.filled.TrendingDown
import androidx.compose.material.icons.automirrored.filled.TrendingFlat
import androidx.compose.material.icons.automirrored.filled.TrendingUp
import androidx.compose.material.icons.filled.Article
import androidx.compose.material.icons.filled.Book
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.LibraryBooks
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavHostController
import com.fatties.readtime.R
import com.fatties.readtime.data.ReadingState
import com.fatties.readtime.data.ReadingStore
import com.fatties.readtime.data.iosWeekday
import com.fatties.readtime.ui.Dates
import com.fatties.readtime.ui.Durations
import com.fatties.readtime.ui.components.AdBanner
import com.fatties.readtime.ui.components.CardTitle
import com.fatties.readtime.ui.components.CoverImage
import com.fatties.readtime.ui.components.ReadTimeCard
import com.fatties.readtime.ui.components.SecondaryText
import com.fatties.readtime.ui.theme.ReadTimeTheme
import java.time.LocalDate
import java.time.YearMonth
import kotlin.math.abs

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StatsScreen(store: ReadingStore, navController: NavHostController) {
    val state by store.state.collectAsStateWithLifecycle()
    val context = LocalContext.current

    Scaffold(
        containerColor = ReadTimeTheme.colors.background,
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.s_stats), fontWeight = FontWeight.Bold) },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = ReadTimeTheme.colors.background,
                    titleContentColor = ReadTimeTheme.colors.text,
                ),
            )
        },
    ) { padding ->
        LazyColumn(
            contentPadding = PaddingValues(
                start = 20.dp,
                end = 20.dp,
                top = padding.calculateTopPadding() + 8.dp,
                bottom = 24.dp,
            ),
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            item { AdBanner() }

            item {
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    StatTile(
                        value = state.currentWeekMinutes.toString(),
                        label = stringResource(R.string.s_minutes_this_week),
                        icon = Icons.Default.Schedule,
                        modifier = Modifier.weight(1f),
                    )
                    StatTile(
                        value = state.finishedBooks.toString(),
                        label = stringResource(R.string.s_books_completed),
                        icon = Icons.Default.CheckCircle,
                        modifier = Modifier.weight(1f),
                    )
                }
            }

            item { ReadingCalendarCard(state) }

            item { TrendsSection(state) }

            item {
                Text(
                    stringResource(R.string.s_all_time),
                    style = MaterialTheme.typography.headlineSmall,
                    color = ReadTimeTheme.colors.text,
                    modifier = Modifier.padding(top = 8.dp),
                )
            }

            item { InsightsCard(state) }

            item { FavouriteGenresCard(state) }
        }
    }
}

@Composable
private fun StatTile(value: String, label: String, icon: ImageVector, modifier: Modifier = Modifier) {
    ReadTimeCard(modifier = modifier, padding = 14.dp) {
        Icon(icon, contentDescription = null, tint = ReadTimeTheme.colors.purple)
        Spacer(Modifier.height(8.dp))
        Text(
            value,
            style = MaterialTheme.typography.headlineSmall,
            color = ReadTimeTheme.colors.text,
        )
        Spacer(Modifier.height(4.dp))
        Text(
            label,
            style = MaterialTheme.typography.bodySmall,
            color = ReadTimeTheme.colors.secondaryText,
        )
    }
}

/** A month grid where each day shows the cover of the book read most that day. */
@Composable
private fun ReadingCalendarCard(state: ReadingState) {
    val context = LocalContext.current
    var monthOffset by remember { mutableIntStateOf(0) }
    val month = remember(monthOffset) { YearMonth.now().minusMonths(monthOffset.toLong()) }

    // Nil entries pad the first week so day 1 lands under its weekday (Monday first).
    val days = remember(month) {
        val first = month.atDay(1)
        val leading = (first.iosWeekday + 5) % 7
        List(leading) { null } + (1..month.lengthOfMonth()).map { month.atDay(it) }
    }
    val weekdaySymbols = remember {
        val symbols = Dates.narrowWeekdays()
        symbols.drop(1) + symbols.first()
    }

    ReadTimeCard {
        Row(verticalAlignment = Alignment.CenterVertically) {
            CardTitle(
                Dates.pattern(context, "MMMMy", month.atDay(1)),
                modifier = Modifier.weight(1f),
            )
            IconButton(onClick = { monthOffset += 1 }) {
                Icon(
                    Icons.AutoMirrored.Filled.KeyboardArrowLeft,
                    contentDescription = stringResource(R.string.s_previous_month),
                    tint = ReadTimeTheme.colors.purple,
                )
            }
            IconButton(onClick = { monthOffset -= 1 }, enabled = monthOffset > 0) {
                Icon(
                    Icons.AutoMirrored.Filled.KeyboardArrowRight,
                    contentDescription = stringResource(R.string.s_next_month),
                    tint = if (monthOffset > 0) ReadTimeTheme.colors.purple else ReadTimeTheme.colors.secondaryText,
                )
            }
        }
        Spacer(Modifier.height(12.dp))

        Row(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
            weekdaySymbols.forEach { symbol ->
                Text(
                    symbol,
                    style = MaterialTheme.typography.labelSmall,
                    color = ReadTimeTheme.colors.secondaryText,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.weight(1f),
                )
            }
        }
        Spacer(Modifier.height(5.dp))

        // A fixed-height grid inside the card, so it can live in the outer scrolling list.
        Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
            days.chunked(7).forEach { week ->
                Row(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                    week.forEach { day ->
                        Box(Modifier.weight(1f)) {
                            if (day == null) {
                                Box(
                                    Modifier
                                        .fillMaxWidth()
                                        .aspectRatio(2f / 3f)
                                )
                            } else {
                                DayCell(state, day)
                            }
                        }
                    }
                    repeat(7 - week.size) { Box(Modifier.weight(1f)) }
                }
            }
        }
    }
}

@Composable
private fun DayCell(state: ReadingState, day: LocalDate) {
    val context = LocalContext.current
    val minutes = state.minutesRead(day)
    val top = if (minutes > 0) state.topActivity(day) else null
    val isToday = day == LocalDate.now()

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .aspectRatio(2f / 3f)
            .clip(RoundedCornerShape(6.dp))
            .background(
                if (minutes > 0) ReadTimeTheme.colors.purple.copy(alpha = 0.35f)
                else ReadTimeTheme.colors.secondaryText.copy(alpha = 0.08f)
            )
            .then(
                if (isToday) Modifier.border(2.dp, ReadTimeTheme.colors.purple, RoundedCornerShape(6.dp))
                else Modifier
            ),
    ) {
        if (top != null && (top.coverName != null || top.coverURL != null)) {
            CoverImage(top.coverName, top.coverURL, modifier = Modifier.fillMaxSize())
        }
        Text(
            Dates.pattern(context, "d", day),
            style = MaterialTheme.typography.labelSmall,
            color = if (top == null) ReadTimeTheme.colors.secondaryText else Color.White,
            modifier = Modifier.padding(3.dp),
        )
    }
}

private enum class TrendPeriod(val labelRes: Int) {
    WEEK(R.string.s_7_days),
    MONTH(R.string.s_30_days),
    YEAR(R.string.s_12_months);

    /** `offset` 0 is the period ending today; 1 is the one before it, and so on. */
    fun interval(offset: Int): Pair<LocalDate, LocalDate> {
        val tomorrow = LocalDate.now().plusDays(1)
        return when (this) {
            WEEK, MONTH -> {
                val length = if (this == WEEK) 7L else 30L
                val end = tomorrow.minusDays(length * offset)
                end.minusDays(length) to end
            }

            YEAR -> {
                val nextMonth = YearMonth.now().plusMonths(1).atDay(1)
                val end = nextMonth.minusMonths(12L * offset)
                end.minusMonths(12) to end
            }
        }
    }

    fun buckets(interval: Pair<LocalDate, LocalDate>): List<Pair<LocalDate, LocalDate>> {
        val result = mutableListOf<Pair<LocalDate, LocalDate>>()
        var start = interval.first
        while (start.isBefore(interval.second)) {
            val next = if (this == YEAR) start.plusMonths(1) else start.plusDays(1)
            result.add(start to next)
            start = next
        }
        return result
    }

    fun rangeLabel(context: android.content.Context, interval: Pair<LocalDate, LocalDate>): String {
        val last = interval.second.minusDays(1)
        val skeleton = if (this == YEAR) "MMMy" else "dMMM"
        return "${Dates.pattern(context, skeleton, interval.first)} – ${Dates.pattern(context, skeleton, last)}"
    }
}

/** Pages, time and finished books for a chosen period, compared with the period before it. */
@Composable
private fun TrendsSection(state: ReadingState) {
    val context = LocalContext.current
    var period by remember { mutableStateOf(TrendPeriod.WEEK) }
    var offset by remember { mutableIntStateOf(0) }
    var menuOpen by remember { mutableStateOf(false) }

    val current = period.interval(offset)
    val previous = period.interval(offset + 1)
    val buckets = period.buckets(current)

    fun pages(range: Pair<LocalDate, LocalDate>) =
        state.activitiesIn(range.first, range.second).sumOf { it.pagesRead ?: 0 }

    fun minutes(range: Pair<LocalDate, LocalDate>) =
        state.activitiesIn(range.first, range.second).sumOf { it.minutes }

    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                stringResource(R.string.s_trends),
                style = MaterialTheme.typography.headlineSmall,
                color = ReadTimeTheme.colors.text,
                modifier = Modifier.weight(1f),
            )
            Box {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(ReadTimeTheme.colors.card)
                        .clickable { menuOpen = true }
                        .padding(horizontal = 12.dp, vertical = 7.dp),
                ) {
                    Text(
                        stringResource(period.labelRes),
                        style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.SemiBold),
                        color = ReadTimeTheme.colors.text,
                    )
                    Icon(Icons.Default.KeyboardArrowDown, contentDescription = null, tint = ReadTimeTheme.colors.text)
                }
                DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                    TrendPeriod.entries.forEach { option ->
                        DropdownMenuItem(
                            text = { Text(stringResource(option.labelRes)) },
                            onClick = {
                                period = option
                                offset = 0
                                menuOpen = false
                            },
                        )
                    }
                }
            }
        }

        Row(verticalAlignment = Alignment.CenterVertically) {
            SecondaryText(period.rangeLabel(context, current), modifier = Modifier.weight(1f))
            IconButton(onClick = { offset += 1 }) {
                Icon(
                    Icons.AutoMirrored.Filled.KeyboardArrowLeft,
                    contentDescription = stringResource(R.string.s_previous_period),
                    tint = ReadTimeTheme.colors.purple,
                )
            }
            IconButton(onClick = { offset -= 1 }, enabled = offset > 0) {
                Icon(
                    Icons.AutoMirrored.Filled.KeyboardArrowRight,
                    contentDescription = stringResource(R.string.s_next_period),
                    tint = if (offset > 0) ReadTimeTheme.colors.purple else ReadTimeTheme.colors.secondaryText,
                )
            }
        }

        TrendCard(
            title = stringResource(R.string.s_pages_read),
            icon = Icons.Default.Article,
            color = Color(0xFF3B82F6),
            current = pages(current),
            previous = pages(previous),
            format = { context.resources.getQuantityString(R.plurals.s_n_pages, it, it) },
            series = buckets.map { pages(it) },
        )
        TrendCard(
            title = stringResource(R.string.s_time_read),
            icon = Icons.Default.Schedule,
            color = ReadTimeTheme.colors.purple,
            current = minutes(current),
            previous = minutes(previous),
            format = { Durations.readable(context, it) },
            series = buckets.map { minutes(it) },
        )
        TrendCard(
            title = stringResource(R.string.s_books_finished),
            icon = Icons.Default.CheckCircle,
            color = ReadTimeTheme.colors.green,
            current = state.booksFinishedIn(current.first, current.second),
            previous = state.booksFinishedIn(previous.first, previous.second),
            format = { context.resources.getQuantityString(R.plurals.s_n_books, it, it) },
            series = buckets.map { state.booksFinishedIn(it.first, it.second) },
        )
    }
}

@Composable
private fun TrendCard(
    title: String,
    icon: ImageVector,
    color: Color,
    current: Int,
    previous: Int,
    format: (Int) -> String,
    series: List<Int>,
) {
    var expanded by remember { mutableStateOf(false) }
    val change = current - previous

    ReadTimeCard(modifier = Modifier.clickable { expanded = !expanded }) {
        Row(verticalAlignment = Alignment.Top) {
            Column(Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Icon(icon, contentDescription = null, tint = ReadTimeTheme.colors.secondaryText, modifier = Modifier.size(16.dp))
                    SecondaryText(title)
                }
                Spacer(Modifier.height(4.dp))
                Text(
                    format(current),
                    style = MaterialTheme.typography.headlineSmall,
                    color = color,
                )
                Spacer(Modifier.height(4.dp))
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    val deltaColor = when {
                        change > 0 -> ReadTimeTheme.colors.green
                        change < 0 -> MaterialTheme.colorScheme.error
                        else -> ReadTimeTheme.colors.secondaryText
                    }
                    Icon(
                        when {
                            change > 0 -> Icons.AutoMirrored.Filled.TrendingUp
                            change < 0 -> Icons.AutoMirrored.Filled.TrendingDown
                            else -> Icons.AutoMirrored.Filled.TrendingFlat
                        },
                        contentDescription = null,
                        tint = deltaColor,
                        modifier = Modifier.size(16.dp),
                    )
                    Text(
                        format(abs(change)),
                        style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Medium),
                        color = deltaColor,
                    )
                    SecondaryText(stringResource(R.string.s_vs_previous_period))
                }
            }
            Icon(
                Icons.Default.KeyboardArrowDown,
                contentDescription = null,
                tint = ReadTimeTheme.colors.secondaryText,
                modifier = Modifier.rotate(if (expanded) 180f else 0f),
            )
        }

        AnimatedVisibility(expanded) {
            Column {
                Spacer(Modifier.height(12.dp))
                BarChart(series, color)
            }
        }
    }
}

/** A plain bar chart; the iOS app uses Swift Charts for the same picture. */
@Composable
private fun BarChart(values: List<Int>, color: Color, modifier: Modifier = Modifier) {
    val maximum = (values.maxOrNull() ?: 0).coerceAtLeast(1)
    Canvas(
        modifier = modifier
            .fillMaxWidth()
            .height(120.dp)
    ) {
        if (values.isEmpty()) return@Canvas
        val gap = if (values.size > 40) 0.5.dp.toPx() else 2.dp.toPx()
        val barWidth = (size.width - gap * (values.size - 1)) / values.size
        values.forEachIndexed { index, value ->
            val barHeight = size.height * (value.toFloat() / maximum)
            drawRect(
                color = if (value == 0) color.copy(alpha = 0.15f) else color,
                topLeft = androidx.compose.ui.geometry.Offset(index * (barWidth + gap), size.height - barHeight),
                size = androidx.compose.ui.geometry.Size(barWidth, barHeight.coerceAtLeast(1f)),
            )
        }
    }
}

@Composable
private fun InsightsCard(state: ReadingState) {
    val context = LocalContext.current
    val genres = state.favouriteGenres(stringResource(R.string.s_other))

    ReadTimeCard(padding = 4.dp) {
        InsightRow(
            stringResource(R.string.s_top_genre),
            Icons.Default.LibraryBooks,
            Color(0xFFF59E0B),
            genres.first.firstOrNull()?.genre,
        )
        InsightDivider()
        InsightRow(
            stringResource(R.string.s_longest_streak),
            Icons.Default.LocalFireDepartment,
            Color(0xFFEF4444),
            state.longestStreak.takeIf { it > 0 }?.let {
                context.resources.getQuantityString(R.plurals.s_n_days, it, it)
            },
        )
        InsightDivider()
        InsightRow(
            stringResource(R.string.s_average_reading_speed),
            Icons.Default.Speed,
            Color(0xFF14B8A6),
            state.pagesPerHour?.let { stringResource(R.string.s_n_pages_hour, it) },
        )
        InsightDivider()
        InsightRow(
            stringResource(R.string.s_average_rating),
            Icons.Default.Star,
            Color(0xFFEAB308),
            state.averageRating?.let { stringResource(R.string.s_s_stars, String.format("%.1f", it)) },
        )
        InsightDivider()
        InsightRow(
            stringResource(R.string.s_average_book_length),
            Icons.Default.Book,
            ReadTimeTheme.colors.secondaryText,
            state.averageFinishedLength?.let {
                context.resources.getQuantityString(R.plurals.s_n_pages, it, it)
            },
        )
    }
}

@Composable
private fun InsightRow(title: String, icon: ImageVector, color: Color, value: String?) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier.padding(horizontal = 12.dp, vertical = 13.dp),
    ) {
        Icon(icon, contentDescription = null, tint = color, modifier = Modifier.width(28.dp))
        Text(title, color = ReadTimeTheme.colors.text, modifier = Modifier.weight(1f))
        Text(
            value ?: "—",
            style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.SemiBold),
            color = if (value == null) ReadTimeTheme.colors.secondaryText else color,
            textAlign = TextAlign.End,
        )
    }
}

@Composable
private fun InsightDivider() {
    HorizontalDivider(
        color = ReadTimeTheme.colors.secondaryText.copy(alpha = 0.15f),
        modifier = Modifier.padding(start = 52.dp),
    )
}

@Composable
private fun FavouriteGenresCard(state: ReadingState) {
    val (shares, byReadingTime) = state.favouriteGenres(stringResource(R.string.s_other))

    ReadTimeCard {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Icon(Icons.Default.Favorite, contentDescription = null, tint = ReadTimeTheme.colors.text)
            CardTitle(stringResource(R.string.s_favourite_genres))
        }
        if (shares.isNotEmpty()) {
            Spacer(Modifier.height(3.dp))
            Text(
                stringResource(
                    if (byReadingTime) R.string.s_by_time_spent_reading else R.string.s_by_books_in_your_library
                ),
                style = MaterialTheme.typography.bodySmall,
                color = ReadTimeTheme.colors.secondaryText,
            )
        }
        Spacer(Modifier.height(14.dp))

        if (shares.isEmpty()) {
            SecondaryText(stringResource(R.string.s_add_books_to_your_library_to_see_your_favourite_genres))
        } else {
            val maximum = shares.maxOf { it.percent }.coerceAtLeast(1)
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                shares.forEach { share ->
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Text(
                            share.genre,
                            style = MaterialTheme.typography.bodyMedium,
                            color = ReadTimeTheme.colors.text,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.width(96.dp),
                        )
                        Box(
                            Modifier
                                .weight(1f)
                                .height(16.dp)
                        ) {
                            Box(
                                Modifier
                                    .fillMaxWidth(share.percent.toFloat() / maximum)
                                    .fillMaxSize()
                                    .clip(CircleShape)
                                    .background(ReadTimeTheme.colors.purple)
                            )
                        }
                        Text(
                            "${share.percent}%",
                            style = MaterialTheme.typography.bodySmall,
                            color = ReadTimeTheme.colors.secondaryText,
                        )
                    }
                }
            }
        }
    }
}

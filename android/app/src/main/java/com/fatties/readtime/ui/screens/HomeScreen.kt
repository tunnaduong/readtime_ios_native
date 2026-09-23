package com.fatties.readtime.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Alarm
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.outlined.TrackChanges
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavHostController
import com.fatties.readtime.R
import com.fatties.readtime.data.Book
import com.fatties.readtime.data.BookStatus
import com.fatties.readtime.data.JournalEntry
import com.fatties.readtime.data.ReadingActivity
import com.fatties.readtime.data.ReadingState
import com.fatties.readtime.data.ReadingStore
import com.fatties.readtime.ui.Dates
import com.fatties.readtime.ui.Routes
import com.fatties.readtime.ui.components.AdBanner
import com.fatties.readtime.ui.components.BookCover
import com.fatties.readtime.ui.components.CardTitle
import com.fatties.readtime.ui.components.CoverImage
import com.fatties.readtime.ui.components.GoalBadge
import com.fatties.readtime.ui.components.ReadTimeCard
import com.fatties.readtime.ui.components.ReadTimeProgress
import com.fatties.readtime.ui.components.SecondaryText
import com.fatties.readtime.ui.components.SectionHeader
import com.fatties.readtime.ui.theme.ReadTimeTheme
import java.time.LocalDate
import kotlin.math.roundToInt

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(store: ReadingStore, navController: NavHostController) {
    val state by store.state.collectAsStateWithLifecycle()
    var showingBookPicker by remember { mutableStateOf(false) }

    Scaffold(
        containerColor = ReadTimeTheme.colors.background,
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.s_home), fontWeight = FontWeight.Bold) },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = ReadTimeTheme.colors.background,
                    titleContentColor = ReadTimeTheme.colors.text,
                ),
                actions = {
                    IconButton(onClick = { navController.navigate(Routes.SETTINGS) }) {
                        Icon(
                            Icons.Default.Settings,
                            contentDescription = stringResource(R.string.s_settings),
                            tint = ReadTimeTheme.colors.text,
                        )
                    }
                },
            )
        },
        floatingActionButton = { ReadNowButton(state, navController) { showingBookPicker = true } },
    ) { padding ->
        LazyColumn(
            modifier = Modifier.fillMaxWidth(),
            contentPadding = PaddingValues(
                start = 20.dp,
                end = 20.dp,
                top = padding.calculateTopPadding() + 8.dp,
                bottom = 96.dp,
            ),
            verticalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            item { AdBanner() }

            item {
                SectionHeader(stringResource(R.string.s_recent_goals), Icons.Outlined.TrackChanges)
            }

            item {
                Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    DailyGoalCard(state)
                    state.activeBook?.let { ActiveBookGoalCard(it) }
                }
            }

            item {
                SectionHeader(stringResource(R.string.s_recent_activities), Icons.Default.Refresh)
            }

            item {
                LazyRow(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    items(state.activities.take(3)) { activity -> ActivityCard(activity) }
                }
            }

            item {
                JournalPreview(
                    entry = state.journalEntries.firstOrNull(),
                    count = state.journalEntries.size,
                    onClick = { navController.navigate(Routes.JOURNAL) },
                )
            }
        }
    }

    if (showingBookPicker) {
        BookPickerSheet(
            books = state.books.filter { it.status != BookStatus.FINISHED },
            onDismiss = { showingBookPicker = false },
            onSelect = { book ->
                showingBookPicker = false
                store.setSelectedBook(book.id)
                navController.navigate(Routes.session(book.id))
            },
        )
    }
}

/** The sheet that asks which book this session is for. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun BookPickerSheet(books: List<Book>, onDismiss: () -> Unit, onSelect: (Book) -> Unit) {
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = ReadTimeTheme.colors.background) {
        Text(
            stringResource(R.string.s_choose_a_book),
            style = MaterialTheme.typography.titleLarge,
            color = ReadTimeTheme.colors.text,
            modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp),
        )
        LazyColumn(
            contentPadding = PaddingValues(20.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            items(books, key = { it.id }) { book ->
                ReadTimeCard(modifier = Modifier.clickable { onSelect(book) }, padding = 14.dp) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                        BookCover(book, 54.dp, 81.dp)
                        Column(Modifier.weight(1f)) {
                            CardTitle(book.title)
                            Spacer(Modifier.height(4.dp))
                            SecondaryText(book.author)
                        }
                        Icon(Icons.Default.PlayArrow, contentDescription = null, tint = ReadTimeTheme.colors.purple)
                    }
                }
            }
        }
    }
}

@Composable
private fun ReadNowButton(state: ReadingState, navController: NavHostController, onPickBook: () -> Unit) {
    val activeBook = state.activeBook
    if (activeBook != null && state.activeSessionBookID == activeBook.id) {
        ResumeButton(activeBook, onClick = { navController.navigate(Routes.session(activeBook.id)) })
    } else {
        Button(
            onClick = onPickBook,
            shape = CircleShape,
            colors = ButtonDefaults.buttonColors(containerColor = ReadTimeTheme.colors.purple),
            contentPadding = PaddingValues(horizontal = 20.dp, vertical = 15.dp),
        ) {
            Icon(Icons.Default.PlayArrow, contentDescription = null)
            Spacer(Modifier.width(8.dp))
            Text(stringResource(R.string.s_read_now), style = MaterialTheme.typography.titleMedium)
        }
    }
}

/** The pill that resumes a session in progress, filled to the book's progress. */
@Composable
private fun ResumeButton(book: Book, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .clip(CircleShape)
            .background(ReadTimeTheme.colors.purple.copy(alpha = 0.55f))
            .clickable(onClick = onClick),
    ) {
        Box(
            Modifier
                .matchParentSize()
                .clip(CircleShape),
        ) {
            Box(
                Modifier
                    .fillMaxWidth(book.progress)
                    .height(200.dp)
                    .background(ReadTimeTheme.colors.purple),
            )
        }
        Row(
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Column {
                Text(
                    stringResource(R.string.s_resume),
                    style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.Medium),
                    color = Color.White,
                )
                Text(
                    book.title,
                    style = MaterialTheme.typography.bodySmall,
                    color = Color.White,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    stringResource(R.string.s_page_n_of_n, book.currentPage, book.totalPages),
                    style = MaterialTheme.typography.labelSmall,
                    color = Color.White.copy(alpha = 0.7f),
                )
            }
            Text(
                "${(book.progress * 100).roundToInt()}%",
                style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.SemiBold),
                color = Color.White,
            )
        }
    }
}

@Composable
private fun DailyGoalCard(state: ReadingState) {
    val context = LocalContext.current
    ReadTimeCard {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Default.Alarm, contentDescription = null, tint = ReadTimeTheme.colors.purple)
            Spacer(Modifier.width(8.dp))
            CardTitle(
                stringResource(R.string.s_n_min, state.dailyGoal),
                color = ReadTimeTheme.colors.purple,
                modifier = Modifier.weight(1f),
            )
            GoalBadge(
                state.routine?.let { GoalFormat.daysLabel(context, it.weekdays.toSet()) }
                    ?: stringResource(R.string.s_every_day)
            )
        }
        Spacer(Modifier.height(14.dp))

        val today = LocalDate.now()
        SecondaryText(
            when {
                state.routineHasEnded -> stringResource(R.string.s_your_routine_has_ended_create_a_new_goal_in_the_goals_tab)
                state.isScheduled(today) -> stringResource(R.string.s_today_n_of_n_minutes, state.minutesToday, state.dailyGoal)
                state.minutesToday >= state.dailyGoal ->
                    stringResource(R.string.s_rest_day_but_you_still_read_n_minutes_nice, state.minutesToday)

                else -> stringResource(R.string.s_rest_day_today_you_ve_read_n_minutes, state.minutesToday)
            }
        )

        Spacer(Modifier.height(14.dp))
        ReadTimeProgress(state.minutesToday.toFloat() / state.dailyGoal.coerceAtLeast(1))
        Spacer(Modifier.height(14.dp))
        WeekTracker(state)
    }
}

/** Monday to Sunday of this week, with a check on each day the daily goal was met. */
@Composable
fun WeekTracker(
    state: ReadingState,
    todayColor: Color = ReadTimeTheme.colors.purple,
    tiled: Boolean = false,
) {
    val context = LocalContext.current
    val today = LocalDate.now()
    Row(horizontalArrangement = Arrangement.spacedBy(if (tiled) 6.dp else 5.dp)) {
        state.currentWeekDays.forEach { day ->
            val isToday = day == today
            val scheduled = state.isScheduled(day)
            val goalMet = state.minutesRead(day) >= state.dailyGoal
            val color = if (isToday) todayColor else ReadTimeTheme.colors.purple
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(5.dp),
                modifier = Modifier
                    .weight(1f)
                    .clip(RoundedCornerShape(10.dp))
                    .background(
                        when {
                            isToday -> todayColor.copy(alpha = if (tiled) 0.12f else 0.07f)
                            tiled -> ReadTimeTheme.colors.background
                            else -> Color.Transparent
                        }
                    )
                    .then(
                        if (isToday) Modifier.border(1.dp, todayColor, RoundedCornerShape(10.dp)) else Modifier
                    )
                    .padding(vertical = if (tiled) 9.dp else 7.dp),
            ) {
                Text(
                    Dates.pattern(context, "EEE", day),
                    style = MaterialTheme.typography.labelSmall,
                    color = if (isToday) todayColor else ReadTimeTheme.colors.text,
                )
                Text(
                    Dates.pattern(context, "d", day),
                    style = MaterialTheme.typography.bodySmall,
                    color = if (isToday) todayColor else ReadTimeTheme.colors.secondaryText,
                )
                Box(Modifier.height(26.dp), contentAlignment = Alignment.Center) {
                    // Reading the goal amount counts even on a day outside the routine.
                    if (scheduled || goalMet) {
                        Icon(
                            if (goalMet) Icons.Default.CheckCircle else Icons.Default.RadioButtonUnchecked,
                            contentDescription = stringResource(
                                if (goalMet) R.string.s_goal_met else R.string.s_goal_not_met
                            ),
                            tint = color.copy(alpha = if (day.isAfter(today)) 0.4f else 1f),
                        )
                    } else {
                        // Not part of the routine: a quiet dot instead of a goal circle.
                        Box(
                            Modifier
                                .size(18.dp)
                                .clip(CircleShape)
                                .background(ReadTimeTheme.colors.secondaryText.copy(alpha = 0.25f))
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun ActiveBookGoalCard(book: Book) {
    ReadTimeCard {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            BookCover(book, 50.dp, 75.dp)
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(7.dp)) {
                CardTitle(book.title, modifier = Modifier.fillMaxWidth())
                SecondaryText(stringResource(R.string.s_page_n_of_n, book.currentPage, book.totalPages))
                ReadTimeProgress(book.progress)
            }
            Box(
                modifier = Modifier
                    .clip(CircleShape)
                    .background(ReadTimeTheme.colors.green.copy(alpha = 0.10f))
                    .padding(12.dp),
            ) {
                Text(
                    "${(book.progress * 100).roundToInt()}%",
                    style = MaterialTheme.typography.titleMedium,
                    color = ReadTimeTheme.colors.green,
                )
            }
        }
    }
}

@Composable
private fun ActivityCard(activity: ReadingActivity) {
    val context = LocalContext.current
    ReadTimeCard(modifier = Modifier.width(170.dp), padding = 12.dp) {
        SecondaryText(Dates.activityLabel(context, activity.date))
        Spacer(Modifier.height(10.dp))
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Icon(Icons.Default.Schedule, contentDescription = null, tint = ReadTimeTheme.colors.text)
            CardTitle(pluralStringResource(R.plurals.s_n_mins, activity.minutes, activity.minutes))
        }
        Spacer(Modifier.height(10.dp))
        // 2:3, the usual book cover shape.
        CoverImage(
            coverName = activity.coverName,
            coverURL = activity.coverURL,
            modifier = Modifier
                .align(Alignment.CenterHorizontally)
                .size(120.dp, 180.dp)
                .clip(RoundedCornerShape(6.dp)),
        )
        Spacer(Modifier.height(10.dp))
        Text(
            activity.bookTitle,
            style = MaterialTheme.typography.bodySmall,
            color = ReadTimeTheme.colors.secondaryText,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

@Composable
private fun JournalPreview(entry: JournalEntry?, count: Int, onClick: () -> Unit) {
    ReadTimeCard(modifier = Modifier.clickable(onClick = onClick)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Default.Edit, contentDescription = null, tint = ReadTimeTheme.colors.text)
            Spacer(Modifier.width(8.dp))
            CardTitle(stringResource(R.string.s_reading_journal_2), modifier = Modifier.weight(1f))
            if (count > 0) {
                Text(
                    pluralStringResource(R.plurals.s_n_entries, count, count),
                    style = MaterialTheme.typography.bodySmall,
                    color = ReadTimeTheme.colors.secondaryText,
                )
            }
            Icon(
                Icons.AutoMirrored.Filled.KeyboardArrowRight,
                contentDescription = null,
                tint = ReadTimeTheme.colors.secondaryText,
            )
        }
        Spacer(Modifier.height(8.dp))
        if (entry != null) {
            Text(
                entry.text,
                style = MaterialTheme.typography.bodyMedium,
                color = ReadTimeTheme.colors.secondaryText,
                maxLines = 3,
                overflow = TextOverflow.Ellipsis,
            )
            if (entry.bookTitle.isNotEmpty()) {
                Spacer(Modifier.height(6.dp))
                Text(
                    entry.bookTitle,
                    style = MaterialTheme.typography.labelSmall,
                    color = ReadTimeTheme.colors.purple,
                )
            }
        } else {
            SecondaryText(stringResource(R.string.s_capture_your_thoughts_about_what_you_re_reading))
        }
    }
}

/** Shared goal wording, the iOS `GoalFormat`. */
object GoalFormat {
    /** Monday-first weekday numbers, the order the app shows a week in. */
    val mondayFirstWeekdays = listOf(2, 3, 4, 5, 6, 7, 1)

    fun weekdayName(weekday: Int): String = Dates.shortWeekdays()[weekday - 1]

    fun daysLabel(context: android.content.Context, weekdays: Set<Int>): String {
        if (weekdays.size == 7) return context.getString(R.string.s_every_day)
        return mondayFirstWeekdays.filter { weekdays.contains(it) }.joinToString(", ") { weekdayName(it) }
    }

    fun minutesLabel(context: android.content.Context, minutes: Int): String =
        if (minutes >= 60 && minutes % 60 == 0) {
            context.resources.getQuantityString(R.plurals.s_n_hours, minutes / 60, minutes / 60)
        } else {
            context.getString(R.string.s_n_min, minutes)
        }

    fun durationLabel(context: android.content.Context, weeks: Int): String =
        if (weeks == 4) context.getString(R.string.s_1_month)
        else context.resources.getQuantityString(R.plurals.s_n_weeks, weeks, weeks)

    fun startLabel(context: android.content.Context, date: LocalDate): String = Dates.startLabel(context, date)
}

package com.fatties.readtime.ui.screens

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.MenuBook
import androidx.compose.material.icons.filled.StopCircle
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.ShowChart
import androidx.compose.material.icons.outlined.TrackChanges
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavHostController
import com.fatties.readtime.R
import com.fatties.readtime.data.AdManager
import com.fatties.readtime.data.AppleDate
import com.fatties.readtime.data.Book
import com.fatties.readtime.data.ReadingStore
import com.fatties.readtime.data.iosWeekday
import com.fatties.readtime.ui.Dates
import com.fatties.readtime.ui.components.BookCover
import com.fatties.readtime.ui.components.CardTitle
import com.fatties.readtime.ui.components.GoalBadge
import com.fatties.readtime.ui.components.ReadTimeCard
import com.fatties.readtime.ui.components.ReadTimeProgress
import com.fatties.readtime.ui.components.SecondaryText
import com.fatties.readtime.ui.theme.ReadTimeTheme
import kotlinx.coroutines.delay
import kotlin.math.max
import kotlin.math.roundToInt

private enum class SessionStage { READING, FINISH, SUMMARY }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReadingSessionScreen(store: ReadingStore, navController: NavHostController, bookID: String) {
    val state by store.state.collectAsStateWithLifecycle()
    val book = state.book(bookID)
    var stage by remember { mutableStateOf(SessionStage.READING) }
    var startedAt by remember { mutableStateOf(AppleDate.now()) }
    var elapsed by remember { mutableLongStateOf(0L) }
    var savedSeconds by remember { mutableLongStateOf(0L) }
    val activity = LocalContext.current as? android.app.Activity

    // Resume the session already in progress, or start a new one.
    LaunchedEffect(bookID) {
        val existing = state.activeSessionStartedAt
        if (existing != null && state.activeSessionBookID == bookID) {
            startedAt = existing
        } else {
            startedAt = AppleDate.now()
            store.startSession(bookID)
        }
    }

    LaunchedEffect(startedAt, stage) {
        while (stage == SessionStage.READING) {
            elapsed = max(0.0, AppleDate.now() - startedAt).toLong()
            delay(1000)
        }
    }

    if (book == null) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Text(stringResource(R.string.s_book_unavailable), style = MaterialTheme.typography.titleLarge)
        }
        return
    }

    when (stage) {
        SessionStage.READING -> ReadingStageScreen(
            book = book,
            elapsed = elapsed,
            onBack = { navController.popBackStack() },
            onEnd = {
                savedSeconds = max(0.0, AppleDate.now() - startedAt).toLong()
                stage = SessionStage.FINISH
            },
        )

        SessionStage.FINISH -> FinishSessionScreen(
            book = book,
            seconds = savedSeconds,
            onFinish = { page, journal ->
                store.completeSession(bookID, savedSeconds.toDouble(), page, journal)
                store.clearSession()
                // The session is saved first; the ad (if one is ready) plays before the summary.
                AdManager.showInterstitial(activity) { stage = SessionStage.SUMMARY }
            },
        )

        SessionStage.SUMMARY -> GoalsUpdatedScreen(
            store = store,
            bookID = bookID,
            onConfirm = { navController.popBackStack() },
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ReadingStageScreen(book: Book, elapsed: Long, onBack: () -> Unit, onEnd: () -> Unit) {
    Scaffold(
        containerColor = ReadTimeTheme.colors.background,
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.s_reading_session), fontWeight = FontWeight.SemiBold) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.s_back))
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = ReadTimeTheme.colors.background,
                    titleContentColor = ReadTimeTheme.colors.text,
                    navigationIconContentColor = ReadTimeTheme.colors.text,
                ),
            )
        },
    ) { padding ->
        LazyColumn(
            contentPadding = PaddingValues(
                start = 20.dp,
                end = 20.dp,
                top = padding.calculateTopPadding() + 8.dp,
                bottom = 32.dp,
            ),
            verticalArrangement = Arrangement.spacedBy(26.dp),
        ) {
            item {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(14.dp),
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(14.dp))
                        .background(ReadTimeTheme.colors.card)
                        .border(1.dp, ReadTimeTheme.colors.purple, RoundedCornerShape(14.dp))
                        .padding(22.dp),
                ) {
                    BookCover(book, 170.dp, 255.dp)
                    Text(
                        book.title,
                        style = MaterialTheme.typography.titleLarge,
                        color = ReadTimeTheme.colors.text,
                        textAlign = TextAlign.Center,
                    )
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Icon(
                            Icons.Default.MenuBook,
                            contentDescription = null,
                            tint = ReadTimeTheme.colors.secondaryText,
                            modifier = Modifier.size(16.dp),
                        )
                        SecondaryText(stringResource(R.string.s_s_n_pages, book.author, book.totalPages))
                    }
                    Text(
                        clockText(elapsed),
                        fontSize = 52.sp,
                        fontWeight = FontWeight.Bold,
                        color = ReadTimeTheme.colors.purple,
                        modifier = Modifier.padding(top = 18.dp),
                    )
                    OutlinedButton(onClick = onEnd, shape = CircleShape) {
                        Icon(Icons.Default.StopCircle, contentDescription = null, tint = ReadTimeTheme.colors.purple)
                        Spacer(Modifier.width(8.dp))
                        Text(stringResource(R.string.s_end_session), color = ReadTimeTheme.colors.purple)
                    }
                }
            }

            item { HorizontalDivider(color = ReadTimeTheme.colors.secondaryText.copy(alpha = 0.2f)) }

            item {
                Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Icon(Icons.Outlined.TrackChanges, contentDescription = null, tint = ReadTimeTheme.colors.text)
                        CardTitle(stringResource(R.string.s_related_goals))
                    }
                    ReadTimeCard {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Column(Modifier.weight(1f)) {
                                CardTitle(stringResource(R.string.s_finish_s, book.title))
                                Spacer(Modifier.height(3.dp))
                                SecondaryText(stringResource(R.string.s_page_n_of_n, book.currentPage, book.totalPages))
                            }
                            GoalBadge("${(book.progress * 100).roundToInt()}%")
                        }
                        Spacer(Modifier.height(14.dp))
                        ReadTimeProgress(book.progress, color = ReadTimeTheme.colors.purple)
                    }
                }
            }
        }
    }
}

@Composable
private fun FinishSessionScreen(book: Book, seconds: Long, onFinish: (Int, String) -> Unit) {
    var currentPage by remember { mutableIntStateOf((book.currentPage + 1).coerceIn(1, book.totalPages.coerceAtLeast(1))) }
    var journal by remember { mutableStateOf("") }
    val minutes = max(1, (seconds / 60.0).roundToInt())

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .background(ReadTimeTheme.colors.background),
        contentPadding = PaddingValues(20.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        item {
            Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
                Box(
                    modifier = Modifier
                        .size(88.dp)
                        .clip(CircleShape)
                        .background(ReadTimeTheme.colors.purple.copy(alpha = 0.08f)),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(Icons.Default.Check, contentDescription = null, tint = ReadTimeTheme.colors.purple)
                }
                Spacer(Modifier.height(14.dp))
                Text(
                    stringResource(R.string.s_finish_session),
                    style = MaterialTheme.typography.headlineSmall,
                    color = ReadTimeTheme.colors.purple,
                )
            }
        }

        item {
            ReadTimeCard {
                Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                    BookCover(book, 64.dp, 96.dp)
                    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        CardTitle(book.title)
                        SecondaryText(book.author)
                        Text(
                            stringResource(R.string.s_n_min, minutes),
                            style = MaterialTheme.typography.titleLarge,
                            color = ReadTimeTheme.colors.purple,
                        )
                    }
                }
            }
        }

        item {
            ReadTimeCard {
                CardTitle(stringResource(R.string.s_save_your_current_page))
                Spacer(Modifier.height(6.dp))
                SecondaryText(stringResource(R.string.s_keep_your_progress_accurate_for_next_time))
                Spacer(Modifier.height(12.dp))
                StepperRow(
                    label = stringResource(R.string.s_page_n_of_n, currentPage, book.totalPages),
                    onDecrement = { currentPage = (currentPage - 1).coerceAtLeast(1) },
                    onIncrement = { currentPage = (currentPage + 1).coerceAtMost(book.totalPages.coerceAtLeast(1)) },
                )
            }
        }

        item {
            ReadTimeCard {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Icon(Icons.Default.Edit, contentDescription = null, tint = ReadTimeTheme.colors.text)
                    CardTitle(stringResource(R.string.s_journal_your_thoughts))
                }
                Spacer(Modifier.height(10.dp))
                OutlinedTextField(
                    value = journal,
                    onValueChange = { journal = it },
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(150.dp),
                )
                Spacer(Modifier.height(6.dp))
                Text(
                    stringResource(R.string.s_anything_you_want_to_remember_keep_it_short_and_clean),
                    style = MaterialTheme.typography.bodySmall,
                    color = ReadTimeTheme.colors.secondaryText,
                )
            }
        }

        item {
            Button(
                onClick = { onFinish(currentPage, journal) },
                shape = CircleShape,
                colors = ButtonDefaults.buttonColors(containerColor = ReadTimeTheme.colors.purple),
                modifier = Modifier
                    .fillMaxWidth()
                    .height(54.dp),
            ) {
                Icon(Icons.Default.Check, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text(stringResource(R.string.s_finish_session))
            }
        }
    }
}

/** Shown after a session is saved: how today's reading moved the daily, book, and yearly goals. */
@Composable
private fun GoalsUpdatedScreen(store: ReadingStore, bookID: String, onConfirm: () -> Unit) {
    val state by store.state.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val dailyGoalMet = state.minutesToday >= state.dailyGoal

    Scaffold(
        containerColor = ReadTimeTheme.colors.background,
        bottomBar = {
            Button(
                onClick = onConfirm,
                shape = CircleShape,
                colors = ButtonDefaults.buttonColors(containerColor = ReadTimeTheme.colors.purple),
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp, vertical = 8.dp)
                    .height(54.dp),
            ) { Text(stringResource(R.string.s_confirm)) }
        },
    ) { padding ->
        LazyColumn(
            contentPadding = PaddingValues(
                start = 20.dp,
                end = 20.dp,
                top = padding.calculateTopPadding() + 24.dp,
                bottom = padding.calculateBottomPadding() + 20.dp,
            ),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            item {
                Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
                    Box(
                        modifier = Modifier
                            .size(112.dp)
                            .clip(CircleShape)
                            .background(ReadTimeTheme.colors.green.copy(alpha = 0.15f)),
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(Icons.Default.Check, contentDescription = null, tint = ReadTimeTheme.colors.green)
                    }
                    Spacer(Modifier.height(10.dp))
                    Text(
                        stringResource(R.string.s_goals_updated),
                        style = MaterialTheme.typography.headlineSmall,
                        color = ReadTimeTheme.colors.green,
                    )
                    Spacer(Modifier.height(6.dp))
                    Text(
                        stringResource(
                            if (dailyGoalMet) R.string.s_you_have_made_good_progress_on_your_goals
                            else R.string.s_every_session_counts_keep_going
                        ),
                        style = MaterialTheme.typography.bodyLarge,
                        color = ReadTimeTheme.colors.secondaryText,
                        textAlign = TextAlign.Center,
                    )
                }
            }

            item {
                ReadTimeCard {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Icon(
                            Icons.Outlined.CalendarMonth,
                            contentDescription = null,
                            tint = ReadTimeTheme.colors.secondaryText,
                            modifier = Modifier.size(16.dp),
                        )
                        SecondaryText(stringResource(R.string.s_routine))
                    }
                    Spacer(Modifier.height(10.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        state.currentWeekDays.forEach { day ->
                            val scheduled = state.routine?.weekdays?.contains(day.iosWeekday) ?: true
                            Text(
                                Dates.pattern(context, "EEE", day),
                                style = MaterialTheme.typography.labelSmall,
                                color = if (scheduled) ReadTimeTheme.colors.purple
                                else ReadTimeTheme.colors.secondaryText.copy(alpha = 0.6f),
                                textAlign = TextAlign.Center,
                                maxLines = 1,
                                modifier = Modifier
                                    .weight(1f)
                                    .border(
                                        1.dp,
                                        if (scheduled) ReadTimeTheme.colors.purple.copy(alpha = 0.35f)
                                        else ReadTimeTheme.colors.secondaryText.copy(alpha = 0.2f),
                                        CircleShape,
                                    )
                                    .padding(vertical = 6.dp),
                            )
                        }
                    }

                    Spacer(Modifier.height(14.dp))
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Icon(
                            Icons.Outlined.ShowChart,
                            contentDescription = null,
                            tint = ReadTimeTheme.colors.secondaryText,
                            modifier = Modifier.size(16.dp),
                        )
                        SecondaryText(stringResource(R.string.s_weekly_tracking))
                    }
                    Spacer(Modifier.height(10.dp))
                    WeekTracker(state, todayColor = ReadTimeTheme.colors.green, tiled = true)
                }
            }

            item {
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    GoalRingCard(
                        progress = state.minutesToday.toFloat() / state.dailyGoal.coerceAtLeast(1),
                        ringLabel = "${state.minutesToday}/${state.dailyGoal}",
                        title = stringResource(R.string.s_n_min, state.dailyGoal),
                        caption = stringResource(R.string.s_read_today),
                        modifier = Modifier.weight(1f),
                    )
                    GoalRingCard(
                        progress = state.finishedBooks.toFloat() / state.yearlyBookGoal.coerceAtLeast(1),
                        ringLabel = "${state.finishedBooks}/${state.yearlyBookGoal}",
                        title = androidx.compose.ui.res.pluralStringResource(
                            R.plurals.s_n_books,
                            state.yearlyBookGoal,
                            state.yearlyBookGoal,
                        ),
                        caption = stringResource(R.string.s_yearly_goal),
                        modifier = Modifier.weight(1f),
                    )
                }
            }
        }
    }
}

@Composable
private fun GoalRingCard(
    progress: Float,
    ringLabel: String,
    title: String,
    caption: String,
    modifier: Modifier = Modifier,
) {
    val animated by animateFloatAsState(progress.coerceIn(0f, 1f), label = "ring")
    ReadTimeCard(modifier = modifier, padding = 14.dp) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Box(Modifier.size(56.dp), contentAlignment = Alignment.Center) {
                val track = ReadTimeTheme.colors.secondaryText.copy(alpha = 0.2f)
                val fill = ReadTimeTheme.colors.green
                androidx.compose.foundation.Canvas(Modifier.fillMaxSize()) {
                    val stroke = Stroke(width = 6.dp.toPx(), cap = StrokeCap.Round)
                    val inset = stroke.width / 2
                    val arcSize = Size(size.width - stroke.width, size.height - stroke.width)
                    drawCircle(color = track, radius = (size.minDimension - stroke.width) / 2, style = stroke)
                    drawArc(
                        color = fill,
                        startAngle = -90f,
                        sweepAngle = 360f * animated,
                        useCenter = false,
                        topLeft = androidx.compose.ui.geometry.Offset(inset, inset),
                        size = arcSize,
                        style = stroke,
                    )
                }
                Text(
                    ringLabel,
                    style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold),
                    color = ReadTimeTheme.colors.green,
                    maxLines = 1,
                )
            }
            Column {
                CardTitle(title)
                Spacer(Modifier.height(2.dp))
                Text(
                    caption,
                    style = MaterialTheme.typography.bodySmall,
                    color = ReadTimeTheme.colors.secondaryText,
                )
            }
        }
    }
}

private fun clockText(seconds: Long): String {
    val total = max(0L, seconds)
    return "%02d:%02d:%02d".format(total / 3600, (total % 3600) / 60, total % 60)
}

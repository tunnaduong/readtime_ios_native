package com.fatties.readtime.ui.screens

import androidx.compose.foundation.background
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Alarm
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.LibraryBooks
import androidx.compose.material.icons.filled.NotificationsActive
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.icons.filled.WbSunny
import androidx.compose.material.icons.outlined.TrackChanges
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.TimePickerState
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavHostController
import com.fatties.readtime.R
import com.fatties.readtime.data.AppleDate
import com.fatties.readtime.data.ReadingState
import com.fatties.readtime.data.ReadingStore
import com.fatties.readtime.ui.Dates
import com.fatties.readtime.ui.Routes
import com.fatties.readtime.ui.components.AdBanner
import com.fatties.readtime.ui.components.CardTitle
import com.fatties.readtime.ui.components.GoalBadge
import com.fatties.readtime.ui.components.ReadTimeCard
import com.fatties.readtime.ui.components.ReadTimeProgress
import com.fatties.readtime.ui.components.SecondaryText
import com.fatties.readtime.ui.theme.ReadTimeTheme
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GoalsScreen(store: ReadingStore, navController: NavHostController) {
    val state by store.state.collectAsStateWithLifecycle()
    val context = LocalContext.current
    var menuOpen by remember { mutableStateOf(false) }

    Scaffold(
        containerColor = ReadTimeTheme.colors.background,
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.s_goals), fontWeight = FontWeight.Bold) },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = ReadTimeTheme.colors.background,
                    titleContentColor = ReadTimeTheme.colors.text,
                ),
                actions = {
                    Box {
                        IconButton(onClick = { menuOpen = true }) {
                            Icon(
                                Icons.Default.Add,
                                contentDescription = stringResource(R.string.s_new_goal),
                                tint = ReadTimeTheme.colors.text,
                            )
                        }
                        NewGoalMenu(
                            expanded = menuOpen,
                            onDismiss = { menuOpen = false },
                            onSelect = { kind ->
                                menuOpen = false
                                navController.navigate(Routes.createGoal(kind))
                            },
                        )
                    }
                },
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

            item { SecondaryText(stringResource(R.string.s_make_time_for_the_books_that_matter)) }

            item {
                RoutineGoalCard(state) { kind -> navController.navigate(Routes.createGoal(kind)) }
            }

            item {
                GoalSummaryCard(
                    title = stringResource(R.string.s_daily_reading),
                    subtitle = stringResource(R.string.s_n_of_n_minutes_today, state.minutesToday, state.dailyGoal),
                    icon = Icons.Default.Timer,
                    progress = state.minutesToday.toFloat() / state.dailyGoal.coerceAtLeast(1),
                    value = stringResource(R.string.s_n_min, state.dailyGoal),
                )
            }

            item {
                GoalSummaryCard(
                    title = stringResource(R.string.s_yearly_book_goal),
                    subtitle = stringResource(R.string.s_n_of_n_books_finished, state.finishedBooks, state.yearlyBookGoal),
                    icon = Icons.Default.LibraryBooks,
                    progress = state.finishedBooks.toFloat() / state.yearlyBookGoal.coerceAtLeast(1),
                    value = pluralStringResource(R.plurals.s_n_books, state.yearlyBookGoal, state.yearlyBookGoal),
                )
            }

            item {
                ReadTimeCard {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Default.Tune, contentDescription = null, tint = ReadTimeTheme.colors.text)
                        Spacer(Modifier.width(8.dp))
                        CardTitle(stringResource(R.string.s_set_your_goals))
                    }
                    Spacer(Modifier.height(12.dp))
                    StepperRow(
                        label = stringResource(R.string.s_daily_goal_n_minutes, state.dailyGoal),
                        onDecrement = { store.setDailyGoal((state.dailyGoal - 5).coerceAtLeast(5)) },
                        onIncrement = { store.setDailyGoal((state.dailyGoal + 5).coerceAtMost(600)) },
                    )
                    Spacer(Modifier.height(8.dp))
                    StepperRow(
                        label = pluralStringResource(R.plurals.s_yearly_goal_n_books, state.yearlyBookGoal, state.yearlyBookGoal),
                        onDecrement = { store.setYearlyBookGoal((state.yearlyBookGoal - 1).coerceAtLeast(1)) },
                        onIncrement = { store.setYearlyBookGoal((state.yearlyBookGoal + 1).coerceAtMost(100)) },
                    )
                }
            }

            item { ReminderCard(state, store) }
        }
    }
}

@Composable
fun NewGoalMenu(expanded: Boolean, onDismiss: () -> Unit, onSelect: (String) -> Unit) {
    DropdownMenu(expanded = expanded, onDismissRequest = onDismiss) {
        DropdownMenuItem(
            text = { Text(stringResource(R.string.s_daily_goal)) },
            leadingIcon = { Icon(Icons.Default.WbSunny, contentDescription = null) },
            onClick = { onSelect("daily") },
        )
        DropdownMenuItem(
            text = { Text(stringResource(R.string.s_custom_goal)) },
            leadingIcon = { Icon(Icons.Default.CalendarMonth, contentDescription = null) },
            onClick = { onSelect("custom") },
        )
    }
}

/** The current reading routine, or a prompt to create one. */
@Composable
private fun RoutineGoalCard(state: ReadingState, onCreate: (String) -> Unit) {
    val context = LocalContext.current
    var menuOpen by remember { mutableStateOf(false) }

    ReadTimeCard {
        val routine = state.routine
        if (routine != null) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Default.Alarm, contentDescription = null, tint = ReadTimeTheme.colors.purple)
                Spacer(Modifier.width(8.dp))
                CardTitle(
                    stringResource(R.string.s_n_min_day, state.dailyGoal),
                    color = ReadTimeTheme.colors.purple,
                    modifier = Modifier.weight(1f),
                )
                GoalBadge(GoalFormat.daysLabel(context, routine.weekdays.toSet()))
            }
            Spacer(Modifier.height(10.dp))
            Text(
                if (state.routineHasEnded) {
                    stringResource(R.string.s_ended_s, Dates.abbreviated(routine.lastDay))
                } else {
                    stringResource(
                        R.string.s_s_s_s,
                        GoalFormat.startLabel(context, routine.startDate.localDate()),
                        Dates.abbreviated(routine.lastDay),
                        GoalFormat.durationLabel(context, routine.weeks),
                    )
                },
                style = MaterialTheme.typography.bodySmall,
                color = ReadTimeTheme.colors.secondaryText,
            )
            Spacer(Modifier.height(12.dp))
            WeekTracker(state)
            Spacer(Modifier.height(6.dp))
            Box {
                TextButton(onClick = { menuOpen = true }) {
                    Icon(Icons.Default.Add, contentDescription = null, tint = ReadTimeTheme.colors.purple)
                    Spacer(Modifier.width(6.dp))
                    Text(stringResource(R.string.s_new_goal), color = ReadTimeTheme.colors.purple)
                }
                NewGoalMenu(
                    expanded = menuOpen,
                    onDismiss = { menuOpen = false },
                    onSelect = {
                        menuOpen = false
                        onCreate(it)
                    },
                )
            }
        } else {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Outlined.TrackChanges, contentDescription = null, tint = ReadTimeTheme.colors.text)
                Spacer(Modifier.width(8.dp))
                CardTitle(stringResource(R.string.s_build_a_reading_habit))
            }
            Spacer(Modifier.height(8.dp))
            SecondaryText(stringResource(R.string.s_choose_how_long_to_read_on_which_days_and_how_many_weeks_to))
            Spacer(Modifier.height(14.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Button(
                    onClick = { onCreate("daily") },
                    shape = CircleShape,
                    colors = ButtonDefaults.buttonColors(containerColor = ReadTimeTheme.colors.purple),
                    modifier = Modifier.weight(1f),
                ) { Text(stringResource(R.string.s_daily_goal)) }
                OutlinedButton(
                    onClick = { onCreate("custom") },
                    shape = CircleShape,
                    modifier = Modifier.weight(1f),
                ) { Text(stringResource(R.string.s_custom_goal), color = ReadTimeTheme.colors.purple) }
            }
        }
    }
}

@Composable
private fun GoalSummaryCard(
    title: String,
    subtitle: String,
    icon: ImageVector,
    progress: Float,
    value: String,
) {
    ReadTimeCard {
        Row(verticalAlignment = Alignment.Top) {
            Box(
                modifier = Modifier
                    .size(48.dp)
                    .clip(CircleShape)
                    .background(ReadTimeTheme.colors.purple.copy(alpha = 0.10f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(icon, contentDescription = null, tint = ReadTimeTheme.colors.purple)
            }
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                CardTitle(title)
                Spacer(Modifier.height(3.dp))
                SecondaryText(subtitle)
            }
            Text(
                value,
                style = MaterialTheme.typography.labelSmall,
                color = ReadTimeTheme.colors.purple,
            )
        }
        Spacer(Modifier.height(14.dp))
        ReadTimeProgress(progress, color = ReadTimeTheme.colors.purple)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ReminderCard(state: ReadingState, store: ReadingStore) {
    var pickingTime by remember { mutableStateOf(false) }
    val reminder = Dates.local(state.reminderTime)

    ReadTimeCard {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Default.NotificationsActive, contentDescription = null, tint = ReadTimeTheme.colors.text)
            Spacer(Modifier.width(8.dp))
            CardTitle(stringResource(R.string.s_gentle_reminder))
        }
        Spacer(Modifier.height(8.dp))
        SecondaryText(stringResource(R.string.s_choose_a_quiet_moment_to_return_to_your_book))
        Spacer(Modifier.height(12.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                stringResource(R.string.s_daily_reading_reminder),
                color = ReadTimeTheme.colors.text,
                modifier = Modifier.weight(1f),
            )
            Switch(
                checked = state.reminderEnabled,
                onCheckedChange = { store.setReminder(it) },
                colors = SwitchDefaults.colors(checkedTrackColor = ReadTimeTheme.colors.purple),
            )
        }
        if (state.reminderEnabled) {
            Spacer(Modifier.height(8.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    stringResource(R.string.s_remind_me_at),
                    color = ReadTimeTheme.colors.text,
                    modifier = Modifier.weight(1f),
                )
                TextButton(onClick = { pickingTime = true }) {
                    Text(Dates.time(reminder), color = ReadTimeTheme.colors.purple)
                }
            }
        }
    }

    if (pickingTime) {
        val pickerState = rememberTimePickerState(initialHour = reminder.hour, initialMinute = reminder.minute)
        TimePickerDialog(
            state = pickerState,
            onDismiss = { pickingTime = false },
            onConfirm = {
                val time = LocalDate.now().atTime(LocalTime.of(pickerState.hour, pickerState.minute))
                store.setReminder(enabled = true, at = AppleDate.of(time.atZone(ZoneId.systemDefault()).toInstant()))
                pickingTime = false
            },
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TimePickerDialog(state: TimePickerState, onDismiss: () -> Unit, onConfirm: () -> Unit) {
    androidx.compose.material3.AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.s_remind_me_at)) },
        text = { TimePicker(state = state) },
        confirmButton = { TextButton(onClick = onConfirm) { Text(stringResource(R.string.s_set)) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.s_cancel)) } },
    )
}

/** A label with − and + buttons, the iOS `Stepper`. */
@Composable
fun StepperRow(label: String, onDecrement: () -> Unit, onIncrement: () -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
        Text(label, color = ReadTimeTheme.colors.text, modifier = Modifier.weight(1f))
        OutlinedButton(onClick = onDecrement, shape = CircleShape, contentPadding = PaddingValues(0.dp), modifier = Modifier.size(36.dp)) {
            Text("−", color = ReadTimeTheme.colors.purple)
        }
        Spacer(Modifier.width(8.dp))
        OutlinedButton(onClick = onIncrement, shape = CircleShape, contentPadding = PaddingValues(0.dp), modifier = Modifier.size(36.dp)) {
            Text("+", color = ReadTimeTheme.colors.purple)
        }
    }
}

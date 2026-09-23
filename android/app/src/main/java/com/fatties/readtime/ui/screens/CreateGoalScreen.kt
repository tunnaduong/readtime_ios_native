package com.fatties.readtime.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Alarm
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.filled.EventAvailable
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.NotificationsActive
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavHostController
import com.fatties.readtime.R
import com.fatties.readtime.data.AppleDate
import com.fatties.readtime.data.ReadingRoutine
import com.fatties.readtime.data.ReadingStore
import com.fatties.readtime.data.iosWeekday
import com.fatties.readtime.ui.Dates
import com.fatties.readtime.ui.components.CardTitle
import com.fatties.readtime.ui.components.GoalBadge
import com.fatties.readtime.ui.components.ReadTimeCard
import com.fatties.readtime.ui.components.SecondaryText
import com.fatties.readtime.ui.theme.ReadTimeTheme
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/** The draft a goal is built from, the iOS `GoalDraft`. */
private data class GoalDraft(
    val minutes: Int = 15,
    val weekdays: Set<Int> = (1..7).toSet(),
    val weeks: Int = 4,
    val startDate: LocalDate = LocalDate.now(),
    val remind: Boolean = true,
) {
    fun routine(): ReadingRoutine = ReadingRoutine(
        weekdays = GoalFormat.mondayFirstWeekdays.filter { weekdays.contains(it) },
        startDate = AppleDate.of(startDate),
        weeks = weeks,
    )
}

private enum class Step { DAILY_SPEC, CUSTOM_DAYS, ROUTINE, PREVIEW }

/**
 * Daily goal: reading time and routine, then a preview.
 * Custom goal: days and reading time, then routine, then a preview.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CreateGoalScreen(store: ReadingStore, navController: NavHostController, kind: String) {
    val state by store.state.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val steps = remember(kind) {
        if (kind == "daily") listOf(Step.DAILY_SPEC, Step.PREVIEW)
        else listOf(Step.CUSTOM_DAYS, Step.ROUTINE, Step.PREVIEW)
    }
    var stepIndex by remember { mutableIntStateOf(0) }
    var draft by remember { mutableStateOf(GoalDraft(weekdays = if (kind == "daily") (1..7).toSet() else emptySet())) }
    val step = steps[stepIndex]

    Scaffold(
        containerColor = ReadTimeTheme.colors.background,
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        stringResource(
                            when (step) {
                                Step.DAILY_SPEC -> R.string.s_create_daily_goal
                                Step.CUSTOM_DAYS, Step.ROUTINE -> R.string.s_custom_read_goal
                                Step.PREVIEW -> R.string.s_goal_preview
                            }
                        ),
                        fontWeight = FontWeight.SemiBold,
                    )
                },
                navigationIcon = {
                    IconButton(onClick = { navController.popBackStack() }) {
                        Icon(Icons.Default.Close, contentDescription = stringResource(R.string.s_cancel))
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = ReadTimeTheme.colors.background,
                    titleContentColor = ReadTimeTheme.colors.text,
                    navigationIconContentColor = ReadTimeTheme.colors.text,
                ),
            )
        },
        bottomBar = {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp, vertical = 10.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                if (step == Step.PREVIEW) {
                    Button(
                        onClick = {
                            store.applyGoal(draft.minutes, draft.routine(), draft.remind)
                            navController.popBackStack()
                        },
                        shape = CircleShape,
                        colors = ButtonDefaults.buttonColors(containerColor = ReadTimeTheme.colors.purple),
                        modifier = Modifier
                            .weight(1f)
                            .height(50.dp),
                    ) { Text(stringResource(R.string.s_create_goal)) }
                } else {
                    OutlinedButton(
                        onClick = {
                            if (stepIndex == 0) navController.popBackStack() else stepIndex -= 1
                        },
                        shape = CircleShape,
                        modifier = Modifier
                            .weight(1f)
                            .height(50.dp),
                    ) { Text(stringResource(R.string.s_back), color = ReadTimeTheme.colors.purple) }
                    Button(
                        onClick = { stepIndex += 1 },
                        enabled = !(step == Step.CUSTOM_DAYS && draft.weekdays.isEmpty()),
                        shape = CircleShape,
                        colors = ButtonDefaults.buttonColors(containerColor = ReadTimeTheme.colors.purple),
                        modifier = Modifier
                            .weight(1f)
                            .height(50.dp),
                    ) { Text(stringResource(R.string.s_next)) }
                }
            }
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            when (step) {
                Step.DAILY_SPEC -> {
                    ReadPerDaySection(draft.minutes) { draft = draft.copy(minutes = it) }
                    RoutineSection(draft, Dates.time(Dates.local(state.reminderTime))) { draft = it }
                }

                Step.CUSTOM_DAYS -> {
                    WeekdaysSection(draft.weekdays) { draft = draft.copy(weekdays = it) }
                    ReadPerDaySection(draft.minutes) { draft = draft.copy(minutes = it) }
                }

                Step.ROUTINE -> RoutineSection(draft, Dates.time(Dates.local(state.reminderTime))) { draft = it }

                Step.PREVIEW -> GoalPreview(draft)
            }
        }
    }
}

/** A titled card that groups one step's choices. */
@Composable
private fun GoalSection(title: String, icon: ImageVector, content: @Composable () -> Unit) {
    ReadTimeCard {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(icon, contentDescription = null, tint = ReadTimeTheme.colors.text)
            Spacer(Modifier.width(8.dp))
            CardTitle(title)
        }
        Spacer(Modifier.height(12.dp))
        content()
    }
}

/** A selectable pill, the iOS `ChoiceChip`. */
@Composable
fun ChoiceChip(title: String, isSelected: Boolean, icon: ImageVector? = null, onClick: () -> Unit) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        modifier = Modifier
            .clip(CircleShape)
            .background(
                if (isSelected) ReadTimeTheme.colors.purple.copy(alpha = 0.14f)
                else ReadTimeTheme.colors.background
            )
            .border(
                1.dp,
                if (isSelected) ReadTimeTheme.colors.purple else ReadTimeTheme.colors.secondaryText.copy(alpha = 0.3f),
                CircleShape,
            )
            .clickable(onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 9.dp),
    ) {
        if (icon != null) {
            Icon(
                icon,
                contentDescription = null,
                tint = if (isSelected) ReadTimeTheme.colors.purple else ReadTimeTheme.colors.text,
                modifier = Modifier.size(16.dp),
            )
        }
        Text(
            title,
            style = MaterialTheme.typography.bodyMedium,
            color = if (isSelected) ReadTimeTheme.colors.purple else ReadTimeTheme.colors.text,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

/** Chips that wrap onto new rows, the iOS `FlowLayout`. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ChipFlow(content: @Composable () -> Unit) {
    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        content()
    }
}

@Composable
private fun ReadPerDaySection(minutes: Int, onChange: (Int) -> Unit) {
    val context = LocalContext.current
    val presets = listOf(15, 30, 60, 120)
    var asking by remember { mutableStateOf(false) }

    GoalSection(stringResource(R.string.s_read_per_day), Icons.Default.Schedule) {
        ChipFlow {
            presets.forEach { preset ->
                ChoiceChip(GoalFormat.minutesLabel(context, preset), minutes == preset) { onChange(preset) }
            }
            val isCustom = !presets.contains(minutes)
            ChoiceChip(
                title = if (isCustom) {
                    stringResource(R.string.s_custom_s, GoalFormat.minutesLabel(context, minutes))
                } else {
                    stringResource(R.string.s_custom)
                },
                isSelected = isCustom,
                icon = Icons.Default.Tune,
            ) { asking = true }
        }
    }

    if (asking) {
        NumberPrompt(
            title = stringResource(R.string.s_minutes_per_day),
            message = stringResource(R.string.s_enter_between_5_and_600_minutes),
            label = stringResource(R.string.s_minutes),
            initial = minutes,
            range = 5..600,
            onDismiss = { asking = false },
            onSet = {
                onChange(it)
                asking = false
            },
        )
    }
}

@Composable
private fun WeekdaysSection(weekdays: Set<Int>, onChange: (Set<Int>) -> Unit) {
    GoalSection(stringResource(R.string.s_selected_days_per_week), Icons.Default.CalendarMonth) {
        ChipFlow {
            GoalFormat.mondayFirstWeekdays.forEach { weekday ->
                ChoiceChip(GoalFormat.weekdayName(weekday), weekdays.contains(weekday)) {
                    onChange(if (weekdays.contains(weekday)) weekdays - weekday else weekdays + weekday)
                }
            }
        }
        if (weekdays.isEmpty()) {
            Spacer(Modifier.height(8.dp))
            Text(
                stringResource(R.string.s_choose_at_least_one_day),
                style = MaterialTheme.typography.bodySmall,
                color = ReadTimeTheme.colors.secondaryText,
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun RoutineSection(draft: GoalDraft, reminderTime: String, onChange: (GoalDraft) -> Unit) {
    val context = LocalContext.current
    val presets = listOf(1, 2, 4)
    var askingWeeks by remember { mutableStateOf(false) }
    var choosingStart by remember { mutableStateOf(false) }

    GoalSection(stringResource(R.string.s_maintain_routine_for), Icons.Default.EventAvailable) {
        ChipFlow {
            presets.forEach { weeks ->
                ChoiceChip(GoalFormat.durationLabel(context, weeks), draft.weeks == weeks) {
                    onChange(draft.copy(weeks = weeks))
                }
            }
            val isCustom = !presets.contains(draft.weeks)
            ChoiceChip(
                title = if (isCustom) {
                    stringResource(R.string.s_custom_s, GoalFormat.durationLabel(context, draft.weeks))
                } else {
                    stringResource(R.string.s_custom)
                },
                isSelected = isCustom,
                icon = Icons.Default.Tune,
            ) { askingWeeks = true }
        }

        Spacer(Modifier.height(14.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Default.Flag, contentDescription = null, tint = ReadTimeTheme.colors.text)
            Spacer(Modifier.width(8.dp))
            Text(stringResource(R.string.s_date_start), color = ReadTimeTheme.colors.text, modifier = Modifier.weight(1f))
            OutlinedButton(onClick = { choosingStart = true }, shape = RoundedCornerShape(10.dp)) {
                Icon(Icons.Default.DateRange, contentDescription = null, tint = ReadTimeTheme.colors.text)
                Spacer(Modifier.width(6.dp))
                Text(GoalFormat.startLabel(context, draft.startDate), color = ReadTimeTheme.colors.text)
            }
        }

        Spacer(Modifier.height(10.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Default.Notifications, contentDescription = null, tint = ReadTimeTheme.colors.text)
                    Spacer(Modifier.width(8.dp))
                    Text(stringResource(R.string.s_remind_me), color = ReadTimeTheme.colors.text)
                }
                Text(
                    stringResource(R.string.s_at_s_on_routine_days, reminderTime),
                    style = MaterialTheme.typography.bodySmall,
                    color = ReadTimeTheme.colors.secondaryText,
                )
            }
            Switch(
                checked = draft.remind,
                onCheckedChange = { onChange(draft.copy(remind = it)) },
                colors = SwitchDefaults.colors(checkedTrackColor = ReadTimeTheme.colors.purple),
            )
        }
    }

    if (askingWeeks) {
        NumberPrompt(
            title = stringResource(R.string.s_number_of_weeks),
            message = stringResource(R.string.s_enter_between_1_and_52_weeks),
            label = stringResource(R.string.s_weeks),
            initial = draft.weeks,
            range = 1..52,
            onDismiss = { askingWeeks = false },
            onSet = {
                onChange(draft.copy(weeks = it))
                askingWeeks = false
            },
        )
    }

    if (choosingStart) {
        val pickerState = rememberDatePickerState(
            initialSelectedDateMillis = draft.startDate.atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli(),
        )
        DatePickerDialog(
            onDismissRequest = { choosingStart = false },
            confirmButton = {
                TextButton(onClick = {
                    pickerState.selectedDateMillis?.let { millis ->
                        onChange(draft.copy(startDate = Instant.ofEpochMilli(millis).atZone(ZoneId.systemDefault()).toLocalDate()))
                    }
                    choosingStart = false
                }) { Text(stringResource(R.string.s_select_date)) }
            },
            dismissButton = {
                TextButton(onClick = { choosingStart = false }) { Text(stringResource(R.string.s_cancel)) }
            },
        ) {
            DatePicker(state = pickerState, title = { Text(stringResource(R.string.s_choose_start_day), Modifier.padding(16.dp)) })
        }
    }
}

@Composable
private fun NumberPrompt(
    title: String,
    message: String,
    label: String,
    initial: Int,
    range: IntRange,
    onDismiss: () -> Unit,
    onSet: (Int) -> Unit,
) {
    var text by remember { mutableStateOf(initial.toString()) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            Column {
                Text(message)
                Spacer(Modifier.height(10.dp))
                OutlinedTextField(
                    value = text,
                    onValueChange = { text = it.filter(Char::isDigit) },
                    label = { Text(label) },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    singleLine = true,
                )
            }
        },
        confirmButton = {
            TextButton(onClick = {
                text.toIntOrNull()?.let { onSet(it.coerceIn(range.first, range.last)) } ?: onDismiss()
            }) { Text(stringResource(R.string.s_set)) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.s_cancel)) } },
    )
}

@Composable
private fun GoalPreview(draft: GoalDraft) {
    val context = LocalContext.current
    val routine = draft.routine()
    // The week (Monday first) the routine starts in.
    val firstWeek = remember(draft.startDate) {
        val monday = draft.startDate.minusDays((draft.startDate.iosWeekday + 5) % 7L)
        (0..6).map { monday.plusDays(it.toLong()) }
    }

    ReadTimeCard(padding = 14.dp) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            PreviewFact(
                stringResource(R.string.s_type),
                Icons.Default.GridView,
                stringResource(R.string.s_habit_build),
                highlighted = true,
                modifier = Modifier.weight(1f),
            )
            PreviewFact(
                stringResource(R.string.s_duration),
                Icons.Default.CalendarMonth,
                GoalFormat.durationLabel(context, draft.weeks),
                modifier = Modifier.weight(1f),
            )
            PreviewFact(
                stringResource(R.string.s_start),
                Icons.Default.Flag,
                GoalFormat.startLabel(context, draft.startDate),
                modifier = Modifier.weight(1f),
            )
        }
    }

    Spacer(Modifier.height(14.dp))

    ReadTimeCard {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Default.Alarm, contentDescription = null, tint = ReadTimeTheme.colors.purple)
            Spacer(Modifier.width(8.dp))
            Text(
                stringResource(R.string.s_n_min_day, draft.minutes),
                style = MaterialTheme.typography.titleLarge,
                color = ReadTimeTheme.colors.purple,
                modifier = Modifier.weight(1f),
            )
            GoalBadge(GoalFormat.daysLabel(context, draft.weekdays))
        }
        Spacer(Modifier.height(8.dp))
        SecondaryText(stringResource(R.string.s_until_s, Dates.abbreviated(routine.lastDay)))
        Spacer(Modifier.height(12.dp))

        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            firstWeek.forEach { day ->
                val active = routine.includes(day)
                val color = if (active) ReadTimeTheme.colors.green else ReadTimeTheme.colors.secondaryText
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(5.dp),
                    modifier = Modifier
                        .weight(1f)
                        .clip(RoundedCornerShape(10.dp))
                        .background(
                            if (active) ReadTimeTheme.colors.green.copy(alpha = 0.08f)
                            else androidx.compose.ui.graphics.Color.Transparent
                        )
                        .then(
                            if (active) Modifier.border(1.dp, ReadTimeTheme.colors.green, RoundedCornerShape(10.dp))
                            else Modifier
                        )
                        .padding(vertical = 8.dp),
                ) {
                    Text(Dates.pattern(context, "EEE", day), style = MaterialTheme.typography.labelSmall, color = color)
                    Text(Dates.pattern(context, "d", day), style = MaterialTheme.typography.bodySmall, color = color)
                    Box(Modifier.height(26.dp), contentAlignment = Alignment.Center) {
                        if (active) {
                            Icon(Icons.Default.RadioButtonUnchecked, contentDescription = null, tint = color)
                        } else {
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

        if (draft.remind) {
            Spacer(Modifier.height(10.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    Icons.Default.NotificationsActive,
                    contentDescription = null,
                    tint = ReadTimeTheme.colors.secondaryText,
                    modifier = Modifier.size(16.dp),
                )
                Spacer(Modifier.width(6.dp))
                Text(
                    stringResource(R.string.s_reminders_on),
                    style = MaterialTheme.typography.bodySmall,
                    color = ReadTimeTheme.colors.secondaryText,
                )
            }
        }
    }
}

@Composable
private fun PreviewFact(
    title: String,
    icon: ImageVector,
    value: String,
    modifier: Modifier = Modifier,
    highlighted: Boolean = false,
) {
    Column(modifier = modifier) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            Icon(
                icon,
                contentDescription = null,
                tint = ReadTimeTheme.colors.secondaryText,
                modifier = Modifier.size(14.dp),
            )
            Text(
                title,
                style = MaterialTheme.typography.bodySmall,
                color = ReadTimeTheme.colors.secondaryText,
            )
        }
        Spacer(Modifier.height(4.dp))
        Text(
            value,
            style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.SemiBold),
            color = if (highlighted) ReadTimeTheme.colors.purple else ReadTimeTheme.colors.text,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

package com.fatties.readtime.ui.screens

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.LibraryBooks
import androidx.compose.material.icons.filled.MenuBook
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Shop
import androidx.compose.material.icons.filled.Sms
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.fatties.readtime.R
import com.fatties.readtime.data.Book
import com.fatties.readtime.data.LibraryTransfer
import com.fatties.readtime.data.ReadingStore
import com.fatties.readtime.data.Settings
import com.fatties.readtime.ui.components.BookCover
import com.fatties.readtime.ui.components.CardTitle
import com.fatties.readtime.ui.components.ReadTimeCard
import com.fatties.readtime.ui.components.SecondaryText
import com.fatties.readtime.ui.theme.ReadTimeTheme

private enum class OnboardingStep { WELCOME, SOURCE, GOAL, IMPORT_BOOKS, FIRST_BOOK }

@Composable
fun OnboardingScreen(store: ReadingStore) {
    var step by remember { mutableStateOf(OnboardingStep.WELCOME) }

    Box(
        Modifier
            .fillMaxSize()
            .background(ReadTimeTheme.colors.background)
    ) {
        when (step) {
            OnboardingStep.WELCOME -> WelcomeStep(
                onDemo = { store.finishOnboarding(withDemoContent = true) },
                onStartFresh = { step = OnboardingStep.SOURCE },
            )

            OnboardingStep.SOURCE -> SourceStep(
                onBack = { step = OnboardingStep.WELCOME },
                onContinue = { step = OnboardingStep.GOAL },
            )

            OnboardingStep.GOAL -> GoalStep(
                store = store,
                onBack = { step = OnboardingStep.SOURCE },
                onContinue = { step = OnboardingStep.IMPORT_BOOKS },
            )

            OnboardingStep.IMPORT_BOOKS -> ImportStep(
                store = store,
                onBack = { step = OnboardingStep.GOAL },
                onContinue = { step = OnboardingStep.FIRST_BOOK },
            )

            OnboardingStep.FIRST_BOOK -> FirstBookStep(
                store = store,
                onBack = { step = OnboardingStep.IMPORT_BOOKS },
                onFinish = { store.finishOnboarding(withDemoContent = false) },
            )
        }
    }
}

@Composable
private fun WelcomeStep(onDemo: () -> Unit, onStartFresh: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(bottom = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Column(
            modifier = Modifier
                .weight(1f)
                .padding(horizontal = 32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Image(
                painter = painterResource(R.drawable.app_icon),
                contentDescription = null,
                contentScale = ContentScale.Fit,
                modifier = Modifier
                    .size(112.dp)
                    .clip(RoundedCornerShape(24.dp)),
            )
            Spacer(Modifier.height(18.dp))
            Text(
                stringResource(R.string.s_welcome_to_readtime),
                style = MaterialTheme.typography.headlineSmall,
                color = ReadTimeTheme.colors.text,
                textAlign = TextAlign.Center,
            )
            Spacer(Modifier.height(10.dp))
            Text(
                stringResource(R.string.s_build_a_gentle_reading_habit_with_daily_goals_timed_sessions),
                style = MaterialTheme.typography.bodyLarge,
                color = ReadTimeTheme.colors.secondaryText,
                textAlign = TextAlign.Center,
            )
        }

        Column(
            modifier = Modifier.padding(horizontal = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            CardTitle(stringResource(R.string.s_how_would_you_like_to_start))

            Button(
                onClick = onStartFresh,
                shape = CircleShape,
                colors = ButtonDefaults.buttonColors(containerColor = ReadTimeTheme.colors.purple),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.padding(vertical = 10.dp)) {
                    Text(stringResource(R.string.s_start_fresh), style = MaterialTheme.typography.titleMedium)
                    Text(
                        stringResource(R.string.s_set_a_goal_and_add_your_first_book),
                        style = MaterialTheme.typography.bodySmall,
                        color = Color.White.copy(alpha = 0.85f),
                    )
                }
            }

            OutlinedButton(onClick = onDemo, shape = CircleShape, modifier = Modifier.fillMaxWidth()) {
                Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.padding(vertical = 10.dp)) {
                    Text(
                        stringResource(R.string.s_explore_with_demo_content),
                        style = MaterialTheme.typography.titleMedium,
                        color = ReadTimeTheme.colors.purple,
                    )
                    Text(
                        stringResource(R.string.s_sample_books_goals_and_activity),
                        style = MaterialTheme.typography.bodySmall,
                        color = ReadTimeTheme.colors.secondaryText,
                    )
                }
            }

            Text(
                stringResource(R.string.s_you_can_load_or_clear_demo_content_anytime_in_settings),
                style = MaterialTheme.typography.bodySmall,
                color = ReadTimeTheme.colors.secondaryText,
                textAlign = TextAlign.Center,
            )
        }
    }
}

/** Shared layout for the onboarding steps after the welcome screen. */
@Composable
private fun StepLayout(
    progress: Int,
    title: String,
    subtitle: String,
    onBack: () -> Unit,
    actions: ColumnScopeActions,
    content: @Composable () -> Unit,
) {
    val total = 4
    Column(Modifier.fillMaxSize()) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(horizontal = 12.dp)) {
            IconButton(onClick = onBack) {
                Icon(
                    Icons.AutoMirrored.Filled.KeyboardArrowLeft,
                    contentDescription = stringResource(R.string.s_back),
                    tint = ReadTimeTheme.colors.purple,
                )
            }
            Row(
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                modifier = Modifier.weight(1f),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Spacer(Modifier.weight(1f))
                (1..total).forEach { index ->
                    Box(
                        Modifier
                            .width(if (index == progress) 24.dp else 8.dp)
                            .height(8.dp)
                            .clip(CircleShape)
                            .background(
                                if (index <= progress) ReadTimeTheme.colors.purple
                                else ReadTimeTheme.colors.secondaryText.copy(alpha = 0.25f)
                            )
                    )
                }
                Spacer(Modifier.weight(1f))
            }
            Spacer(Modifier.width(44.dp))
        }

        Column(
            modifier = Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState())
                .padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    title,
                    style = MaterialTheme.typography.headlineSmall,
                    color = ReadTimeTheme.colors.text,
                )
                Text(
                    subtitle,
                    style = MaterialTheme.typography.bodyLarge,
                    color = ReadTimeTheme.colors.secondaryText,
                )
            }
            content()
        }

        Column(
            modifier = Modifier
                .padding(horizontal = 24.dp)
                .padding(bottom = 20.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            actions.content()
        }
    }
}

/** Lets a step pass its buttons to [StepLayout]. */
private class ColumnScopeActions(val content: @Composable () -> Unit)

@Composable
private fun PrimaryButton(label: String, enabled: Boolean = true, onClick: () -> Unit) {
    Button(
        onClick = onClick,
        enabled = enabled,
        shape = CircleShape,
        colors = ButtonDefaults.buttonColors(containerColor = ReadTimeTheme.colors.purple),
        modifier = Modifier
            .fillMaxWidth()
            .height(52.dp),
    ) { Text(label, style = MaterialTheme.typography.titleMedium) }
}

private enum class ReferralSource(val rawValue: String, val labelRes: Int, val icon: ImageVector) {
    APP_STORE("appStore", R.string.s_app_store, Icons.Default.Shop),
    SEARCH("search", R.string.s_google_search, Icons.Default.Search),
    SOCIAL("social", R.string.s_facebook_instagram_threads, Icons.Default.Sms),
    VIDEO("video", R.string.s_tiktok_youtube, Icons.Default.PlayCircle),
    FRIENDS("friends", R.string.s_friends_family, Icons.Default.People),
    OTHER("other", R.string.s_other, Icons.Default.MoreHoriz),
}

@Composable
private fun SourceStep(onBack: () -> Unit, onContinue: () -> Unit) {
    val context = LocalContext.current
    var selection by remember { mutableStateOf<ReferralSource?>(null) }

    StepLayout(
        progress = 1,
        title = stringResource(R.string.s_where_did_you_hear_about_readtime),
        subtitle = stringResource(R.string.s_it_helps_us_know_how_readers_find_the_app),
        onBack = onBack,
        actions = ColumnScopeActions {
            PrimaryButton(stringResource(R.string.s_continue), enabled = selection != null) {
                selection?.let { Settings.setReferralAnswerSent(context) }
                onContinue()
            }
            TextButton(onClick = onContinue) {
                Text(stringResource(R.string.s_skip), color = ReadTimeTheme.colors.purple)
            }
        },
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            ReferralSource.entries.forEach { source ->
                val isSelected = selection == source
                ReadTimeCard(
                    modifier = Modifier
                        .clickable { selection = source }
                        .then(
                            if (isSelected) Modifier.border(2.dp, ReadTimeTheme.colors.purple, RoundedCornerShape(14.dp))
                            else Modifier
                        ),
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                        Icon(source.icon, contentDescription = null, tint = ReadTimeTheme.colors.purple)
                        Text(
                            stringResource(source.labelRes),
                            style = MaterialTheme.typography.titleMedium,
                            color = ReadTimeTheme.colors.text,
                            modifier = Modifier.weight(1f),
                        )
                        Icon(
                            if (isSelected) Icons.Default.CheckCircle else Icons.Default.RadioButtonUnchecked,
                            contentDescription = null,
                            tint = if (isSelected) ReadTimeTheme.colors.purple
                            else ReadTimeTheme.colors.secondaryText.copy(alpha = 0.5f),
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun GoalStep(store: ReadingStore, onBack: () -> Unit, onContinue: () -> Unit) {
    var minutesChosen by remember { mutableStateOf(true) }
    var minutes by remember { mutableIntStateOf(20) }
    var books by remember { mutableIntStateOf(12) }

    StepLayout(
        progress = 2,
        title = stringResource(R.string.s_choose_your_goal),
        subtitle = stringResource(R.string.s_start_small_you_can_change_it_anytime_in_goals),
        onBack = onBack,
        actions = ColumnScopeActions {
            PrimaryButton(stringResource(R.string.s_continue)) {
                if (minutesChosen) store.setDailyGoal(minutes) else store.setYearlyBookGoal(books)
                onContinue()
            }
        },
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
            GoalChoiceCard(
                icon = Icons.Default.Schedule,
                title = pluralStringResource(R.plurals.s_read_n_minutes_a_day, minutes, minutes),
                subtitle = stringResource(R.string.s_build_a_daily_reading_habit),
                isSelected = minutesChosen,
                onSelect = { minutesChosen = true },
            ) {
                StepperRow(
                    label = "",
                    onDecrement = {
                        minutes = (minutes - 5).coerceAtLeast(5)
                        minutesChosen = true
                    },
                    onIncrement = {
                        minutes = (minutes + 5).coerceAtMost(180)
                        minutesChosen = true
                    },
                )
            }

            GoalChoiceCard(
                icon = Icons.Default.LibraryBooks,
                title = pluralStringResource(R.plurals.s_read_n_books_a_year, books, books),
                subtitle = stringResource(R.string.s_finish_more_of_the_books_you_want_to_read),
                isSelected = !minutesChosen,
                onSelect = { minutesChosen = false },
            ) {
                StepperRow(
                    label = "",
                    onDecrement = {
                        books = (books - 1).coerceAtLeast(1)
                        minutesChosen = false
                    },
                    onIncrement = {
                        books = (books + 1).coerceAtMost(100)
                        minutesChosen = false
                    },
                )
            }
        }
    }
}

@Composable
private fun GoalChoiceCard(
    icon: ImageVector,
    title: String,
    subtitle: String,
    isSelected: Boolean,
    onSelect: () -> Unit,
    accessory: @Composable () -> Unit,
) {
    ReadTimeCard(
        modifier = Modifier
            .clickable(onClick = onSelect)
            .then(
                if (isSelected) Modifier.border(2.dp, ReadTimeTheme.colors.purple, RoundedCornerShape(14.dp))
                else Modifier
            ),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            Box(
                modifier = Modifier
                    .size(48.dp)
                    .clip(CircleShape)
                    .background(ReadTimeTheme.colors.purple.copy(alpha = 0.12f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(icon, contentDescription = null, tint = ReadTimeTheme.colors.purple)
            }
            Column(Modifier.weight(1f)) {
                CardTitle(title)
                Spacer(Modifier.height(3.dp))
                SecondaryText(subtitle)
            }
            Icon(
                if (isSelected) Icons.Default.CheckCircle else Icons.Default.RadioButtonUnchecked,
                contentDescription = null,
                tint = if (isSelected) ReadTimeTheme.colors.purple
                else ReadTimeTheme.colors.secondaryText.copy(alpha = 0.5f),
            )
        }
        Spacer(Modifier.height(14.dp))
        accessory()
    }
}

@Composable
private fun ImportStep(store: ReadingStore, onBack: () -> Unit, onContinue: () -> Unit) {
    val context = LocalContext.current
    var importedCount by remember { mutableStateOf<Int?>(null) }
    var errorMessage by remember { mutableStateOf<String?>(null) }

    val pickCSV = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        runCatching { LibraryTransfer.booksFromCSV(context, uri) }
            .onSuccess {
                importedCount = (importedCount ?: 0) + store.importBooks(it)
                errorMessage = null
            }
            .onFailure {
                errorMessage = context.getString(R.string.s_no_books_were_found_in_this_file_export_your_library_as_csv)
            }
    }

    fun pick() = pickCSV.launch(arrayOf("text/csv", "text/comma-separated-values", "text/plain", "*/*"))

    StepLayout(
        progress = 3,
        title = stringResource(R.string.s_bringing_some_books_with_you),
        subtitle = stringResource(R.string.s_import_your_library_from_another_reading_app_you_can_also_do),
        onBack = onBack,
        actions = ColumnScopeActions {
            PrimaryButton(
                stringResource(if (importedCount == null) R.string.s_skip else R.string.s_continue),
                onClick = onContinue,
            )
        },
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            ImportCard(
                title = stringResource(R.string.s_import_from_goodreads),
                hint = stringResource(R.string.s_my_books_import_and_export_export_library),
                icon = Icons.Default.MenuBook,
                onClick = { pick() },
            )
            ImportCard(
                title = stringResource(R.string.s_import_from_storygraph),
                hint = stringResource(R.string.s_manage_account_export_storygraph_library),
                icon = Icons.Default.BarChart,
                onClick = { pick() },
            )

            importedCount?.let { count ->
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Icon(Icons.Default.CheckCircle, contentDescription = null, tint = ReadTimeTheme.colors.green)
                    Text(
                        context.resources.getQuantityString(R.plurals.s_imported_n_books, count, count),
                        style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.SemiBold),
                        color = ReadTimeTheme.colors.green,
                    )
                }
            }

            errorMessage?.let {
                Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
            }
        }
    }
}

@Composable
private fun ImportCard(title: String, hint: String, icon: ImageVector, onClick: () -> Unit) {
    ReadTimeCard(modifier = Modifier.clickable(onClick = onClick)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            Icon(icon, contentDescription = null, tint = ReadTimeTheme.colors.purple)
            Column(Modifier.weight(1f)) {
                CardTitle(title)
                Spacer(Modifier.height(2.dp))
                Text(
                    hint,
                    style = MaterialTheme.typography.bodySmall,
                    color = ReadTimeTheme.colors.secondaryText,
                )
            }
            Icon(Icons.Default.Download, contentDescription = null, tint = ReadTimeTheme.colors.secondaryText)
        }
    }
}

@Composable
private fun FirstBookStep(store: ReadingStore, onBack: () -> Unit, onFinish: () -> Unit) {
    val state by store.state.collectAsStateWithLifecycle()
    var adding by remember { mutableStateOf(false) }

    if (adding) {
        AddBookScreen(store = store, onDismiss = { adding = false }, bookID = null)
        return
    }

    StepLayout(
        progress = 4,
        title = stringResource(R.string.s_add_your_first_book),
        subtitle = stringResource(R.string.s_what_are_you_reading_now_or_what_s_next_on_your_list),
        onBack = onBack,
        actions = ColumnScopeActions {
            PrimaryButton(
                stringResource(if (state.books.isEmpty()) R.string.s_skip_for_now else R.string.s_start_reading),
                onClick = onFinish,
            )
        },
    ) {
        val first = state.books.firstOrNull()
        if (first != null) {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                FirstBookCard(first)
                TextButton(onClick = { adding = true }) {
                    Icon(Icons.Default.Add, contentDescription = null, tint = ReadTimeTheme.colors.purple)
                    Spacer(Modifier.width(6.dp))
                    Text(stringResource(R.string.s_add_another_book), color = ReadTimeTheme.colors.purple)
                }
            }
        } else {
            ReadTimeCard(
                modifier = Modifier
                    .clickable { adding = true }
                    .border(1.5.dp, ReadTimeTheme.colors.purple.copy(alpha = 0.4f), RoundedCornerShape(14.dp)),
                padding = 24.dp,
            ) {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Box(
                        modifier = Modifier
                            .size(88.dp)
                            .clip(CircleShape)
                            .background(ReadTimeTheme.colors.purple.copy(alpha = 0.12f)),
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(Icons.Default.MenuBook, contentDescription = null, tint = ReadTimeTheme.colors.purple)
                    }
                    Spacer(Modifier.height(12.dp))
                    CardTitle(stringResource(R.string.s_search_or_add_a_book))
                    Spacer(Modifier.height(6.dp))
                    Text(
                        stringResource(R.string.s_find_it_online_to_fill_in_the_cover_and_details_automaticall),
                        style = MaterialTheme.typography.bodyMedium,
                        color = ReadTimeTheme.colors.secondaryText,
                        textAlign = TextAlign.Center,
                    )
                }
            }
        }
    }
}

@Composable
private fun FirstBookCard(book: Book) {
    ReadTimeCard(padding = 14.dp) {
        Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            BookCover(book, 64.dp, 96.dp)
            Column(Modifier.weight(1f)) {
                CardTitle(book.title)
                Spacer(Modifier.height(4.dp))
                SecondaryText(book.author)
            }
        }
    }
}

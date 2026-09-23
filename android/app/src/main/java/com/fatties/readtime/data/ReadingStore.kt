package com.fatties.readtime.data

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import com.fatties.readtime.widget.WidgetUpdater
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import kotlin.math.max
import kotlin.math.roundToInt

/** Everything the app reads and writes: the library, sessions, journal, and goals. */
class ReadingStore(application: Application) : AndroidViewModel(application) {
    private val context get() = getApplication<Application>()

    private val _state = MutableStateFlow(ReadingState())
    val state: StateFlow<ReadingState> = _state.asStateFlow()

    private var autosave: Job? = null

    init {
        val saved = LocalStore.load(context)
        if (saved != null) {
            _state.value = ReadingState(
                books = saved.books,
                activities = saved.activities,
                journalEntries = saved.journalEntries,
                dailyGoal = saved.dailyGoal,
                yearlyBookGoal = saved.yearlyBookGoal,
                routine = saved.routine,
                reminderEnabled = saved.reminderEnabled ?: false,
                reminderTime = saved.reminderTime ?: defaultReminderTime(),
                selectedBookID = saved.selectedBookID,
            )
            markLegacyDemoItems()
            val session = Settings.activeSession(context)
            if (session != null) {
                update { it.copy(activeSessionBookID = session.bookID, activeSessionStartedAt = session.startedAt) }
            }
            if (state.value.reminderEnabled) {
                ReminderManager.schedule(context, state.value.reminderTime, state.value.routine?.weekdays ?: (1..7).toList())
            }
        } else {
            _state.value = ReadingState(needsOnboarding = true, reminderTime = defaultReminderTime())
        }
    }

    // MARK: Saving

    private fun update(transform: (ReadingState) -> ReadingState) {
        _state.value = transform(_state.value)
        scheduleSave()
    }

    /** Saves shortly after anything changes, like the iOS app's debounced autosave. */
    private fun scheduleSave() {
        autosave?.cancel()
        autosave = viewModelScope.launch {
            delay(300)
            save()
        }
    }

    fun save() {
        // Nothing is written until onboarding finishes, so quitting halfway shows it again next launch.
        if (_state.value.needsOnboarding) return
        LocalStore.save(context, snapshot())
        val state = _state.value
        val bookID = state.activeSessionBookID
        val startedAt = state.activeSessionStartedAt
        Settings.setActiveSession(context, if (bookID != null && startedAt != null) ActiveSessionState(bookID, startedAt) else null)
        // Home screen widgets read the same file, so redraw them whenever it changes.
        viewModelScope.launch { WidgetUpdater.updateAll(context) }
    }

    fun snapshot(): ReadingSnapshot {
        val state = _state.value
        return ReadingSnapshot(
            books = state.books,
            activities = state.activities,
            journalEntries = state.journalEntries,
            dailyGoal = state.dailyGoal,
            yearlyBookGoal = state.yearlyBookGoal,
            routine = state.routine,
            reminderEnabled = state.reminderEnabled,
            reminderTime = state.reminderTime,
            selectedBookID = state.selectedBookID,
            savedAt = AppleDate.now(),
        )
    }

    fun restore(snapshot: ReadingSnapshot) {
        update {
            it.copy(
                books = snapshot.books,
                activities = snapshot.activities,
                journalEntries = snapshot.journalEntries,
                dailyGoal = snapshot.dailyGoal,
                yearlyBookGoal = snapshot.yearlyBookGoal,
                routine = snapshot.routine,
                selectedBookID = null,
            )
        }
    }

    // MARK: Onboarding and demo content

    fun finishOnboarding(withDemoContent: Boolean) {
        if (withDemoContent) loadDemoContent()
        _state.value = _state.value.copy(needsOnboarding = false)
        // Save right away so a fresh start with no changes isn't asked again next launch.
        save()
    }

    val hasDemoContent: Boolean
        get() = _state.value.run {
            books.any { it.isDemo == true } || activities.any { it.isDemo == true } || journalEntries.any { it.isDemo == true }
        }

    /** Adds the sample library alongside the reader's own data. */
    fun loadDemoContent() {
        clearDemoContent()
        update {
            it.copy(
                books = it.books + DemoContent.books,
                activities = (it.activities + DemoContent.activities).sortedByDescending { activity -> activity.date.value },
                journalEntries = (it.journalEntries + DemoContent.journalEntries).sortedByDescending { entry -> entry.date.value },
            )
        }
    }

    /** Removes only the sample library, keeping everything the reader added. */
    fun clearDemoContent() {
        if (!hasDemoContent) return
        update { state ->
            val books = state.books.filterNot { it.isDemo == true }
            state.copy(
                books = books,
                activities = state.activities.filterNot { it.isDemo == true },
                journalEntries = state.journalEntries.filterNot { it.isDemo == true },
                selectedBookID = state.selectedBookID?.takeIf { id -> books.any { it.id == id } },
            )
        }
    }

    /** Data saved before demo items were flagged: recognise the sample items by their content. */
    private fun markLegacyDemoItems() {
        val sampleBooks = DemoContent.books
        val sampleActivities = DemoContent.activities
        val sampleJournal = DemoContent.journalEntries
        _state.value = _state.value.let { state ->
            state.copy(
                books = state.books.map { book ->
                    if (book.isDemo != null) book
                    else book.copy(isDemo = sampleBooks.any { it.title == book.title && it.coverName == book.coverName })
                },
                activities = state.activities.map { activity ->
                    if (activity.isDemo != null) activity
                    else activity.copy(isDemo = sampleActivities.any { it.bookTitle == activity.bookTitle && it.minutes == activity.minutes })
                },
                journalEntries = state.journalEntries.map { entry ->
                    if (entry.isDemo != null) entry
                    else entry.copy(isDemo = sampleJournal.any { it.text == entry.text })
                },
            )
        }
    }

    // MARK: Goals and settings

    fun setDailyGoal(minutes: Int) = update { it.copy(dailyGoal = minutes) }

    fun setYearlyBookGoal(books: Int) = update { it.copy(yearlyBookGoal = books) }

    fun setSelectedBook(id: String?) = update { it.copy(selectedBookID = id) }

    fun setReminder(enabled: Boolean, at: AppleDate = _state.value.reminderTime) {
        update { it.copy(reminderEnabled = enabled, reminderTime = at) }
        if (enabled) {
            ReminderManager.schedule(context, at, _state.value.routine?.weekdays ?: (1..7).toList())
        } else {
            ReminderManager.cancel(context)
        }
    }

    /** Saves a goal created in the goal flow and schedules its reminders. */
    fun applyGoal(minutes: Int, routine: ReadingRoutine, remind: Boolean) {
        update { it.copy(dailyGoal = minutes, routine = routine, reminderEnabled = remind) }
        if (remind) {
            ReminderManager.schedule(context, _state.value.reminderTime, routine.weekdays)
        } else {
            ReminderManager.cancel(context)
        }
    }

    // MARK: Books

    fun addBook(book: Book) = update { state ->
        val stamped = if (book.status == BookStatus.FINISHED && book.finishedAt == null) book.copy(finishedAt = AppleDate.now()) else book
        state.copy(books = listOf(stamped) + state.books)
    }

    /**
     * Saves edits to a book. Sessions and journal entries refer to books by title, so a rename
     * and a new cover carry over to them.
     */
    fun updateBook(book: Book) = update { state ->
        val index = state.books.indexOfFirst { it.id == book.id }
        if (index < 0) return@update state
        val oldTitle = state.books[index].title
        val updated = if (book.status == BookStatus.FINISHED) {
            book.copy(finishedAt = book.finishedAt ?: AppleDate.now())
        } else {
            book.copy(finishedAt = null, rating = null)
        }
        state.copy(
            books = state.books.toMutableList().also { it[index] = updated },
            activities = state.activities.map {
                if (it.bookTitle == oldTitle) it.copy(bookTitle = updated.title, coverName = updated.coverName, coverURL = updated.coverURL) else it
            },
            journalEntries = state.journalEntries.map {
                if (it.bookTitle == oldTitle) it.copy(bookTitle = updated.title) else it
            },
        )
    }

    /** Removes a book from the library. Its past sessions and journal entries stay. */
    fun deleteBook(id: String) = update { state ->
        state.copy(
            books = state.books.filterNot { it.id == id },
            selectedBookID = state.selectedBookID?.takeIf { it != id },
        )
    }

    /** Adds books that aren't already in the library (same title and author). Returns how many were added. */
    fun importBooks(imported: List<Book>): Int {
        fun key(book: Book) = "${book.title.lowercase().trim()}|${book.author.lowercase().trim()}"
        val existing = _state.value.books.map(::key).toMutableSet()
        val added = mutableListOf<Book>()
        for (book in imported) {
            if (existing.add(key(book))) added.add(book)
        }
        if (added.isNotEmpty()) update { it.copy(books = it.books + added) }
        return added.size
    }

    fun book(id: String?): Book? = id?.let { wanted -> _state.value.books.firstOrNull { it.id == wanted } }

    // MARK: Sessions

    fun startSession(bookID: String) {
        update { it.copy(activeSessionBookID = bookID, activeSessionStartedAt = AppleDate.now()) }
        save()
    }

    fun clearSession() {
        update { it.copy(activeSessionBookID = null, activeSessionStartedAt = null) }
        Settings.setActiveSession(context, null)
    }

    fun completeSession(bookID: String, seconds: Double, page: Int, journal: String) = update { state ->
        val index = state.books.indexOfFirst { it.id == bookID }
        if (index < 0) return@update state

        val roundedMinutes = max(1, (seconds / 60).roundToInt())
        val book = state.books[index]
        val previousPage = book.currentPage
        val newPage = minOf(page, book.totalPages)
        val status = if (newPage >= book.totalPages) BookStatus.FINISHED else BookStatus.READING
        val completed = book.copy(
            currentPage = newPage,
            status = status,
            finishedAt = if (status == BookStatus.FINISHED) book.finishedAt ?: AppleDate.now() else book.finishedAt,
        )

        val activity = ReadingActivity(
            date = AppleDate.now(),
            minutes = roundedMinutes,
            bookTitle = completed.title,
            coverName = completed.coverName,
            coverURL = completed.coverURL,
            pagesRead = max(0, completed.currentPage - previousPage),
        )

        val trimmedJournal = journal.trim()
        val journalEntries = if (trimmedJournal.isEmpty()) state.journalEntries else {
            listOf(JournalEntry(date = AppleDate.now(), bookTitle = completed.title, text = trimmedJournal)) + state.journalEntries
        }

        state.copy(
            books = state.books.toMutableList().also { it[index] = completed },
            activities = listOf(activity) + state.activities,
            journalEntries = journalEntries,
        )
    }

    // MARK: Journal

    /** Adds a new entry or replaces the existing one with the same id, keeping newest first. */
    fun saveJournalEntry(entry: JournalEntry) = update { state ->
        val entries = state.journalEntries.toMutableList()
        val index = entries.indexOfFirst { it.id == entry.id }
        if (index >= 0) entries[index] = entry else entries.add(entry)
        state.copy(journalEntries = entries.sortedByDescending { it.date.value })
    }

    fun deleteJournalEntry(id: String) = update { state ->
        state.copy(journalEntries = state.journalEntries.filterNot { it.id == id })
    }

    private fun defaultReminderTime(): AppleDate =
        AppleDate.of(LocalDate.now().atTime(LocalTime.of(20, 0)).atZone(ZoneId.systemDefault()).toInstant())
}

/** Builds the single [ReadingStore] the whole app shares. */
class ReadTimeStoreFactory(private val application: Application) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T = ReadingStore(application) as T
}

package com.fatties.readtime.ui.screens

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
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
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.outlined.StarOutline
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MenuAnchorType
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.fatties.readtime.R
import com.fatties.readtime.data.Book
import com.fatties.readtime.data.BookSearch
import com.fatties.readtime.data.BookSearchResult
import com.fatties.readtime.data.BookStatus
import com.fatties.readtime.data.CoverCache
import com.fatties.readtime.data.ReadingStore
import com.fatties.readtime.ui.components.CardTitle
import com.fatties.readtime.ui.components.CoverImage
import com.fatties.readtime.ui.components.ReadTimeCard
import com.fatties.readtime.ui.components.SecondaryText
import com.fatties.readtime.ui.theme.ReadTimeTheme
import kotlinx.coroutines.delay

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AddBookScreen(store: ReadingStore, onDismiss: () -> Unit, bookID: String?) {
    val state by store.state.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val editing = remember(bookID, state.books) { state.book(bookID) }

    var title by remember { mutableStateOf(editing?.title.orEmpty()) }
    var author by remember { mutableStateOf(editing?.author.orEmpty()) }
    var genre by remember { mutableStateOf(editing?.genre ?: context.getString(R.string.s_general)) }
    var pageCount by remember { mutableIntStateOf(editing?.totalPages ?: 250) }
    var currentPage by remember { mutableIntStateOf(editing?.currentPage ?: 0) }
    var status by remember { mutableStateOf(editing?.status ?: BookStatus.WANT_TO_READ) }
    var rating by remember { mutableIntStateOf(editing?.rating ?: 0) }
    var coverName by remember { mutableStateOf(editing?.coverName) }
    var coverURL by remember { mutableStateOf(editing?.coverURL) }
    var confirmingDelete by remember { mutableStateOf(false) }
    var photoError by remember { mutableStateOf<String?>(null) }

    var query by remember { mutableStateOf("") }
    var results by remember { mutableStateOf<List<BookSearchResult>>(emptyList()) }
    var isSearching by remember { mutableStateOf(false) }
    var searchMessage by remember { mutableStateOf<String?>(null) }

    val pickPhoto = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        runCatching { CoverCache.saveUploadedCover(context, uri) }
            .onSuccess {
                coverURL = it
                coverName = null
                photoError = null
            }
            .onFailure { photoError = context.getString(R.string.s_couldn_t_use_that_photo_try_another_one) }
    }

    // Runs whenever the query changes, after a short pause so typing doesn't fire a request per key.
    LaunchedEffect(query) {
        val trimmed = query.trim()
        if (trimmed.length < 2) {
            results = emptyList()
            searchMessage = null
            isSearching = false
            return@LaunchedEffect
        }
        delay(450)
        isSearching = true
        runCatching { BookSearch.search(trimmed) }
            .onSuccess { found ->
                results = found
                searchMessage = if (found.isEmpty()) {
                    context.getString(R.string.s_no_books_found_you_can_still_add_it_manually_below)
                } else {
                    null
                }
            }
            .onFailure {
                results = emptyList()
                searchMessage = context.getString(R.string.s_couldn_t_search_right_now_check_your_connection_or_add_the_b)
            }
        isSearching = false
    }

    val isValid = title.isNotBlank() && author.isNotBlank()

    fun save() {
        val book = (editing ?: Book()).copy(
            title = title.trim(),
            author = author.trim(),
            genre = genre.trim(),
            totalPages = pageCount,
            currentPage = minOf(currentPage, pageCount),
            status = status,
            rating = if (status == BookStatus.FINISHED && rating > 0) rating else null,
            coverName = coverName,
            coverURL = coverURL,
        )
        if (editing == null) store.addBook(book) else store.updateBook(book)
        onDismiss()
    }

    Scaffold(
        containerColor = ReadTimeTheme.colors.background,
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        stringResource(if (editing == null) R.string.s_new_book else R.string.s_edit_book),
                        fontWeight = FontWeight.SemiBold,
                    )
                },
                navigationIcon = {
                    IconButton(onClick = { onDismiss() }) {
                        Icon(Icons.Default.Close, contentDescription = stringResource(R.string.s_cancel))
                    }
                },
                actions = {
                    IconButton(onClick = { save() }, enabled = isValid) {
                        Icon(Icons.Default.Check, contentDescription = stringResource(R.string.s_save))
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = ReadTimeTheme.colors.background,
                    titleContentColor = ReadTimeTheme.colors.text,
                    navigationIconContentColor = ReadTimeTheme.colors.text,
                    actionIconContentColor = ReadTimeTheme.colors.purple,
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
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            item {
                ReadTimeCard {
                    CardTitle(stringResource(R.string.s_find_a_book))
                    Spacer(Modifier.height(10.dp))
                    OutlinedTextField(
                        value = query,
                        onValueChange = { query = it },
                        label = { Text(stringResource(R.string.s_title_author_or_isbn)) },
                        leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
                        trailingIcon = {
                            when {
                                isSearching -> CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                                query.isNotEmpty() -> IconButton(onClick = { query = "" }) {
                                    Icon(
                                        Icons.Default.Close,
                                        contentDescription = stringResource(R.string.s_clear_search),
                                    )
                                }
                            }
                        },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                    )
                    searchMessage?.let {
                        Spacer(Modifier.height(8.dp))
                        SecondaryText(it)
                    }
                    if (query.isEmpty()) {
                        Spacer(Modifier.height(8.dp))
                        SecondaryText(stringResource(R.string.s_search_online_to_fill_in_the_details_and_cover_automatically))
                    }
                }
            }

            items(results, key = { it.id }) { result ->
                BookSearchResultRow(result) {
                    title = result.title
                    author = result.authors.joinToString(", ")
                    result.genre?.let { genre = it }
                    result.pageCount?.let { pageCount = it.coerceIn(1, 5_000) }
                    coverURL = result.coverURL
                    if (coverURL != null) coverName = null
                    query = ""
                }
            }

            item {
                ReadTimeCard {
                    CardTitle(stringResource(R.string.s_book_details))
                    Spacer(Modifier.height(12.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                        CoverImage(
                            coverName = coverName,
                            coverURL = coverURL,
                            modifier = Modifier
                                .size(60.dp, 90.dp)
                                .clip(RoundedCornerShape(5.dp)),
                        )
                        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            TextButton(onClick = {
                                pickPhoto.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                            }) {
                                Icon(Icons.Default.PhotoLibrary, contentDescription = null)
                                Spacer(Modifier.width(6.dp))
                                Text(
                                    stringResource(
                                        if (coverName != null || coverURL != null) R.string.s_change_cover
                                        else R.string.s_upload_cover
                                    )
                                )
                            }
                            if (coverName != null || coverURL != null) {
                                TextButton(onClick = {
                                    coverName = null
                                    coverURL = null
                                }) {
                                    Text(
                                        stringResource(R.string.s_remove_cover),
                                        color = MaterialTheme.colorScheme.error,
                                    )
                                }
                            }
                            photoError?.let {
                                Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
                            }
                        }
                    }

                    Spacer(Modifier.height(12.dp))
                    Field(stringResource(R.string.s_title), title) { title = it }
                    Spacer(Modifier.height(8.dp))
                    Field(stringResource(R.string.s_author), author) { author = it }
                    Spacer(Modifier.height(8.dp))
                    Field(stringResource(R.string.s_genre), genre) { genre = it }
                    Spacer(Modifier.height(12.dp))
                    StepperRow(
                        label = stringResource(R.string.s_pages_n, pageCount),
                        onDecrement = { pageCount = (pageCount - 1).coerceAtLeast(1) },
                        onIncrement = { pageCount = (pageCount + 1).coerceAtMost(5_000) },
                    )
                    if (editing != null) {
                        Spacer(Modifier.height(8.dp))
                        StepperRow(
                            label = stringResource(R.string.s_current_page_n, currentPage),
                            onDecrement = { currentPage = (currentPage - 1).coerceAtLeast(0) },
                            onIncrement = { currentPage = (currentPage + 1).coerceAtMost(pageCount) },
                        )
                    }
                }
            }

            item {
                ReadTimeCard {
                    CardTitle(stringResource(R.string.s_shelf))
                    Spacer(Modifier.height(12.dp))
                    StatusPicker(status) { status = it }
                    if (status == BookStatus.FINISHED) {
                        Spacer(Modifier.height(12.dp))
                        StarRatingPicker(rating) { rating = it }
                    }
                }
            }

            if (editing != null) {
                item {
                    TextButton(
                        onClick = { confirmingDelete = true },
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Text(stringResource(R.string.s_delete_book), color = MaterialTheme.colorScheme.error)
                    }
                }
            }
        }
    }

    if (confirmingDelete && editing != null) {
        AlertDialog(
            onDismissRequest = { confirmingDelete = false },
            title = { Text(stringResource(R.string.s_delete_this_book)) },
            text = {
                Text(stringResource(R.string.s_s_will_be_removed_from_your_library_your_reading_history_and, title))
            },
            confirmButton = {
                TextButton(onClick = {
                    store.deleteBook(editing.id)
                    onDismiss()
                }) {
                    Text(stringResource(R.string.s_delete_book), color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { confirmingDelete = false }) { Text(stringResource(R.string.s_cancel)) }
            },
        )
    }
}

@Composable
private fun Field(label: String, value: String, onChange: (String) -> Unit) {
    OutlinedTextField(
        value = value,
        onValueChange = onChange,
        label = { Text(label) },
        singleLine = true,
        modifier = Modifier.fillMaxWidth(),
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun StatusPicker(status: BookStatus, onChange: (BookStatus) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    ExposedDropdownMenuBox(expanded = expanded, onExpandedChange = { expanded = it }) {
        OutlinedTextField(
            value = status.title(),
            onValueChange = {},
            readOnly = true,
            label = { Text(stringResource(R.string.s_status)) },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
            modifier = Modifier
                .menuAnchor(MenuAnchorType.PrimaryNotEditable)
                .fillMaxWidth(),
        )
        ExposedDropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            BookStatus.entries.forEach { option ->
                DropdownMenuItem(
                    text = { Text(option.title()) },
                    onClick = {
                        onChange(option)
                        expanded = false
                    },
                )
            }
        }
    }
}

@Composable
fun StarRatingPicker(rating: Int, onChange: (Int) -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(stringResource(R.string.s_rating), color = ReadTimeTheme.colors.text, modifier = Modifier.weight(1f))
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            (1..5).forEach { star ->
                Icon(
                    if (star <= rating) Icons.Default.Star else Icons.Outlined.StarOutline,
                    contentDescription = pluralStringResource(R.plurals.s_n_stars, star, star),
                    tint = if (star <= rating) ReadTimeTheme.colors.amber else ReadTimeTheme.colors.secondaryText,
                    modifier = Modifier.clickable { onChange(if (rating == star) 0 else star) },
                )
            }
        }
    }
}

@Composable
private fun BookSearchResultRow(result: BookSearchResult, onSelect: () -> Unit) {
    val details = buildList {
        if (result.authors.isNotEmpty()) add(result.authors.joinToString(", "))
        result.year?.let { add(it) }
    }.joinToString(" · ")

    ReadTimeCard(modifier = Modifier.clickable(onClick = onSelect), padding = 12.dp) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            CoverImage(
                coverName = null,
                coverURL = result.thumbnailURL,
                modifier = Modifier
                    .size(40.dp, 60.dp)
                    .clip(RoundedCornerShape(4.dp)),
            )
            Column(Modifier.weight(1f)) {
                Text(
                    result.title,
                    style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.SemiBold),
                    color = ReadTimeTheme.colors.text,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
                if (details.isNotEmpty()) {
                    Text(
                        details,
                        style = MaterialTheme.typography.bodySmall,
                        color = ReadTimeTheme.colors.secondaryText,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                result.pageCount?.let {
                    Text(
                        pluralStringResource(R.plurals.s_n_pages, it, it),
                        style = MaterialTheme.typography.bodySmall,
                        color = ReadTimeTheme.colors.secondaryText,
                    )
                }
            }
            Icon(Icons.Default.AddCircle, contentDescription = null, tint = ReadTimeTheme.colors.purple)
        }
    }
}

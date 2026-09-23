package com.fatties.readtime.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavHostController
import com.fatties.readtime.R
import com.fatties.readtime.data.Book
import com.fatties.readtime.data.BookStatus
import com.fatties.readtime.data.ReadingStore
import com.fatties.readtime.ui.Routes
import com.fatties.readtime.ui.components.AdBanner
import com.fatties.readtime.ui.components.BookCover
import com.fatties.readtime.ui.components.CardTitle
import com.fatties.readtime.ui.components.ReadTimeCard
import com.fatties.readtime.ui.components.ReadTimeProgress
import com.fatties.readtime.ui.components.SecondaryText
import com.fatties.readtime.ui.theme.ReadTimeTheme

@Composable
fun BookStatus.title(): String = stringResource(
    when (this) {
        BookStatus.READING -> R.string.s_reading
        BookStatus.WANT_TO_READ -> R.string.s_want_to_read
        BookStatus.FINISHED -> R.string.s_finished
    }
)

@Composable
fun BookStatus.color(): Color = when (this) {
    BookStatus.READING -> ReadTimeTheme.colors.purple
    BookStatus.WANT_TO_READ -> ReadTimeTheme.colors.amber
    BookStatus.FINISHED -> ReadTimeTheme.colors.green
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LibraryScreen(store: ReadingStore, navController: NavHostController) {
    val state by store.state.collectAsStateWithLifecycle()
    var filter by remember { mutableStateOf<BookStatus?>(null) }
    var deleting by remember { mutableStateOf<Book?>(null) }

    val books = remember(state.books, filter) {
        filter?.let { wanted -> state.books.filter { it.status == wanted } } ?: state.books
    }

    Scaffold(
        containerColor = ReadTimeTheme.colors.background,
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.s_library), fontWeight = FontWeight.Bold) },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = ReadTimeTheme.colors.background,
                    titleContentColor = ReadTimeTheme.colors.text,
                ),
                actions = {
                    IconButton(onClick = { navController.navigate(Routes.addBook()) }) {
                        Icon(
                            Icons.Default.Add,
                            contentDescription = stringResource(R.string.s_add_a_book),
                            tint = ReadTimeTheme.colors.text,
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
                top = padding.calculateTopPadding() + 4.dp,
                bottom = 24.dp,
            ),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            item { AdBanner() }

            item {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    StatusChip(stringResource(R.string.s_all), filter == null) { filter = null }
                    BookStatus.entries.forEach { status ->
                        StatusChip(status.title(), filter == status) { filter = status }
                    }
                }
            }

            items(books, key = { it.id }) { book ->
                BookLibraryCard(
                    book = book,
                    onEdit = { navController.navigate(Routes.addBook(book.id)) },
                    onDelete = { deleting = book },
                )
            }
        }
    }

    deleting?.let { book ->
        AlertDialog(
            onDismissRequest = { deleting = null },
            title = { Text(stringResource(R.string.s_delete_this_book)) },
            text = {
                Text(stringResource(R.string.s_s_will_be_removed_from_your_library_your_reading_history_and, book.title))
            },
            confirmButton = {
                TextButton(onClick = {
                    store.deleteBook(book.id)
                    deleting = null
                }) {
                    Text(stringResource(R.string.s_delete_book), color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { deleting = null }) { Text(stringResource(R.string.s_cancel)) }
            },
        )
    }
}

@Composable
private fun StatusChip(label: String, selected: Boolean, onClick: () -> Unit) {
    FilterChip(
        selected = selected,
        onClick = onClick,
        label = { Text(label) },
        colors = FilterChipDefaults.filterChipColors(
            selectedContainerColor = ReadTimeTheme.colors.purple.copy(alpha = 0.16f),
            selectedLabelColor = ReadTimeTheme.colors.purple,
            labelColor = ReadTimeTheme.colors.text,
        ),
    )
}

@OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
@Composable
private fun BookLibraryCard(book: Book, onEdit: () -> Unit, onDelete: () -> Unit) {
    var menuOpen by remember { mutableStateOf(false) }

    Box {
        ReadTimeCard(
            modifier = Modifier.combinedClickable(onClick = onEdit, onLongClick = { menuOpen = true }),
            padding = 14.dp,
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                BookCover(book, 64.dp, 96.dp)
                Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    CardTitle(book.title)
                    SecondaryText(book.author)
                    Text(
                        book.genre,
                        style = MaterialTheme.typography.bodySmall,
                        color = ReadTimeTheme.colors.secondaryText,
                    )
                    if (book.status == BookStatus.READING) {
                        ReadTimeProgress(book.progress, color = ReadTimeTheme.colors.purple)
                        Text(
                            stringResource(R.string.s_page_n_of_n, book.currentPage, book.totalPages),
                            style = MaterialTheme.typography.bodySmall,
                            color = ReadTimeTheme.colors.secondaryText,
                        )
                    }
                }
                Text(
                    book.status.title(),
                    style = MaterialTheme.typography.labelSmall,
                    color = book.status.color(),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(book.status.color().copy(alpha = 0.10f))
                        .padding(horizontal = 9.dp, vertical = 6.dp),
                )
            }
        }

        DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
            DropdownMenuItem(
                text = { Text(stringResource(R.string.s_edit)) },
                leadingIcon = { Icon(Icons.Default.Edit, contentDescription = null) },
                onClick = {
                    menuOpen = false
                    onEdit()
                },
            )
            DropdownMenuItem(
                text = { Text(stringResource(R.string.s_delete), color = MaterialTheme.colorScheme.error) },
                leadingIcon = {
                    Icon(Icons.Default.Delete, contentDescription = null, tint = MaterialTheme.colorScheme.error)
                },
                onClick = {
                    menuOpen = false
                    onDelete()
                },
            )
        }
    }
}

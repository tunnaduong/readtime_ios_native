package com.fatties.readtime.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.MenuBook
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavHostController
import com.fatties.readtime.R
import com.fatties.readtime.data.AppleDate
import com.fatties.readtime.data.JournalEntry
import com.fatties.readtime.data.ReadingStore
import com.fatties.readtime.ui.Dates
import com.fatties.readtime.ui.components.ReadTimeCard
import com.fatties.readtime.ui.components.SecondaryText
import com.fatties.readtime.ui.theme.ReadTimeTheme

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun JournalScreen(store: ReadingStore, navController: NavHostController) {
    val state by store.state.collectAsStateWithLifecycle()
    var editing by remember { mutableStateOf<JournalEntry?>(null) }
    var isNew by remember { mutableStateOf(false) }

    Scaffold(
        containerColor = ReadTimeTheme.colors.background,
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.s_reading_journal), fontWeight = FontWeight.Bold) },
                navigationIcon = {
                    IconButton(onClick = { navController.popBackStack() }) {
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
        floatingActionButton = {
            FloatingActionButton(
                onClick = {
                    editing = JournalEntry(bookTitle = state.activeBook?.title.orEmpty(), text = "")
                    isNew = true
                },
                containerColor = ReadTimeTheme.colors.purple,
            ) {
                Icon(Icons.Default.Edit, contentDescription = stringResource(R.string.s_new_entry))
            }
        },
    ) { padding ->
        if (state.journalEntries.isEmpty()) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .padding(32.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                Icon(
                    Icons.Default.MenuBook,
                    contentDescription = null,
                    tint = ReadTimeTheme.colors.purple.copy(alpha = 0.6f),
                )
                Spacer(Modifier.height(12.dp))
                Text(
                    stringResource(R.string.s_no_journal_entries_yet),
                    style = MaterialTheme.typography.titleLarge,
                    color = ReadTimeTheme.colors.text,
                )
                Spacer(Modifier.height(8.dp))
                Text(
                    stringResource(R.string.s_write_down_quotes_ideas_and_feelings_from_your_reading_entri),
                    style = MaterialTheme.typography.bodyMedium,
                    color = ReadTimeTheme.colors.secondaryText,
                    textAlign = TextAlign.Center,
                )
            }
        } else {
            LazyColumn(
                contentPadding = PaddingValues(
                    start = 20.dp,
                    end = 20.dp,
                    top = padding.calculateTopPadding() + 8.dp,
                    bottom = 96.dp,
                ),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                items(state.journalEntries, key = { it.id }) { entry ->
                    JournalEntryRow(
                        entry = entry,
                        onClick = {
                            editing = entry
                            isNew = false
                        },
                    )
                }
            }
        }
    }

    editing?.let { entry ->
        JournalEntryEditor(
            entry = entry,
            isNew = isNew,
            bookTitles = state.books.map { it.title },
            onSave = {
                store.saveJournalEntry(it.copy(text = it.text.trim()))
                editing = null
            },
            onDelete = {
                store.deleteJournalEntry(entry.id)
                editing = null
            },
            onCancel = { editing = null },
        )
    }
}

@Composable
private fun JournalEntryRow(entry: JournalEntry, onClick: () -> Unit) {
    ReadTimeCard(modifier = Modifier.clickable(onClick = onClick), padding = 14.dp) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                Dates.abbreviatedWithTime(Dates.local(entry.date)),
                style = MaterialTheme.typography.bodySmall,
                color = ReadTimeTheme.colors.secondaryText,
                modifier = Modifier.weight(1f),
            )
            if (entry.bookTitle.isNotEmpty()) {
                Text(
                    entry.bookTitle,
                    style = MaterialTheme.typography.labelSmall,
                    color = ReadTimeTheme.colors.purple,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
        Spacer(Modifier.height(6.dp))
        Text(
            entry.text,
            style = MaterialTheme.typography.bodyLarge,
            color = ReadTimeTheme.colors.text,
            maxLines = 4,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun JournalEntryEditor(
    entry: JournalEntry,
    isNew: Boolean,
    bookTitles: List<String>,
    onSave: (JournalEntry) -> Unit,
    onDelete: () -> Unit,
    onCancel: () -> Unit,
) {
    var text by remember { mutableStateOf(entry.text) }
    var bookTitle by remember { mutableStateOf(entry.bookTitle) }
    var pickingBook by remember { mutableStateOf(false) }
    var confirmingDelete by remember { mutableStateOf(false) }
    val context = LocalContext.current

    // Keep the entry's book selectable even if it was removed from the library.
    val titles = remember(bookTitles, entry.bookTitle) {
        if (entry.bookTitle.isNotEmpty() && !bookTitles.contains(entry.bookTitle)) {
            listOf(entry.bookTitle) + bookTitles
        } else {
            bookTitles
        }
    }

    AlertDialog(
        onDismissRequest = onCancel,
        title = {
            Text(stringResource(if (isNew) R.string.s_new_entry else R.string.s_edit_entry))
        },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                ExposedDropdownMenuBox(
                    expanded = pickingBook,
                    onExpandedChange = { pickingBook = it },
                ) {
                    OutlinedTextField(
                        value = bookTitle.ifEmpty { stringResource(R.string.s_none) },
                        onValueChange = {},
                        readOnly = true,
                        label = { Text(stringResource(R.string.s_book)) },
                        trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = pickingBook) },
                        modifier = Modifier
                            .menuAnchor(androidx.compose.material3.MenuAnchorType.PrimaryNotEditable)
                            .fillMaxWidth(),
                    )
                    ExposedDropdownMenu(expanded = pickingBook, onDismissRequest = { pickingBook = false }) {
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.s_none)) },
                            onClick = {
                                bookTitle = ""
                                pickingBook = false
                            },
                        )
                        titles.forEach { title ->
                            DropdownMenuItem(
                                text = { Text(title) },
                                onClick = {
                                    bookTitle = title
                                    pickingBook = false
                                },
                            )
                        }
                    }
                }

                OutlinedTextField(
                    value = text,
                    onValueChange = { text = it },
                    label = { Text(stringResource(R.string.s_entry)) },
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(180.dp),
                )

                if (!isNew) {
                    TextButton(onClick = { confirmingDelete = true }) {
                        Icon(Icons.Default.Delete, contentDescription = null, tint = MaterialTheme.colorScheme.error)
                        Spacer(Modifier.width(6.dp))
                        Text(stringResource(R.string.s_delete_entry), color = MaterialTheme.colorScheme.error)
                    }
                }
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    onSave(entry.copy(text = text, bookTitle = bookTitle, date = entry.date.takeIf { !isNew } ?: AppleDate.now()))
                },
                enabled = text.isNotBlank(),
            ) {
                Icon(Icons.Default.Check, contentDescription = null)
                Spacer(Modifier.width(6.dp))
                Text(stringResource(R.string.s_save))
            }
        },
        dismissButton = {
            TextButton(onClick = onCancel) {
                Icon(Icons.Default.Close, contentDescription = null)
                Spacer(Modifier.width(6.dp))
                Text(stringResource(R.string.s_cancel))
            }
        },
    )

    if (confirmingDelete) {
        AlertDialog(
            onDismissRequest = { confirmingDelete = false },
            title = { Text(stringResource(R.string.s_delete_this_entry)) },
            confirmButton = {
                TextButton(onClick = onDelete) {
                    Text(stringResource(R.string.s_delete_entry), color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { confirmingDelete = false }) { Text(stringResource(R.string.s_cancel)) }
            },
        )
    }
}

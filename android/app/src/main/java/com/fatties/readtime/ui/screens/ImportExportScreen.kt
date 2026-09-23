package com.fatties.readtime.ui.screens

import android.content.Intent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Save
import androidx.compose.material.icons.filled.TableChart
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
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
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavHostController
import com.fatties.readtime.R
import com.fatties.readtime.data.LibraryTransfer
import com.fatties.readtime.data.ReadingSnapshot
import com.fatties.readtime.data.ReadingStore
import com.fatties.readtime.ui.components.CardTitle
import com.fatties.readtime.ui.components.ReadTimeCard
import com.fatties.readtime.ui.components.SecondaryText
import com.fatties.readtime.ui.theme.ReadTimeTheme

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ImportExportScreen(store: ReadingStore, navController: NavHostController) {
    val context = LocalContext.current
    val state by store.state.collectAsStateWithLifecycle()
    var message by remember { mutableStateOf<String?>(null) }
    var pendingBackup by remember { mutableStateOf<ReadingSnapshot?>(null) }

    fun share(uri: android.net.Uri, mimeType: String) {
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = mimeType
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(Intent.createChooser(intent, null))
    }

    val pickCSV = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        runCatching { LibraryTransfer.booksFromCSV(context, uri) }
            .onSuccess { books ->
                val added = store.importBooks(books)
                message = context.resources.getQuantityString(R.plurals.s_imported_n_books, added, added)
            }
            .onFailure {
                message = context.getString(R.string.s_no_books_were_found_in_this_file_export_your_library_as_csv)
            }
    }

    val pickBackup = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        runCatching { LibraryTransfer.readBackup(context, uri) }
            .onSuccess { pendingBackup = it }
            .onFailure {
                message = context.getString(R.string.s_no_books_were_found_in_this_file_export_your_library_as_csv)
            }
    }

    Scaffold(
        containerColor = ReadTimeTheme.colors.background,
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.s_import_export), fontWeight = FontWeight.SemiBold) },
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
                ReadTimeCard(padding = 4.dp) {
                    Column {
                        RowHeader(stringResource(R.string.s_export))
                        SettingsLikeRow(stringResource(R.string.s_export_backup_json), Icons.Default.Save) {
                            runCatching { LibraryTransfer.backupFile(context, store.snapshot()) }
                                .onSuccess { share(it, "application/json") }
                        }
                        SettingsLikeRow(stringResource(R.string.s_export_books_csv), Icons.Default.TableChart) {
                            runCatching { LibraryTransfer.booksCSVFile(context, state.books) }
                                .onSuccess { share(it, "text/csv") }
                        }
                    }
                }
            }

            item {
                SecondaryText(stringResource(R.string.s_a_backup_has_everything_books_sessions_journal_and_goals_the))
            }

            item {
                ReadTimeCard(padding = 4.dp) {
                    Column {
                        RowHeader(stringResource(R.string.s_import))
                        SettingsLikeRow(
                            stringResource(R.string.s_import_from_goodreads_or_storygraph),
                            Icons.Default.Download,
                        ) {
                            pickCSV.launch(arrayOf("text/csv", "text/comma-separated-values", "text/plain", "*/*"))
                        }
                        SettingsLikeRow(stringResource(R.string.s_restore_from_backup_file), Icons.Default.History) {
                            pickBackup.launch(arrayOf("application/json", "text/plain", "*/*"))
                        }
                    }
                }
            }

            item {
                SecondaryText(stringResource(R.string.s_in_goodreads_go_to_my_books_import_and_export_export_library))
            }
        }
    }

    pendingBackup?.let { backup ->
        AlertDialog(
            onDismissRequest = { pendingBackup = null },
            title = { Text(stringResource(R.string.s_restore_this_backup)) },
            confirmButton = {
                TextButton(onClick = {
                    store.restore(backup)
                    pendingBackup = null
                    message = context.getString(R.string.s_your_reading_data_was_restored)
                }) {
                    Text(
                        stringResource(R.string.s_replace_data_on_this_iphone),
                        color = MaterialTheme.colorScheme.error,
                    )
                }
            },
            dismissButton = {
                TextButton(onClick = { pendingBackup = null }) { Text(stringResource(R.string.s_cancel)) }
            },
        )
    }

    message?.let { text ->
        AlertDialog(
            onDismissRequest = { message = null },
            text = { Text(text) },
            confirmButton = {
                TextButton(onClick = { message = null }) { Text(stringResource(R.string.s_ok)) }
            },
        )
    }
}

@Composable
private fun RowHeader(title: String) {
    CardTitle(title, modifier = Modifier.padding(start = 12.dp, top = 10.dp, bottom = 2.dp))
}

@Composable
private fun SettingsLikeRow(title: String, icon: ImageVector, onClick: () -> Unit) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 14.dp),
    ) {
        Icon(icon, contentDescription = null, tint = ReadTimeTheme.colors.text)
        Spacer(Modifier.width(12.dp))
        Text(title, color = ReadTimeTheme.colors.text)
    }
}

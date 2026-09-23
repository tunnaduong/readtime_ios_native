package com.fatties.readtime.ui.screens

import android.content.Intent
import android.net.Uri
import android.provider.Settings as AndroidSettings
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.ImportExport
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Language
import androidx.compose.material.icons.filled.LibraryBooks
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.WorkspacePremium
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavHostController
import com.fatties.readtime.BuildConfig
import com.fatties.readtime.R
import com.fatties.readtime.data.AppLanguage
import com.fatties.readtime.data.AppearanceController
import com.fatties.readtime.data.AppearanceMode
import com.fatties.readtime.data.PurchaseManager
import com.fatties.readtime.data.ReadingStore
import com.fatties.readtime.ui.Routes
import com.fatties.readtime.ui.components.CardTitle
import com.fatties.readtime.ui.components.ReadTimeCard
import com.fatties.readtime.ui.components.SecondaryText
import com.fatties.readtime.ui.theme.ReadTimeTheme

object AppInfo {
    const val SUPPORT_EMAIL = "support@tunnaduong.com"
    const val TERMS_URL = "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
    val version: String get() = "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})"
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    store: ReadingStore,
    purchases: PurchaseManager,
    appearance: AppearanceController,
    navController: NavHostController,
) {
    val context = LocalContext.current
    val state by store.state.collectAsStateWithLifecycle()
    val purchaseState by purchases.state.collectAsStateWithLifecycle()
    var confirmingClearDemo by remember { mutableStateOf(false) }
    var choosingLanguage by remember { mutableStateOf(false) }
    var language by remember { mutableStateOf(AppLanguage.current()) }

    val hasDemo = remember(state.books, state.activities, state.journalEntries) { store.hasDemoContent }

    Scaffold(
        containerColor = ReadTimeTheme.colors.background,
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.s_settings), fontWeight = FontWeight.SemiBold) },
                navigationIcon = {
                    IconButton(onClick = { navController.popBackStack() }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.s_done))
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
                    SettingsRow(
                        title = stringResource(
                            if (purchaseState.isPremium) R.string.s_readtime_premium else R.string.s_get_premium
                        ),
                        icon = Icons.Default.WorkspacePremium,
                        tint = ReadTimeTheme.colors.purple,
                        value = if (purchaseState.isPremium) stringResource(R.string.s_no_ads) else purchaseState.priceDescription,
                        enabled = !purchaseState.isPremium,
                    ) { navController.navigate(Routes.PAYWALL) }
                }
            }

            item {
                ReadTimeCard {
                    CardTitle(stringResource(R.string.s_appearance))
                    Spacer(Modifier.height(12.dp))
                    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                        AppearanceMode.entries.forEachIndexed { index, mode ->
                            SegmentedButton(
                                selected = appearance.mode == mode,
                                onClick = { appearance.set(context, mode) },
                                shape = SegmentedButtonDefaults.itemShape(index, AppearanceMode.entries.size),
                                colors = SegmentedButtonDefaults.colors(
                                    activeContainerColor = ReadTimeTheme.colors.purple.copy(alpha = 0.16f),
                                    activeContentColor = ReadTimeTheme.colors.purple,
                                ),
                            ) {
                                Text(
                                    stringResource(
                                        when (mode) {
                                            AppearanceMode.SYSTEM -> R.string.s_system
                                            AppearanceMode.LIGHT -> R.string.s_light
                                            AppearanceMode.DARK -> R.string.s_dark
                                        }
                                    )
                                )
                            }
                        }
                    }
                }
            }

            item {
                ReadTimeCard(padding = 4.dp) {
                    SettingsRow(
                        title = stringResource(R.string.s_language),
                        icon = Icons.Default.Language,
                        value = language.displayName(stringResource(R.string.s_system)),
                    ) { choosingLanguage = true }
                }
            }

            item {
                ReadTimeCard(padding = 4.dp) {
                    SettingsRow(
                        title = stringResource(R.string.s_import_export),
                        icon = Icons.Default.ImportExport,
                    ) { navController.navigate(Routes.IMPORT_EXPORT) }
                }
            }

            item {
                ReadTimeCard(padding = 4.dp) {
                    SettingsRow(
                        title = stringResource(R.string.s_load_demo_content),
                        icon = Icons.Default.LibraryBooks,
                        tint = if (hasDemo) ReadTimeTheme.colors.secondaryText else ReadTimeTheme.colors.purple,
                        enabled = !hasDemo,
                    ) { store.loadDemoContent() }
                    SettingsRow(
                        title = stringResource(R.string.s_clear_demo_content),
                        icon = Icons.Default.Delete,
                        tint = if (hasDemo) MaterialTheme.colorScheme.error else ReadTimeTheme.colors.secondaryText,
                        enabled = hasDemo,
                    ) { confirmingClearDemo = true }
                }
            }

            item {
                ReadTimeCard(padding = 4.dp) {
                    SettingsRow(stringResource(R.string.s_about), Icons.Default.Info) {
                        navController.navigate(Routes.ABOUT)
                    }
                    SettingsRow(stringResource(R.string.s_send_feedback), Icons.Default.Email) {
                        val body = "\n\n---\nApp version: ${AppInfo.version}\nAndroid ${android.os.Build.VERSION.RELEASE}"
                        val intent = Intent(Intent.ACTION_SENDTO).apply {
                            data = Uri.parse("mailto:${AppInfo.SUPPORT_EMAIL}")
                            putExtra(Intent.EXTRA_SUBJECT, context.getString(R.string.s_readtime_support))
                            putExtra(Intent.EXTRA_TEXT, body)
                        }
                        runCatching { context.startActivity(intent) }
                    }
                    SettingsRow(stringResource(R.string.s_share_readtime), Icons.Default.Share) {
                        val intent = Intent(Intent.ACTION_SEND).apply {
                            type = "text/plain"
                            putExtra(
                                Intent.EXTRA_TEXT,
                                context.getString(R.string.s_i_m_building_a_reading_habit_with_readtime),
                            )
                        }
                        context.startActivity(Intent.createChooser(intent, null))
                    }
                    SettingsRow(stringResource(R.string.s_terms_of_use), Icons.Default.Description) {
                        runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(AppInfo.TERMS_URL))) }
                    }
                }
            }

            item {
                Text(
                    stringResource(R.string.s_app_version_s, AppInfo.version),
                    style = MaterialTheme.typography.bodySmall,
                    color = ReadTimeTheme.colors.secondaryText,
                    textAlign = TextAlign.Center,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 12.dp),
                )
            }
        }
    }

    if (choosingLanguage) {
        AlertDialog(
            onDismissRequest = { choosingLanguage = false },
            title = { Text(stringResource(R.string.s_language)) },
            text = {
                Column {
                    AppLanguage.entries.forEach { option ->
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable {
                                    language = option
                                    choosingLanguage = false
                                    // Recreates the activity with the new language.
                                    AppLanguage.apply(option)
                                }
                                .padding(vertical = 12.dp),
                        ) {
                            Text(
                                option.displayName(stringResource(R.string.s_system)),
                                color = ReadTimeTheme.colors.text,
                                modifier = Modifier.weight(1f),
                            )
                            if (option == language) {
                                Icon(Icons.Default.Check, contentDescription = null, tint = ReadTimeTheme.colors.purple)
                            }
                        }
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = { choosingLanguage = false }) { Text(stringResource(R.string.s_cancel)) }
            },
        )
    }

    if (confirmingClearDemo) {
        AlertDialog(
            onDismissRequest = { confirmingClearDemo = false },
            title = { Text(stringResource(R.string.s_clear_demo_content_2)) },
            confirmButton = {
                TextButton(onClick = {
                    store.clearDemoContent()
                    confirmingClearDemo = false
                }) {
                    Text(stringResource(R.string.s_clear_demo_content), color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { confirmingClearDemo = false }) { Text(stringResource(R.string.s_cancel)) }
            },
        )
    }
}

@Composable
private fun SettingsRow(
    title: String,
    icon: ImageVector,
    value: String? = null,
    trailing: ImageVector? = null,
    tint: Color = ReadTimeTheme.colors.text,
    enabled: Boolean = true,
    onClick: () -> Unit,
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .clickable(enabled = enabled, onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 14.dp),
    ) {
        Icon(icon, contentDescription = null, tint = tint)
        Spacer(Modifier.width(12.dp))
        Text(title, color = tint, modifier = Modifier.weight(1f))
        if (value != null) {
            Text(value, color = ReadTimeTheme.colors.secondaryText)
            Spacer(Modifier.width(6.dp))
        }
        if (trailing != null) {
            Icon(trailing, contentDescription = null, tint = ReadTimeTheme.colors.secondaryText)
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AboutScreen(navController: NavHostController) {
    Scaffold(
        containerColor = ReadTimeTheme.colors.background,
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.s_about), fontWeight = FontWeight.SemiBold) },
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
        Column(
            modifier = Modifier
                .padding(padding)
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            ReadTimeCard {
                CardTitle(stringResource(R.string.app_name))
                Spacer(Modifier.height(6.dp))
                SecondaryText(stringResource(R.string.s_app_version_s, AppInfo.version))
            }
            ReadTimeCard {
                SecondaryText(stringResource(R.string.s_make_time_for_the_books_that_matter))
            }
        }
    }
}

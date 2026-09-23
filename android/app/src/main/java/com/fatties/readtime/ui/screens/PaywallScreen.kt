package com.fatties.readtime.ui.screens

import android.app.Activity
import androidx.compose.foundation.background
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
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.fatties.readtime.R
import com.fatties.readtime.data.PurchaseManager
import com.fatties.readtime.ui.theme.ReadTimeTheme

private data class Benefit(val titleRes: Int, val detailRes: Int, val icon: ImageVector)

private val BENEFITS = listOf(
    Benefit(R.string.s_no_ads, R.string.s_read_without_banners_full_screen_ads_or_ads_when_you_open_th, Icons.Default.VisibilityOff),
    Benefit(R.string.s_support_an_independent_developer, R.string.s_your_purchase_keeps_readtime_growing_and_improving, Icons.Default.Favorite),
    Benefit(R.string.s_everything_else_stays_free, R.string.s_goals_reading_sessions_stats_journal_and_icloud_backup_are_y, Icons.Default.CheckCircle),
)

/** The Premium pitch, matching the iOS paywall. */
@Composable
fun PaywallScreen(purchases: PurchaseManager, onClose: () -> Unit) {
    val state by purchases.state.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val activity = context as? Activity

    Column(
        Modifier
            .fillMaxSize()
            .background(ReadTimeTheme.colors.purple)
    ) {
        LazyColumn(
            modifier = Modifier.weight(1f),
            contentPadding = PaddingValues(24.dp),
            verticalArrangement = Arrangement.spacedBy(28.dp),
        ) {
            item {
                IconButton(onClick = onClose) {
                    Icon(
                        Icons.Default.Close,
                        contentDescription = stringResource(R.string.s_close),
                        tint = Color.White,
                    )
                }
            }

            item {
                Text(
                    stringResource(R.string.s_why_readers_go_premium),
                    style = MaterialTheme.typography.headlineSmall,
                    color = Color.White,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth(),
                )
            }

            items(BENEFITS.size) { index ->
                val benefit = BENEFITS[index]
                Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                    Box(
                        modifier = Modifier
                            .size(48.dp)
                            .clip(RoundedCornerShape(12.dp))
                            .background(Color.White.copy(alpha = 0.18f)),
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(benefit.icon, contentDescription = null, tint = Color.White)
                    }
                    Column {
                        Text(
                            stringResource(benefit.titleRes),
                            style = MaterialTheme.typography.titleMedium,
                            color = Color.White,
                        )
                        Spacer(Modifier.height(4.dp))
                        Text(
                            stringResource(benefit.detailRes),
                            style = MaterialTheme.typography.bodyMedium,
                            color = Color.White.copy(alpha = 0.8f),
                        )
                    }
                }
            }
        }

        Column(
            modifier = Modifier.padding(horizontal = 24.dp, vertical = 16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Button(
                onClick = { activity?.let { purchases.buyPremium(it) } },
                enabled = !state.isWorking,
                shape = CircleShape,
                colors = ButtonDefaults.buttonColors(containerColor = Color.White),
                modifier = Modifier
                    .fillMaxWidth()
                    .height(56.dp),
            ) {
                if (state.isWorking) {
                    CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp, color = ReadTimeTheme.colors.purple)
                } else {
                    Text(
                        state.freeTrialDescription?.let { stringResource(R.string.s_try_s_free, it) }
                            ?: stringResource(R.string.s_get_premium),
                        style = MaterialTheme.typography.titleMedium,
                        color = ReadTimeTheme.colors.purple,
                    )
                }
            }

            state.priceDescription?.let { price ->
                Text(
                    if (state.freeTrialDescription != null) stringResource(R.string.s_then_s_cancel_anytime, price) else price,
                    style = MaterialTheme.typography.bodySmall,
                    color = Color.White.copy(alpha = 0.8f),
                )
            }

            TextButton(onClick = { purchases.restorePurchases() }) {
                Text(
                    stringResource(R.string.s_restore_purchases),
                    style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.SemiBold),
                    color = Color.White,
                )
            }
        }
    }

    state.message?.let { message ->
        AlertDialog(
            onDismissRequest = { purchases.clearMessage() },
            title = { Text(stringResource(R.string.s_premium)) },
            text = { Text(message) },
            confirmButton = {
                TextButton(onClick = { purchases.clearMessage() }) { Text(stringResource(R.string.s_ok)) }
            },
        )
    }
}

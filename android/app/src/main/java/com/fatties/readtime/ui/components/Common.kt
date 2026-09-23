package com.fatties.readtime.ui.components

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Book
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.fatties.readtime.data.Book
import com.fatties.readtime.data.CoverCache
import com.fatties.readtime.ui.theme.ReadTimeTheme

/** The white rounded card every section sits on (`.readTimeCard()` on iOS). */
@Composable
fun ReadTimeCard(
    modifier: Modifier = Modifier,
    padding: Dp = 16.dp,
    content: @Composable ColumnScope.() -> Unit,
) {
    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(14.dp),
        color = ReadTimeTheme.colors.card,
    ) {
        Column(modifier = Modifier.padding(padding), content = content)
    }
}

/** A title with a leading icon, as on the Home and Goals tabs. */
@Composable
fun SectionHeader(
    title: String,
    icon: ImageVector,
    modifier: Modifier = Modifier,
    action: @Composable RowScope.() -> Unit = {},
) {
    Row(
        modifier = modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(icon, contentDescription = null, tint = ReadTimeTheme.colors.text)
        Text(
            text = title,
            style = MaterialTheme.typography.titleMedium,
            color = ReadTimeTheme.colors.text,
            modifier = Modifier.weight(1f),
        )
        action()
    }
}

/** A bundled cover, a downloaded one, or a placeholder — the iOS `CoverImage`. */
@Composable
fun CoverImage(coverName: String?, coverURL: String?, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val drawable = coverName?.let { name ->
        val id = context.resources.getIdentifier(name.replace('-', '_'), "drawable", context.packageName)
        if (id == 0) null else id
    }
    Box(modifier = modifier.background(ReadTimeTheme.colors.purple.copy(alpha = 0.10f))) {
        when {
            drawable != null -> Image(
                painter = painterResource(drawable),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
            )

            coverURL != null -> AsyncImage(
                model = CoverCache.request(context, coverURL),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
            )

            else -> Icon(
                Icons.Default.Book,
                contentDescription = null,
                tint = ReadTimeTheme.colors.purple,
                modifier = Modifier.align(Alignment.Center),
            )
        }
    }
}

@Composable
fun BookCover(book: Book, width: Dp, height: Dp, modifier: Modifier = Modifier) {
    CoverImage(
        coverName = book.coverName,
        coverURL = book.coverURL,
        modifier = modifier
            .size(width, height)
            .clip(RoundedCornerShape(5.dp)),
    )
}

/** A rounded progress bar in the app's green. */
@Composable
fun ReadTimeProgress(progress: Float, modifier: Modifier = Modifier, color: Color = ReadTimeTheme.colors.green) {
    LinearProgressIndicator(
        progress = { progress.coerceIn(0f, 1f) },
        modifier = modifier
            .fillMaxWidth()
            .height(6.dp)
            .clip(CircleShape),
        color = color,
        trackColor = color.copy(alpha = 0.18f),
        drawStopIndicator = {},
    )
}

/** The pill showing which days a goal runs on. */
@Composable
fun GoalBadge(text: String, modifier: Modifier = Modifier) {
    Text(
        text = text,
        style = MaterialTheme.typography.labelSmall,
        color = ReadTimeTheme.colors.purple,
        maxLines = 1,
        modifier = modifier
            .border(1.dp, ReadTimeTheme.colors.purple.copy(alpha = 0.35f), CircleShape)
            .padding(horizontal = 10.dp, vertical = 6.dp),
    )
}

@Composable
fun SecondaryText(text: String, modifier: Modifier = Modifier) {
    Text(
        text = text,
        style = MaterialTheme.typography.bodyMedium,
        color = ReadTimeTheme.colors.secondaryText,
        modifier = modifier,
    )
}

@Composable
fun CardTitle(text: String, modifier: Modifier = Modifier, color: Color = ReadTimeTheme.colors.text) {
    Text(
        text = text,
        style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.SemiBold),
        color = color,
        modifier = modifier,
    )
}

/** Fixed-size spacer helpers keep the screen code close to the SwiftUI original. */
@Composable
fun VSpace(height: Dp) = Box(Modifier.height(height))

@Composable
fun HSpace(width: Dp) = Box(Modifier.width(width))

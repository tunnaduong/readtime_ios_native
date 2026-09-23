package com.fatties.readtime.widget

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalContext
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.LinearProgressIndicator
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.appwidget.updateAll
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.ContentScale
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.fatties.readtime.MainActivity
import com.fatties.readtime.R
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.roundToInt

private val PURPLE = Color(0xFF6941C6)
private val GREEN = Color(0xFF03B403)
private val AMBER = Color(0xFFE37D13)

/** The book you're reading and how far you've got. */
class CurrentBookWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val entry = WidgetData.load(context)
        provideContent {
            WidgetSurface {
                val book = entry.book
                if (book == null) {
                    EmptyState()
                } else {
                    Row(modifier = GlanceModifier.fillMaxSize(), verticalAlignment = Alignment.CenterVertically) {
                        Cover(entry, width = 60, height = 90)
                        Spacer(GlanceModifier.width(12.dp))
                        Column(modifier = GlanceModifier.defaultWeight()) {
                            Text(
                                book.title,
                                maxLines = 2,
                                style = TextStyle(
                                    color = GlanceTheme.colors.onSurface,
                                    fontSize = 15.sp,
                                    fontWeight = FontWeight.Medium,
                                ),
                            )
                            Text(
                                book.author,
                                maxLines = 1,
                                style = TextStyle(color = GlanceTheme.colors.onSurfaceVariant, fontSize = 13.sp),
                            )
                            Spacer(GlanceModifier.height(8.dp))
                            ProgressLine(book.progress)
                            Spacer(GlanceModifier.height(6.dp))
                            Row(modifier = GlanceModifier.fillMaxWidth()) {
                                Text(
                                    LocalContext.current.getString(
                                        R.string.s_page_n_of_n,
                                        book.currentPage,
                                        book.totalPages,
                                    ),
                                    style = TextStyle(color = GlanceTheme.colors.onSurfaceVariant, fontSize = 12.sp),
                                    modifier = GlanceModifier.defaultWeight(),
                                )
                                Text(
                                    "${(book.progress * 100).roundToInt()}%",
                                    style = TextStyle(color = ColorProvider(GREEN), fontSize = 12.sp),
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

/** Today's reading against your goal, and your streak. */
class DailyGoalWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val entry = WidgetData.load(context)
        provideContent {
            WidgetSurface {
                Row(modifier = GlanceModifier.fillMaxSize(), verticalAlignment = Alignment.CenterVertically) {
                    GoalRing(entry)
                    Spacer(GlanceModifier.width(16.dp))
                    Column(modifier = GlanceModifier.defaultWeight()) {
                        Text(
                            if (entry.streak > 0) {
                                LocalContext.current.getString(R.string.widget_n_day_streak, entry.streak)
                            } else {
                                LocalContext.current.getString(R.string.widget_start_a_streak)
                            },
                            maxLines = 2,
                            style = TextStyle(
                                color = if (entry.streak > 0) ColorProvider(AMBER) else GlanceTheme.colors.onSurfaceVariant,
                                fontSize = 13.sp,
                                fontWeight = if (entry.streak > 0) FontWeight.Medium else FontWeight.Normal,
                            ),
                        )
                        Spacer(GlanceModifier.height(10.dp))
                        WeekDots(entry)
                    }
                }
            }
        }
    }
}

@Composable
private fun WidgetSurface(content: @Composable () -> Unit) {
    GlanceTheme {
        Box(
            modifier = GlanceModifier
                .fillMaxSize()
                .background(GlanceTheme.colors.widgetBackground)
                .cornerRadius(16.dp)
                .padding(14.dp)
                .clickable(actionStartActivity(android.content.Intent(LocalContext.current, MainActivity::class.java))),
        ) {
            content()
        }
    }
}

@Composable
private fun Cover(entry: WidgetEntry, width: Int, height: Int) {
    val bitmap = entry.cover
    if (bitmap != null) {
        Image(
            provider = ImageProvider(bitmap),
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = GlanceModifier
                .size(width.dp, height.dp)
                .cornerRadius(6.dp),
        )
    } else {
        Box(
            modifier = GlanceModifier
                .size(width.dp, height.dp)
                .cornerRadius(6.dp)
                .background(ColorProvider(PURPLE.copy(alpha = 0.12f))),
            contentAlignment = Alignment.Center,
        ) {
            Image(
                provider = ImageProvider(R.drawable.ic_notification),
                contentDescription = null,
                modifier = GlanceModifier.size(22.dp),
            )
        }
    }
}

@Composable
private fun ProgressLine(progress: Float) {
    LinearProgressIndicator(
        progress = progress.coerceIn(0f, 1f),
        modifier = GlanceModifier.fillMaxWidth().height(6.dp).cornerRadius(3.dp),
        color = ColorProvider(GREEN),
        backgroundColor = ColorProvider(PURPLE.copy(alpha = 0.18f)),
    )
}

@Composable
private fun GoalRing(entry: WidgetEntry) {
    Column(
        modifier = GlanceModifier
            .size(92.dp)
            .cornerRadius(46.dp)
            .background(ColorProvider(PURPLE.copy(alpha = 0.12f)))
            .padding(10.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            "${entry.minutesToday}",
            style = TextStyle(
                color = ColorProvider(PURPLE),
                fontSize = 22.sp,
                fontWeight = FontWeight.Bold,
            ),
        )
        Text(
            LocalContext.current.getString(R.string.widget_of_n_min, entry.dailyGoal),
            maxLines = 1,
            style = TextStyle(color = GlanceTheme.colors.onSurfaceVariant, fontSize = 11.sp),
        )
    }
}

@Composable
private fun WeekDots(entry: WidgetEntry) {
    val formatter = DateTimeFormatter.ofPattern("EEEEE", Locale.getDefault())
    Row {
        entry.week.forEach { (day, minutes) ->
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = GlanceModifier.padding(end = 6.dp),
            ) {
                Text(
                    day.format(formatter),
                    style = TextStyle(color = GlanceTheme.colors.onSurfaceVariant, fontSize = 10.sp),
                )
                Spacer(GlanceModifier.height(4.dp))
                Box(
                    modifier = GlanceModifier
                        .size(10.dp)
                        .cornerRadius(5.dp)
                        .background(
                            ColorProvider(
                                when {
                                    entry.dailyGoal > 0 && minutes >= entry.dailyGoal -> GREEN
                                    minutes > 0 -> PURPLE.copy(alpha = 0.55f)
                                    else -> PURPLE.copy(alpha = 0.15f)
                                }
                            )
                        ),
                ) {}
            }
        }
    }
}

@Composable
private fun EmptyState() {
    Column(
        modifier = GlanceModifier.fillMaxSize(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            LocalContext.current.getString(R.string.widget_add_a_book),
            style = TextStyle(color = GlanceTheme.colors.onSurfaceVariant, fontSize = 13.sp),
        )
    }
}

class CurrentBookWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = CurrentBookWidget()
}

class DailyGoalWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = DailyGoalWidget()
}

/** Redraws both widgets, the counterpart of iOS's `WidgetCenter.reloadAllTimelines()`. */
object WidgetUpdater {
    suspend fun updateAll(context: Context) {
        runCatching {
            CurrentBookWidget().updateAll(context)
            DailyGoalWidget().updateAll(context)
        }
    }
}

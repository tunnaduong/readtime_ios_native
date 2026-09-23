package com.fatties.readtime.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import com.fatties.readtime.data.AppearanceMode

/** The app's palette, matching the iOS app's `Color.readTime…` values. */
data class ReadTimeColors(
    val purple: Color,
    val background: Color,
    val card: Color,
    val text: Color,
    val secondaryText: Color,
    val green: Color,
    val amber: Color,
)

private val LightColors = ReadTimeColors(
    purple = Color(0xFF6941C6),
    background = Color(0xFFF1F5F9),
    card = Color(0xFFFFFFFF),
    text = Color(0xFF334158),
    secondaryText = Color(0xFF6B7280),
    green = Color(0xFF03B403),
    amber = Color(0xFFE37D13),
)

private val DarkColors = ReadTimeColors(
    purple = Color(0xFF9A7BEA),
    background = Color(0xFF0B0C10),
    card = Color(0xFF1C1D23),
    text = Color(0xFFDAE0EA),
    secondaryText = Color(0xFF9CA3AF),
    green = Color(0xFF03B403),
    amber = Color(0xFFE37D13),
)

val LocalReadTimeColors = staticCompositionLocalOf { LightColors }

/** `Color.readTime…` on iOS; use as `ReadTimeTheme.colors.purple`. */
object ReadTimeTheme {
    val colors: ReadTimeColors
        @Composable @ReadOnlyComposable get() = LocalReadTimeColors.current
}

private val AppTypography = Typography(
    headlineSmall = TextStyle(fontSize = 22.sp, fontWeight = FontWeight.SemiBold),
    titleLarge = TextStyle(fontSize = 20.sp, fontWeight = FontWeight.SemiBold),
    titleMedium = TextStyle(fontSize = 17.sp, fontWeight = FontWeight.SemiBold),
    bodyLarge = TextStyle(fontSize = 16.sp),
    bodyMedium = TextStyle(fontSize = 15.sp),
    bodySmall = TextStyle(fontSize = 13.sp),
    labelSmall = TextStyle(fontSize = 11.sp, fontWeight = FontWeight.Medium),
)

@Composable
fun ReadTimeTheme(appearance: AppearanceMode = AppearanceMode.SYSTEM, content: @Composable () -> Unit) {
    val dark = when (appearance) {
        AppearanceMode.SYSTEM -> isSystemInDarkTheme()
        AppearanceMode.LIGHT -> false
        AppearanceMode.DARK -> true
    }
    val colors = if (dark) DarkColors else LightColors
    val scheme = if (dark) {
        darkColorScheme(
            primary = colors.purple,
            onPrimary = Color.White,
            background = colors.background,
            onBackground = colors.text,
            surface = colors.card,
            onSurface = colors.text,
            surfaceVariant = colors.card,
            onSurfaceVariant = colors.secondaryText,
            secondary = colors.purple,
        )
    } else {
        lightColorScheme(
            primary = colors.purple,
            onPrimary = Color.White,
            background = colors.background,
            onBackground = colors.text,
            surface = colors.card,
            onSurface = colors.text,
            surfaceVariant = colors.card,
            onSurfaceVariant = colors.secondaryText,
            secondary = colors.purple,
        )
    }

    CompositionLocalProvider(LocalReadTimeColors provides colors) {
        MaterialTheme(colorScheme = scheme, typography = AppTypography, content = content)
    }
}

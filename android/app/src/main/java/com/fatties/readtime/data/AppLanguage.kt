package com.fatties.readtime.data

import androidx.appcompat.app.AppCompatDelegate
import androidx.core.os.LocaleListCompat
import java.util.Locale

/**
 * The languages ReadTime ships, chosen inside the app. Android 13+ stores the choice as a
 * per-app language in system settings; older versions keep it in the app's own storage
 * (`autoStoreLocales` in the manifest).
 */
enum class AppLanguage(val tag: String) {
    SYSTEM(""),
    ENGLISH("en"),
    VIETNAMESE("vi"),
    SPANISH("es"),
    JAPANESE("ja"),
    CHINESE_SIMPLIFIED("zh-Hans");

    /** The language's own name, e.g. "Tiếng Việt". */
    fun displayName(systemLabel: String): String {
        if (this == SYSTEM) return systemLabel
        val locale = Locale.forLanguageTag(tag)
        return locale.getDisplayName(locale).replaceFirstChar { it.titlecase(locale) }
    }

    companion object {
        /** The language the app is currently showing, or [SYSTEM] when it follows the device. */
        fun current(): AppLanguage {
            val tag = AppCompatDelegate.getApplicationLocales().toLanguageTags()
            if (tag.isEmpty()) return SYSTEM
            return entries.firstOrNull { it.tag.isNotEmpty() && tag.startsWith(it.tag) } ?: SYSTEM
        }

        fun apply(language: AppLanguage) {
            val locales = if (language == SYSTEM) {
                LocaleListCompat.getEmptyLocaleList()
            } else {
                LocaleListCompat.forLanguageTags(language.tag)
            }
            AppCompatDelegate.setApplicationLocales(locales)
        }
    }
}

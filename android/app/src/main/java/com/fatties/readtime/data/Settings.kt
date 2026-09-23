package com.fatties.readtime.data

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/** Device preferences, the counterpart of the iOS app's `@AppStorage` values. */
object Settings {
    private const val NAME = "readtime"
    private const val KEY_APPEARANCE = "appearance"
    private const val KEY_ACTIVE_SESSION = "activeSession"
    private const val KEY_REFERRAL_SENT = "referralAnswerSent"
    private const val KEY_ONBOARDED = "hasOnboarded"

    private fun preferences(context: Context) = context.getSharedPreferences(NAME, Context.MODE_PRIVATE)

    fun appearance(context: Context): AppearanceMode =
        AppearanceMode.fromRaw(preferences(context).getString(KEY_APPEARANCE, null))

    fun setAppearance(context: Context, mode: AppearanceMode) {
        preferences(context).edit().putString(KEY_APPEARANCE, mode.rawValue).apply()
    }

    fun activeSession(context: Context): ActiveSessionState? {
        val raw = preferences(context).getString(KEY_ACTIVE_SESSION, null) ?: return null
        return runCatching { LocalStore.json.decodeFromString<ActiveSessionState>(raw) }.getOrNull()
    }

    fun setActiveSession(context: Context, session: ActiveSessionState?) {
        val editor = preferences(context).edit()
        if (session == null) editor.remove(KEY_ACTIVE_SESSION)
        else editor.putString(KEY_ACTIVE_SESSION, LocalStore.json.encodeToString(ActiveSessionState.serializer(), session))
        editor.apply()
    }

    fun referralAnswerSent(context: Context): Boolean = preferences(context).getBoolean(KEY_REFERRAL_SENT, false)

    fun setReferralAnswerSent(context: Context) {
        preferences(context).edit().putBoolean(KEY_REFERRAL_SENT, true).apply()
    }

    fun hasOnboarded(context: Context): Boolean = preferences(context).getBoolean(KEY_ONBOARDED, false)

    fun setHasOnboarded(context: Context) {
        preferences(context).edit().putBoolean(KEY_ONBOARDED, true).apply()
    }
}

enum class AppearanceMode(val rawValue: String) {
    SYSTEM("system"),
    LIGHT("light"),
    DARK("dark");

    companion object {
        fun fromRaw(raw: String?): AppearanceMode = entries.firstOrNull { it.rawValue == raw } ?: SYSTEM
    }
}

/** Holds the chosen appearance for the whole app, so Settings can change it live. */
class AppearanceController(context: Context) {
    var mode by mutableStateOf(Settings.appearance(context))
        private set

    fun set(context: Context, newMode: AppearanceMode) {
        mode = newMode
        Settings.setAppearance(context, newMode)
    }
}

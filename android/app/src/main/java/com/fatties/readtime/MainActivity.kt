package com.fatties.readtime

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.runtime.remember
import com.fatties.readtime.data.AdManager
import com.fatties.readtime.data.AppearanceController
import com.fatties.readtime.data.ReadTimeStoreFactory
import com.fatties.readtime.data.ReadingStore
import com.fatties.readtime.data.PurchaseManager
import com.fatties.readtime.data.PurchaseManagerFactory
import com.fatties.readtime.data.ReminderManager
import com.fatties.readtime.ui.ReadTimeApp
import com.fatties.readtime.ui.theme.ReadTimeTheme

class MainActivity : AppCompatActivity() {
    private val store: ReadingStore by viewModels { ReadTimeStoreFactory(application) }
    private val purchases: PurchaseManager by viewModels { PurchaseManagerFactory(application) }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        ReminderManager.createChannel(this)
        // Ads start once onboarding is behind the reader, like the iOS app.
        if (!store.state.value.needsOnboarding) AdManager.start(this)

        setContent {
            val appearance = remember { AppearanceController(this) }
            ReadTimeTheme(appearance.mode) {
                ReadTimeApp(store = store, purchases = purchases, appearance = appearance)
            }
        }
    }

    override fun onStop() {
        super.onStop()
        // Leaving the app is the last chance to write anything still held in memory.
        store.save()
    }
}

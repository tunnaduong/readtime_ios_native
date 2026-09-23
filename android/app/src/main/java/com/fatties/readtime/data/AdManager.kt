package com.fatties.readtime.data

import android.app.Activity
import android.content.Context
import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.fatties.readtime.BuildConfig
import com.google.android.gms.ads.AdError
import com.google.android.gms.ads.AdRequest
import com.google.android.gms.ads.FullScreenContentCallback
import com.google.android.gms.ads.LoadAdError
import com.google.android.gms.ads.MobileAds
import com.google.android.gms.ads.interstitial.InterstitialAd
import com.google.android.gms.ads.interstitial.InterstitialAdLoadCallback

/**
 * Google AdMob: a banner at the top of the main tabs, and an interstitial when a reading
 * session ends — the same places the iOS app shows them. Premium readers see none.
 *
 * The unit ids come from `BuildConfig` and default to Google's test ids; set the real ones in
 * `android/local.properties` (`admobAppId`, `admobBannerUnitId`, `admobInterstitialUnitId`).
 */
object AdManager {
    const val BANNER_UNIT_ID = BuildConfig.ADMOB_BANNER_UNIT_ID
    private const val INTERSTITIAL_UNIT_ID = BuildConfig.ADMOB_INTERSTITIAL_UNIT_ID

    /** Premium readers never see ads; banners and interstitials check this. */
    var isAdFree by mutableStateOf(false)

    var isStarted by mutableStateOf(false)
        private set

    private var interstitial: InterstitialAd? = null
    private var isLoading = false

    fun start(context: Context) {
        if (isStarted || isAdFree) return
        isStarted = true
        MobileAds.initialize(context.applicationContext) {
            loadInterstitial(context.applicationContext)
        }
    }

    private fun loadInterstitial(context: Context) {
        if (isAdFree || interstitial != null || isLoading) return
        isLoading = true
        InterstitialAd.load(
            context,
            INTERSTITIAL_UNIT_ID,
            AdRequest.Builder().build(),
            object : InterstitialAdLoadCallback() {
                override fun onAdLoaded(ad: InterstitialAd) {
                    isLoading = false
                    interstitial = ad
                }

                override fun onAdFailedToLoad(error: LoadAdError) {
                    isLoading = false
                    interstitial = null
                    Log.d("ReadTime", "interstitial failed: ${error.message}")
                }
            },
        )
    }

    /**
     * Shows the interstitial if one is ready, then runs [onDismiss]. When no ad is ready the
     * callback runs straight away, so the app never waits on an ad.
     */
    fun showInterstitial(activity: Activity?, onDismiss: () -> Unit) {
        val ad = interstitial
        if (isAdFree || activity == null || ad == null) {
            onDismiss()
            if (!isAdFree && activity != null) loadInterstitial(activity.applicationContext)
            return
        }
        ad.fullScreenContentCallback = object : FullScreenContentCallback() {
            override fun onAdDismissedFullScreenContent() {
                interstitial = null
                loadInterstitial(activity.applicationContext)
                onDismiss()
            }

            override fun onAdFailedToShowFullScreenContent(error: AdError) {
                interstitial = null
                loadInterstitial(activity.applicationContext)
                onDismiss()
            }
        }
        interstitial = null
        ad.show(activity)
    }
}

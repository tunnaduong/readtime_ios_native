package com.fatties.readtime.data

import android.app.Activity
import android.app.Application
import android.util.Log
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.android.billingclient.api.AcknowledgePurchaseParams
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingFlowParams
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.PendingPurchasesParams
import com.android.billingclient.api.ProductDetails
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.PurchasesUpdatedListener
import com.android.billingclient.api.QueryProductDetailsParams
import com.android.billingclient.api.QueryPurchasesParams
import com.android.billingclient.api.acknowledgePurchase
import com.android.billingclient.api.queryProductDetails
import com.android.billingclient.api.queryPurchasesAsync
import com.fatties.readtime.BuildConfig
import com.fatties.readtime.R
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** What the paywall and settings read about Premium. */
data class PurchaseState(
    val isPremium: Boolean = false,
    val isWorking: Boolean = false,
    /** The localised price, e.g. "29.000 ₫" or "US$4.99/year". */
    val priceDescription: String? = null,
    /** How long the introductory free trial runs, when the product offers one. */
    val freeTrialDescription: String? = null,
    val message: String? = null,
)

/**
 * Google Play Billing, the Android counterpart of the iOS StoreKit `PurchaseManager`.
 * The product is looked up as a subscription first, then as a one-time purchase, so the same
 * product id works either way.
 */
class PurchaseManager(application: Application) : AndroidViewModel(application), PurchasesUpdatedListener {
    private val context get() = getApplication<Application>()
    private val productID = BuildConfig.PREMIUM_PRODUCT_ID

    private val _state = MutableStateFlow(PurchaseState())
    val state: StateFlow<PurchaseState> = _state.asStateFlow()

    private var product: ProductDetails? = null
    private var productType = BillingClient.ProductType.SUBS

    private val billing = BillingClient.newBuilder(application)
        .setListener(this)
        .enablePendingPurchases(PendingPurchasesParams.newBuilder().enableOneTimeProducts().build())
        .build()

    init {
        connect()
    }

    private fun connect() {
        billing.startConnection(object : BillingClientStateListener {
            override fun onBillingSetupFinished(result: BillingResult) {
                if (result.responseCode != BillingClient.BillingResponseCode.OK) {
                    Log.d("ReadTime", "billing unavailable: ${result.debugMessage}")
                    return
                }
                viewModelScope.launch {
                    loadProduct()
                    refreshEntitlements()
                }
            }

            override fun onBillingServiceDisconnected() {
                // Play reconnects on the next purchase or refresh; nothing to do here.
            }
        })
    }

    private suspend fun loadProduct() {
        for (type in listOf(BillingClient.ProductType.SUBS, BillingClient.ProductType.INAPP)) {
            val params = QueryProductDetailsParams.newBuilder()
                .setProductList(
                    listOf(
                        QueryProductDetailsParams.Product.newBuilder()
                            .setProductId(productID)
                            .setProductType(type)
                            .build()
                    )
                )
                .build()
            val result = billing.queryProductDetails(params)
            val details = result.productDetailsList?.firstOrNull()
            if (details != null) {
                product = details
                productType = type
                _state.value = _state.value.copy(
                    priceDescription = priceOf(details),
                    freeTrialDescription = freeTrialOf(details),
                )
                return
            }
        }
    }

    private fun priceOf(details: ProductDetails): String? {
        details.oneTimePurchaseOfferDetails?.let { return it.formattedPrice }
        val phase = details.subscriptionOfferDetails
            ?.flatMap { it.pricingPhases.pricingPhaseList }
            ?.firstOrNull { it.priceAmountMicros > 0 }
            ?: return null
        return "${phase.formattedPrice}/${periodLabel(phase.billingPeriod)}"
    }

    private fun freeTrialOf(details: ProductDetails): String? {
        val trial = details.subscriptionOfferDetails
            ?.flatMap { it.pricingPhases.pricingPhaseList }
            ?.firstOrNull { it.priceAmountMicros == 0L }
            ?: return null
        return periodLabel(trial.billingPeriod, plural = true)
    }

    /** Turns an ISO 8601 period such as "P1Y" or "P7D" into "year" / "7 days". */
    private fun periodLabel(period: String, plural: Boolean = false): String {
        val match = Regex("P(\\d+)([DWMY])").find(period) ?: return period
        val count = match.groupValues[1].toIntOrNull() ?: 1
        val unit = when (match.groupValues[2]) {
            "D" -> R.string.s_day_2
            "W" -> R.string.s_week
            "M" -> R.string.s_month
            else -> R.string.s_year
        }
        val unitText = context.getString(unit)
        return if (plural || count > 1) "$count $unitText" else unitText
    }

    suspend fun refreshEntitlements() {
        var owned = false
        for (type in listOf(BillingClient.ProductType.SUBS, BillingClient.ProductType.INAPP)) {
            val purchases = billing.queryPurchasesAsync(
                QueryPurchasesParams.newBuilder().setProductType(type).build()
            ).purchasesList
            for (purchase in purchases) {
                if (purchase.products.contains(productID) && purchase.purchaseState == Purchase.PurchaseState.PURCHASED) {
                    owned = true
                    acknowledge(purchase)
                }
            }
        }
        setPremium(owned)
    }

    fun buyPremium(activity: Activity) {
        val details = product
        if (details == null) {
            _state.value = _state.value.copy(
                message = context.getString(R.string.s_premium_isn_t_available_right_now_please_try_again_later)
            )
            return
        }
        val productParams = BillingFlowParams.ProductDetailsParams.newBuilder().setProductDetails(details)
        details.subscriptionOfferDetails?.firstOrNull()?.let { productParams.setOfferToken(it.offerToken) }
        val params = BillingFlowParams.newBuilder()
            .setProductDetailsParamsList(listOf(productParams.build()))
            .build()
        _state.value = _state.value.copy(isWorking = true)
        billing.launchBillingFlow(activity, params)
    }

    fun restorePurchases() {
        _state.value = _state.value.copy(isWorking = true)
        viewModelScope.launch {
            refreshEntitlements()
            _state.value = _state.value.copy(
                isWorking = false,
                message = context.getString(
                    if (_state.value.isPremium) R.string.s_your_purchases_have_been_restored
                    else R.string.s_no_previous_purchases_were_found
                ),
            )
        }
    }

    override fun onPurchasesUpdated(result: BillingResult, purchases: MutableList<Purchase>?) {
        _state.value = _state.value.copy(isWorking = false)
        when (result.responseCode) {
            BillingClient.BillingResponseCode.OK -> viewModelScope.launch {
                purchases?.forEach { purchase ->
                    if (purchase.purchaseState == Purchase.PurchaseState.PURCHASED) {
                        acknowledge(purchase)
                        setPremium(true)
                        _state.value = _state.value.copy(
                            message = context.getString(R.string.s_welcome_to_readtime_premium)
                        )
                    } else if (purchase.purchaseState == Purchase.PurchaseState.PENDING) {
                        _state.value = _state.value.copy(
                            message = context.getString(R.string.s_your_purchase_is_pending_approval)
                        )
                    }
                }
            }

            BillingClient.BillingResponseCode.USER_CANCELED -> Unit

            else -> _state.value = _state.value.copy(message = result.debugMessage.ifEmpty { null })
        }
    }

    private suspend fun acknowledge(purchase: Purchase) {
        if (purchase.isAcknowledged) return
        billing.acknowledgePurchase(
            AcknowledgePurchaseParams.newBuilder().setPurchaseToken(purchase.purchaseToken).build()
        )
    }

    private fun setPremium(premium: Boolean) {
        _state.value = _state.value.copy(isPremium = premium)
        // Premium readers never see ads.
        AdManager.isAdFree = premium
    }

    fun clearMessage() {
        _state.value = _state.value.copy(message = null)
    }

    override fun onCleared() {
        super.onCleared()
        billing.endConnection()
    }
}

class PurchaseManagerFactory(private val application: Application) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T = PurchaseManager(application) as T
}

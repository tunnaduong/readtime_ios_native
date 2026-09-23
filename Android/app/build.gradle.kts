import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

// Release signing. Values come from the environment first (so passwords need not be
// written down anywhere), then from android/keystore.properties, which is git-ignored.
val keystoreProperties = Properties()
val keystoreFile = rootProject.file("keystore.properties")
if (keystoreFile.exists()) keystoreFile.inputStream().use { keystoreProperties.load(it) }

fun signingValue(environmentName: String, propertyName: String): String? =
    System.getenv(environmentName) ?: keystoreProperties.getProperty(propertyName)

val releaseStorePath: String? = signingValue("READTIME_KEYSTORE", "storeFile")

android {
    namespace = "com.fatties.readtime"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.fatties.readtime"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"
        resourceConfigurations += listOf("en", "vi", "es", "ja", "zh-rCN")

        // AdMob ids. The defaults are Google's own test ids; override them in
        // android/local.properties with admobAppId / admobBannerUnitId / admobInterstitialUnitId.
        val properties = Properties()
        val propertiesFile = rootProject.file("local.properties")
        if (propertiesFile.exists()) propertiesFile.inputStream().use { properties.load(it) }
        fun property(name: String, fallback: String): String = properties.getProperty(name) ?: fallback
        manifestPlaceholders["admobAppId"] = property("admobAppId", "ca-app-pub-3940256099942544~3347511713")
        buildConfigField("String", "ADMOB_BANNER_UNIT_ID", "\"${property("admobBannerUnitId", "ca-app-pub-3940256099942544/6300978111")}\"")
        buildConfigField("String", "ADMOB_INTERSTITIAL_UNIT_ID", "\"${property("admobInterstitialUnitId", "ca-app-pub-3940256099942544/1033173712")}\"")
        buildConfigField("String", "PREMIUM_PRODUCT_ID", "\"com.fatties.readtime.premium\"")
    }

    signingConfigs {
        if (releaseStorePath != null) {
            create("release") {
                storeFile = rootProject.file(releaseStorePath)
                storePassword = signingValue("READTIME_KEYSTORE_PASSWORD", "storePassword")
                keyAlias = signingValue("READTIME_KEY_ALIAS", "keyAlias") ?: "upload"
                keyPassword = signingValue("READTIME_KEY_PASSWORD", "keyPassword")
            }
        } else {
            logger.warn(
                "ReadTime: no upload key configured, so release builds are unsigned. " +
                    "See android/RELEASE.md."
            )
        }
    }

    buildTypes {
        release {
            // Never falls back to the debug key: Play rejects debug-signed uploads, and a
            // build that looks signed but isn't wastes a trip through the Console.
            signingConfig = signingConfigs.findByName("release")
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }
}

dependencies {
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.appcompat)
    implementation(libs.play.services.ads)
    implementation(libs.billing.ktx)
    implementation(libs.glance.appwidget)
    implementation(libs.glance.material3)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.navigation.compose)
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.graphics)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.material.icons.extended)
    implementation(libs.androidx.work.runtime.ktx)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.coil.compose)
    debugImplementation(libs.androidx.compose.ui.tooling)
    coreLibraryDesugaring(libs.desugar.jdk.libs)
}

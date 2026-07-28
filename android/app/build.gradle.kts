plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "be.taxirecettes.copilote"
    compileSdk = 34

    defaultConfig {
        applicationId = "be.taxirecettes.copilote"
        minSdk = 26
        targetSdk = 34
        versionCode = 37
        versionName = "0.37"
    }

    // 3 variantes = 3 apps installables côte à côte
    flavorDimensions += "role"
    productFlavors {
        create("chauffeur") {
            dimension = "role"
            // garde l'applicationId existant -> met à jour l'app déjà installée
            resValue("string", "app_name", "Taxi Recettes")
            buildConfigField("String", "LAUNCH_URL", "\"https://appassets.androidplatform.net/assets/webapp/index.html\"")
            buildConfigField("boolean", "IS_DRIVER", "true")
        }
        create("patron") {
            dimension = "role"
            applicationId = "be.taxirecettes.patron"
            resValue("string", "app_name", "Taxi Patron")
            buildConfigField("String", "LAUNCH_URL", "\"https://alaeedine1997.github.io/taxi-recettes/patron.html\"")
            buildConfigField("boolean", "IS_DRIVER", "false")
        }
        create("superadmin") {
            dimension = "role"
            applicationId = "be.taxirecettes.admin"
            resValue("string", "app_name", "Taxi Admin")
            buildConfigField("String", "LAUNCH_URL", "\"https://alaeedine1997.github.io/taxi-recettes/admin.html\"")
            buildConfigField("boolean", "IS_DRIVER", "false")
        }
    }

    val releaseKeystore = System.getenv("ANDROID_KEYSTORE_PATH")
    val releaseStorePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
    val releaseKeyAlias = System.getenv("ANDROID_KEY_ALIAS")
    val releaseKeyPassword = System.getenv("ANDROID_KEY_PASSWORD")
    val stableSigning = if (!releaseKeystore.isNullOrBlank()) signingConfigs.create("stable") {
        storeFile = file(releaseKeystore)
        storePassword = releaseStorePassword
        keyAlias = releaseKeyAlias
        keyPassword = releaseKeyPassword
    } else null

    buildTypes {
        getByName("release") {
            isMinifyEnabled = false
            signingConfig = stableSigning
        }
        getByName("debug") {
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
    buildFeatures {
        buildConfig = true
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.appcompat:appcompat:1.7.0")
    // 1.12.1 reste compatible avec AGP 8.5/compileSdk 34 tout en fournissant
    // WebViewAssetLoader. Les profils ART de 1.14 exigent une chaîne plus récente.
    implementation("androidx.webkit:webkit:1.12.1")
}

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
        versionCode = 27
        versionName = "0.27"
    }

    // 3 variantes = 3 apps installables côte à côte
    flavorDimensions += "role"
    productFlavors {
        create("chauffeur") {
            dimension = "role"
            // garde l'applicationId existant -> met à jour l'app déjà installée
            resValue("string", "app_name", "Taxi Recettes")
            buildConfigField("String", "LAUNCH_URL", "\"file:///android_asset/webapp/index.html\"")
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

    signingConfigs {
        create("stable") {
            storeFile = file("signing/taxi.keystore")
            storePassword = "taxicopilote"
            keyAlias = "taxi"
            keyPassword = "taxicopilote"
        }
    }

    buildTypes {
        getByName("release") {
            isMinifyEnabled = false
            signingConfig = signingConfigs.getByName("stable")
        }
        getByName("debug") {
            isMinifyEnabled = false
            signingConfig = signingConfigs.getByName("stable")
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
}

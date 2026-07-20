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
        versionCode = 23
        versionName = "0.23"
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

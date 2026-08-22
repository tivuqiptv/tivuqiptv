import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val tivuqKeystoreProperties = Properties()
val tivuqKeystorePropertiesFile = rootProject.file("key.properties")
val hasTivuqReleaseKey = tivuqKeystorePropertiesFile.exists()
if (hasTivuqReleaseKey) {
    FileInputStream(tivuqKeystorePropertiesFile).use {
        tivuqKeystoreProperties.load(it)
    }
}

android {
    namespace = "com.tivuq.iptv"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.tivuq.iptv"
        minSdk = flutter.minSdkVersion  // Android TV için minimum 21 gerekli
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasTivuqReleaseKey) {
            create("tivuqRelease") {
                keyAlias = tivuqKeystoreProperties["keyAlias"] as String
                keyPassword = tivuqKeystoreProperties["keyPassword"] as String
                storeFile = rootProject.file(
                    tivuqKeystoreProperties["storeFile"] as String,
                )
                storePassword = tivuqKeystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Arkadaş testlerindeki mevcut debug-imzalı kurulumları bozmamak
            // için anahtar yokken debug imzasına düşer. Korumalı ticari derleme
            // betiği ise key.properties yoksa kesinlikle paket üretmez.
            signingConfig = if (hasTivuqReleaseKey) {
                signingConfigs.getByName("tivuqRelease")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation(files("libs/exoplayer-ffmpeg-2.19.1-mp3.aar"))
    implementation("com.google.android.exoplayer:exoplayer-core:2.19.1")
    implementation("com.google.android.exoplayer:exoplayer-hls:2.19.1")
    implementation("androidx.media3:media3-exoplayer:1.11.0")
    implementation("androidx.media3:media3-ui:1.11.0")
    implementation("androidx.media3:media3-exoplayer-hls:1.11.0")
    implementation("androidx.media3:media3-session:1.11.0")
    implementation("androidx.media3:media3-common:1.11.0")
}

import java.io.FileInputStream
import java.util.Properties

// Release signing material lives outside the repository. A development device
// update may explicitly retain its debug certificate without clearing user data.
// Distributable releases must never silently fall back to that certificate.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) FileInputStream(keystorePropertiesFile).use { load(it) }
}
val hasReleaseSigning = keystorePropertiesFile.exists() &&
    listOf("storeFile", "storePassword", "keyAlias", "keyPassword").all { keystoreProperties[it] != null }

val deviceDebugSigning = System.getenv("TRIMMY_DEVICE_DEBUG_SIGNING") == "true"

gradle.taskGraph.whenReady {
    if (allTasks.any { it.name.contains("Release", ignoreCase = true) } &&
        !hasReleaseSigning && !deviceDebugSigning) {
        throw GradleException("Release signing is missing. Configure android/key.properties, or explicitly set TRIMMY_DEVICE_DEBUG_SIGNING=true for a local device build.")
    }
}

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.trimmy.trimmy"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.trimmy.trimmy"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // privy_flutter 0.10.2's native dependency requires Android API 28.
        minSdk = 28
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["appLabel"] = "Trimmy"
        manifestPlaceholders["privyRedirectScheme"] = "com.trimmy.trimmy.privy"
    }

    flavorDimensions += "experience"
    productFlavors {
        create("production") {
            dimension = "experience"
        }
        create("review") {
            dimension = "experience"
            applicationIdSuffix = ".review"
            versionNameSuffix = "-review"
            manifestPlaceholders["appLabel"] = "Trimmy UI Review"
            manifestPlaceholders["privyRedirectScheme"] = "com.trimmy.trimmy.review.privy"
        }
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigning && !deviceDebugSigning) {
                signingConfigs.getByName("release")
            } else {
                // Explicit local-device build; never a store/release artifact.
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Add Google Services plugin for Firebase
    id("com.google.gms.google-services")
}

android {
    namespace = "com.example.minor_project"
    compileSdk = 36
    ndkVersion = "27.0.12077973"  // Updated to fix NDK version conflict

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true  // ✅ FIXED: Added 'is' prefix for Kotlin DSL
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.minor_project"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26  // Changed from flutter.minSdkVersion to 26 for health plugin compatibility
        targetSdk = 33
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Enable multidex support for Firebase
        multiDexEnabled = true
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Firebase BOM - manages all Firebase library versions
    implementation(platform("com.google.firebase:firebase-bom:32.7.0"))

    // Firebase Authentication
    implementation("com.google.firebase:firebase-auth")

    // Cloud Firestore
    implementation("com.google.firebase:firebase-firestore")

    // Firebase Analytics (optional, but recommended for health apps)
    implementation("com.google.firebase:firebase-analytics")

    // Multidex support
    implementation("androidx.multidex:multidex:2.0.1")

    // ✅ FIXED: Desugaring support for flutter_local_notifications
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}
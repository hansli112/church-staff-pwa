import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The Flutter tool passes --dart-define(-from-file) values to Gradle as
// comma-separated base64 "KEY=value" entries.
val dartDefines: Map<String, String> =
    (findProperty("dart-defines") as String? ?: "")
        .split(",")
        .filter { it.isNotEmpty() }
        .map { String(Base64.getDecoder().decode(it)).split("=", limit = 2) }
        .filter { it.size == 2 }
        .associate { it[0] to it[1] }

android {
    namespace = "app.marthasit"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "app.marthasit"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Firebase needs 23+.
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Firebase Analytics starts before Dart runs and reads the app ID
        // from resources, not from the FirebaseOptions main.dart passes
        // (without it: "Missing google_app_id. Firebase Analytics disabled").
        // There is no google-services.json, so copy it from the build's
        // --dart-define-from-file.
        dartDefines["FIREBASE_ANDROID_APP_ID"]?.let { resValue("string", "google_app_id", it) }
    }

    // The upload key for Google Play, from android/key.properties (not in
    // git; docs/firebase-setup.md). Without it a release build is signed
    // with the debug key, so `flutter run --release` still works.
    val keyProperties = Properties().apply {
        val file = rootProject.file("key.properties")
        if (file.exists()) file.inputStream().use { load(it) }
    }
    signingConfigs {
        if (keyProperties.isNotEmpty()) {
            create("upload") {
                storeFile = file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("upload") ?: signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

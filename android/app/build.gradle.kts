plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.test_app_1"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "29.0.13113456"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // App/OS-facing package identity. Deliberately DIFFERENT from the
        // `namespace` above (which stays com.example.test_app_1 so the Kotlin
        // package + MethodChannel strings + MainActivity path are unchanged).
        // The OS keys all remembered per-app decisions — the WifiNetwork-
        // Specifier approval and MIUI's intent-chooser "don't ask again"
        // default — to THIS applicationId, so bumping it is the clean-room
        // reset when a wrong choice gets cached (uninstall/network-reset don't
        // clear MIUI's preferred-activity default). Bump the suffix again if it
        // ever needs another pristine identity.
        applicationId = "com.smartcane.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // LiteRT-LM requires Android 12 (API 31) minimum.
        minSdk = 31
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    androidResources {
        // Prevent Android from compressing large model files — they are already
        // optimal binary formats and compression would corrupt/bloat them.
        noCompress += listOf("onnx", "txt", "tflite", "litertlm")
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    // LiteRT-LM on-device LLM inference (Gemma 4 E2B) — DISABLED.
    // Its AAR bundles libLiteRt.so, which collides with the LiteRT runtime
    // shipped by the ultralytics_yolo vision plugin (mergeDebugNativeLibs:
    // "2 files found with path 'lib/arm64-v8a/libLiteRt.so'").  The LLM is
    // feature-flagged off and its model asset is not bundled, so this is
    // dead weight until re-enabled.  See MainActivity.kt for the matching
    // stubbed channel and re-enable notes.
    // implementation("com.google.ai.edge.litertlm:litertlm-android:latest.release")
}

flutter {
    source = "../.."
}

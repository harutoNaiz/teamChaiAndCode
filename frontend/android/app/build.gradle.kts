plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

dependencies {
    implementation("androidx.appsearch:appsearch:1.1.0")
    implementation("androidx.appsearch:appsearch-local-storage:1.1.0")
    implementation("com.google.mediapipe:tasks-text:1.0.0")
    implementation("com.google.mlkit:text-recognition:16.0.1")
    // Pin the stable release so builds remain reproducible (latest alpha may
    // require a newer Kotlin compiler than the Flutter toolchain).
    implementation("com.google.ai.edge.litertlm:litertlm-android:0.16.1")
}

android {
    namespace = "com.example.team_chai_and_code"
    compileSdk = flutter.compileSdkVersion
    // Use the valid NDK already installed on the development machine. The
    // previously pinned 26.1 copy is incomplete (missing source.properties).
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.example.team_chai_and_code"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

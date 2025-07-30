plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services") // ✅ Firebase services plugin
}

android {
    namespace = "com.example.drivergo"

    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973" // ✅ NDK version for compatibility with plugins

    defaultConfig {
        applicationId = "com.example.drivergo"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = "11"
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug") // ❗Change in production!
        }
    }
}

flutter {
    source = "../.."
}

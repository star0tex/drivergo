plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services") // ✅ Firebase services plugin
}

android {
    namespace = "com.example.drivergo"

    compileSdk = 35 // ✅ Updated from flutter.compileSdkVersion
    ndkVersion = "27.0.12077973" // ✅ NDK version for compatibility with plugins

    defaultConfig {
        applicationId = "com.example.drivergo"
        minSdk = 23 // ✅ Updated from flutter.minSdkVersion
        targetSdk = 34 // ✅ Updated from flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true // ✅ Added for handling 64K method limit
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true // ✅ Enables desugaring
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

dependencies {
    // ✅ Core library desugaring
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
    
    // ✅ Firebase dependencies
    implementation(platform("com.google.firebase:firebase-bom:32.7.0"))
    implementation("com.google.firebase:firebase-auth")
    
    // ✅ Multidex support
    implementation("androidx.multidex:multidex:2.0.1")
}
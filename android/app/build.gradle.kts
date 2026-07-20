plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.afrinova_academy"
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
        applicationId = "com.example.afrinova_academy"
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    // Fix duplicate native libraries (Kotlin DSL syntax)
    packaging {
        jniLibs {
            pickFirsts.add("lib/arm64-v8a/libc++_shared.so")
            pickFirsts.add("lib/armeabi-v7a/libc++_shared.so")
            pickFirsts.add("lib/x86/libc++_shared.so")
            pickFirsts.add("lib/x86_64/libc++_shared.so")
        }
    }
}

configurations.all {
    resolutionStrategy {
        
        exclude(group = "androidx.media3", module = "media3-exoplayer-rtsp")
    }
}

flutter {
    source = "../.."
}
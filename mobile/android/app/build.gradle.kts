plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "app.quill.reader"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by the Readium Android artifacts.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "app.quill.reader"
        manifestPlaceholders["appLabel"] = "Quill"
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        debug {
            applicationIdSuffix = ".dev"
            versionNameSuffix = "-dev"
            manifestPlaceholders["appLabel"] = "Quill Dev"
        }
        // Flutter creates "profile" as a copy of debug before the block above runs, so without
        // this it would carry the released app's ID and could replace the phone's Quill.
        // Profile = Quill Dev at release speed (AOT), for performance measurements.
        getByName("profile") {
            applicationIdSuffix = ".dev"
            versionNameSuffix = "-dev-profile"
            manifestPlaceholders["appLabel"] = "Quill Dev"
        }
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    // Reads RAR 4 archives (CBR comics); extraction only. UnRAR licence: not to be used to
    // write a RAR compressor.
    implementation("com.github.junrar:junrar:7.5.5")
}

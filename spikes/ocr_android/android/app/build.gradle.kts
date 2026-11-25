// SPDX-License-Identifier: GPL-3.0-or-later
plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "io.github.frerol.doxapdf.ocrlab"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "io.github.frerol.doxapdf.ocrlab"
        minSdk = 29
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    sourceSets {
        getByName("main") {
            jniLibs.srcDir(rootProject.file("../../../third_party/pdfium/jniLibs"))
        }
    }

    buildTypes {
        release {
            // Local split APKs for measurement use the debug key.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    implementation("cz.adaptech.tesseract4android:tesseract4android:4.9.0")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// PDFium is bundled from third_party/pdfium (see docs/plan/04-pdf-engine.md §2).
val pdfiumJniLibs = rootProject.file("../../third_party/pdfium/jniLibs")

val checkPdfium by tasks.registering {
    description = "Fails early when the PDFium binaries have not been fetched."
    val marker = pdfiumJniLibs.resolve("arm64-v8a/libpdfium.so")
    doLast {
        if (!marker.exists()) {
            throw GradleException(
                "PDFium binaries not found in $pdfiumJniLibs. " +
                    "Run tools/fetch_pdfium.sh android from the repository root.",
            )
        }
    }
}

tasks.named("preBuild") { dependsOn(checkPdfium) }

android {
    namespace = "io.github.frerol.doxapdf"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "io.github.frerol.doxapdf"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 29 // Android 10, see docs/plan/11-mvp.md
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    sourceSets {
        getByName("main") {
            // PDFium binaries fetched by tools/fetch_pdfium.sh (git-ignored).
            jniLibs.srcDir(pdfiumJniLibs)
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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

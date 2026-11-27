// SPDX-License-Identifier: GPL-3.0-or-later

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

// Release signing from the environment. DOXA_REQUIRE_RELEASE_SIGNING=true
// (set by release.yml) makes a missing key an error instead of a silent
// fallback to the debug key.
val releaseKeystore: String? = System.getenv("DOXA_RELEASE_KEYSTORE")?.takeIf { it.isNotBlank() }

fun releaseSigning(name: String): String =
    System.getenv(name)?.takeIf { it.isNotEmpty() }
        ?: throw GradleException("$name must be set when DOXA_RELEASE_KEYSTORE is.")

if (releaseKeystore == null && System.getenv("DOXA_REQUIRE_RELEASE_SIGNING") == "true") {
    throw GradleException("DOXA_REQUIRE_RELEASE_SIGNING is set but DOXA_RELEASE_KEYSTORE is not.")
}

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
        // The version code from pubspec.yaml, the same for every per-ABI APK
        // (force-version-code-ignoring-abi in gradle.properties), so it keeps
        // the order of docs/plan/07-build-release.md §4.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    sourceSets {
        getByName("main") {
            // PDFium binaries fetched by tools/fetch_pdfium.sh (git-ignored).
            jniLibs.srcDir(pdfiumJniLibs)
        }
    }

    signingConfigs {
        // The release key is held by the maintainer and kept in CI secrets
        // (docs/plan/07-build-release.md §4); release.yml passes it in here.
        if (releaseKeystore != null) {
            create("release") {
                storeFile = file(releaseKeystore)
                storePassword = releaseSigning("DOXA_RELEASE_STORE_PASSWORD")
                keyAlias = releaseSigning("DOXA_RELEASE_KEY_ALIAS")
                keyPassword = releaseSigning("DOXA_RELEASE_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            // Without the release key, local release builds are signed with
            // the debug key so `flutter run --release` keeps working.
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
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

pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    // Pinned to the last 8.x line on purpose: AGP 9's "built-in Kotlin"
    // silently drops Kotlin compilation for plugins that still apply the
    // classic `org.jetbrains.kotlin.android` plugin in their own
    // android/build.gradle (file_picker, audiotags) — their sources never
    // get a compileDebugKotlin task, so the app fails to link against
    // them ("cannot find symbol ... FilePickerPlugin"). See
    // https://kotl.in/gradle/agp-built-in-kotlin.
    id("com.android.application") version "8.13.2" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
    id("org.gradle.toolchains.foojay-resolver-convention") version "1.0.0"
}

include(":app")

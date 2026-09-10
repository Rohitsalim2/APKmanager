pluginManagement {
    val flutterSdkPath: String by extra("flutter.sdk") {
        file("local.properties").run {
            val properties = Properties()
            inputStream().use { properties.load(it) }
            properties.getProperty("flutter.sdk") ?: error("flutter.sdk not set in local.properties")
        }
    }
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.2.1" apply false
    id("org.jetbrains.kotlin.android") version "1.9.22" apply false
}

include(":app")
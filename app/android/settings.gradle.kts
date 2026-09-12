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
    id("com.android.application") version "9.0.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
    // Push (P3.4/P3.5): processa android/app/google-services.json — falha o
    // build se o arquivo não existir. Bloqueio conhecido: o app/README.md
    // § Firebase documenta que ele fica versionado ali, mas só o humano
    // consegue baixá-lo do Console Firebase (projeto lyfta-a3bd3); até lá,
    // qualquer build Android fica bloqueado por este plugin, não pelo
    // `firebase_messaging` em si.
    id("com.google.gms.google-services") version "4.4.2" apply false
}

include(":app")

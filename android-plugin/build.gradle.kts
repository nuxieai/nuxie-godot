import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
  id("com.android.library")
  id("org.jetbrains.kotlin.android")
}

val pluginName = "NuxieGodot"
val pluginPackageName = "ai.nuxie.godot"

android {
  namespace = pluginPackageName
  compileSdk = 36

  buildFeatures {
    buildConfig = true
  }

  defaultConfig {
    minSdk = 23

    manifestPlaceholders["godotPluginName"] = pluginName
    manifestPlaceholders["godotPluginPackageName"] = pluginPackageName
    buildConfigField("String", "GODOT_PLUGIN_NAME", "\"${pluginName}\"")
    setProperty("archivesBaseName", pluginName)
  }

  compileOptions {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
  }

  kotlin {
    compilerOptions {
      jvmTarget.set(JvmTarget.JVM_17)
    }
  }
}

dependencies {
  implementation("org.godotengine:godot:4.5.1.stable")
  implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")

  implementation("ai.nuxie:nuxie-android:0.1.0")

  testImplementation("junit:junit:4.13.2")
}

val copyDebugAAR by tasks.registering(Copy::class) {
  from("build/outputs/aar")
  include("$pluginName-debug.aar")
  into("../addons/nuxie/android/bin/debug")
}

val copyReleaseAAR by tasks.registering(Copy::class) {
  from("build/outputs/aar")
  include("$pluginName-release.aar")
  into("../addons/nuxie/android/bin/release")
}

tasks.named("assemble") {
  finalizedBy(copyDebugAAR)
  finalizedBy(copyReleaseAAR)
}

tasks.configureEach {
  when (name) {
    "assembleDebug" -> finalizedBy(copyDebugAAR)
    "assembleRelease" -> finalizedBy(copyReleaseAAR)
  }
}

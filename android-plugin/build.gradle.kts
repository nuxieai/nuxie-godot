import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
  id("com.android.library")
  id("org.jetbrains.kotlin.android")
}

val pins = groovy.json.JsonSlurper().parse(rootProject.file("NATIVE-PINS.json")) as Map<*, *>
val androidRevision = (pins["android"] as Map<*, *>)["revision"] as String
val godotVersion = pins["godot"] as String
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
    consumerProguardFiles("consumer-rules.pro")

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
  compileOnly("org.godotengine:godot:$godotVersion.stable")
  implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")

  implementation("ai.nuxie:nuxie-android:0.2.0-$androidRevision")

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

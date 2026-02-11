import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
  id("com.android.library")
  id("org.jetbrains.kotlin.android")
}

val pluginName = "NuxieGodot"
val pluginPackageName = "io.nuxie.godot"

android {
  namespace = pluginPackageName
  compileSdk = 34

  buildFeatures {
    buildConfig = true
  }

  defaultConfig {
    minSdk = 21

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

  val localSdk = project.findProject(":nuxie-android-sdk")
  if (localSdk != null) {
    implementation(localSdk)
  } else {
    implementation("io.nuxie:nuxie-android:0.0.1")
  }
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

val copyExportTemplate by tasks.registering(Copy::class) {
  from("export_template")
  into("../addons/nuxie/android")
}

tasks.named("assemble") {
  finalizedBy(copyDebugAAR)
  finalizedBy(copyReleaseAAR)
  finalizedBy(copyExportTemplate)
}

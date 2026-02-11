pluginManagement {
  repositories {
    google {
      content {
        includeGroupByRegex("com\\.android.*")
        includeGroupByRegex("com\\.google.*")
        includeGroupByRegex("androidx.*")
      }
    }
    mavenCentral()
    gradlePluginPortal()
  }
}

dependencyResolutionManagement {
  repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
  repositories {
    google()
    mavenCentral()
  }
}

rootProject.name = "nuxie-godot"

include(":android-plugin")

val localNuxieAndroid = file("../nuxie-android")
if (localNuxieAndroid.exists()) {
  include(":nuxie-core")
  project(":nuxie-core").projectDir = file("../nuxie-android/nuxie-core")

  include(":nuxie-android-sdk")
  project(":nuxie-android-sdk").projectDir = file("../nuxie-android/nuxie-android")
}

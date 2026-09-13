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
    providers.environmentVariable("NUXIE_ANDROID_MAVEN_REPO").orNull?.let { maven(url = uri(it)) }
    maven { url = uri(".native/maven") }
    google()
    mavenCentral()
  }
}

rootProject.name = "nuxie-godot"
include(":android-plugin")

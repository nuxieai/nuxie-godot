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
    google()
    mavenCentral()
  }
}

providers.environmentVariable("NUXIE_ANDROID_SOURCE_DIR").orNull?.let { sourceDirectory ->
  includeBuild(sourceDirectory) {
    dependencySubstitution {
      substitute(module("ai.nuxie:nuxie-android")).using(project(":nuxie-android"))
    }
  }
}

rootProject.name = "nuxie-godot"

include(":android-plugin")

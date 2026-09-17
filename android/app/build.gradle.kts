import java.io.File

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

private fun gitOutput(repositoryRoot: File, vararg arguments: String): String? = runCatching {
    val process = ProcessBuilder(listOf("git") + arguments.toList())
        .directory(repositoryRoot)
        .redirectErrorStream(true)
        .start()
    val output = process.inputStream.bufferedReader().use { it.readText().trim() }
    if (process.waitFor() == 0) output else null
}.getOrNull()

private fun buildConfigString(value: String): String =
    "\"${value.replace("\\", "\\\\").replace("\"", "\\\"")}\""

val repositoryRoot = rootDir.parentFile
val buildCommitSha = gitOutput(repositoryRoot, "rev-parse", "--verify", "HEAD") ?: "unknown"
val buildBranch = gitOutput(repositoryRoot, "symbolic-ref", "--short", "-q", "HEAD")
    ?.takeIf { it.isNotBlank() }
    ?: "unknown"
val workingTreeStatus = gitOutput(repositoryRoot, "status", "--porcelain", "--untracked-files=all")
val buildDirty = when {
    buildCommitSha == "unknown" || workingTreeStatus == null -> "unknown"
    workingTreeStatus.isEmpty() -> "false"
    else -> "true"
}

android {
    namespace = "cn.edu.xjtu.xjtu_campus"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    buildFeatures {
        buildConfig = true
    }

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "cn.edu.xjtu.xjtu_campus"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        buildConfigField("String", "BUILD_COMMIT_SHA", buildConfigString(buildCommitSha))
        buildConfigField("String", "BUILD_BRANCH", buildConfigString(buildBranch))
        buildConfigField("String", "BUILD_DIRTY", buildConfigString(buildDirty))
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

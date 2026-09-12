plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.pichai.farmer"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        multiDexEnabled = true
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.pichai.farmer"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Never produce a distributable artifact signed by the debug key.
            val storeFile = System.getenv("FARM_RELEASE_STORE_FILE")
            val storePassword = System.getenv("FARM_RELEASE_STORE_PASSWORD")
            val keyAlias = System.getenv("FARM_RELEASE_KEY_ALIAS")
            val keyPassword = System.getenv("FARM_RELEASE_KEY_PASSWORD")
            val signingValues = listOf(storeFile, storePassword, keyAlias, keyPassword)
            if (signingValues.any { it.isNullOrBlank() }) {
                if (gradle.startParameter.taskNames.any { it.lowercase().contains("release") }) {
                    throw GradleException("Refusing release APK/AAB without explicit signing properties")
                }
            } else {
                signingConfig = signingConfigs.create("release") {
                    this.storeFile = file(requireNotNull(storeFile))
                    this.storePassword = requireNotNull(storePassword)
                    this.keyAlias = requireNotNull(keyAlias)
                    this.keyPassword = requireNotNull(keyPassword)
                }
            }
        }
    }
}
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
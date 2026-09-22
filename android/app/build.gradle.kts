plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

import java.io.FileInputStream
import java.util.Properties

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.eglobal.wallet"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.eglobal.wallet"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            // Appcircle exposes the selected Android keystore through reserved
            // AC_ANDROID_* environment variables. Keep local key.properties/
            // KEY_* support for local development and other CI environments.
            val appcircleKeystorePath = System.getenv("AC_ANDROID_KEYSTORE_PATH")
            val appcircleKeystorePassword = System.getenv("AC_ANDROID_KEYSTORE_PASSWORD")
            val appcircleAlias = System.getenv("AC_ANDROID_ALIAS")
            val appcircleAliasPassword = System.getenv("AC_ANDROID_ALIAS_PASSWORD")

            val useAppcircleSigning =
                System.getenv("AC_APPCIRCLE").toBoolean() &&
                !appcircleKeystorePath.isNullOrBlank() &&
                !appcircleKeystorePassword.isNullOrBlank() &&
                !appcircleAlias.isNullOrBlank() &&
                !appcircleAliasPassword.isNullOrBlank()

            val keyAliasProp = if (useAppcircleSigning) {
                appcircleAlias
            } else {
                keystoreProperties.getProperty("keyAlias") ?: System.getenv("KEY_ALIAS")
            }
            val keyPasswordProp = if (useAppcircleSigning) {
                appcircleAliasPassword
            } else {
                keystoreProperties.getProperty("keyPassword") ?: System.getenv("KEY_PASSWORD")
            }
            val storeFileProp = if (useAppcircleSigning) {
                appcircleKeystorePath
            } else {
                keystoreProperties.getProperty("storeFile") ?: System.getenv("STORE_FILE")
            }
            val storePasswordProp = if (useAppcircleSigning) {
                appcircleKeystorePassword
            } else {
                keystoreProperties.getProperty("storePassword") ?: System.getenv("STORE_PASSWORD")
            }

            if (
                !keyAliasProp.isNullOrBlank() &&
                !keyPasswordProp.isNullOrBlank() &&
                !storeFileProp.isNullOrBlank() &&
                !storePasswordProp.isNullOrBlank()
            ) {
                keyAlias = keyAliasProp
                keyPassword = keyPasswordProp
                storeFile = file(storeFileProp)
                storePassword = storePasswordProp
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            val releaseSigning = signingConfigs.findByName("release")
            if (releaseSigning != null && releaseSigning.storeFile != null && releaseSigning.storeFile!!.exists()) {
                signingConfig = releaseSigning
            } else {
                val isReleaseTask = gradle.startParameter.taskNames.any { it.contains("Release", ignoreCase = true) }
                if (isReleaseTask) {
                    throw GradleException(
                        "Release build failed: Missing key.properties or valid Appcircle/local release keystore. " +
                        "Select a valid Android keystore in Appcircle or configure key.properties for local builds."
                    )
                }
            }
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}

flutter {
    source = "../.."
}

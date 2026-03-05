import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services") 



}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.deksi.pharmacy"
    // flutter.compileSdkVersion sometimes lags behind the newest Android APIs.
    // The build failure (android:attr/lStar not found) required bumping the
    // compileSdk.  Several plugins in the project (e.g. google_sign_in_android,
    // image_picker_android) need SDK 36 or higher.  Use the highest SDK the
    // installed Android SDK supports (36 at time of writing).
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Enable core library desugaring for libraries that require Java 8+ APIs
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.deksi.pharmacy"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = 36 // target the same or higher than compileSdk
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    if (keystorePropertiesFile.exists()) {
        signingConfigs {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }

        buildTypes {
            release {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    } else {
        buildTypes {
            release {
                // No signing config available; building without release signing.
            }
        }
    }
}

// Firebase native SDKs are managed by FlutterFire plugins; avoid adding
// direct Android dependencies here to prevent version conflicts.

flutter {
    source = "../.."
}

dependencies {
    // Required for libraries that use newer Java APIs and need desugaring
    // Use a recent desugar_jdk_libs to satisfy plugin AAR requirements
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

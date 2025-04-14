plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin") // Flutter plugin must be last
    id("com.google.gms.google-services") //firebase json gradle plugin, app level

}

android {
    namespace = "com.milo.memorykeeper.milo"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"


    defaultConfig {
        applicationId = "com.milo.memorykeeper.milo"
        minSdk = 24
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "11"
    }

    buildTypes {
        getByName("release") {
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    implementation(platform("com.google.firebase:firebase-bom:33.12.0")) //import the firebase BOM
    implementation("com.google.firebase:firebase-analytics") //when BOM used, versions in firebase not specified
    implementation("com.google.firebase:firebase-storage") //Required for firebase storage
}

apply(plugin = "com.google.gms.google-services")

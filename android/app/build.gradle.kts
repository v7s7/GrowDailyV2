import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // Reads android/app/google-services.json and generates the Firebase
    // config resources every FlutterFire plugin looks up at runtime. Without
    // it firebase_messaging silently never gets an FCM token on Android.
    id("com.google.gms.google-services")
    // Uploads the deobfuscation/native symbol mapping so a release stack
    // trace in Crashlytics is readable instead of R8-mangled. iOS has had
    // crash reporting since the firebase_crashlytics pin in pubspec.yaml;
    // this is the Android half of it.
    id("com.google.firebase.crashlytics")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing. Deliberately NOT checked into git: android/key.properties
// holds the upload keystore's passwords and android/*.jks the key itself
// (both listed in .gitignore). When the file is absent - a fresh clone, or
// CI without the secret - the release build falls back to debug signing so
// `flutter build apk --release` still works locally; only a build with a
// real key.properties can produce an artifact Play will accept.
// See ANDROID_RELEASE.md for how to generate the keystore.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    namespace = "com.growdaily.v2"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Required by flutter_local_notifications 18.x, which fails the build
        // outright without it:
        //   ':flutter_local_notifications' requires core library desugaring
        //   to be enabled for :app  (task :app:checkReleaseAarMetadata)
        //
        // Still required at minSdk 26 even though java.time is native there:
        // the plugin declares the requirement in its AAR metadata, so the
        // check above fails regardless of this app's own floor. What minSdk
        // 26 changes is the risk, not the requirement - the back-ported
        // implementation is no longer the one actually running.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // Must stay exactly com.growdaily.v2: it matches the iOS bundle id,
        // and it is the package_name the Firebase Android app
        // (1:508215311979:android:ccb9c6e15496fac81fbb2e) is registered
        // under. Changing it orphans google-services.json and, once the app
        // is live, is a permanent break - Play treats a new applicationId as
        // an entirely different app.
        applicationId = "com.growdaily.v2"
        // 26 (Android 8.0), deliberately above the 24 this dependency set
        // actually requires (app_links 7.0.0 declares 24, record_android
        // 1.5.2 declares 23) and above Flutter's own default of 24.
        //
        // The reason is testability, not a dependency. Android 7.x arm64
        // system images will not run on this project's Apple Silicon build
        // machine - three separate boot attempts crashed - so API 24/25 is
        // the one range that cannot be verified before shipping. It is also
        // precisely the range where the core library desugaring below is
        // load-bearing for behaviour rather than just for compilation:
        // java.time is native from 26 up, so at this floor the back-ported
        // implementation is no longer what schedules anyone's reminders.
        //
        // Android 7.x is low single digits of active devices and falling.
        // Shipping it untested was the worse trade.
        minSdk = maxOf(flutter.minSdkVersion, 26)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = keystoreProperties["storeFile"]?.let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // R8 on, with the keep rules in proguard-rules.pro. Without
            // those rules R8 strips reflection-reached classes in RevenueCat
            // and the Firebase/Play Billing stack, which fails at runtime in
            // release only - exactly the class of bug that never shows up in
            // a debug build.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // The back-ported java.* implementation that isCoreLibraryDesugaringEnabled
    // above compiles against.
    //
    // 2.1.5, not the 1.2.2 in flutter_local_notifications' own README: that
    // README predates AGP 8. The 1.x line does not work with AGP 8.11 and
    // compileSdk 36 (this project's versions), while 2.x requires AGP 8.1+,
    // which is satisfied. Version list checked against Google's Maven repo
    // rather than assumed.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

// GENERATED FILE — replace with output from: flutterfire configure
//
// Steps:
//   dart pub global activate flutterfire_cli
//   flutterfire configure --project=YOUR_EXISTING_FIREBASE_PROJECT_ID
//
// Using your existing Firebase project preserves all current user accounts.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not configured for $defaultTargetPlatform.',
        );
    }
  }

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyB2dC_6ddlr2YRha5Y85GPNd3KpIlHFaqQ',
    appId: '1:508215311979:ios:1e5f8d525db5d9841fbb2e',
    messagingSenderId: '508215311979',
    projectId: 'grow-daily-339ef',
    storageBucket: 'grow-daily-339ef.firebasestorage.app',
    iosClientId: '508215311979-mgcmcfoo34l3i8kbtckqh0qmi0oud9p2.apps.googleusercontent.com',
    iosBundleId: 'com.example.growDailyV2',
  );
  // TODO: replace placeholder values after running `flutterfire configure`

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyA5x-guZJ4BGXpa-IUN9iV7Wj45ww4lBQk',
    appId: '1:508215311979:android:ccb9c6e15496fac81fbb2e',
    messagingSenderId: '508215311979',
    projectId: 'grow-daily-339ef',
    storageBucket: 'grow-daily-339ef.firebasestorage.app',
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDPRsJ600XqWwWxpq4a6YQPoY1PM80v0iE',
    appId: '1:508215311979:web:76e5b77a301b7e931fbb2e',
    messagingSenderId: '508215311979',
    projectId: 'grow-daily-339ef',
    authDomain: 'grow-daily-339ef.firebaseapp.com',
    storageBucket: 'grow-daily-339ef.firebasestorage.app',
    measurementId: 'G-K4LLS0RY6B',
  );
}

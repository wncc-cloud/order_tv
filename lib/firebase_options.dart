import 'package:firebase_core/firebase_core.dart';

/// Explicit Firebase config for the `why-not-cafe-prod` project — no
/// `google-services.json`, no Gradle `google-services` plugin.
///
/// Values pulled from the registered Android app (package name
/// `com.whynotcafe.kitchen_display`) via `firebase apps:sdkconfig ANDROID`.
class DefaultFirebaseOptions {
  DefaultFirebaseOptions._();

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAWXN8JJACgcAWT9r2BPmbyACUAeOWVxfo',
    appId: '1:871637263829:android:a36f6ca96849181a5c495c',
    messagingSenderId: '871637263829',
    projectId: 'why-not-cafe-prod',
    storageBucket: 'why-not-cafe-prod.firebasestorage.app',
  );
}

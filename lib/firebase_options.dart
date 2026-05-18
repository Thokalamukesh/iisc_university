import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;

    throw UnsupportedError(
      'Firebase options are configured for web only.',
    );
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyD9beiGD9smcvARm2Ah7p83uw-V0PTQKy8',
    appId: '1:774491345865:web:ea2fb6d08ea063fc618e18',
    messagingSenderId: '774491345865',
    projectId: 'gitam-university',
    authDomain: 'gitam-university.firebaseapp.com',
    storageBucket: 'gitam-university.firebasestorage.app',
  );
}

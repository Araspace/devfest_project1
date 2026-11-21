import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'home_page.dart';

/// Firebase web config comes from --dart-define so no keys live in the repo.
/// Without it the app runs with the offline demo agents.
class AppConfig {
  static const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const senderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  static const model = String.fromEnvironment('GEMINI_MODEL', defaultValue: 'gemini-2.5-flash');

  static bool get hasFirebase => apiKey.isNotEmpty && appId.isNotEmpty && projectId.isNotEmpty;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var live = false;
  String? initError;
  if (AppConfig.hasFirebase) {
    try {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: AppConfig.apiKey,
          appId: AppConfig.appId,
          projectId: AppConfig.projectId,
          messagingSenderId: AppConfig.senderId,
        ),
      );
      live = true;
    } catch (e) {
      initError = 'Firebase init failed, using offline demo agents: $e';
    }
  }
  runApp(BelegGuardApp(liveAvailable: live, initError: initError));
}

class BelegGuardApp extends StatelessWidget {
  const BelegGuardApp({super.key, required this.liveAvailable, this.initError});
  final bool liveAvailable;
  final String? initError;

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness b) => ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2B4BA0), brightness: b),
          useMaterial3: true,
        );
    return MaterialApp(
      title: 'BelegGuard',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: HomePage(liveAvailable: liveAvailable, initError: initError, modelName: AppConfig.model),
    );
  }
}

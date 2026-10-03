import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'features/startup/startup_screen.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const DevicePermissionLab());
}

class DevicePermissionLab extends StatelessWidget {
  const DevicePermissionLab({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'News Live',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3451B2),
        ),
        useMaterial3: true,
      ),
      home: const StartupScreen(),
    );
  }
}
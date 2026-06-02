import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'core/theme/game_theme.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: GameColors.background,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  await Hive.initFlutter();
  // Phase 2: register Hive type adapters here
  // Hive.registerAdapter(UserAccountAdapter());
  // Hive.registerAdapter(HabitModelAdapter());
  // Hive.registerAdapter(DailyLogModelAdapter());

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const ProviderScope(child: GrowDailyApp()));
}

class GrowDailyApp extends StatelessWidget {
  const GrowDailyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GrowDaily',
      debugShowCheckedModeBanner: false,
      theme: GameTheme.dark,
      home: const _BootstrapScreen(),
    );
  }
}

class _BootstrapScreen extends StatelessWidget {
  const _BootstrapScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'GrowDaily',
              style: GameTextStyles.displayLarge,
            ),
            SizedBox(height: GameSpacing.sm),
            Text(
              'V2',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: GameColors.gold,
                letterSpacing: 4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

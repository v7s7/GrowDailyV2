import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'core/services/notification_service.dart';
import 'core/theme/game_theme.dart';
import 'features/dashboard/screens/dashboard_screen.dart';
import 'features/matrix/screens/matrix_screen.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: GameColors.background,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  await Hive.initFlutter();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await NotificationService.instance.init();
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
      initialRoute: '/',
      routes: {
        '/': (_) => const DashboardScreen(),
        '/matrix': (_) => const MatrixScreen(),
      },
    );
  }
}

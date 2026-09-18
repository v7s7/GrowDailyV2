// The Night Review history's day sheet, dated in Arabic under the real
// localization delegates.
//
// Its header was DateFormat('EEEE, MMM d'), which in the app drew
// «الأربعاء, أغسطس ١٢»: month first, a Latin comma, Arabic-Indic digits,
// over a calendar whose own day numbers are Latin. It reads «الأربعاء، 12
// أغسطس» now, the form weekdayDateLabel gives every other day header.
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/core/services/local_store_service.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/night_review/models/mood.dart';
import 'package:grow_daily_v2/features/night_review/notifiers/night_review_history_notifier.dart';
import 'package:grow_daily_v2/features/night_review/screens/night_review_history_screen.dart';

/// August 2026 with one reviewed day, whatever the store's load says.
class _FixedHistory extends NightReviewHistoryNotifier {
  _FixedHistory(this.fixed) : super(null) {
    super.state = fixed;
  }

  final NightReviewHistoryState fixed;

  @override
  set state(NightReviewHistoryState value) => super.state = fixed;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('night_review_history_date_');
    Hive.init(tmp.path);
    // Both loads a guest runs (the history's own, and matrixProvider's at
    // tap time) read these; opened here, never inside a testWidgets body.
    await LocalStoreService.dailyBox();
    await LocalStoreService.settingsBox();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await tmp.delete(recursive: true);
  });

  // Wednesday 12 August 2026.
  final wed = DateTime(2026, 8, 12);
  final august = NightReviewHistoryState(
    monthStart: DateTime(2026, 8),
    entries: {
      wed.toDateKey(): const NightReviewDayEntry(
        mood: Mood.good,
        reflection: 'يوم هادئ',
        habitsDone: 3,
        greenSquares: 4,
      ),
    },
    isLoading: false,
  );

  Future<void> openDay(WidgetTester tester, Locale locale) async {
    tester.view.physicalSize = const Size(400 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
        nightReviewHistoryProvider.overrideWith((ref) => _FixedHistory(august)),
      ],
      child: MaterialApp(
        locale: locale,
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: GameTheme.dark,
        home: const NightReviewHistoryScreen(),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('12'));
    await tester.pumpAndSettle();
  }

  testWidgets('Arabic: «الأربعاء، 12 أغسطس»', (tester) async {
    await openDay(tester, const Locale('ar'));
    expect(find.text('الأربعاء، 12 أغسطس'), findsOneWidget);
    expect(find.text('الأربعاء, أغسطس ١٢'), findsNothing);
    // The month header above was already fixed; still Latin.
    expect(find.text('أغسطس 2026'), findsOneWidget);
  });

  testWidgets('English keeps «Wednesday, Aug 12»', (tester) async {
    await openDay(tester, const Locale('en'));
    expect(find.text('Wednesday, Aug 12'), findsOneWidget);
  });
}

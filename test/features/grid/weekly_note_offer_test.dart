// The Saturday note's question under «حصاد الأسبوع» (Aziz, 2026-09-24, page
// item 8): the note is off until the person chooses it, and this line is
// where the app asks, in his words: «نذكّرك بحصاد أسبوعك كل سبت الصبح؟» with
// «إيه» and «لا، شكرًا». Either answer ends the asking; «إيه» turns it on.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/providers/weekly_note_offer_provider.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/grid/widgets/weekly_recap_card.dart';
import 'package:grow_daily_v2/features/settings/models/notification_settings.dart';
import 'package:grow_daily_v2/features/settings/notifiers/notification_settings_notifier.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory tmp;
  const notificationsChannel =
      MethodChannel('dexterous.com/flutter/local_notifications');

  /// What the phone answers when «إيه» asks for notification permission.
  var granted = true;

  setUpAll(IOSFlutterLocalNotificationsPlugin.registerWith);

  // In memory, opened here and never inside a test: see
  // prayer_reminder_direction_test.dart for why awaiting a store from
  // inside testWidgets hangs the file.
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('weekly_note_offer');
    Hive.init(tmp.path);
    await Hive.openBox<dynamic>('box_settings', bytes: Uint8List(0));
    granted = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationsChannel, (call) async {
      return call.method == 'requestPermissions' ? granted : null;
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationsChannel, null);
    await Hive.close();
    await tmp.delete(recursive: true);
  });

  Future<ProviderContainer> pump(WidgetTester tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: kSupportedLocales,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: GameTheme.dark,
        home: const Scaffold(body: WeeklyNoteOffer()),
      ),
    ));
    await tester.pumpAndSettle();
    return container;
  }

  group('when the line shows', () {
    const off = NotificationSettings();
    test('off by default, so a new person is asked', () {
      expect(off.weeklyNoteOn, isFalse);
      expect(weeklyNoteOfferShown(settings: off, answered: false), isTrue);
    });
    test('not once answered', () {
      expect(weeklyNoteOfferShown(settings: off, answered: true), isFalse);
    });
    test('not while the note is on', () {
      expect(
        weeklyNoteOfferShown(
            settings: off.copyWith(weeklyNoteOn: true), answered: false),
        isFalse,
      );
    });
    test('not with every notification switched off', () {
      expect(
        weeklyNoteOfferShown(
            settings: off.copyWith(masterEnabled: false), answered: false),
        isFalse,
      );
    });
  });

  group('stored settings', () {
    test('a stored old switch reads as not chosen', () {
      // Every saved copy carried weeklyDigestEnabled: true, chosen or not.
      final read = NotificationSettings.fromMap({'weeklyDigestEnabled': true});
      expect(read.weeklyNoteOn, isFalse);
    });
    test('the new choice survives a round trip, and old builds follow it', () {
      final map = const NotificationSettings(weeklyNoteOn: true).toMap();
      expect(NotificationSettings.fromMap(map).weeklyNoteOn, isTrue);
      expect(map['weeklyDigestEnabled'], isTrue);
      expect(const NotificationSettings().toMap()['weeklyDigestEnabled'],
          isFalse);
    });
  });

  testWidgets('asks in his words', (tester) async {
    // An iPhone 17 Pro's width in points: nothing may overflow there.
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pump(tester);
    expect(find.text('نذكّرك بحصاد أسبوعك كل سبت الصبح؟'), findsOneWidget);
    expect(find.text('إيه'), findsOneWidget);
    expect(find.text('لا، شكرًا'), findsOneWidget);
  });

  final iOS = TargetPlatformVariant.only(TargetPlatform.iOS);

  testWidgets('«إيه» turns the note on and ends the asking', (tester) async {
    final container = await pump(tester);
    await tester.tap(find.text('إيه'));
    await tester.pumpAndSettle();
    expect(container.read(notificationSettingsProvider).weeklyNoteOn, isTrue);
    expect(container.read(weeklyNoteOfferAnsweredProvider), isTrue);
    expect(find.byType(SnackBar), findsNothing);
  }, variant: iOS);

  testWidgets('«إيه» with notifications refused says so', (tester) async {
    granted = false;
    final container = await pump(tester);
    await tester.tap(find.text('إيه'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(container.read(notificationSettingsProvider).weeklyNoteOn, isTrue,
        reason: 'the choice is kept; it arrives once they are allowed');
    expect(
      find.text(
          'الإشعارات موقوفة من إعدادات النظام. لن يصلك أي تذكير حتى يتم تفعيلها.'),
      findsOneWidget,
    );
  }, variant: iOS);

  testWidgets('«لا، شكرًا» leaves it off and ends the asking', (tester) async {
    final container = await pump(tester);
    await tester.tap(find.text('لا، شكرًا'));
    await tester.pumpAndSettle();
    expect(container.read(notificationSettingsProvider).weeklyNoteOn, isFalse);
    expect(container.read(weeklyNoteOfferAnsweredProvider), isTrue);
  }, variant: iOS);
}

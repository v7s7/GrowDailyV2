// The admin's pop-up on screen: when it appears, and when it must not.
//
// What has to hold:
//   - it appears once, a moment after the app opens, and never again on
//     this device once shown;
//   - one that arrives in the middle of a session waits for the next open;
//   - a moment's inactive blip is not an open;
//   - never over the first-run walkthrough, never stacked on another
//     dialog or a pushed screen, but a reminder's home screen is home;
//   - only what the server confirms goes up, never a stale copy;
//   - a test pop-up reaches only the account it names.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/providers/first_run_offer_provider.dart';
import 'package:grow_daily_v2/core/providers/onboarding_provider.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/broadcast/app_update.dart';
import 'package:grow_daily_v2/features/broadcast/broadcast_announcer.dart';
import 'package:grow_daily_v2/features/broadcast/broadcast_message.dart';
import 'package:grow_daily_v2/features/mascot/sprout.dart';

final _start = DateTime(2026, 9, 22, 12);

BroadcastPopup _popup({String id = 'p_1', Set<String> hashes = const {}}) =>
    BroadcastPopup(
      id: id,
      titleAr: 'تحديث جديد $id',
      bodyAr: 'صار عندك تذكير لكل صلاة.',
      buttonAr: 'تمام',
      startsAt: _start.subtract(const Duration(hours: 1)),
      endsAt: _start.add(const Duration(days: 7)),
      testUidHashes: hashes,
    );

void main() {
  late DateTime clock;

  setUp(() {
    clock = _start;
    BroadcastStore.persistSeen = false;
    // The server agrees with the device unless a test says otherwise.
    BroadcastStore.debugServerRead = () async => BroadcastStore.current;
  });
  tearDown(BroadcastStore.reset);

  Future<void> pumpHome(
    WidgetTester tester, {
    bool onboardingSeen = true,
    String? uid,
    Locale locale = const Locale('ar'),
    // The update prompt's inputs: this phone's build and store. Only read
    // once a gate exists, so a test with no `update` never touches them.
    Future<int?> Function()? build,
    TargetPlatform? platform = TargetPlatform.iOS,
    StoreLauncher? launcher,
  }) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          onboardingSeenProvider.overrideWith((ref) => onboardingSeen),
          firstRunOfferAskedProvider.overrideWith((ref) => true),
          broadcastUidProvider.overrideWithValue(uid),
          appBuildNumberProvider.overrideWith((ref) => (build ?? () async => 84)()),
          updatePlatformProvider.overrideWithValue(platform),
          if (launcher != null) storeLauncherProvider.overrideWithValue(launcher),
        ],
        child: MaterialApp(
          theme: GameTheme.light,
          locale: locale,
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: BroadcastAnnouncer(
            now: () => clock,
            child: const Scaffold(body: Center(child: Text('home'))),
          ),
          // The way main.dart opens a tapped reminder: a second home
          // screen, pushed by name over '/'.
          onGenerateRoute: (settings) => settings.name == '/grid'
              ? PageRouteBuilder<void>(
                  settings: settings,
                  pageBuilder: (_, __, ___) =>
                      const Scaffold(body: Center(child: Text('grid'))),
                )
              : null,
        ),
      ),
    );
  }

  /// Background and back, the way a real return to the app goes: through
  /// every state in between, which is also the only order
  /// AppLifecycleListener accepts.
  Future<void> leaveAndReturn(WidgetTester tester) async {
    for (final state in const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
    }
  }

  Future<void> closePopup(WidgetTester tester) async {
    await tester.tap(find.text('تمام'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows once, a moment after the app opens, and never again',
      (tester) async {
    BroadcastStore.debugPublish(BroadcastState(everyone: _popup()));
    await pumpHome(tester);

    await tester.pump(const Duration(milliseconds: 500));
    expect(
      find.byType(AlertDialog),
      findsNothing,
      reason: "the first frame's own work goes first",
    );

    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump();
    expect(find.text('تحديث جديد p_1'), findsOneWidget);
    expect(BroadcastStore.seen, contains('p_1'));

    await closePopup(tester);
    expect(find.byType(AlertDialog), findsNothing);

    clock = clock.add(const Duration(hours: 2));
    await leaveAndReturn(tester);
    await tester.pump(const Duration(seconds: 2));
    expect(
      find.byType(AlertDialog),
      findsNothing,
      reason: 'once per device',
    );
  });

  testWidgets('one that arrives mid-session waits for the next open',
      (tester) async {
    await pumpHome(tester);
    await tester.pump(const Duration(seconds: 2));

    clock = clock.add(const Duration(minutes: 5));
    BroadcastStore.debugPublish(BroadcastState(everyone: _popup()));
    await tester.pump(const Duration(seconds: 3));
    expect(
      find.byType(AlertDialog),
      findsNothing,
      reason: 'never in the middle of someone using the app',
    );

    clock = clock.add(const Duration(minutes: 1));
    await leaveAndReturn(tester);
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pump();
    expect(find.text('تحديث جديد p_1'), findsOneWidget);
    await closePopup(tester);
  });

  testWidgets(
      'the live document answering just after a cold start still '
      'counts as the open', (tester) async {
    await pumpHome(tester);
    await tester.pump(const Duration(seconds: 3));
    clock = clock.add(const Duration(seconds: 3));

    BroadcastStore.debugPublish(BroadcastState(everyone: _popup()));
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pump();
    expect(find.byType(AlertDialog), findsOneWidget);
    await closePopup(tester);
  });

  testWidgets('an inactive blip is not an open', (tester) async {
    await pumpHome(tester);
    await tester.pump(const Duration(seconds: 2));
    clock = clock.add(const Duration(minutes: 5));
    BroadcastStore.debugPublish(BroadcastState(everyone: _popup()));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 2));
    expect(
      find.byType(AlertDialog),
      findsNothing,
      reason: 'Control Center or Face ID never left the screen',
    );
  });

  testWidgets('never over the first-run walkthrough', (tester) async {
    BroadcastStore.debugPublish(BroadcastState(everyone: _popup()));
    await pumpHome(tester, onboardingSeen: false);
    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(AlertDialog), findsNothing);
    expect(
      BroadcastStore.seen,
      isEmpty,
      reason: 'still owed for next time',
    );
  });

  testWidgets('waits for another dialog to close instead of stacking on it',
      (tester) async {
    BroadcastStore.debugPublish(BroadcastState(everyone: _popup()));
    await pumpHome(tester);
    final homeContext = tester.element(find.text('home'));
    unawaited(
      showDialog<void>(
        context: homeContext,
        builder: (ctx) => AlertDialog(
          title: const Text('room finished'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('close'),
            ),
          ],
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pump();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('room finished'), findsOneWidget);

    await tester.tap(find.text('close'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(find.text('تحديث جديد p_1'), findsOneWidget);
    await closePopup(tester);
  });

  testWidgets('a test pop-up reaches only the account it names',
      (tester) async {
    BroadcastStore.debugPublish(
      BroadcastState(
        test: _popup(id: 'p_test', hashes: {broadcastUidHash('uidAziz')}),
      ),
    );
    await pumpHome(tester, uid: 'uidSomeoneElse');
    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('the named test account sees it', (tester) async {
    BroadcastStore.debugPublish(
      BroadcastState(
        test: _popup(id: 'p_test', hashes: {broadcastUidHash('uidAziz')}),
      ),
    );
    await pumpHome(tester, uid: 'uidAziz');
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pump();
    expect(find.text('تحديث جديد p_test'), findsOneWidget);
    await closePopup(tester);
  });

  testWidgets(
      'an English app shows the Arabic, right to left, when no '
      'English was written', (tester) async {
    BroadcastStore.debugPublish(BroadcastState(everyone: _popup()));
    await pumpHome(tester, locale: const Locale('en'));
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pump();
    final title = tester.widget<Text>(find.text('تحديث جديد p_1'));
    expect(title.textDirection, TextDirection.rtl);
    await closePopup(tester);
  });

  testWidgets("a reminder's home screen is home: the pop-up still shows",
      (tester) async {
    BroadcastStore.debugPublish(BroadcastState(everyone: _popup()));
    await pumpHome(tester);
    unawaited(
      Navigator.of(tester.element(find.text('home'))).pushNamed('/grid'),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pump();
    expect(find.text('grid'), findsOneWidget);
    expect(find.text('تحديث جديد p_1'), findsOneWidget);
    await closePopup(tester);
  });

  testWidgets('waits while another screen is pushed on top', (tester) async {
    BroadcastStore.debugPublish(BroadcastState(everyone: _popup()));
    await pumpHome(tester);
    final navigator = Navigator.of(tester.element(find.text('home')));
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Center(child: Text('room'))),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pump();
    expect(find.byType(AlertDialog), findsNothing);

    navigator.pop();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(find.text('تحديث جديد p_1'), findsOneWidget);
    await closePopup(tester);
  });

  testWidgets('a pop-up the server no longer has never shows from the copy',
      (tester) async {
    BroadcastStore.debugPublish(BroadcastState(everyone: _popup()));
    BroadcastStore.debugServerRead = () async => BroadcastState.empty;
    await pumpHome(tester);
    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(AlertDialog), findsNothing);
    expect(BroadcastStore.seen, isEmpty);
  });

  testWidgets('shows what the server has now, not the older copy',
      (tester) async {
    BroadcastStore.debugPublish(BroadcastState(everyone: _popup()));
    BroadcastStore.debugServerRead =
        () async => BroadcastState(everyone: _popup(id: 'p_2'));
    await pumpHome(tester);
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pump();
    expect(find.text('تحديث جديد p_2'), findsOneWidget);
    expect(find.text('تحديث جديد p_1'), findsNothing);
    expect(BroadcastStore.seen, {'p_2'});
    await closePopup(tester);
  });

  testWidgets('offline at the open: nothing unconfirmed, asked again',
      (tester) async {
    BroadcastStore.debugPublish(BroadcastState(everyone: _popup()));
    var asked = 0;
    BroadcastStore.debugServerRead = () async {
      asked++;
      return asked == 1 ? null : BroadcastStore.current;
    };
    await pumpHome(tester);
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pump();
    expect(find.byType(AlertDialog), findsNothing);
    expect(BroadcastStore.seen, isEmpty);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(asked, 2);
    expect(find.text('تحديث جديد p_1'), findsOneWidget);
    await closePopup(tester);
  });

  testWidgets('a clock set back since the open does not hold it open',
      (tester) async {
    await pumpHome(tester);
    await tester.pump(const Duration(seconds: 2));
    clock = clock.subtract(const Duration(hours: 1));
    BroadcastStore.debugPublish(
      BroadcastState(
        everyone: BroadcastPopup(
          id: 'p_late',
          titleAr: 'تحديث جديد p_late',
          bodyAr: 'نص',
          buttonAr: 'تمام',
          startsAt: clock.subtract(const Duration(hours: 1)),
          endsAt: clock.add(const Duration(days: 7)),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(AlertDialog), findsNothing);
  });

  // The pop-up that sends someone on an old build to the store. It rides the
  // same open as the admin's message, so the rules above hold for it too;
  // what is pinned here is what is its own: who is asked, how often, what the
  // button opens, and the one kind that cannot be put off.
  group('the update prompt', () {
    const ar = S(Locale('ar'));
    const en = S(Locale('en'));

    AppUpdateGate gate({
      int iosLatest = 90,
      int iosMin = 0,
      int androidLatest = 0,
      int androidMin = 0,
    }) =>
        AppUpdateGate(
          iosLatest: iosLatest,
          iosMin: iosMin,
          androidLatest: androidLatest,
          androidMin: androidMin,
        );

    Finder doum() => find.byWidgetPredicate(
          (w) => w is Sprout && w.pose == kUpdatePose,
        );

    Future<void> settle(WidgetTester tester) async {
      await tester.pump(const Duration(milliseconds: 1300));
      await tester.pump();
    }

    testWidgets(
        'an older build is offered the update: Doum in his bulb pose, and a '
        'way to put it off', (tester) async {
      BroadcastStore.debugPublish(BroadcastState(update: gate()));
      await pumpHome(tester);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(AlertDialog), findsNothing);

      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump();
      expect(find.text(ar.updateAvailableTitle), findsOneWidget);
      expect(find.text(ar.updateAvailableBody), findsOneWidget);
      expect(doum(), findsOneWidget);
      expect(kUpdatePose, SproutPose.idea);
      // The size every question pop-up draws him at.
      expect(tester.widget<Sprout>(doum()).height, kSproutQuestionHeight);
      expect(find.text(ar.updateNow), findsOneWidget);
      expect(find.text(ar.updateLater), findsOneWidget);
      expect(BroadcastStore.updateAskedAt, clock, reason: 'counted as it goes up');

      await tester.tap(find.text(ar.updateLater));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('an English app gets the English words', (tester) async {
      BroadcastStore.debugPublish(BroadcastState(update: gate()));
      await pumpHome(tester, locale: const Locale('en'));
      await settle(tester);
      expect(find.text(en.updateAvailableTitle), findsOneWidget);
      expect(find.text(en.updateAvailableBody), findsOneWidget);
      expect(find.text(en.updateNow), findsOneWidget);
      await tester.tap(find.text(en.updateLater));
      await tester.pumpAndSettle();
    });

    testWidgets('once a day, however many times the app is opened',
        (tester) async {
      BroadcastStore.debugPublish(BroadcastState(update: gate()));
      await pumpHome(tester);
      await settle(tester);
      await tester.tap(find.text(ar.updateLater));
      await tester.pumpAndSettle();

      clock = clock.add(const Duration(hours: 2));
      await leaveAndReturn(tester);
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(AlertDialog), findsNothing, reason: 'offered 2 hours ago');

      clock = clock.add(const Duration(hours: 23));
      await leaveAndReturn(tester);
      await settle(tester);
      expect(
        find.text(ar.updateAvailableTitle),
        findsOneWidget,
        reason: 'a day on, still not updated, it asks again',
      );
      await tester.tap(find.text(ar.updateLater));
      await tester.pumpAndSettle();
    });

    testWidgets('Update opens the store page and closes the prompt',
        (tester) async {
      final opened = <Uri>[];
      BroadcastStore.debugPublish(BroadcastState(update: gate()));
      await pumpHome(
        tester,
        launcher: (uri) async {
          opened.add(uri);
          return true;
        },
      );
      await settle(tester);
      await tester.tap(find.text(ar.updateNow));
      await tester.pumpAndSettle();
      expect(opened, [Uri.parse('https://apps.apple.com/app/id6788149393')]);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('on Android the Play app is tried first, then the page',
        (tester) async {
      final tried = <Uri>[];
      BroadcastStore.debugPublish(
        BroadcastState(update: gate(iosLatest: 0, androidLatest: 90)),
      );
      await pumpHome(
        tester,
        platform: TargetPlatform.android,
        launcher: (uri) async {
          tried.add(uri);
          return uri.scheme != 'market';
        },
      );
      await settle(tester);
      await tester.tap(find.text(ar.updateNow));
      await tester.pumpAndSettle();
      expect(tried.map((u) => u.toString()), [
        'market://details?id=com.growdaily.v2',
        'https://play.google.com/store/apps/details?id=com.growdaily.v2',
      ]);
    });

    testWidgets('a build that is up to date, or newer, is never asked',
        (tester) async {
      var asked = 0;
      BroadcastStore.debugServerRead = () async {
        asked++;
        return BroadcastStore.current;
      };
      BroadcastStore.debugPublish(BroadcastState(update: gate()));
      for (final build in [90, 91]) {
        await pumpHome(tester, build: () async => build);
        await tester.pump(const Duration(seconds: 3));
        expect(find.byType(AlertDialog), findsNothing, reason: 'build $build');
        await tester.pumpWidget(const SizedBox());
      }
      expect(asked, 0, reason: 'nothing owed, so not a single read');
    });

    testWidgets('a gate set only for the other platform does not reach this one',
        (tester) async {
      BroadcastStore.debugPublish(
        BroadcastState(update: gate(iosLatest: 0, androidLatest: 90)),
      );
      await pumpHome(tester);
      await tester.pump(const Duration(seconds: 3));
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets(
        'a phone that cannot read its build, or has no store, is left alone '
        'even by the wall', (tester) async {
      BroadcastStore.debugPublish(
        BroadcastState(update: gate(iosMin: 90)),
      );
      await pumpHome(tester, build: () async => null);
      await tester.pump(const Duration(seconds: 3));
      expect(find.byType(AlertDialog), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await pumpHome(tester, platform: null);
      await tester.pump(const Duration(seconds: 3));
      expect(find.byType(AlertDialog), findsNothing, reason: 'the web');
    });

    testWidgets('with no gate the build is never even asked for',
        (tester) async {
      var reads = 0;
      BroadcastStore.debugPublish(BroadcastState(everyone: _popup()));
      await pumpHome(
        tester,
        build: () async {
          reads++;
          return 84;
        },
      );
      await settle(tester);
      expect(find.text('تحديث جديد p_1'), findsOneWidget);
      expect(reads, 0);
      await closePopup(tester);
    });

    testWidgets('never over the first-run walkthrough', (tester) async {
      BroadcastStore.debugPublish(BroadcastState(update: gate()));
      await pumpHome(tester, onboardingSeen: false);
      await tester.pump(const Duration(seconds: 3));
      expect(find.byType(AlertDialog), findsNothing);
      expect(BroadcastStore.updateAskedAt, isNull, reason: 'still owed');
    });

    testWidgets('offline at the open: nothing unconfirmed, and no wall',
        (tester) async {
      BroadcastStore.debugPublish(
        BroadcastState(update: gate(iosMin: 90)),
      );
      BroadcastStore.debugServerRead = () async => null;
      await pumpHome(tester);
      await tester.pump(const Duration(seconds: 5));
      expect(
        find.byType(AlertDialog),
        findsNothing,
        reason: 'a phone with no connection is never locked out of its habits',
      );
    });

    testWidgets('what the server has now decides, not the older copy',
        (tester) async {
      BroadcastStore.debugPublish(BroadcastState(update: gate()));
      BroadcastStore.debugServerRead = () async => BroadcastState.empty;
      await pumpHome(tester);
      await tester.pump(const Duration(seconds: 3));
      expect(find.byType(AlertDialog), findsNothing);
      expect(BroadcastStore.updateAskedAt, isNull);
    });

    testWidgets('an update goes before a message, which keeps for the next open',
        (tester) async {
      BroadcastStore.debugPublish(
        BroadcastState(everyone: _popup(), update: gate()),
      );
      await pumpHome(tester);
      await settle(tester);
      expect(find.text(ar.updateAvailableTitle), findsOneWidget);
      expect(find.text('تحديث جديد p_1'), findsNothing);
      expect(BroadcastStore.seen, isEmpty, reason: 'the message is still owed');
      await tester.tap(find.text(ar.updateLater));
      await tester.pumpAndSettle();

      clock = clock.add(const Duration(hours: 2));
      await leaveAndReturn(tester);
      await settle(tester);
      expect(find.text('تحديث جديد p_1'), findsOneWidget);
      await closePopup(tester);
    });

    group('the wall (below the oldest build allowed)', () {
      AppUpdateGate wall() => gate(iosLatest: 85, iosMin: 85);

      testWidgets('has no later, no tap outside and no back', (tester) async {
        final opened = <Uri>[];
        BroadcastStore.debugPublish(BroadcastState(update: wall()));
        await pumpHome(
          tester,
          launcher: (uri) async {
            opened.add(uri);
            return true;
          },
        );
        await settle(tester);
        expect(find.text(ar.updateRequiredTitle), findsOneWidget);
        expect(find.text(ar.updateRequiredBody), findsOneWidget);
        expect(find.text(ar.updateLater), findsNothing);
        expect(doum(), findsOneWidget);

        await tester.tapAt(const Offset(4, 4));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget, reason: 'the scrim');

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget, reason: 'the back button');

        await tester.tap(find.text(ar.updateNow));
        await tester.pumpAndSettle();
        expect(opened, hasLength(1));
        expect(
          find.byType(AlertDialog),
          findsOneWidget,
          reason: 'it stays until the app is really updated',
        );
        expect(
          BroadcastStore.updateAskedAt,
          isNull,
          reason: 'a wall is not an offer that is spent for a day',
        );
      });

      testWidgets(
          'comes down by itself when the admin lowers the minimum under '
          'an open app', (tester) async {
        BroadcastStore.debugPublish(BroadcastState(update: wall()));
        await pumpHome(tester);
        await settle(tester);
        expect(find.text(ar.updateRequiredTitle), findsOneWidget);

        BroadcastStore.debugPublish(
          BroadcastState(update: gate(iosLatest: 85)),
        );
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
      });

      testWidgets('stays while the document changes but the wall does not',
          (tester) async {
        BroadcastStore.debugPublish(BroadcastState(update: wall()));
        await pumpHome(tester);
        await settle(tester);

        BroadcastStore.debugPublish(
          BroadcastState(everyone: _popup(), update: wall()),
        );
        await tester.pumpAndSettle();
        expect(find.text(ar.updateRequiredTitle), findsOneWidget);
      });
    });
  });
}

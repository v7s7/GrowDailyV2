// Who is asked to update, when, and where the button goes, with no screen.
//
// What has to hold:
//   - a build is only asked when the admin has said a newer one is live, and
//     only from the pair for ITS platform (Apple and Google release on
//     different days);
//   - a phone that cannot be sure (no gate, no store, an unreadable build
//     number) is never told it is out of date, above all not by the wall,
//     which has no way out;
//   - the offer that can be put off comes back once a day and not sooner,
//     the wall at every open, and a clock set back never keeps either quiet;
//   - the button opens the store page: Apple's, or Play's own app first and
//     its web page when that will not open.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/broadcast/app_update.dart';
import 'package:grow_daily_v2/features/broadcast/broadcast_message.dart';

final _noon = DateTime(2026, 9, 30, 12);

const _gate = AppUpdateGate(iosLatest: 90, androidLatest: 88);

AppUpdateNeed _need({
  AppUpdateGate? gate = _gate,
  TargetPlatform? platform = TargetPlatform.iOS,
  int? build = 84,
  DateTime? askedAt,
  DateTime? now,
}) =>
    appUpdateNeed(
      gate: gate,
      platform: platform,
      build: build,
      now: now ?? _noon,
      askedAt: askedAt,
    );

void main() {
  group('which build is asked', () {
    test('an older build is offered the update', () {
      expect(_need(), AppUpdateNeed.available);
      expect(_need(build: 89), AppUpdateNeed.available);
    });

    test('the newest build, or a newer one (TestFlight, a beta), is not', () {
      expect(_need(build: 90), AppUpdateNeed.none);
      expect(_need(build: 91), AppUpdateNeed.none);
    });

    test('each platform reads its own pair: 89 is old on iOS, current on Android',
        () {
      expect(_need(build: 89), AppUpdateNeed.available);
      expect(
        _need(build: 89, platform: TargetPlatform.android),
        AppUpdateNeed.none,
      );
      expect(
        _need(build: 87, platform: TargetPlatform.android),
        AppUpdateNeed.available,
      );
    });

    test('a platform the admin left at 0 is never asked', () {
      const iosOnly = AppUpdateGate(iosLatest: 90);
      expect(
        _need(gate: iosOnly, platform: TargetPlatform.android),
        AppUpdateNeed.none,
      );
    });

    test('below the oldest build allowed is the wall, not an offer', () {
      const wall = AppUpdateGate(iosLatest: 90, iosMin: 85);
      expect(_need(gate: wall), AppUpdateNeed.mandatory);
      expect(_need(gate: wall, build: 85), AppUpdateNeed.available);
      expect(_need(gate: wall, build: 90), AppUpdateNeed.none);
    });

    test('an oldest build of 0 means there is no wall at all', () {
      expect(
        _need(gate: const AppUpdateGate(iosLatest: 90)),
        AppUpdateNeed.available,
      );
    });

    test('a phone that cannot be sure is left alone, wall or no wall', () {
      const wall = AppUpdateGate(iosLatest: 90, iosMin: 90);
      expect(_need(gate: null), AppUpdateNeed.none);
      expect(_need(gate: wall, build: null), AppUpdateNeed.none);
      expect(_need(gate: wall, build: 0), AppUpdateNeed.none);
      expect(_need(gate: wall, build: -1), AppUpdateNeed.none);
      expect(_need(gate: wall, platform: null), AppUpdateNeed.none, reason: 'web');
      for (final desktop in [
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.fuchsia,
      ]) {
        expect(_need(gate: wall, platform: desktop), AppUpdateNeed.none);
      }
    });
  });

  group('how often', () {
    test('an offer made less than a day ago is not made again', () {
      expect(
        _need(askedAt: _noon.subtract(const Duration(hours: 23, minutes: 59))),
        AppUpdateNeed.none,
      );
      expect(
        _need(askedAt: _noon.subtract(const Duration(minutes: 1))),
        AppUpdateNeed.none,
      );
    });

    test('a day later it is', () {
      expect(_need(askedAt: _noon.subtract(kUpdateAskEvery)), AppUpdateNeed.available);
      expect(
        _need(askedAt: _noon.subtract(const Duration(days: 9))),
        AppUpdateNeed.available,
      );
    });

    test('a clock set back since the last offer does not keep it quiet', () {
      expect(
        _need(askedAt: _noon.add(const Duration(days: 30))),
        AppUpdateNeed.available,
      );
    });

    test('the wall is not rationed: it comes at every open', () {
      const wall = AppUpdateGate(iosLatest: 90, iosMin: 85);
      expect(
        _need(gate: wall, askedAt: _noon.subtract(const Duration(minutes: 1))),
        AppUpdateNeed.mandatory,
      );
    });
  });

  group('the store page', () {
    test('iOS goes to the App Store page, Android to Play then its web page',
        () {
      expect(
        storeListingUris(TargetPlatform.iOS).map((u) => u.toString()),
        ['https://apps.apple.com/app/id6788149393'],
      );
      expect(
        storeListingUris(TargetPlatform.android).map((u) => u.toString()),
        [
          'market://details?id=com.growdaily.v2',
          'https://play.google.com/store/apps/details?id=com.growdaily.v2',
        ],
      );
      expect(storeListingUris(TargetPlatform.macOS), isEmpty);
    });

    test('the ids are the ones the join page already sends people to', () {
      // public/join/index.html links the same two; a drift here would send
      // the pop-up's button somewhere the website does not.
      expect(kAppStoreId, '6788149393');
      expect(kAndroidPackage, 'com.growdaily.v2');
    });

    test('opens the first link that will open, and stops there', () async {
      final tried = <String>[];
      final ok = await openStoreListing(TargetPlatform.android, (uri) async {
        tried.add(uri.scheme);
        return uri.scheme == 'market';
      });
      expect(ok, isTrue);
      expect(tried, ['market']);
    });

    test('falls back to the web page when the Play app will not open, even '
        'when it throws', () async {
      final tried = <String>[];
      final ok = await openStoreListing(TargetPlatform.android, (uri) async {
        tried.add(uri.scheme);
        if (uri.scheme == 'market') throw StateError('no Play app');
        return true;
      });
      expect(ok, isTrue);
      expect(tried, ['market', 'https']);
    });

    test('says so when nothing opened, and opens nothing where there is no store',
        () async {
      expect(
        await openStoreListing(TargetPlatform.iOS, (_) async => false),
        isFalse,
      );
      var launched = 0;
      expect(
        await openStoreListing(TargetPlatform.linux, (_) async {
          launched++;
          return true;
        }),
        isFalse,
      );
      expect(launched, 0);
    });
  });
}

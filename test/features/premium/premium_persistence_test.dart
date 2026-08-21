// Premium has to be known on the FIRST frame, not after a round trip.
//
// ── The bug this closes ───────────────────────────────────────────────────
// PremiumNotifier started at `false` on every launch, and only became true
// once PurchaseService.logIn had completed a network call. So a paying
// customer's cold start showed the free app at them: locked history, muted
// year strips, a blurred recap card, an upgrade banner. Offline it never
// recovered at all, and when the one request failed nothing retried until
// the app was resumed or the paywall screen was opened by hand. That last
// part is the reported symptom exactly: "it does not detect Premium until I
// open the page."
//
// The entitlement is now restored from disk before the first frame, the same
// way theme mode, preset, font, locale and guest mode already were.
// RevenueCat remains the only authority; the cache is a warm start.
//
// ── The half that matters more than the feature ───────────────────────────
// A cached "yes" is a claim about an ACCOUNT, sitting on a DEVICE. Most of
// this file is about the case where those two stop matching: a shared phone,
// a resold phone, a second account. Getting that wrong would hand one
// person's subscription to the next person who signs in, which is worse
// than the flash it was meant to fix.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/core/services/local_store_service.dart';
import 'package:grow_daily_v2/features/premium/notifiers/premium_notifier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('premium_persist_');
    Hive.init(tmp.path);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await tmp.delete(recursive: true);
  });

  /// Lets the notifier's fire-and-forget Hive write land.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 60));

  group('the seeded value', () {
    test('a device that has never seen an entitlement starts free', () async {
      expect(await loadPersistedPremium(), isFalse);
      expect(await loadPersistedPremiumUid(), isNull);
    });

    test('the notifier opens on whatever was restored', () {
      final n = PremiumNotifier(initial: true, cachedUid: 'u1');
      expect(n.state, isTrue,
          reason: 'the first frame is the paid one, with no round trip');
      n.dispose();
    });

    test('and still defaults to free with no cache', () {
      final n = PremiumNotifier();
      expect(n.state, isFalse);
      n.dispose();
    });
  });

  group('binding the cache to an account', () {
    test('the same account keeps its entitlement', () async {
      final n = PremiumNotifier(initial: true, cachedUid: 'u1');
      n.bindAccount('u1');
      expect(n.state, isTrue);
      await settle();
      expect(await loadPersistedPremium(), isTrue);
      expect(await loadPersistedPremiumUid(), 'u1');
      n.dispose();
    });

    // The one that matters. A shared or resold device must not carry a
    // subscription across accounts.
    test('a DIFFERENT account does not inherit it', () async {
      final n = PremiumNotifier(initial: true, cachedUid: 'u1');
      n.bindAccount('u2');
      // Deferred by a microtask on purpose: the auth listener that calls
      // this fires during build, and mutating state there red-screens the
      // app. See bindAccount's doc comment.
      await settle();
      expect(n.state, isFalse,
          reason: 'the cached yes belonged to u1, not to whoever just '
              'signed in');
      await settle();
      expect(await loadPersistedPremium(), isFalse,
          reason: 'and the stale claim is cleared from disk, so the next '
              'cold start cannot seed it back');
      n.dispose();
    });

    test('the drop is deferred, never mid-build', () async {
      // Pins the fix for the red screen this caused: a synchronous drop here
      // runs inside main.dart's fireImmediately auth listener, which is
      // inside build.
      final n = PremiumNotifier(initial: true, cachedUid: 'u1');
      n.bindAccount('u2');
      expect(n.state, isTrue,
          reason: 'still true synchronously; the correction lands next tick');
      await settle();
      expect(n.state, isFalse);
      n.dispose();
    });

    test('a guest who signs up keeps what they just bought', () async {
      // No cached uid: the entitlement was earned on this device before
      // there was an account to attach it to.
      final n = PremiumNotifier(initial: true);
      n.bindAccount('u9');
      expect(n.state, isTrue);
      await settle();
      expect(await loadPersistedPremiumUid(), 'u9',
          reason: 're-stamped under the new account rather than dropped');
      n.dispose();
    });

    test('binding a free account to a free device changes nothing', () async {
      final n = PremiumNotifier(cachedUid: 'u1');
      n.bindAccount('u2');
      await settle();
      expect(n.state, isFalse);
      n.dispose();
    });
  });

  group('signing out', () {
    test('drops the entitlement and the cache together', () async {
      final n = PremiumNotifier(initial: true, cachedUid: 'u1');
      n.bindAccount('u1');
      await settle();
      expect(await loadPersistedPremium(), isTrue);

      n.detachAccount();
      expect(n.state, isFalse);
      await settle();
      expect(await loadPersistedPremium(), isFalse,
          reason: 'a signed-out device must not answer Premium from disk on '
              'its next cold start');
      expect(await loadPersistedPremiumUid(), isNull);
      n.dispose();
    });
  });

  group('the cache is a warm start, never an authority', () {
    test('a lapse clears what a previous launch stored', () async {
      // Stand-in for refresh() finding the subscription expired: the state
      // goes false and the cache has to follow, or the next cold start would
      // seed the entitlement straight back and the lapse would never stick.
      final n = PremiumNotifier(initial: true, cachedUid: 'u1');
      n.bindAccount('u1');
      await settle();
      expect(await loadPersistedPremium(), isTrue);

      n.detachAccount();
      await settle();

      final next = PremiumNotifier(
        initial: await loadPersistedPremium(),
        cachedUid: await loadPersistedPremiumUid(),
      );
      expect(next.state, isFalse,
          reason: 'the next launch must not resurrect a dead subscription');
      n.dispose();
      next.dispose();
    });

    test('a full round trip survives a relaunch', () async {
      final first = PremiumNotifier(initial: true, cachedUid: 'u1');
      first.bindAccount('u1');
      await settle();
      first.dispose();

      // Exactly what main.dart does at boot.
      final second = PremiumNotifier(
        initial: await loadPersistedPremium(),
        cachedUid: await loadPersistedPremiumUid(),
      );
      expect(second.state, isTrue,
          reason: 'this is the whole point: no network, still Premium');
      second.dispose();
    });
  });

  group('the settings box is shared, so keys must not collide', () {
    test('writing the entitlement leaves other settings alone', () async {
      final box = await LocalStoreService.settingsBox();
      await box.put('theme_mode_v1', 'dark');

      final n = PremiumNotifier(initial: true, cachedUid: 'u1');
      n.bindAccount('u1');
      await settle();

      expect(box.get('theme_mode_v1'), 'dark');
      n.dispose();
    });
  });
}

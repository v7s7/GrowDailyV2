// Booting with a restored entitlement, through a real ProviderScope mount.
//
// ── What this guards, and what it honestly cannot ────────────────────────
// The bug that prompted this file was a red screen on cold start: binding
// the restored entitlement called ref.read(premiumProvider...) straight from
// main.dart's auth listener, which is registered with `fireImmediately` and
// therefore runs inside initState while the root ProviderScope is still
// MOUNTING. On device that intermittently threw
// ('!_dirty': is not true, framework.dart Element.rebuild) and the app
// opened on a red screen instead of the grid. Deferring the read by a
// microtask fixed it, verified by A/B with the debugger attached: zero
// assertions on the original, reproducible with the synchronous read, zero
// again once deferred.
//
// That assertion does NOT reproduce here, and this file says so rather than
// pretending otherwise. The harness below really does put the read inside
// the scope's mount (the stack goes initState -> _firstBuild -> mount ->
// _UncontrolledProviderScopeElement.mount), but a widget test's root attach
// and its two-provider graph are not the real app's, and the assertion never
// fires. An earlier version of this file asserted that it did; that test
// passed only because Hive was uninitialised and a DIFFERENT error was being
// caught, which is worse than no test at all.
//
// So this file guards the CONTRACT rather than the crash: whatever order the
// boot happens in, a restored entitlement survives it, a stale one is
// dropped, and mounting raises nothing. The crash itself stays
// device-verified, and the reason is written down in main.dart at the call
// site. If you add another premium call to that listener, defer it.
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/premium/notifiers/premium_notifier.dart';

import '../../helpers/fake_user.dart';

/// Whether the harness guards its sign-out branch the way main.dart does.
enum _SignOut {
  /// `uid == null` treated as a sign-out, which is what shipped briefly and
  /// wiped the entitlement on every cold start.
  unguarded,

  /// Only a RESOLVED null counts, which is what main.dart does now.
  guarded,
}

/// How the harness reaches for premium from inside the mounting scope.
enum _Reach {
  /// What main.dart used to do, and what red-screened the app.
  synchronous,

  /// What main.dart does now.
  deferred,
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('premium_boot_');
    Hive.init(tmp.path);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await tmp.delete(recursive: true);
  });

  /// Mounts the harness the way runApp mounts main.dart: a fresh root, a
  /// ProviderScope carrying the premium override, and a signed-in account
  /// so the listener's uid branch actually runs.
  Future<void> boot(
    WidgetTester tester, {
    required _Reach reach,
    bool premium = true,
    String cachedUid = 'u1',
    String signedInUid = 'u1',
    _SignOut signOut = _SignOut.guarded,
    bool signedIn = true,
  }) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        // A Stream.value emits ASYNCHRONOUSLY, so the listener's first
        // fire is AsyncLoading with a null uid, exactly as on a real cold
        // start. That first fire is the whole subject of these tests.
        authStateProvider.overrideWith((ref) => Stream<User?>.value(
            signedIn ? fakeUser(signedInUid) : null)),
        premiumProvider.overrideWith((ref) => PremiumNotifier(
              initial: premium,
              cachedUid: cachedUid,
            )),
      ],
      child: _BootHarness(reach: reach, signOut: signOut),
    ));
  }

  group('the boot contract', () {
    testWidgets('a synchronous mid-mount bind still boots', (tester) async {
      // Kept as the control for the deferred cases below, and as the record
      // that this shape does not reproduce the device assertion in a widget
      // test. It must at least never throw something ELSE, which is how the
      // earlier version of this file fooled itself.
      await boot(tester, reach: _Reach.synchronous);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('deferring the bind boots clean', (tester) async {
      await boot(tester, reach: _Reach.deferred);
      await tester.pump();
      expect(tester.takeException(), isNull,
          reason: 'a microtask runs after the mount finishes, so the '
              'notifier is created outside the scope\'s first build');
    });

    testWidgets('and the restored entitlement survives the boot',
        (tester) async {
      // The whole point of the cache: Premium is true on the first frame,
      // with no round trip. Deferring the bind must not cost that.
      await boot(tester, reach: _Reach.deferred);
      await tester.pump();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(_BootHarness)),
      );
      expect(container.read(premiumProvider), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a different account is still dropped, just a tick later',
        (tester) async {
      // The safety property has to survive the deferral: the cached yes
      // belonged to u1, and u2 just signed in.
      await boot(tester,
          reach: _Reach.deferred, cachedUid: 'u1', signedInUid: 'u2');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final container = ProviderScope.containerOf(
        tester.element(find.byType(_BootHarness)),
      );
      expect(container.read(premiumProvider), isFalse,
          reason: 'one person\'s subscription must never reach the next '
              'person to sign in on the device');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a cold start does NOT wipe the restored entitlement',
        (tester) async {
      // The bug: authStateProvider's first fire on every cold start is
      // AsyncLoading with a null uid. Read as "signed out", it wiped the
      // entitlement restored from disk before Firebase Auth had answered,
      // so the app was only right again once RevenueCat replied over the
      // network. Offline it never recovered, which is precisely what the
      // cache was added to fix.
      await boot(tester, reach: _Reach.deferred);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final container = ProviderScope.containerOf(
        tester.element(find.byType(_BootHarness)),
      );
      expect(container.read(premiumProvider), isTrue,
          reason: 'a launch that has not resolved auth yet is not a sign-out');
    });

    testWidgets('and the unguarded version really does wipe it',
        (tester) async {
      // The control. Without this the test above could pass against a build
      // where the sign-out branch had simply stopped running at all.
      await boot(tester, reach: _Reach.deferred, signOut: _SignOut.unguarded);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final container = ProviderScope.containerOf(
        tester.element(find.byType(_BootHarness)),
      );
      expect(container.read(premiumProvider), isFalse,
          reason: 'this is the shape that shipped briefly, and it must still '
              'be observable or the guarded test proves nothing');
    });

    testWidgets('a real sign-out still drops the entitlement', (tester) async {
      // The guard must not swallow the case it exists beside: a RESOLVED
      // null is a genuine sign-out and has to clear everything.
      await boot(tester, reach: _Reach.deferred, signedIn: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final container = ProviderScope.containerOf(
        tester.element(find.byType(_BootHarness)),
      );
      expect(container.read(premiumProvider), isFalse,
          reason: 'AsyncData(null) is a sign-out, and hasValue is true for it');
    });

    testWidgets('a free device stays free and still boots clean',
        (tester) async {
      await boot(tester, reach: _Reach.deferred, premium: false);
      await tester.pump();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(_BootHarness)),
      );
      expect(container.read(premiumProvider), isFalse);
      expect(tester.takeException(), isNull);
    });
  });
}

/// main.dart's shape, reduced to the part that matters.
///
/// A ConsumerStatefulWidget directly under the root ProviderScope, whose
/// initState registers a `fireImmediately` listener on auth. That listener
/// runs synchronously during mount, which is the entire reason this file
/// exists.
class _BootHarness extends ConsumerStatefulWidget {
  final _Reach reach;
  final _SignOut signOut;
  const _BootHarness({required this.reach, required this.signOut});

  @override
  ConsumerState<_BootHarness> createState() => _BootHarnessState();
}

class _BootHarnessState extends ConsumerState<_BootHarness> {
  @override
  void initState() {
    super.initState();
    ref.listenManual(authStateProvider, (previous, next) {
      final uid = next.asData?.value?.uid;
      if (uid == null) {
        // main.dart's sign-out branch, in both its shapes.
        final treatAsSignOut =
            widget.signOut == _SignOut.unguarded || next.hasValue;
        if (treatAsSignOut) {
          Future.microtask(() {
            if (!mounted) return;
            ref.read(premiumProvider.notifier).detachAccount();
          });
        }
        return;
      }
      switch (widget.reach) {
        case _Reach.synchronous:
          ref.read(premiumProvider.notifier).bindAccount(uid);
        case _Reach.deferred:
          Future.microtask(() {
            if (!mounted) return;
            ref.read(premiumProvider.notifier).bindAccount(uid);
          });
      }
    }, fireImmediately: true);
  }

  @override
  Widget build(BuildContext context) {
    // Watched, not ignored: the real app has widgets depending on this all
    // over (locked history, muted strips, the recap card), and a dependent
    // is what makes the scope care when the provider appears mid-mount.
    ref.watch(premiumProvider);
    return const SizedBox.shrink();
  }
}

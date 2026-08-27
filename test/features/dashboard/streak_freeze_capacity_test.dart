// The streak-freeze bank cap, which stopped being a constant.
//
// Capacity above the starting three is purchasable, which makes it one of
// the few repeatable gold sinks in the app. That turns a compile-time
// constant into a per-user persisted number, and a persisted number has a
// failure mode a constant never had: every account written before the field
// existed reads it as absent.
//
// So the constant did not go away, it became the FLOOR. These tests pin
// that, because an upgrade that silently took two freeze slots off every
// existing account is exactly the "nothing may be taken from an existing
// user" failure the whole economy pass has been avoiding.
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/services/local_store_service.dart';
import 'package:grow_daily_v2/core/services/notification_service.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/dashboard/notifiers/dashboard_notifier.dart';
import 'package:hive/hive.dart';

import '../../helpers/never_bonus_random.dart';
import '../../helpers/wait_until.dart';

void main() {
  DashboardState withCapacity(int c) => DashboardState(
        level: 1,
        currentLevelXp: 0,
        cumulativeXp: 0,
        gold: 0,
        streak: 0,
        completions: const {},
        freezeCapacity: c,
      );

  group('the bank cap floors at the original three', () {
    test('a legacy account with no stored capacity keeps its three slots', () {
      // The default, and what every document written before this field
      // existed parses to.
      expect(
        withCapacity(0).freezeCapacityOrDefault,
        DashboardNotifier.maxStreakFreezes,
      );
    });

    test('a corrupt or negative stored value cannot shrink the bank', () {
      for (final stored in [-5, 1, 2]) {
        expect(
          withCapacity(stored).freezeCapacityOrDefault,
          DashboardNotifier.maxStreakFreezes,
          reason: 'stored $stored must not shrink the bank',
        );
      }
    });

    test('a purchased slot raises it', () {
      expect(withCapacity(4).freezeCapacityOrDefault, 4);
      expect(withCapacity(5).freezeCapacityOrDefault, 5);
    });

    test('a corrupt value far above the ceiling cannot hand out free slots',
        () {
      // Without the cap a hand-edited document storing 99 would be honoured
      // as ninety-nine slots.
      expect(
        withCapacity(99).freezeCapacityOrDefault,
        DashboardNotifier.maxFreezeCapacity,
      );
    });

    test('the constant is the floor, not the ceiling', () {
      // If this ever fails, someone has turned maxStreakFreezes back into a
      // cap and purchased capacity has stopped working.
      expect(
        withCapacity(DashboardNotifier.maxStreakFreezes + 2)
            .freezeCapacityOrDefault,
        greaterThan(DashboardNotifier.maxStreakFreezes),
      );
    });
  });

  group('buying a slot', () {
    late Directory tmp;
    final containers = <ProviderContainer>[];

    Future<ProviderContainer> launch() async {
      final c = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
          dashboardProvider.overrideWith(
            (ref) => DashboardNotifier(null, random: NeverBonusRandom()),
          ),
        ],
      );
      containers.add(c);
      await c.read(authStateProvider.future);
      c.read(dashboardProvider);
      await waitUntil(
        () => !c.read(dashboardProvider).isLoading,
        describe: 'the dashboard to load',
      );
      await c.read(dashboardProvider.notifier).ready;
      return c;
    }

    setUp(() async {
      NotificationService.instance.celebrationsEnabled = false;
      tmp = await Directory.systemTemp.createTemp('freeze_slot_');
      Hive.init(tmp.path);
    });

    tearDown(() async {
      for (final c in containers) {
        c.dispose();
      }
      containers.clear();
      await LocalStoreService.settleDailyWrites();
      await Hive.deleteFromDisk();
      await tmp.delete(recursive: true);
    });

    test('a slot that is not on offer can never be bought', () async {
      final c = await launch();
      final n = c.read(dashboardProvider.notifier);
      for (final slot in [0, 3, 6, 99, -1]) {
        expect(await n.buyFreezeSlot(slot), isFalse, reason: 'slot $slot');
      }
    });

    test('slots are bought in order, so slot 5 cannot skip slot 4', () async {
      // Without this an account at capacity 3 could buy slot 5 and never pay
      // slot 4's price.
      final c = await launch();
      final n = c.read(dashboardProvider.notifier);
      expect(await n.buyFreezeSlot(5), isFalse);
      expect(
        c.read(dashboardProvider).freezeCapacityOrDefault,
        DashboardNotifier.maxStreakFreezes,
      );
    });

    test('an account below the level gate cannot buy', () async {
      // A fresh guest is level 1; slot 4 gates at 10.
      final c = await launch();
      expect(c.read(dashboardProvider).level, lessThan(10));
      expect(
        await c.read(dashboardProvider.notifier).buyFreezeSlot(4),
        isFalse,
      );
    });

    test('an account that cannot afford it keeps its gold', () async {
      final c = await launch();
      final before = c.read(dashboardProvider).gold;
      expect(
        await c.read(dashboardProvider.notifier).buyFreezeSlot(4),
        isFalse,
      );
      expect(c.read(dashboardProvider).gold, before);
    });

    test('every offered slot is priced above the price of one freeze', () {
      // A slot that cost less than a freeze would be a strictly better buy
      // than the thing it holds, which inverts the ladder.
      for (final offer in DashboardNotifier.freezeSlots.values) {
        expect(offer.cost, greaterThan(DashboardNotifier.streakFreezeCost));
      }
    });

    test('the offered slots exactly fill the gap between floor and ceiling',
        () {
      // If these ever disagree, either a slot is unreachable or the ceiling
      // can never be reached.
      final offered = DashboardNotifier.freezeSlots.keys.toList()..sort();
      expect(
        offered,
        [
          for (var i = DashboardNotifier.maxStreakFreezes + 1;
              i <= DashboardNotifier.maxFreezeCapacity;
              i++)
            i,
        ],
      );
    });
  });
}

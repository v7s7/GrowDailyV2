// The user's own reward list, and the one place in it where money moves.
//
// This is the gold sink. Gold had almost nothing to buy: the whole accessory
// catalogue is 3,710 and a committed board earns about 77 a day, so it
// emptied around day 48 and the balance only grew afterwards. A user-priced
// reward is the only sink that cannot empty, because its capacity is set by
// the person earning.
//
// The money path is one call to spendGold and nothing else, which is what
// makes it safe. These tests pin that: that a claim spends exactly the
// price, that it never spends twice, that it leaves the reward alone so it
// can be taken again, and that a malformed stored record costs only itself.
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/services/local_store_service.dart';
import 'package:grow_daily_v2/core/services/notification_service.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/dashboard/notifiers/dashboard_notifier.dart';
import 'package:grow_daily_v2/features/rewards/models/custom_reward.dart';
import 'package:grow_daily_v2/features/rewards/notifiers/custom_rewards_notifier.dart';
import 'package:hive/hive.dart';

import '../../helpers/never_bonus_random.dart';
import '../../helpers/wait_until.dart';

void main() {
  group('the model', () {
    test('a price is stored in gold and clamped, never in days', () {
      // Storing days would re-price an existing reward whenever the
      // suggestion constant moved, which is the only way this feature could
      // ever make something cost more than it did yesterday.
      final r = CustomReward.create(name: 'قهوة', priceGold: 400);
      expect(r.priceGold, 400);
      expect(
        CustomReward.create(name: 'x', priceGold: 0).priceGold,
        kCustomRewardMinPrice,
      );
      expect(
        CustomReward.create(name: 'x', priceGold: 10000000).priceGold,
        kCustomRewardMaxPrice,
      );
    });

    test('a name is trimmed on the way in', () {
      expect(CustomReward.create(name: '  قهوة  ', priceGold: 10).name, 'قهوة');
    });

    test('one malformed record costs only itself', () {
      // The whole defensive contract. A list parse that throws would leave
      // the screen unusable over a single bad field.
      expect(
        CustomReward.fromMap({'id': 'a', 'name': 'ok', 'priceGold': 5}),
        isNotNull,
      );
      expect(CustomReward.fromMap({'id': 'a', 'priceGold': 5}), isNull);
      expect(
        CustomReward.fromMap({'id': 'a', 'name': '   ', 'priceGold': 5}),
        isNull,
      );
      expect(
        CustomReward.fromMap({'id': '', 'name': 'ok', 'priceGold': 5}),
        isNull,
      );
      expect(CustomReward.fromMap({'id': 'a', 'name': 'ok'}), isNull);
      expect(
        CustomReward.fromMap({'id': 'a', 'name': 'ok', 'priceGold': 'lots'}),
        isNull,
      );
    });

    test('a price that arrived as a double still names a real price', () {
      // Firestore and a JSON round trip both do this.
      final r =
          CustomReward.fromMap({'id': 'a', 'name': 'ok', 'priceGold': 5.0});
      expect(r?.priceGold, 5);
    });

    test('an unreadable date does not discard the reward', () {
      // createdAt only orders the list. Losing a reward over it would be
      // throwing away the thing the user wrote to save the sort.
      final r = CustomReward.fromMap(
        {'id': 'a', 'name': 'ok', 'priceGold': 5, 'createdAt': 'not a date'},
      );
      expect(r, isNotNull);
    });

    test('a round trip through storage preserves everything that matters', () {
      final r = CustomReward.create(name: 'طلعة', priceGold: 250);
      final back = CustomReward.fromMap(r.toMap());
      expect(back!.id, r.id);
      expect(back.name, r.name);
      expect(back.priceGold, r.priceGold);
    });
  });

  group('price suggestions', () {
    test('a suggestion is a number a person would say out loud', () {
      // 418.9 reads as arithmetic; 420 reads as a price.
      expect(priceForDays(7) % 5, 0);
      expect(priceForDays(30) % 5, 0);
    });

    test('a very cheap reward is still allowed to be cheap', () {
      expect(priceForDays(0.1), greaterThanOrEqualTo(kCustomRewardMinPrice));
    });

    test('days and price are inverses within rounding', () {
      expect(daysForPrice(priceForDays(7)), closeTo(7, 0.5));
    });
  });

  group('against real storage', () {
    late Directory tmp;
    final containers = <ProviderContainer>[];

    Future<ProviderContainer> launch() async {
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
          dashboardProvider.overrideWith(
            (ref) => DashboardNotifier(null, random: NeverBonusRandom()),
          ),
        ],
      );
      containers.add(container);
      await container.read(authStateProvider.future);
      container.read(dashboardProvider);
      await waitUntil(
        () => !container.read(dashboardProvider).isLoading,
        describe: 'the dashboard to finish its initial load',
      );
      await container.read(dashboardProvider.notifier).ready;
      container.read(customRewardsProvider);
      await waitUntil(
        () => !container.read(customRewardsProvider).isLoading,
        describe: 'the reward list to load',
      );
      return container;
    }

    /// Puts a known amount of gold on the account by completing a habit
    /// priced for it, so no test has to reach into state directly.
    Future<void> earn(ProviderContainer c, int gold) async {
      await c.read(dashboardProvider.notifier).completeHabit(
            habitId: 'funding-${DateTime.now().microsecondsSinceEpoch}',
            xpReward: 1,
            goldReward: gold,
            frequencyTarget: 1,
            allHabitsDoneAfter: false,
            category: 'quran',
          );
    }

    setUp(() async {
      NotificationService.instance.celebrationsEnabled = false;
      tmp = await Directory.systemTemp.createTemp('custom_rewards_');
      Hive.init(tmp.path);
    });

    tearDown(() async {
      for (final container in containers) {
        container.dispose();
      }
      containers.clear();
      await LocalStoreService.settleDailyWrites();
      await Hive.deleteFromDisk();
      await tmp.delete(recursive: true);
    });

    test('a claim spends exactly the price and nothing else', () async {
      final c = await launch();
      await earn(c, 500);
      final before = c.read(dashboardProvider).gold;

      final r = c
          .read(customRewardsProvider.notifier)
          .add(name: 'قهوة', priceGold: 120)!;
      final ok = await c.read(customRewardsProvider.notifier).claim(r.id);

      expect(ok, isTrue);
      expect(c.read(dashboardProvider).gold, before - 120);
    });

    test('a claim leaves the reward alone so it can be taken again', () async {
      // The property the whole design rests on: because a claim does not
      // touch the reward record, spendGold is the entire transaction and
      // there is no second write to half-land.
      final c = await launch();
      await earn(c, 500);
      final r = c
          .read(customRewardsProvider.notifier)
          .add(name: 'قهوة', priceGold: 100)!;

      await c.read(customRewardsProvider.notifier).claim(r.id);
      final after = c.read(customRewardsProvider).byId(r.id);

      expect(after, isNotNull, reason: 'a claimed reward stays on the list');
      expect(after!.name, 'قهوة');
      expect(after.priceGold, 100);
    });

    test('a reward costing more than the balance cannot be claimed', () async {
      final c = await launch();
      final before = c.read(dashboardProvider).gold;
      final r = c
          .read(customRewardsProvider.notifier)
          .add(name: 'غالية', priceGold: before + 5000)!;

      expect(await c.read(customRewardsProvider.notifier).claim(r.id), isFalse);
      expect(
        c.read(dashboardProvider).gold,
        before,
        reason: 'a refused claim must not move the balance',
      );
    });

    test('two claims fired together cannot both spend', () async {
      // spendGold rolls back by restoring an ABSOLUTE snapshot, so two
      // overlapping spends lose an update and can hand one reward over
      // free. One at a time makes that unreachable.
      final c = await launch();
      await earn(c, 500);
      final before = c.read(dashboardProvider).gold;
      final n = c.read(customRewardsProvider.notifier);
      final a = n.add(name: 'أ', priceGold: 60)!;
      final b = n.add(name: 'ب', priceGold: 30)!;

      final results = await Future.wait([n.claim(a.id), n.claim(b.id)]);

      expect(
        results.where((r) => r).length,
        1,
        reason: 'exactly one of two concurrent claims may succeed',
      );
      expect(
        c.read(dashboardProvider).gold,
        before - 60,
        reason: 'only the winning claim may have moved the balance',
      );
    });

    test('the list is bounded', () async {
      final c = await launch();
      final n = c.read(customRewardsProvider.notifier);
      for (var i = 0; i < kCustomRewardListMax; i++) {
        expect(n.add(name: 'r$i', priceGold: 10), isNotNull);
      }
      expect(n.add(name: 'one too many', priceGold: 10), isNull);
      expect(
        c.read(customRewardsProvider).rewards.length,
        kCustomRewardListMax,
      );
    });

    test('a blank name is refused', () async {
      final c = await launch();
      expect(
        c.read(customRewardsProvider.notifier).add(name: '   ', priceGold: 10),
        isNull,
      );
    });

    test('rewards survive a restart', () async {
      final first = await launch();
      first
          .read(customRewardsProvider.notifier)
          .add(name: 'قهوة الجمعة', priceGold: 300);
      await LocalStoreService.settleDailyWrites();

      final second = await launch();
      final list = second.read(customRewardsProvider).rewards;
      expect(list.length, 1);
      expect(list.single.name, 'قهوة الجمعة');
      expect(list.single.priceGold, 300);
    });

    test('undo puts back the exact record, once', () async {
      final c = await launch();
      final n = c.read(customRewardsProvider.notifier);
      final r = n.add(name: 'قهوة', priceGold: 90)!;

      n.remove(r.id);
      expect(c.read(customRewardsProvider).byId(r.id), isNull);

      n.restore(r);
      expect(c.read(customRewardsProvider).byId(r.id)!.priceGold, 90);

      // A stale snackbar tapped twice must not duplicate the row.
      n.restore(r);
      expect(c.read(customRewardsProvider).rewards.length, 1);
    });

    test('the closet subtitle counts what is actually affordable', () async {
      final c = await launch();
      final n = c.read(customRewardsProvider.notifier);
      n.add(name: 'cheap', priceGold: 10);
      n.add(name: 'mid', priceGold: 100);
      n.add(name: 'dear', priceGold: 5000);
      final s = c.read(customRewardsProvider);

      expect(s.affordableCount(150), 2);
      expect(s.closestShortfall(150), 4850);
      expect(
        s.closestShortfall(999999),
        isNull,
        reason: 'nothing is out of reach when everything is affordable',
      );
    });
  });
}

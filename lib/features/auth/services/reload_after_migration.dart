import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../character/notifiers/character_notifier.dart';
import '../../character/notifiers/prestige_notifier.dart';
import '../../dashboard/notifiers/dashboard_notifier.dart';
import '../../grid/notifiers/weekly_grid_notifier.dart';
import '../../habits/catalog/habit_plans.dart';
import '../../habits/notifiers/catalog_overrides_notifier.dart';
import '../../habits/notifiers/custom_habits_notifier.dart';
import '../../habits/notifiers/habit_order_notifier.dart';
import '../../matrix/notifiers/matrix_notifier.dart';
import '../../rewards/notifiers/custom_rewards_notifier.dart';

/// Re-reads everything the migration just wrote.
///
/// Without this the app is correct on the server and wrong on screen. By
/// the time someone taps "bring it over" they are already signed in, so
/// every one of these notifiers has ALREADY run its load against an
/// account that was empty a moment ago, and each one caches that result
/// for the life of the notifier. The data would only appear on the next
/// cold start, which reads as the migration having silently done nothing.
///
/// Invalidating recreates each notifier, and each constructor re-runs its
/// own load - the same path a sign-in takes. Deliberately a hand-written
/// list rather than something clever: every provider here corresponds to a
/// section GuestMigrationService actually writes, so the two lists are
/// meant to be read side by side and change together.
void reloadAfterGuestMigration(WidgetRef ref) {
  // Profile-document fields: the economy, the character, prestige.
  ref.invalidate(dashboardProvider);
  ref.invalidate(characterProvider);
  ref.invalidate(prestigeProvider);
  // Which habits exist, in what order, with which edits.
  ref.invalidate(activeCatalogProvider);
  ref.invalidate(customHabitsProvider);
  ref.invalidate(catalogOverridesProvider);
  ref.invalidate(habitOrderProvider);
  // The daily documents, which is what the grid paints.
  ref.invalidate(weeklyGridProvider);
  // Subcollections.
  ref.invalidate(matrixProvider);
  ref.invalidate(customRewardsProvider);
}

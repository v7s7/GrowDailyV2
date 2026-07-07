import '../../habits/models/habit_model.dart';

enum QuickWinCadence { daily, weekly }

/// A small, optional, personalized suggestion shown on Today — distinct
/// from a habit: it doesn't color the Grid and doesn't touch the streak.
/// See [QuickWinCatalog] (in `../catalog/quick_win_catalog.dart`) for the
/// actual list of these.
class QuickWin {
  final String id;
  final String titleEn;
  final String titleAr;
  final HabitCategory category;
  final QuickWinCadence cadence;
  final int xpReward;
  final int goldReward;

  /// Weekly only: how many green days this week, for an active habit in
  /// [category], complete this win automatically. Null means it can't be
  /// safely inferred from existing data — the UI falls back to a manual
  /// "mark done" action instead of a progress bar.
  final int? autoTrackTarget;

  const QuickWin({
    required this.id,
    required this.titleEn,
    required this.titleAr,
    required this.category,
    required this.cadence,
    required this.xpReward,
    required this.goldReward,
    this.autoTrackTarget,
  });

  String title(bool isAr) => isAr ? titleAr : titleEn;
}

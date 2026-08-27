import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../habits/catalog/islamic_habit_catalog.dart';
import '../../habits/notifiers/custom_habits_notifier.dart';
import '../../habits/widgets/add_habit_sheet.dart';
import '../notifiers/rooms_notifier.dart' show suggestExistingMatch;
import '../../../shared/widgets/app_snackbar.dart';

/// Bottom sheet: pick exactly one of this account's own habits, excluding
/// [excludeIds] (already linked elsewhere relevant to the caller) - the
/// single-select counterpart to CreateRoomSheet's/JoinRoomSheet's own
/// multi-select checklists (_PlanHabitPicker/_OwnHabitMultiField), reused by
/// both a leader adding one habit to a shared room's plan (see
/// RoomDetailScreen's app-bar "Add a habit", RoomsController.addSharedHabit)
/// and any participant adding one more of their own habits to an
/// 'own'-mode room's tracking (see _MyPlanCard's "Add another habit",
/// RoomsController.addMyLinkedHabit). A single tap on an existing habit
/// picks and closes - there's nothing to confirm afterward, unlike the
/// multi-select checklists this deliberately isn't one of. The persistent
/// "Create a new habit" row at the top is the exception: it opens the same
/// full habit-creation screen used everywhere else in the app, and once
/// that's saved, this sheet closes with the freshly created habit exactly
/// as if it had been picked from the list - no dead end for someone whose
/// existing habits don't cover what this room needs.
///
/// [isSharedTemplate] shows a short note under the create option: whatever
/// gets created here becomes the [RoomHabitTemplate] every other
/// participant in a shared-mode room is later offered to link or clone
/// (see RoomsController.addSharedHabit) - not relevant, and left off, for
/// the 'own'-mode self-serve call site, where there's no shared plan for
/// anyone else to inherit.
///
/// Returns the picked (or newly created) habit, or null if dismissed
/// without picking.
Future<IslamicHabitTemplate?> pickOwnHabitSheet(
  BuildContext context, {
  required String title,
  required String hint,
  List<String> excludeIds = const [],
  bool isSharedTemplate = false,
}) {
  HapticFeedback.selectionClick();
  return showModalBottomSheet<IslamicHabitTemplate>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    useSafeArea: true,
    builder: (_) => _PickOwnHabitSheet(
      title: title,
      hint: hint,
      excludeIds: excludeIds,
      isSharedTemplate: isSharedTemplate,
    ),
  );
}

class _PickOwnHabitSheet extends ConsumerWidget {
  final String title;
  final String hint;
  final List<String> excludeIds;
  final bool isSharedTemplate;
  const _PickOwnHabitSheet({
    required this.title,
    required this.hint,
    required this.excludeIds,
    required this.isSharedTemplate,
  });

  /// Opens the ordinary habit-creation screen (standalone, not the tabbed
  /// hub with the Islamic catalog/Plans browse - a room already knows
  /// exactly what it needs one specific new habit for, so the catalog-
  /// browsing/multi-habit-bundle tabs there would be a detour, not a
  /// shortcut). On a successful create, nudges - doesn't block - if the
  /// new name looks like one of this account's other habits (excluding
  /// itself), same fuzzy match already used to suggest a likely existing
  /// habit when resolving a newly added shared-plan slot, then closes this
  /// whole sheet with the created habit.
  Future<void> _createNew(BuildContext context, WidgetRef ref) async {
    HapticFeedback.selectionClick();
    final created = await showModalBottomSheet<IslamicHabitTemplate>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (_) => const AddHabitSheet(),
    );
    if (created == null || !context.mounted) return;
    final others =
        ref.read(habitListProvider).where((h) => h.id != created.id).toList();
    final match = suggestExistingMatch(created.name, others);
    if (match != null && context.mounted) {
      ScaffoldMessenger.of(context).showOne(
        SnackBar(
          content: Text(S.of(context).roomPossibleDuplicateWarning(match.name)),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        ),
      );
    }
    if (!context.mounted) return;
    Navigator.of(context).pop(created);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final habits = ref
        .watch(habitListProvider)
        .where((h) => !excludeIds.contains(h.id))
        .toList();

    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
      decoration: BoxDecoration(
        color: gp.surfaceHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: gp.border, width: 0.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 4),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: gp.border, borderRadius: BorderRadius.circular(2)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
            child: Text(title,
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800, color: gp.textPrimary)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(hint,
                style: TextStyle(fontSize: 12, color: gp.textSec, height: 1.35)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => _createNew(context, ref),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      color: GameColors.gold.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: GameColors.gold.withOpacity(0.4)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.add_circle_rounded,
                            size: 18, color: GameColors.gold),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(s.roomCreateNewHabitAction,
                              style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: GameColors.gold)),
                        ),
                      ],
                    ),
                  ),
                ),
                if (isSharedTemplate) ...[
                  const SizedBox(height: 6),
                  Text(s.roomCreateNewHabitSharedNote,
                      style: TextStyle(fontSize: 11, color: gp.textSec, height: 1.3)),
                ],
              ],
            ),
          ),
          Flexible(
            child: habits.isEmpty
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: gp.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: gp.border, width: 0.5),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline_rounded,
                              size: 16, color: gp.textTert),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(s.roomNoMoreHabitsToAdd,
                                style:
                                    TextStyle(fontSize: 12.5, color: gp.textSec)),
                          ),
                        ],
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                    child: Container(
                      decoration: BoxDecoration(
                        color: gp.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: gp.border, width: 0.5),
                      ),
                      child: Column(
                        children: [
                          for (var i = 0; i < habits.length; i++) ...[
                            if (i != 0) Divider(height: 1, color: gp.border),
                            InkWell(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                Navigator.of(context).pop(habits[i]);
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 14),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(habits[i].name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.w600,
                                              color: gp.textPrimary)),
                                    ),
                                    Icon(Icons.chevron_right_rounded,
                                        size: 18, color: gp.textTert),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

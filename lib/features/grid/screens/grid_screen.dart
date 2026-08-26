import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/extensions/datetime_ext.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../../core/providers/app_guide_provider.dart';
import '../../onboarding/notifiers/guide_chain.dart';
import '../../../core/providers/home_tab_provider.dart';
import '../../../shared/widgets/category_icon.dart';
import '../../../shared/widgets/coach_mark_overlay.dart';
import '../../../shared/widgets/comeback_card.dart';
import '../../../shared/widgets/get_started_checklist_card.dart';
import '../../../shared/widgets/safe_wrap_text.dart';
import '../../../shared/widgets/week_picker_sheet.dart';
import '../../../shared/widgets/victory_burst.dart';
import '../../dashboard/notifiers/dashboard_notifier.dart';
import '../../dashboard/widgets/reaction_overlays.dart';
import '../../habits/catalog/habit_plans.dart';
import '../../habits/catalog/islamic_habit_catalog.dart';
import '../../habits/widgets/habit_actions_sheet.dart';
import '../../habits/models/habit_model.dart';
import '../../habits/notifiers/custom_habits_notifier.dart';
import '../../habits/notifiers/habit_resume_notifier.dart';
import '../../habits/widgets/pause_until_sheet.dart';
import '../../habits/models/weekly_quota_plan.dart';
import '../../habits/widgets/add_habit_hub_sheet.dart';
import '../../habits/widgets/add_habit_sheet.dart';
import '../../rooms/notifiers/rooms_notifier.dart';
import '../../../shared/widgets/habit_limit_gate.dart';
import '../../premium/notifiers/premium_notifier.dart';
import '../../../shared/widgets/history_demo_gate.dart';
import '../models/square_state.dart';
import '../notifiers/weekly_grid_notifier.dart';
import '../widgets/daily_quote_line.dart';

// This screen used to be one ~2,160-line file. It's now split by UI concern
// across this file plus four `part` files below — `part`/`part of` (not
// separate libraries with their own imports) specifically so every widget
// class that moves keeps sharing this file's exact single import list, with
// zero risk of a moved chunk silently missing an import (something there's
// no compiler in the loop here to catch). Nothing that imports GridScreen
// itself needed to change: every class moved into a part file was already
// private (leading underscore), so nothing outside this file could
// reference it before or after this split — GridScreen/categoryVisual below
// are the only two things this file has ever exported.
part 'grid_screen_summary.dart'; // _SelectionBar, _GridHeader, _NavArrow, _SummaryCard, _RingStat, _MiniStat
part 'grid_screen_table.dart'; // _GridTable/_GridTableState (the interactive board + tap/reward handlers), _BoostBadge, _SquareCell
part 'grid_screen_cell_editor.dart'; // _CellEditorSheet/_CellEditorSheetState (long-press palette + note editor), _PaletteSwatch
part 'grid_screen_misc.dart'; // _GridSkeleton, _GridSectionHeader, _GridEmptyState

/// Themed tint color for a habit row's category chip. The IconData half of
/// this tuple is legacy — actual rendering goes through [CategoryIcon],
/// which prefers the custom glyph art and only falls back to a Material
/// icon for categories without custom art. Kept here since callers still
/// destructure the color.
// Must agree with HabitCategory's own icon/localizedName/toJson grouping
// (habit_model.dart) - faith/quran/athkar/fasting/sadaqah are all "Faith"
// there (fasting and sadaqah are still acts of worship, not a Focus or
// Money habit just because one involves self-restraint and the other
// involves giving money). This function used to split fasting into the
// Focus group and sadaqah into the Money group, so a Sadaqah habit's Grid
// row/cell-editor color (fed straight into CategoryIcon - see
// grid_screen_table.dart/grid_screen_cell_editor.dart) read as the same
// amber "Money" color as a savings habit, which is exactly backwards for
// an Islamic-habits app treating charity as worship, not budgeting.
(IconData, Color) categoryVisual(HabitCategory category) => switch (category) {
      // Kept in lockstep with HabitCategory.icon — see the comment there for
      // why faith, fasting and health each earned their own glyph. Colors
      // deliberately unchanged: the split is about telling habits apart at a
      // glance, not about repainting the palette, and faith/quran/athkar
      // sharing emerald is what keeps them reading as one family.
      HabitCategory.faith => (Icons.mosque_rounded, GameColors.emerald),
      HabitCategory.fasting => (Icons.no_food_rounded, GameColors.emerald),
      HabitCategory.quran ||
      HabitCategory.athkar ||
      HabitCategory.sadaqah =>
        (Icons.menu_book_rounded, GameColors.emerald),
      HabitCategory.health =>
        (Icons.favorite_rounded, GameColors.iconStreak),
      HabitCategory.fitness =>
        (Icons.fitness_center_rounded, GameColors.iconStreak),
      HabitCategory.learning => (Icons.school_rounded, GameColors.iconXp),
      HabitCategory.focus =>
        (Icons.center_focus_strong_rounded, GameColors.iconXp),
      HabitCategory.money => (Icons.savings_rounded, GameColors.warning),
      HabitCategory.mind => (Icons.psychology_rounded, GameColors.rarityEpic),
      HabitCategory.social => (Icons.groups_rounded, GameColors.gold),
      // Own fixed color (see GameColors.iconSleep's doc comment) instead of
      // reusing rarityEpic, which Mind already sits on - the two used to
      // be visually identical apart from icon shape.
      HabitCategory.sleep => (Icons.bedtime_rounded, GameColors.iconSleep),
      HabitCategory.custom => (Icons.star_rounded, GameColors.gold),
    };

/// The Weekly Victory Grid — the flagship "color your life" experience.
///
/// Rows are habits, columns are the seven days of the week (Sat → Fri).
/// Tapping a square cycles white → yellow → green → white; a long-press opens
/// the full palette plus a daily reflection note. Long-pressing a habit's
/// *name* instead starts multi-select (mirrors Matrix's task selection), so
/// several habits can be checked off and removed together in one action.
class GridScreen extends ConsumerStatefulWidget {
  const GridScreen({super.key});

  @override
  ConsumerState<GridScreen> createState() => _GridScreenState();
}

class _GridScreenState extends ConsumerState<GridScreen> {
  final Set<String> _selectedIds = {};
  // App Guide's own coach-marks (see CoachMarkOverlay near the
  // bottom of build()) — _addHabitKey lives on whichever of the FAB /
  // empty-state button is actually mounted (only one ever is), _todayCellKey
  // on today's own square in row 0 of whichever _GridTable is displayed
  // first (see _GridTable.todayCellKey's doc comment for why a single
  // square, not the whole row).
  final GlobalKey _addHabitKey = GlobalKey();
  final GlobalKey _todayCellKey = GlobalKey();

  /// Selection mode entered from the header with nothing selected yet.
  /// Without this, "selection mode" could only mean "something is already
  /// selected", so an explicit Select control had no state to turn on.
  bool _selectionArmed = false;

  bool get _selectionMode => _selectionArmed || _selectedIds.isNotEmpty;

  void _armSelection() {
    setState(() => _selectionArmed = true);
  }

  void _toggleSelection(String id) {
    setState(() {
      if (!_selectedIds.remove(id)) _selectedIds.add(id);
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedIds.clear();
      _selectionArmed = false;
    });
  }

  /// Custom habits are archived (CustomHabitsNotifier.archive); preset
  /// habits are deactivated (ActiveCatalogNotifier.toggle) — same split
  /// Today's own single-habit delete and Grid's old action sheet used.
  /// Neither one is a hard delete any more: both leave the habit's real
  /// history (name, schedule, past completions) intact for the Heatmap
  /// and Insights, they just stop showing up as active starting now. See
  /// IslamicHabitTemplate.archivedAt. Either way, anything still counted
  /// toward an open room gets unlinked from it as part of the same action
  /// (see RoomsController.unlinkHabitEverywhere) - with a heads-up dialog
  /// first if that applies to any of the selection, so a multi-select
  /// sweep never quietly breaks a room in the background.
  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) return;
    // Belt and braces on top of the row itself refusing selection while
    // paused (see _GridTable's label GestureDetector): removing a habit
    // that is already off the board runs toggle() on an inactive preset,
    // which re-activates it — the exact opposite of what the button says,
    // and it would slip past the habit cap on the way.
    final pausedIds = {
      for (final h in ref.read(habitsArchivedTodayProvider)) h.id,
    };
    _selectedIds.removeWhere(pausedIds.contains);
    if (_selectedIds.isEmpty) return;
    final linked = ref.read(myLinkedRoomHabitsProvider);
    final affectedRoomNames = <String>{
      for (final id in _selectedIds)
        for (final room in linked[id] ?? const []) room.name,
    };
    if (affectedRoomNames.isNotEmpty) {
      final s = S.of(context);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(s.habitLinkedRoomWarningTitle),
          content: Text(
              s.habitLinkedRoomWarningBody(affectedRoomNames.toList())),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(s.habitDeleteLinkedRoomCancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: GameColors.error),
              child: Text(s.habitDeleteAnywayAction),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    HapticFeedback.mediumImpact();
    final count = _selectedIds.length;
    // Captured before _clearSelection/the loop below triggers rebuilds —
    // this Scaffold's messenger stays valid regardless.
    final messenger = ScaffoldMessenger.of(context);
    final s = S.of(context);
    final rooms = ref.read(roomsControllerProvider);
    final totalCompletions = ref.read(dashboardProvider).habitTotalCompletions;
    // Captured before the loop clears the selection - Undo below needs to
    // know exactly which habits went, and which kind each one was.
    final removed = <({String id, bool isCatalog, bool everCompleted})>[];
    for (final id in _selectedIds) {
      rooms.unlinkHabitEverywhere(id).ignore();
      final everCompleted = (totalCompletions[id] ?? 0) > 0;
      removed.add((
        id: id,
        isCatalog: IslamicHabitCatalog.findById(id) != null,
        everCompleted: everCompleted,
      ));
      // Catalog ids are a fixed, known set (IslamicHabitCatalog.templates —
      // same check add_habit_sheet/custom_habits_notifier already rely on
      // elsewhere), so this is correct regardless of whether a custom
      // habit is currently active or already soft-archived. The previous
      // `customHabitsProvider`-membership check only ever saw *active*
      // custom habits — an already-archived one (e.g. still showing today
      // via habitsArchivedTodayProvider after an earlier delete) would
      // silently fall through to the catalog branch below and hand its
      // random custom-habit id to ActiveCatalogNotifier.toggle() as if it
      // were a real catalog id.
      if (IslamicHabitCatalog.findById(id) == null) {
        ref
            .read(customHabitsProvider.notifier)
            .archive(id, everCompleted: everCompleted);
      } else {
        ref
            .read(activeCatalogProvider.notifier)
            .toggle(id, everCompleted: everCompleted);
      }
    }
    _clearSelection();
    // ── Undo ────────────────────────────────────────────────────────────
    // Deleting a habit had no way back, while deleting a mere task did. The
    // data was never actually lost (archive keeps the whole template so the
    // Heatmap and Insights stay honest) - there was simply nothing anywhere
    // that could put it back, so a habit someone had built themselves, with
    // their own name, cue, frequency and reminder, ended one tap from gone.
    // The confirmation even said "Removed from your list", quietly reassuring
    // about stats while saying nothing about the habit.
    //
    // A habit that was never completed is hard-deleted rather than archived
    // (see CustomHabitsNotifier.archive's everCompleted), so there is nothing
    // to restore for those and Undo is only offered when at least one of the
    // removed habits can actually come back.
    final restorable =
        removed.where((r) => r.isCatalog || r.everCompleted).toList();
    // Same reason as _pauseHabit's: an Undo that is still on screen for a
    // batch the user has already moved past is worse than no Undo.
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          count == 1
              ? s.habitArchivedConfirmation
              : s.habitsArchivedConfirmation(count),
        ),
        duration: const Duration(seconds: 6),
        // Floating + swipe-down-to-dismiss, so it behaves the way a snackbar
        // does in every other app: it can be pushed out of the way instead of
        // being sat through. It was neither before — a fixed snackbar with the
        // default horizontal dismiss, which on a screen whose whole surface is
        // a tappable board meant six seconds of a banner you could not get rid
        // of. Six seconds stays (Undo needs a moment to be noticed and
        // reached); what changed is that waiting is no longer the only option.
        behavior: SnackBarBehavior.floating,
        dismissDirection: DismissDirection.down,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        action: restorable.isEmpty
            ? null
            : SnackBarAction(
                label: s.undo,
                onPressed: () {
                  HapticFeedback.lightImpact();
                  for (final r in restorable) {
                    if (r.isCatalog) {
                      // Toggling a catalog id back on re-activates it and
                      // clears its archive date - the same path Plans uses.
                      // Only while it is genuinely still off, though:
                      // toggle() is a toggle, and this button lives for six
                      // seconds, long enough to put one of these habits back
                      // by hand first. Undo would then switch that one off
                      // again, which is not undoing anything. Same guard the
                      // single-habit pause Undo carries.
                      if (!ref.read(activeCatalogProvider).contains(r.id)) {
                        ref.read(activeCatalogProvider.notifier).toggle(r.id);
                      }
                    } else {
                      ref.read(customHabitsProvider.notifier).unarchive(r.id);
                    }
                  }
                },
              ),
      ),
    );
  }

  /// Resolves a long-pressed id to its template before opening the menu.
  /// Reads the same combined list the board renders (active plus habits
  /// paused earlier today, which stay visible until the day is over), so
  /// a long-press can never miss a row the user can actually see.
  void _onHabitLongPress(String id) {
    final all = [
      ...ref.read(habitListProvider),
      ...ref.read(habitsArchivedTodayProvider),
    ];
    final match = all.where((h) => h.id == id).toList();
    if (match.isEmpty) return;
    _showHabitActions(match.first);
  }

  /// Long-press on one habit: edit, pause, or delete forever.
  ///
  /// Replaces long-press-starts-multi-select. Pause routes to the same
  /// archive path the old "remove" used (history preserved, id preserved,
  /// resumable from Add Habit), which is what that button always did —
  /// it just never said so and never offered a way back.
  Future<void> _showHabitActions(IslamicHabitTemplate habit) async {
    final isCatalog = IslamicHabitCatalog.findById(habit.id) != null;
    final name = habit.localName(S.of(context).isAr);
    // Only ever true for a habit paused earlier today, whose row stays on
    // the board for the rest of the day — see showHabitActions's isPaused.
    final isPaused = habit.archivedAt != null;
    final action = await showHabitActions(
      context,
      habitName: name,
      canDeleteForever: !isCatalog,
      isPaused: isPaused,
    );
    if (action == null || !mounted) return;
    switch (action) {
      case HabitAction.edit:
        _editSelected(habit);
      case HabitAction.pause:
        await _pauseHabit(habit, isCatalog: isCatalog, name: name);
      case HabitAction.resume:
        _resumeHabit(habit, isCatalog: isCatalog, name: name);
      case HabitAction.deleteForever:
        if (!await _confirmRoomImpact(habit.id, pausing: false)) return;
        if (!mounted) return;
        final ok = await confirmDeleteForever(context, habitName: name);
        if (!ok || !mounted) return;
        HapticFeedback.mediumImpact();
        // Unlink first, same as every other permanent removal path (see
        // _deleteSelected). A room left pointing at a habit that no longer
        // exists doesn't over-credit — syncLinkedHabitsProgress bails on an
        // unresolvable id — it does something quieter and worse: that
        // member's WHOLE room stops syncing, every other linked habit
        // included, until someone notices the hint on Room Detail.
        ref.read(roomsControllerProvider).unlinkHabitEverywhere(habit.id).ignore();
        ref.read(customHabitsProvider.notifier).deleteForever(habit.id);
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text(S.of(context).habitDeletedConfirmation(name)),
              behavior: SnackBarBehavior.floating,
              dismissDirection: DismissDirection.down,
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            ),
          );
    }
  }

  /// Heads-up dialog for the rooms a habit is counted in, before an action
  /// that takes it off the board. Returns false if the person backs out.
  ///
  /// The same dialog _deleteSelected shows, for the same reason: a room
  /// pointing at a habit this device can no longer resolve does not
  /// over-credit (syncLinkedHabitsProgress returns early on an
  /// unresolvable linked id) — it stops that member's room syncing
  /// entirely, every other linked habit in it included. Unlinking the one
  /// habit is strictly better for them than freezing the whole room, but
  /// it is not reversible, so it is never done silently.
  Future<bool> _confirmRoomImpact(String habitId, {required bool pausing}) async {
    final rooms = ref.read(myLinkedRoomHabitsProvider)[habitId] ?? const [];
    final roomNames = <String>{
      // Pausing only affects a room that is actually running: a lobby
      // room has not started grading anyone yet, and an ended one is a
      // finished record that today's absence cannot change. Delete
      // forever still names them all, because unlinking really does
      // reach every room.
      for (final room in rooms)
        if (!pausing || room.isLive) room.name,
    };
    if (roomNames.isEmpty) return true;
    final s = S.of(context);
    final names = roomNames.toList();
    // Rooms where this habit is the member's ONLY counted one get a
    // different sentence, because the reassurance the normal one gives is
    // false there: with nothing else linked there is no "rest of your
    // habits" to be graded on, and every paused day scores zero. See
    // mySoleRoomHabitsProvider.
    final soleNames = <String>{
      for (final room in ref.read(mySoleRoomHabitsProvider)[habitId] ?? const [])
        if (!pausing || room.isLive) room.name,
    }.toList();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(s.habitLinkedRoomWarningTitle),
        content: Text(pausing
            ? (soleNames.isNotEmpty
                ? s.habitPauseSoleRoomHabitBody(soleNames)
                : s.habitPauseLinkedRoomBody(names))
            : s.habitLinkedRoomWarningBody(names)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.habitDeleteLinkedRoomCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            // Red is for the one that cannot be taken back. Pause can.
            style: pausing
                ? null
                : TextButton.styleFrom(foregroundColor: GameColors.error),
            child: Text(pausing
                ? s.habitPauseAnywayAction
                : s.habitDeleteAnywayAction),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  /// Puts a paused habit back on the board, from the long-press menu on a
  /// row paused earlier today.
  ///
  /// Gated on the habit cap: resuming adds to the active list exactly like
  /// adding does, so without this a free account at its limit could pause
  /// habits, add replacements, then resume the old ones and sit above the
  /// cap indefinitely.
  void _resumeHabit(
    IslamicHabitTemplate habit, {
    required bool isCatalog,
    required String name,
  }) {
    if (!canAddHabits(ref)) {
      showHabitLimitGate(context, ref);
      return;
    }
    HapticFeedback.lightImpact();
    if (isCatalog) {
      ref.read(activeCatalogProvider.notifier).toggle(habit.id);
    } else {
      ref.read(customHabitsProvider.notifier).unarchive(habit.id);
    }
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(S.of(context).habitResumedConfirmation(name)),
          behavior: SnackBarBehavior.floating,
          dismissDirection: DismissDirection.down,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        ),
      );
  }

  /// Pauses one habit, with Undo. Same archive call the multi-select
  /// remove makes, so a preset switches off and a custom habit soft-
  /// archives, both keeping every recorded day. The one difference is
  /// eraseIfEmpty below: remove may hard-delete a habit that was never
  /// completed, pause never does.
  Future<void> _pauseHabit(
    IslamicHabitTemplate habit, {
    required bool isCatalog,
    required String name,
  }) async {
    // Rooms get a heads-up, but NOT an unlink. Unlinking was tried first,
    // to spare the member the daily hit below, and it is the wrong trade
    // for an action whose whole promise is that it can be taken back:
    // RoomsController.unlinkHabitEverywhere walks every code in
    // users/{uid}.roomCodes, so it reaches rooms whose competition ended
    // months ago; it decides shared-slot preservation from an in-memory
    // roomProvider read that is empty until those streams warm up; and
    // nothing puts the link back on Resume. Worst of all, the warning is
    // built from myLinkedRoomHabitsProvider, which is legitimately empty
    // on a cold start — so a pause moments after launch would unlink
    // silently, with no dialog at all.
    //
    // Leaving the link alone does NOT cost the member points while the habit
    // is away: a paused habit now leaves both sides of the sum (see
    // roomHasGradableHabit), so the member is graded on whatever else they
    // linked, and only a plan whose every habit is paused scores zero. Nothing
    // is permanent either: resuming brings the habit back and the next full
    // resync regrades the last kRoomSyncWindowDays. The dialog says exactly
    // that (habitPauseLinkedRoomBody / habitPauseSoleRoomHabitBody).
    if (!await _confirmRoomImpact(habit.id, pausing: true)) return;
    if (!mounted) return;
    // "لي متى؟" — asked before anything is archived, so backing out here
    // leaves the habit exactly where it was. The default answer is the
    // manual pause this flow has always done, so confirming straight
    // through costs one tap and changes nothing.
    final until = await showPauseUntilSheet(context, habitName: name);
    if (!until.confirmed || !mounted) return;
    final s = S.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final everCompleted =
        (ref.read(dashboardProvider).habitTotalCompletions[habit.id] ?? 0) > 0;
    HapticFeedback.mediumImpact();
    // eraseIfEmpty: false — Pause never destroys, not even a habit that
    // was never completed. The sheet's own hint promises the record is
    // kept and the habit comes back whenever you want; the remove path
    // keeps the old hard-delete, because "remove" promises the opposite.
    if (isCatalog) {
      ref.read(activeCatalogProvider.notifier).toggle(
            habit.id,
            everCompleted: everCompleted,
            eraseIfEmpty: false,
          );
    } else {
      ref.read(customHabitsProvider.notifier).archive(
            habit.id,
            everCompleted: everCompleted,
            eraseIfEmpty: false,
          );
    }
    // Newest action wins. SnackBars QUEUE by default, and each of these
    // lives 6 seconds with its own Undo, so pausing three habits in a row
    // left the third one's confirmation sitting behind two stale ones:
    // for the next 12 seconds the board said "X paused" about a habit
    // that was paused two taps ago, offering an Undo for it. Clearing
    // first means the visible confirmation always describes what just
    // happened.
    // Written after the archive lands, and unconditionally: passing null
    // for a manual pause CLEARS any date left over from a previous pause of
    // the same habit, which would otherwise still be armed and resume it
    // out of nowhere weeks later.
    ref.read(habitResumeScheduleProvider.notifier).schedule(habit.id, until.at)
        .ignore();
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(until.at == null
            ? s.habitPausedConfirmation(name)
            : '${s.habitPausedConfirmation(name)} · '
                '${s.resumesOnBadge(formatResumeDate(until.at!, s.isAr, withTime: until.withTime))}'),
        duration: const Duration(seconds: 6),
        behavior: SnackBarBehavior.floating,
        dismissDirection: DismissDirection.down,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        // Always offered. Pause passes eraseIfEmpty: false above, so there
        // is always something to put back — including a habit that had
        // never been completed, which the old rule silently destroyed and
        // then, correctly for that behavior, refused to offer an Undo for.
        action: SnackBarAction(
          label: s.undo,
          onPressed: () {
            HapticFeedback.lightImpact();
            // Undoing the pause undoes the booking with it, or a habit put
            // straight back on the board would still be carrying a return
            // date for a pause that no longer exists.
            ref
                .read(habitResumeScheduleProvider.notifier)
                .schedule(habit.id, null)
                .ignore();
            if (isCatalog) {
              // toggle() is a toggle, and this button sits on screen for
              // six seconds — long enough to Resume the same habit from
              // the Add Habit sheet first. Undo would then take an active
              // habit and pause it again, which is not undoing anything.
              // Only act while the habit is genuinely still paused.
              // unarchive() below is already a no-op on an active habit,
              // so the custom branch needs no equivalent.
              if (!ref.read(activeCatalogProvider).contains(habit.id)) {
                ref.read(activeCatalogProvider.notifier).toggle(habit.id);
              }
            } else {
              ref.read(customHabitsProvider.notifier).unarchive(habit.id);
            }
          },
        ),
      ),
    );
  }

  /// Opens the full edit sheet for one habit. Reached two ways now: the
  /// Edit row of the long-press actions menu, and the toolbar button that
  /// appears when exactly one editable habit is selected. Preset habits
  /// aren't editable here either way, matching Today's own onEdit gating.
  void _editSelected(IslamicHabitTemplate habit) {
    HapticFeedback.lightImpact();
    _clearSelection();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // Matches showAddHabitHub's config exactly (add_habit_hub_sheet.dart)
      // — see dashboard_screen.dart's _showEditHabit for why this matters:
      // without it, this sheet's own maxHeight math (add_habit_sheet.dart)
      // sizes against the full screen height instead of the safe-area-
      // trimmed one, landing the footer button in a different spot than
      // the same sheet opened via Add Habit.
      useSafeArea: true,
      builder: (_) => AddHabitSheet(existing: habit),
    );
  }

  @override
  Widget build(BuildContext context) {
    registerDashboardReactions(context, ref);

    final gp = context.gp;
    final s = S.of(context);
    // Today's archived habits ride along here purely for display — a
    // habit deleted moments ago shouldn't vanish from Grid before the day
    // that deleted it is even over. See habitsArchivedTodayProvider's doc
    // comment for why this stays a separate provider instead of folding
    // into habitListProvider itself.
    final habits = [
      ...ref.watch(habitListProvider),
      ...ref.watch(habitsArchivedTodayProvider),
    ];
    final grid = ref.watch(weeklyGridProvider);
    final activeLesson = ref.watch(activeAppGuideLessonProvider);

    // Auto-dismiss App Guide's coach-mark the instant its real goal is
    // actually met, regardless of exactly how — tapping through the
    // circled FAB is the expected path, but nothing stops someone from
    // adding a habit some other way (Today's own Add Habit, say) while
    // this lesson happens to still be active. Without this, the circle
    // would keep pointing at a FAB that already did its job.
    ref.listen<List<IslamicHabitTemplate>>(habitListProvider, (previous, next) {
      if ((previous?.isEmpty ?? true) &&
          next.isNotEmpty &&
          ref.read(activeAppGuideLessonProvider) == AppGuideLesson.addHabit) {
        // advanceGuideAfter, not `= null`. Clearing was the whole reason the
        // guide stopped after one step: the circle vanished and nothing said
        // there were three more. This hands over to "colour today's square",
        // which lives on this same screen and is now, finally, a row that
        // exists to point at. See guide_chain.dart for why continuing a run
        // is not the same thing as starting one.
        advanceGuideAfter(ref, AppGuideLesson.addHabit);
      }
    });
    ref.listen<DashboardState>(dashboardProvider, (previous, next) {
      if ((previous?.cumulativeXp ?? 0) <= 0 &&
          next.cumulativeXp > 0 &&
          ref.read(activeAppGuideLessonProvider) == AppGuideLesson.colorSquare) {
        // Stops here rather than jumping to the Tasks tab: the next step
        // lives on another screen, and moving somebody there because they
        // finished something is the uninvited tour again. The Get Started
        // card is on that screen too, already showing step 3.
        advanceGuideAfter(ref, AppGuideLesson.colorSquare);
      }
    });

    // Build habits and quit habits render as two separate boards — coloring
    // a square means opposite things across the two ("I did it" vs "I
    // stayed away from it"), so mixing them in one table made the eye do
    // that translation row by row. Split lists, same row widgets. When one
    // list is empty the split (and its headers) disappears entirely, so
    // anyone not using quit habits sees exactly the single board they
    // always had.
    final buildHabits = [
      for (final h in habits)
        if (h.goalType != GoalType.quit) h,
    ];
    final quitHabits = [
      for (final h in habits)
        if (h.goalType == GoalType.quit) h,
    ];
    final showSplit = buildHabits.isNotEmpty && quitHabits.isNotEmpty;

    // Presets are editable too now. This used to require the id to be in
    // customHabitsProvider, which meant a catalog habit had no edit button
    // anywhere in the app: activate صلاة الضحى from a Plan and its reminder
    // and frequency were fixed forever, with deleting and rebuilding it as a
    // custom habit - losing its history and room links - the only way round.
    // Their edits are stored as an override against the catalog id (see
    // CatalogHabitOverride), so the habit keeps its id and its whole past.
    IslamicHabitTemplate? singleEditableSelection;
    if (_selectedIds.length == 1) {
      final id = _selectedIds.first;
      for (final h in habits) {
        if (h.id == id) {
          singleEditableSelection = h;
          break;
        }
      }
    }

    return Scaffold(
      backgroundColor: gp.bg,
      // No nav bar here anymore — HomeShell (the swipeable 3-tab PageView
      // this screen now always lives inside) owns the single GameNavBar.
      body: Stack(
        children: [
        SafeArea(
        bottom: false,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics()),
          slivers: [
            SliverToBoxAdapter(
              child: _GridHeader(
                onStartSelection:
                    habits.isEmpty || _selectionMode ? null : _armSelection,
                state: grid,
                // Mirrors the old FAB's own condition exactly: while there
                // are no habits, _GridEmptyState below owns _addHabitKey and
                // renders the bigger pair of buttons instead.
                showAddAction: habits.isNotEmpty,
                addHabitKey: habits.isNotEmpty ? _addHabitKey : null,
              ),
            ),
            // "You're back" — renders itself away unless there's actually a
            // comeback to acknowledge. It used to sit on the Today screen,
            // which nothing in the app could navigate to, so the one moment
            // built to welcome someone back was the one moment they had to
            // arrive via a notification to ever see.
            SliverToBoxAdapter(
              child: ComebackCard(state: ref.watch(dashboardProvider)),
            ),
            SliverToBoxAdapter(
              child: GetStartedChecklistCard(
                onAddHabit: () =>
                    showAddHabitHub(context, ref, initialTab: HubTab.plans),
                // Matrix's own screen owns the actual "add a task" action
                // (see matrix_screen.dart's _showAdd) - from here, the
                // right move is just getting there. See
                // requestedHomeTabProvider's doc comment.
                onAddTask: () =>
                    ref.read(requestedHomeTabProvider.notifier).state = 2,
              ),
            ),
            // The day's line. Below the two cards above rather than above
            // them, because both of those self-hide when they have nothing to
            // say: on an ordinary day this sits directly under the header, and
            // on a day that has a comeback or an unfinished checklist it stays
            // out of their way instead of pushing them down the screen.
            const SliverToBoxAdapter(child: DailyQuoteLine()),
            if (_selectionMode)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: _SelectionBar(
                    count: _selectedIds.length,
                    onClear: _clearSelection,
                    onDelete: _deleteSelected,
                    onEdit: singleEditableSelection == null
                        ? null
                        : () => _editSelected(singleEditableSelection!),
                  ),
                ),
              ),
            // Loading is checked before "empty" - without it, a returning
            // user with a real habit list would see "no habits yet, add
            // one!" flash for however long CustomHabitsNotifier/
            // ActiveCatalogNotifier's own first read takes, right before
            // their actual list pops in and replaces it. See
            // habitsStillLoadingProvider's own doc comment.
            if (habits.isEmpty && ref.watch(habitsStillLoadingProvider))
              // Not `const` — GameColors.gold is a mutable `static Color`
              // (theme-preset system), not a compile-time constant. See
              // BUILD_LESSONS.md #6.
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: CircularProgressIndicator(
                      color: GameColors.gold, strokeWidth: 2),
                ),
              )
            else if (habits.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _GridEmptyState(addButtonKey: _addHabitKey),
              )
            else ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: _SummaryCard(habits: habits, state: grid)
                      .animate()
                      .fadeIn(duration: 400.ms)
                      .slideY(begin: -0.05, curve: Curves.easeOut),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  // Keyed on the visible week so navigating weeks slides the
                  // whole board in, rather than snapping cell colors.
                  child: AnimatedSwitcher(
                    duration: GameMotion.relaxed,
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween(
                          begin: const Offset(0.04, 0),
                          end: Offset.zero,
                        ).animate(anim),
                        child: child,
                      ),
                    ),
                    child: grid.isLoading
                        ? const _GridSkeleton()
                        : KeyedSubtree(
                            key: ValueKey(grid.weekStart),
                            child: !showSplit
                                ? _GridTable(
                                    habits: habits,
                                    state: grid,
                                    selectionMode: _selectionMode,
                                    selectedIds: _selectedIds,
                                    onSelectionToggle: _toggleSelection,
                                    onHabitLongPress: _onHabitLongPress,
                                    todayCellKey: _todayCellKey,
                                  )
                                : Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      _GridSectionHeader(
                                        icon: Icons.bolt_rounded,
                                        color: GameColors.gold,
                                        label: s.gridSectionBuild,
                                        count: buildHabits.length,
                                      ),
                                      _GridTable(
                                        habits: buildHabits,
                                        state: grid,
                                        selectionMode: _selectionMode,
                                        selectedIds: _selectedIds,
                                        onSelectionToggle: _toggleSelection,
                                        onHabitLongPress: _onHabitLongPress,
                                        todayCellKey: _todayCellKey,
                                      ),
                                      const SizedBox(height: 18),
                                      // Shield + emerald, matching the quit
                                      // pill's own visual language on
                                      // HabitCard — the same "staying clean"
                                      // identity everywhere it appears.
                                      _GridSectionHeader(
                                        icon: Icons.shield_rounded,
                                        color: GameColors.emerald,
                                        label: s.gridSectionQuit,
                                        count: quitHabits.length,
                                      ),
                                      _GridTable(
                                        habits: quitHabits,
                                        state: grid,
                                        selectionMode: _selectionMode,
                                        selectedIds: _selectedIds,
                                        onSelectionToggle: _toggleSelection,
                                        onHabitLongPress: _onHabitLongPress,
                                      ),
                                    ],
                                  ),
                          ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                  child: Text(
                    s.gridSlogan,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontStyle: FontStyle.italic,
                      color: gp.textTert,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        ),
        ),
          // App Guide's on-demand "Add a habit" / "Track a day" lessons -
          // deliberately the only thing that ever dims this screen, and only
          // ever because the person just asked for it: from Settings, from the
          // Get Started card, or by answering yes to the first-run question
          // (see FirstRunOfferScreen). Nothing here is driven by a persisted
          // flag, so no launch can produce a dim on its own.
          //
          // The ValueKey is load-bearing. Both lessons render through this one
          // widget, so without it a lesson change reuses the same Element and
          // therefore the same State: the overlay keeps _didEnsureVisible true
          // and never scrolls the NEW target into view, and paints the old
          // target's rect until the next frame's measurement lands.
          if (activeLesson == AppGuideLesson.addHabit ||
              activeLesson == AppGuideLesson.colorSquare)
            CoachMarkOverlay(
              key: ValueKey(activeLesson),
              targetKey: activeLesson == AppGuideLesson.addHabit
                  ? _addHabitKey
                  : _todayCellKey,
              title: appGuideLessonCoachTitle(activeLesson!, s.isAr),
              body: appGuideLessonCoachBody(activeLesson, s.isAr),
              onDismiss: () =>
                  ref.read(activeAppGuideLessonProvider.notifier).state = null,
            ),
        ],
      ),
      // No floatingActionButton. Add-habit moved into the header row (see
      // _GridHeader's showAddAction) because a FAB floats *over* the board,
      // and on a habit list long enough to reach it the gold circle sat
      // exactly on top of a real, tappable square — reported from a device as
      // "the squares aren't in a straight line". The trailing
      // SliverToBoxAdapter spacer only clears the last item once you have
      // scrolled to the bottom; it does nothing mid-scroll, and nothing at
      // all for a cell in the middle of the board. A FAB over a list is
      // normal; over a grid where every cell is the interaction, it is not.
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/extensions/datetime_ext.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../../core/providers/app_guide_provider.dart';
import '../../../core/providers/home_tab_provider.dart';
import '../../../shared/widgets/category_icon.dart';
import '../../../shared/widgets/coach_mark_overlay.dart';
import '../../../shared/widgets/comeback_card.dart';
import '../../../shared/widgets/get_started_checklist_card.dart';
import '../../../shared/widgets/safe_wrap_text.dart';
import '../../../shared/widgets/victory_burst.dart';
import '../../dashboard/notifiers/dashboard_notifier.dart';
import '../../dashboard/widgets/reaction_overlays.dart';
import '../../habits/catalog/habit_plans.dart';
import '../../habits/catalog/islamic_habit_catalog.dart';
import '../../habits/models/habit_model.dart';
import '../../habits/notifiers/custom_habits_notifier.dart';
import '../../habits/widgets/add_habit_hub_sheet.dart';
import '../../habits/widgets/add_habit_sheet.dart';
import '../../rooms/notifiers/rooms_notifier.dart';
import '../models/square_state.dart';
import '../notifiers/weekly_grid_notifier.dart';

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
      HabitCategory.faith ||
      HabitCategory.quran ||
      HabitCategory.athkar ||
      HabitCategory.fasting ||
      HabitCategory.sadaqah =>
        (Icons.menu_book_rounded, GameColors.emerald),
      HabitCategory.health || HabitCategory.fitness =>
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

  bool get _selectionMode => _selectedIds.isNotEmpty;

  void _startSelection(String id) {
    setState(() => _selectedIds.add(id));
  }

  void _toggleSelection(String id) {
    setState(() {
      if (!_selectedIds.remove(id)) _selectedIds.add(id);
    });
  }

  void _clearSelection() {
    setState(_selectedIds.clear);
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
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          count == 1
              ? s.habitArchivedConfirmation
              : s.habitsArchivedConfirmation(count),
        ),
        duration: const Duration(seconds: 6),
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
                      ref.read(activeCatalogProvider.notifier).toggle(r.id);
                    } else {
                      ref.read(customHabitsProvider.notifier).unarchive(r.id);
                    }
                  }
                },
              ),
      ),
    );
  }

  /// Opens the full edit sheet for the single selected habit — kept so
  /// repurposing long-press for selection doesn't quietly remove Grid's
  /// only way to edit a custom habit's cue/frequency. Only ever offered
  /// for a single, custom selection; preset habits aren't editable here,
  /// matching Today's own onEdit gating.
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
        ref.read(activeAppGuideLessonProvider.notifier).state = null;
      }
    });
    ref.listen<DashboardState>(dashboardProvider, (previous, next) {
      if ((previous?.cumulativeXp ?? 0) <= 0 &&
          next.cumulativeXp > 0 &&
          ref.read(activeAppGuideLessonProvider) == AppGuideLesson.colorSquare) {
        ref.read(activeAppGuideLessonProvider.notifier).state = null;
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
            SliverToBoxAdapter(child: _GridHeader(state: grid)),
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
                                    onSelectionStart: _startSelection,
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
                                        onSelectionStart: _startSelection,
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
                                        onSelectionStart: _startSelection,
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
          // App Guide's on-demand "Add a habit" / "Track a day" lessons —
          // deliberately the only thing that ever dims this screen, and only
          // ever because the person just asked for it from Settings. First
          // run teaches through the Get Started checklist above instead: an
          // inline card that sits in the page and can be ignored, rather
          // than a modal overlay thrown at someone who has not acted yet.
          if (activeLesson == AppGuideLesson.addHabit ||
              activeLesson == AppGuideLesson.colorSquare)
            CoachMarkOverlay(
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
      // Today is the primary place to add/browse habits. Grid only needs a
      // secondary, smaller way back into the same Add Habit Hub for when
      // the grid isn't empty — the empty state's own "Browse Plans" button
      // covers the zero-habit case, so this single small icon FAB is
      // deliberately the *lesser* affordance, not a duplicate of Today's.
      floatingActionButton: habits.isEmpty
          ? null
          : FloatingActionButton.small(
              key: _addHabitKey,
              heroTag: 'grid-add',
              // Always opens on the normal Add Goal default, guided or not —
              // AddHabitHub itself now shows a one-time hint explaining the
              // Plans/Add Goal choice when reached via App Guide, so this
              // FAB doesn't need to pick a tab on its behalf.
              onPressed: () => showAddHabitHub(context, ref),
              // Solid gold fill instead of a neutral surface tone with just
              // a gold icon — the button itself is now the accent, not only
              // its glyph, so it reads as the one colorful, clearly-tappable
              // thing on the screen rather than blending into the same dark
              // neutral surfaces as everything around it.
              backgroundColor: GameColors.gold,
              foregroundColor: GameColors.onGold,
              elevation: 0,
              tooltip: s.addHabit,
              // Not `const` — GameColors.gold/onGold are mutable `static`
              // getters (theme-preset system), not compile-time constants.
              // See BUILD_LESSONS.md #6.
              child: Icon(Icons.add_rounded,
                  size: 20, color: GameColors.onGold),
            ).animate(delay: 500.ms).fadeIn().slideY(begin: 0.4),
    );
  }
}

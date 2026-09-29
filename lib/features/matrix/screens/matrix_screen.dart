import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/datetime_ext.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/app_guide_provider.dart';
import '../../../core/providers/day_clock_provider.dart'
    show dayClockSourceProvider;
import '../../../core/utils/western_digits.dart';
import '../../onboarding/notifiers/guide_chain.dart';
import '../../../core/providers/home_tab_provider.dart';
import '../../../core/providers/nav_layout_provider.dart' show NavTab;
import '../../../core/theme/game_theme.dart';
import '../../../shared/widgets/coach_mark_overlay.dart';
import '../../../shared/widgets/get_started_checklist_card.dart';
import '../models/matrix_task.dart';
import '../notifiers/matrix_notifier.dart';
import '../task_day.dart';
import '../widgets/add_task_sheet.dart';
import '../widgets/edit_quadrant_sheet.dart';
import '../widgets/quadrant_card.dart';
import '../widgets/task_detail_sheet.dart';
import '../widgets/task_month_sheet.dart'
    show showTaskMonthSheet, taskDayTitle;
import 'matrix_history_screen.dart';
import '../../../shared/widgets/app_snackbar.dart';

// Which day a task belongs to, which boards it shows on, and why it is the
// day the task is FOR rather than the day it was typed: task_day.dart. Every
// set on this screen (the day board, «مُرحّلة», «قادمة», the badge below)
// reads it, so none of them can file a task somewhere the others do not.

/// Today's still-open tasks: open, and their day ([taskDay]) is today. The
/// same set the day lens shows open on today's board, which is also where a
/// tap on the badge lands. Carried-over tasks are excluded on purpose, as
/// they are from that board: they have their own chip. The bottom bar's
/// Tasks badge (navBadgesProvider) shows this number.
///
/// A task created on Sunday for Tuesday 17:00 is counted on Tuesday, not
/// Sunday, and a task with a "2 days before" warning is not counted until
/// its own day; both were wrong while this counted by the day a task was
/// created and by its first reminder.
int matrixOpenTodayCount(Iterable<MatrixTask> tasks, DateTime now) =>
    openOnDayCount(tasks, now.startOfDay);

/// What a board row says under its title, or null to say nothing (and take
/// no height, see _AnimatedTaskStackState._rowHeightFor).
///
/// Only what the board around the row does not already say:
///  * [dayLens] (the row sits on its own day's board, which is the only day
///    an open task shows on there): the time, if it has one. The header
///    already names the day.
///  * Fav, All and the two chips mix days, so a task whose day is not
///    [today] shows its date («30 سبتمبر»), and its time after it when it
///    has one («30 سبتمبر · 4:30 م»). A task for today shows only its time.
///  * An untimed task on its own day, and every done task, say nothing: a
///    done row has nothing left to plan, and a line on every row would be
///    noise that hides the lines that matter.
///
/// The time is the moment the person picked (the anchor), never an early
/// warning, the same moment [taskDay] files the task by. Western digits,
/// through [westernDate]. The year is added only for another year's day.
/// One function, called once per row by the screen and handed down, so the
/// height the stack reserves and the line the tile draws never disagree.
@visibleForTesting
String? matrixRowMeta(
  MatrixTask t, {
  required bool dayLens,
  required DateTime today,
  required bool isAr,
}) {
  if (t.isDone) return null;
  final locale = isAr ? 'ar' : 'en';
  final anchor =
      MatrixTask.resolveAnchor(t.reminderAnchorAt, t.reminderAts)?.toLocal();
  final time = anchor == null ? null : westernDate(anchor, 'h:mm a', locale);
  final day = taskDay(t);
  if (dayLens || day.isSameDayAs(today)) return time;
  var date = westernDate(day, isAr ? 'd MMMM' : 'MMM d', locale);
  if (day.year != today.year) {
    date = isAr ? '$date ${day.year}' : '$date, ${day.year}';
  }
  return time == null ? date : '$date · $time';
}

/// The three top-level lenses on the board — see _MatrixScreenState._filter.
/// Deliberately just three plain client-side filters over one already-loaded
/// task list, not three separate queries: nothing here needs a network round
/// trip to switch.
///
/// [today] is the DAY lens: one day's board, the day the header names
/// (_MatrixScreenState._selectedDay, today unless the arrows or the month
/// moved it). The segment is still called «اليوم» because tapping it always
/// comes back to today.
enum _MatrixFilter { today, fav, all }

class MatrixScreen extends ConsumerStatefulWidget {
  const MatrixScreen({super.key});

  @override
  ConsumerState<MatrixScreen> createState() => _MatrixScreenState();
}

class _MatrixScreenState extends ConsumerState<MatrixScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _armDayTimer();
    // The widget's quick-add link can arrive before this screen exists:
    // with Tasks out of the bottom bar, HomeShell pushes this screen as a
    // route AFTER the deep link set the flag, so the ref.listen in build
    // (which only fires on changes) never sees it. One post-frame check
    // covers that case; the listener still covers a link that lands while
    // this screen is already up. Both reset the flag, so the sheet opens
    // once either way.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !ref.read(requestedMatrixQuickAddProvider)) return;
      ref.read(requestedMatrixQuickAddProvider.notifier).state = false;
      _showAdd(context, ref, MatrixQuadrant.doFirst, day: _today);
    });
  }

  @override
  void dispose() {
    _dayTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  final Set<String> _selectedIds = {};
  // App Guide's "Add a task" coach-mark target — see the CoachMarkOverlay
  // near the end of build(). The Do First quadrant is the canonical "add a
  // task" spot here, same choice GetStartedChecklistCard's onAddTask above
  // already makes.
  final GlobalKey _addTaskCardKey = GlobalKey();
  // The day lens is the default: today's board, the same set a brand-new
  // user with nothing carried over would expect to land on. Nothing to
  // migrate for existing boards either: which board a task is on is worked
  // out fresh on every build (task_day.dart), never stored, so it can't
  // disagree with what's actually on the board the way a saved preference
  // could.
  _MatrixFilter _filter = _MatrixFilter.today;
  // The day the header names and the day lens shows. Null is today, and
  // follows the clock: a board left open over midnight turns to the new
  // day by itself (see _armDayTimer). Set by the header's arrows and its
  // month sheet, and by an add's «عرض»; cleared by the «اليوم» segment,
  // the only way back that is needed (Aziz: "we already have a button for
  // today"). Kept while Fav, All or a chip is showing, so the header can
  // still say which day the arrows will step from. Lives in this State
  // only: HomeShell keeps no page alive, so leaving the Tasks tab and
  // coming back opens on today again, which is accepted.
  DateTime? _selectedDay;
  // A second, independent filter layered on top of the segments (mutually
  // exclusive with them, see the toggle's onChanged below): open tasks
  // whose day has gone (task_day.dart's isCarriedOver). Date-based and
  // computed fresh on every build rather than stored on the task, so it
  // can never go stale the way a stored flag could.
  bool _carriedOverOnly = false;
  // The forward-looking twin of [_carriedOverOnly]. Mutually exclusive with
  // it and with the Fav/All segments: each is a separate lens on one board,
  // and switching any of them backs out of the others.
  bool _upcomingOnly = false;

  // ── The clock ──────────────────────────────────────────────────────────
  //
  // "Today" is read from dayClockSourceProvider, the same source
  // dayClockProvider reads (DateTime.now in the app, a fixed instant in a
  // test that wants one), and re-read by this screen's own timer at the
  // next real midnight and on every resume.
  //
  // Not a watch of dayClockProvider itself, which would do the same job:
  // that provider arms an hours-long Timer in the container, and in a
  // widget test whose container outlives the tree (every test that pumps
  // this screen through UncontrolledProviderScope, the filter row layout
  // test among them) the timer is still pending when the tree goes, which
  // fails the test outright. A timer owned by this State is cancelled with
  // it. The badge (navBadgesProvider) does watch dayClockProvider; both
  // turn at the same midnight, so the badge and this board agree.
  //
  // startOfDay, NOT effectiveDay: tasks roll over at real midnight, on
  // purpose (task_day.dart's header has the reason).
  Timer? _dayTimer;

  DateTime get _now => ref.read(dayClockSourceProvider)();
  DateTime get _today => _now.startOfDay;

  /// Rebuilds at the coming midnight, then re-arms for the one after. A
  /// suspended app's timer can fire late or not at all, so resume re-reads
  /// the clock too (see [didChangeAppLifecycleState]).
  void _armDayTimer() {
    _dayTimer?.cancel();
    final now = _now;
    final midnight = DateTime(now.year, now.month, now.day + 1);
    _dayTimer = Timer(midnight.difference(now) + const Duration(seconds: 1),
        () {
      if (!mounted) return;
      setState(_followClockIfToday);
      _armDayTimer();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    setState(_followClockIfToday);
    _armDayTimer();
  }

  /// A board walked to Wednesday that is still open when Wednesday comes is
  /// showing today: from then on it follows the clock like any other today
  /// board, rather than turning into a past day at the next midnight.
  void _followClockIfToday() {
    final selected = _selectedDay;
    if (selected != null && selected.isSameDayAs(_today)) _selectedDay = null;
  }

  /// The day the header names: the selected day, or today.
  DateTime _viewDay(DateTime today) => _selectedDay ?? today;

  /// Whether the board is the day lens (no Fav, All or chip in charge).
  bool get _dayLensActive =>
      _filter == _MatrixFilter.today && !_carriedOverOnly && !_upcomingOnly;

  /// Shows [day]'s board: the day lens, any Fav/All/chip lens backed out of,
  /// as every day control on this screen does. Today is stored as null so
  /// it keeps following the clock.
  ///
  /// A selection ends when the board changes under it. The selected tasks
  /// are the old board's, and Delete deletes every selected id whether it
  /// is on screen or not: a selection kept across an arrow tap would bin
  /// yesterday's picks from tomorrow's board, with only the undo snackbar
  /// to say so. Picking the day already on screen changes nothing, so it
  /// keeps the selection.
  void _selectDay(DateTime day) {
    final today = _today;
    final next = day.isSameDayAs(today) ? null : day.startOfDay;
    final sameBoard = _dayLensActive &&
        (next == null
            ? _selectedDay == null
            : _selectedDay != null && next.isSameDayAs(_selectedDay!));
    setState(() {
      _selectedDay = next;
      _filter = _MatrixFilter.today;
      _carriedOverOnly = false;
      _upcomingOnly = false;
      if (!sameBoard) _selectedIds.clear();
    });
  }

  /// The arrows: one day from the day the header names, also when Fav, All
  /// or a chip is showing (the header keeps naming it, dimmed, for exactly
  /// this). DateTime(y, m, d + n), never .add(Duration(days: n)).
  void _stepDay(int by) {
    final from = _viewDay(_today);
    _selectDay(DateTime(from.year, from.month, from.day + by));
  }

  Future<void> _openMonth(BuildContext context) async {
    final picked = await showTaskMonthSheet(
      context,
      selected: _viewDay(_today),
      tasks: ref.read(matrixProvider).tasks,
    );
    if (picked == null || !mounted) return;
    _selectDay(picked);
  }

  /// The day a new task is for when it is added from the board: the day on
  /// screen when the day lens shows today or a later day, today otherwise.
  /// A past day's board, Fav, All and the chips have no day of their own a
  /// new task could sensibly go to, and nothing is added for a day that has
  /// gone.
  DateTime _addDay() {
    final today = _today;
    final day = _viewDay(today);
    return _dayLensActive && day.isAfter(today) ? day : today;
  }

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

  void _deleteSelected() {
    if (_selectedIds.isEmpty) return;
    HapticFeedback.mediumImpact();
    final notifier = ref.read(matrixProvider.notifier);
    final removed = ref
        .read(matrixProvider)
        .tasks
        .where((t) => _selectedIds.contains(t.id))
        .toList();
    final count = removed.length;
    notifier.deleteMany(_selectedIds);
    _clearSelection();
    _showUndoSnackbar(
      message: S.of(context).matrixTasksDeleted(count),
      onUndo: () => notifier.restoreMany(removed),
    );
  }

  MatrixTask? _findTask(String id) {
    for (final t in ref.read(matrixProvider).tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  void _deleteTask(String id) {
    final task = _findTask(id);
    if (task == null) return;
    HapticFeedback.mediumImpact();
    ref.read(matrixProvider.notifier).delete(id);
    _showUndoSnackbar(
      message: S.of(context).matrixTaskDeleted(task.title),
      onUndo: () => ref.read(matrixProvider.notifier).restore(task),
    );
  }

  void _moveTask(String id, MatrixQuadrant q) {
    HapticFeedback.selectionClick();
    ref.read(matrixProvider.notifier).move(id, q);
  }

  // Drag-and-drop specifically — unlike _moveTask (used by the "..." sheet's
  // plain "move to quadrant" option, which always appends to the end),
  // this carries *where* the task was dropped, so it can land at a precise
  // row instead of always landing last.
  void _reorderTask(String id, MatrixQuadrant q, String? beforeId) {
    HapticFeedback.selectionClick();
    ref.read(matrixProvider.notifier).reorder(id, q, beforeId: beforeId);
  }

  /// Whether [t] is currently visible under the active lens (the day lens,
  /// Fav, All, or a chip). build() fills the board with exactly this, and
  /// it is handed to QuadrantExpandedScreen as its filter, so the expanded
  /// quadrant applies the same lens and stays live (it re-filters
  /// matrixProvider's data on every rebuild) instead of freezing on a
  /// snapshot from the moment it was opened. Also what decides whether an
  /// add needs its «عرض» snackbar ([_announceHiddenAdds]).
  bool _isVisibleUnderFilter(MatrixTask t) => _visibleOn(t, _today);

  /// [_isVisibleUnderFilter] against a [today] the caller already read, so
  /// one build reads the clock once and cannot straddle midnight halfway
  /// through its sets.
  bool _visibleOn(MatrixTask t, DateTime today) {
    // «قادمة» and «مُرحّلة»: open tasks whose day is after or before today.
    // With today's open tasks these split every open task exactly once
    // (task_day.dart), so no open task is on none of the three or on two.
    if (_upcomingOnly) return isUpcoming(t, today);
    if (_carriedOverOnly) return isCarriedOver(t, today);
    return switch (_filter) {
      // One day's board: planned for it, or done on it (showsOnDay).
      _MatrixFilter.today => showsOnDay(t, _viewDay(today)),
      // Fav and All are explicit lenses the user asked for by name, so
      // tasks of every day belong in them, each row saying its day (see
      // matrixRowMeta). Done tasks only for the day they were finished on,
      // as before: older ones live in Completed history.
      _MatrixFilter.fav => (t.isFav && !t.isDone) || _doneOn(t, today),
      _MatrixFilter.all => !t.isDone || _doneOn(t, today),
    };
  }

  /// Done, and finished on [today]'s calendar day.
  static bool _doneOn(MatrixTask t, DateTime today) {
    final done = t.completedAt;
    return t.isDone && done != null && done.toLocal().isSameDayAs(today);
  }

  /// Row lines for QuadrantExpandedScreen, read live like its filter (see
  /// matrixRowMeta for what a row says).
  String? _metaFor(MatrixTask t) => matrixRowMeta(
        t,
        dayLens: _dayLensActive,
        today: _today,
        isAr: S.of(context).isAr,
      );

  /// Pushes QuadrantExpandedScreen for [quadrant] — a near-fullscreen view
  /// of just that quadrant's tasks, opened from its header (see
  /// quadrant_card.dart's new onExpand). A plain custom PageRouteBuilder
  /// rather than Hero: this app has no compiler/device in the loop while
  /// building it, and a scale+fade of the whole incoming screen is far
  /// harder to get subtly wrong (mismatched Hero tags, RTL-mirrored
  /// alignment, etc.) than it is smooth and clean — which is exactly what
  /// was asked for. Every callback below is the *exact same* one already
  /// wired to this quadrant's compact QuadrantCard, so completing, adding,
  /// moving, or deleting a task behaves identically whichever screen it's
  /// done from.
  void _openQuadrantExpanded(
    BuildContext context,
    WidgetRef ref,
    MatrixQuadrant quadrant,
  ) {
    HapticFeedback.lightImpact();
    final today = _today;
    // Read once, at open: nothing on the covered board can change the lens
    // while this route is on top.
    final pastDay = _dayLensActive && _viewDay(today).isBefore(today);
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (context, animation, secondaryAnimation) =>
            QuadrantExpandedScreen(
          quadrant: quadrant,
          isVisible: _isVisibleUnderFilter,
          metaFor: _metaFor,
          pastDay: pastDay,
          onToggle: (id) {
            HapticFeedback.lightImpact();
            ref.read(matrixProvider.notifier).toggle(id);
          },
          onDelete: _deleteTask,
          onMove: _moveTask,
          onReorder: _reorderTask,
          onToggleFav: (id) => ref.read(matrixProvider.notifier).toggleFav(id),
          onAddTapped: () => _showAdd(context, ref, quadrant),
          onOpenDetails: (task) => _openTaskDetails(context, ref, task),
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.94, end: 1.0).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  /// Opens the rename/recolor sheet for [quadrant] — wired to a long-press
  /// on QuadrantCard's header (see the four instantiations below). Reads
  /// matrixProvider fresh via `ref.read` rather than the already-watched
  /// `matrixState` local in build(), since this is only ever called from
  /// an event handler, never from inside build() itself.
  void _editQuadrant(
    BuildContext context,
    WidgetRef ref,
    MatrixQuadrant quadrant,
  ) {
    final matrixState = ref.read(matrixProvider);
    final isAr = S.of(context).isAr;
    showEditQuadrantSheet(
      context,
      ref,
      quadrant: quadrant,
      currentTitle: matrixState.titleFor(quadrant, isAr),
      currentColorHex: matrixState.quadrantColors[quadrant.name],
    );
  }

  void _showUndoSnackbar({
    required String message,
    required VoidCallback onUndo,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showOne(
      SnackBar(
        content: Text(message),
        // Never pin the bar open. See AppSnackBar.
        persist: false,
        action: SnackBarAction(
          label: S.of(context).matrixUndo,
          onPressed: onUndo,
        ),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final matrixState = ref.watch(matrixProvider);

    // The Matrix widget's "+" button (see requestedMatrixQuickAddProvider's
    // doc comment), consumed exactly once, same one-shot pattern as
    // _OnboardingOrGrid's pendingJoinCodeProvider listener in main.dart.
    // Safe unconditionally on every build, same reasoning as HomeShell's own
    // ref.listen(requestedHomeTabProvider, ...). HomeShell's PageView keeps
    // no page alive, so this State exists only while the Tasks page is up:
    // this listener covers a link that lands while it is, and initState's
    // post-frame check covers one that set the flag before the page was
    // built. The tab switch itself is requestedHomeTabProvider's job, set
    // alongside this one by the same deep-link handler. Always today's day:
    // a quick add from outside the app has no board day behind it.
    ref.listen<bool>(requestedMatrixQuickAddProvider, (previous, next) {
      if (!next) return;
      ref.read(requestedMatrixQuickAddProvider.notifier).state = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        _showAdd(context, ref, MatrixQuadrant.doFirst, day: _today);
      });
    });

    // Auto-dismiss App Guide's "Add a task" coach-mark the instant a task
    // actually exists, however it got added — same reasoning as Grid's own
    // habitListProvider/dashboardProvider listeners (see grid_screen.dart).
    ref.listen<MatrixState>(matrixProvider, (previous, next) {
      if ((previous?.tasks.isEmpty ?? true) &&
          next.tasks.isNotEmpty &&
          ref.read(activeAppGuideLessonProvider) == AppGuideLesson.addTask) {
        // The next step (Rooms) lives on the Profile tab, so this stops the
        // dim rather than moving anyone. See guide_chain.dart.
        advanceGuideAfter(ref, AppGuideLesson.addTask);
      }
    });

    // One clock read for the whole build (see _armDayTimer for why this is
    // the source and not dayClockProvider). Real midnight, not the habits'
    // 10:00 cutoff: task_day.dart's header has the tasks-vs-habits split.
    final today = ref.watch(dayClockSourceProvider)().startOfDay;
    final day = _viewDay(today);
    final dayLens = _dayLensActive;
    // A day that has gone, on the day lens: its board is a record, not a
    // plan, so the quadrants drop their count pill, their "add" body and
    // their «+ أضف مهمة أخرى» row (see QuadrantCard.pastDay).
    final pastDay = dayLens && day.isBefore(today);

    // A task stays on its own board, struck through, not gone, for the
    // rest of the day it was finished on. That's the "proof you did it"
    // moment a lot of task apps lose by yanking the row away the instant
    // you check it. Fav and All drop it once the calendar day rolls over
    // at midnight; it stays on its day's board (and the day it was for)
    // and in Completed history via the header icon.
    final completedCount = matrixState.tasks.where((t) => t.isDone).length;
    final favCount =
        matrixState.tasks.where((t) => t.isFav && !t.isDone).length;
    // Open, and their day has gone (task_day.dart's isCarriedOver): the
    // stuff that's easy to lose track of. By the task's day rather than
    // isFav on purpose: favoriting something doesn't protect it from going
    // stale, and this is meant to catch exactly that, starred or not. A
    // task planned for a day still ahead is never here: it hasn't arrived,
    // so it isn't stale.
    final carriedOver =
        matrixState.tasks.where((t) => isCarriedOver(t, today)).toList();
    // Open, and planned for a day after today. Surfaced by _UpcomingChip
    // with a count, so a task planned ahead can never quietly disappear the
    // way tasks did the last time this screen filed by the reminder day.
    final upcoming =
        matrixState.tasks.where((t) => isUpcoming(t, today)).toList();
    // The board itself: exactly _isVisibleUnderFilter, so the expanded
    // quadrant and the «عرض» check can never show a different set.
    final tasks =
        matrixState.tasks.where((t) => _visibleOn(t, today)).toList();
    String? metaFor(MatrixTask t) =>
        matrixRowMeta(t, dayLens: dayLens, today: today, isAr: s.isAr);

    if (matrixState.isLoading) {
      return Scaffold(
        backgroundColor: gp.bg,
        body: SafeArea(
          child: Center(
            child: CircularProgressIndicator(
              color: GameColors.gold,
              strokeWidth: 2,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: gp.bg,
      // Nav bar now owned by HomeShell — see that widget's doc comment.
      //
      // body is a Stack (not just SafeArea) so App Guide's "Add a task"
      // coach-mark can render as a sibling overlay above the real board —
      // see the CoachMarkOverlay conditional right after this Column's
      // closing brackets, near the end of this method. Everything between
      // here and there (the untouched ~300-line Column below) is
      // deliberately left at its original indentation rather than reflowed
      // two spaces deeper: Dart doesn't care about indentation, and
      // reindenting that much already-working layout code was pure risk
      // for zero behavior change.
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  // Even on both sides, with a 48pt spacer mirroring the
                  // History button below: the day sits in the true centre
                  // of the bar (Aziz, 2026-09-29: "the day in the center of
                  // the upper bar, not on right"), not just the centre of
                  // what History leaves over.
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Row(
                    children: [
                      // The page title «مصفوفة الأهداف» gave way to the day
                      // the board shows (Aziz picked this over a second row
                      // under the lens strip, which would have cost every
                      // quadrant 20pt). No separate "today" pill: the
                      // «اليوم» segment below is the way back.
                      const SizedBox(width: 48),
                      Expanded(
                        child: Align(
                          alignment: Alignment.center,
                          child: _DayNavigator(
                            title: taskDayTitle(day, s, now: today),
                            // Every weekday name, with a two-digit date, in
                            // every month of the shown day's year (the 22nd
                            // to the 28th), plus today's own «اليوم، …»
                            // title: the widest title that year can have.
                            // Centred in the bar, the whole navigator
                            // re-centres whenever the slot changes width, so
                            // a slot sized per month moved BOTH arrows at
                            // every new month name, and one that left out
                            // «اليوم، 29 سبتمبر» moved them on the first
                            // step away from today. Named against 1 January
                            // of today's year, so a year other than today's
                            // carries its year the way the real title does
                            // (named against the day itself, every title of
                            // another year outgrew the slot).
                            slotTitles: [
                              for (var m = 1; m <= 12; m++)
                                for (var i = 0; i < 7; i++)
                                  taskDayTitle(
                                    DateTime(day.year, m, 22 + i),
                                    s,
                                    now: DateTime(today.year),
                                  ),
                              taskDayTitle(today, s, now: today),
                            ],
                            dimmed: !dayLens,
                            onPrev: () => _stepDay(-1),
                            onNext: () => _stepDay(1),
                            onOpenMonth: () => _openMonth(context),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Badge(
                          label: Text('$completedCount'),
                          isLabelVisible: completedCount > 0,
                          backgroundColor: GameColors.gold,
                          textColor: Colors.black,
                          child: Icon(
                            Icons.check_circle_outline_rounded,
                            color: gp.textSec,
                          ),
                        ),
                        tooltip: s.matrixCompletedTitle,
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const MatrixHistoryScreen(),
                            ),
                          );
                        },
                      ),
                    ],
                  ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.05),
                ),
                GetStartedChecklistCard(
                  // Grid's own screen owns the actual "add a habit" action (see
                  // grid_screen.dart's showAddHabitHub call) - from here, the
                  // right move is just getting there. See
                  // requestedHomeTabProvider's doc comment.
                  onAddHabit: () => ref
                      .read(requestedHomeTabProvider.notifier)
                      .state = NavTab.grid,
                  onAddTask: () => _showAdd(
                    context,
                    ref,
                    MatrixQuadrant.doFirst,
                    day: today,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    // One strip, one line, on every screen. This was a Wrap,
                    // which dropped Upcoming onto a second row the moment the
                    // three controls outgrew the width - which is most phones
                    // in Arabic, where the words run longer, and the narrow
                    // ones in either language. They are three lenses on the
                    // same board, so a stray second line reads like a
                    // different kind of control rather than the third member
                    // of a set. scaleDown shrinks the whole strip together
                    // where it has to and leaves it at full size where it
                    // fits, so no device gets a wrapped row and no device
                    // pays for the ones that would have wrapped.
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: 8,
                        children: [
                          _MatrixFilterToggle(
                            filter: _filter,
                            favCount: favCount,
                            // Also blank while the day lens shows a day
                            // other than today: «اليوم» lit over Wednesday's
                            // board would be the same false claim a lit
                            // segment over a chip's board is. Tapping it is
                            // the way back to today.
                            lensOverridden: _carriedOverOnly ||
                                _upcomingOnly ||
                                (_filter == _MatrixFilter.today &&
                                    !day.isSameDayAs(today)),
                            onChanged: (v) => setState(() {
                              _filter = v;
                              // Each segment, carried-over and upcoming are
                              // separate lenses on the same board:
                              // switching one backs out of the others
                              // instead of trying to combine them.
                              _carriedOverOnly = false;
                              _upcomingOnly = false;
                              // «اليوم» means today, whichever day the
                              // arrows had walked to. Fav and All keep the
                              // day, so the header can still name it.
                              // Coming back from another day swaps the
                              // board, so it ends a selection the way the
                              // arrows do (see _selectDay).
                              if (v == _MatrixFilter.today) {
                                if (_selectedDay != null) _selectedIds.clear();
                                _selectedDay = null;
                              }
                            }),
                          ),
                          // `|| _carriedOverOnly`: the chip is the only control
                          // that clears its own lens, so it must outlive the
                          // list it counts. Finish the last carried-over task
                          // while filtered to them and the count hits zero;
                          // drop the chip at that moment and the board sits
                          // empty, still filtered, with Today painted as if
                          // it were showing you everything. Mounting it at
                          // zero keeps the way out on screen.
                          if (_filter != _MatrixFilter.fav &&
                              (carriedOver.isNotEmpty || _carriedOverOnly))
                            _CarriedOverChip(
                              count: carriedOver.length,
                              active: _carriedOverOnly,
                              onTap: () => setState(() {
                                _carriedOverOnly = !_carriedOverOnly;
                                _upcomingOnly = false;
                              }),
                            ),
                          // Sits after carried-over on purpose, so the row
                          // reads left to right as past then future. Hidden
                          // when nothing is waiting, same as its twin: a
                          // permanent "0 upcoming" would be noise on most
                          // days.
                          if (_filter != _MatrixFilter.fav &&
                              (upcoming.isNotEmpty || _upcomingOnly))
                            _UpcomingChip(
                              count: upcoming.length,
                              active: _upcomingOnly,
                              onTap: () => setState(() {
                                _upcomingOnly = !_upcomingOnly;
                                _carriedOverOnly = false;
                              }),
                            ),
                        ],
                      ),
                    ),
                  ),
                ).animate(delay: 50.ms).fadeIn(duration: 300.ms),
                if (_selectionMode) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: _SelectionBar(
                      count: _selectedIds.length,
                      onClear: _clearSelection,
                      onDelete: _deleteSelected,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      const SizedBox(width: 16),
                      Expanded(
                        child: _AxisLabel(
                          label: s.matrixUrgent,
                          icon: Icons.bolt_rounded,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _AxisLabel(
                          label: s.matrixNotUrgent,
                          icon: Icons.schedule_rounded,
                        ),
                      ),
                    ],
                  ).animate(delay: 100.ms).fadeIn(duration: 300.ms),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Column(
                          children: [
                            Expanded(
                              child: _RotatedAxisLabel(
                                label: s.matrixImportant,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: _RotatedAxisLabel(
                                label: s.matrixNotImportant,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: QuadrantCard(
                                        key: _addTaskCardKey,
                                        quadrant: MatrixQuadrant.doFirst,
                                        tasks: tasks
                                            .where(
                                              (t) =>
                                                  t.quadrant ==
                                                  MatrixQuadrant.doFirst,
                                            )
                                            .toList(),
                                        onToggle: (id) {
                                          HapticFeedback.lightImpact();
                                          ref
                                              .read(matrixProvider.notifier)
                                              .toggle(id);
                                        },
                                        onDelete: _deleteTask,
                                        onMove: _moveTask,
                                        onReorder: _reorderTask,
                                        onToggleFav: (id) => ref
                                            .read(matrixProvider.notifier)
                                            .toggleFav(id),
                                        onAddTapped: () => _showAdd(
                                          context,
                                          ref,
                                          MatrixQuadrant.doFirst,
                                        ),
                                        onOpenDetails: (task) =>
                                            _openTaskDetails(
                                          context,
                                          ref,
                                          task,
                                        ),
                                        selectionMode: _selectionMode,
                                        metaFor: metaFor,
                                        pastDay: pastDay,
                                        selectedIds: _selectedIds,
                                        onSelectionToggle: _toggleSelection,
                                        onSelectionStart: _startSelection,
                                        onExpand: () => _openQuadrantExpanded(
                                          context,
                                          ref,
                                          MatrixQuadrant.doFirst,
                                        ),
                                        title: matrixState.titleFor(
                                          MatrixQuadrant.doFirst,
                                          s.isAr,
                                        ),
                                        color: matrixState
                                            .colorFor(MatrixQuadrant.doFirst),
                                        onEditQuadrant: () => _editQuadrant(
                                          context,
                                          ref,
                                          MatrixQuadrant.doFirst,
                                        ),
                                      )
                                          .animate(delay: 150.ms)
                                          .fadeIn(duration: 350.ms)
                                          .scaleXY(
                                            begin: 0.96,
                                            end: 1,
                                            curve: Curves.easeOutBack,
                                          ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: QuadrantCard(
                                        quadrant: MatrixQuadrant.schedule,
                                        tasks: tasks
                                            .where(
                                              (t) =>
                                                  t.quadrant ==
                                                  MatrixQuadrant.schedule,
                                            )
                                            .toList(),
                                        onToggle: (id) {
                                          HapticFeedback.lightImpact();
                                          ref
                                              .read(matrixProvider.notifier)
                                              .toggle(id);
                                        },
                                        onDelete: _deleteTask,
                                        onMove: _moveTask,
                                        onReorder: _reorderTask,
                                        onToggleFav: (id) => ref
                                            .read(matrixProvider.notifier)
                                            .toggleFav(id),
                                        onAddTapped: () => _showAdd(
                                          context,
                                          ref,
                                          MatrixQuadrant.schedule,
                                        ),
                                        onOpenDetails: (task) =>
                                            _openTaskDetails(
                                          context,
                                          ref,
                                          task,
                                        ),
                                        selectionMode: _selectionMode,
                                        metaFor: metaFor,
                                        pastDay: pastDay,
                                        selectedIds: _selectedIds,
                                        onSelectionToggle: _toggleSelection,
                                        onSelectionStart: _startSelection,
                                        onExpand: () => _openQuadrantExpanded(
                                          context,
                                          ref,
                                          MatrixQuadrant.schedule,
                                        ),
                                        title: matrixState.titleFor(
                                          MatrixQuadrant.schedule,
                                          s.isAr,
                                        ),
                                        color: matrixState
                                            .colorFor(MatrixQuadrant.schedule),
                                        onEditQuadrant: () => _editQuadrant(
                                          context,
                                          ref,
                                          MatrixQuadrant.schedule,
                                        ),
                                      )
                                          .animate(delay: 200.ms)
                                          .fadeIn(duration: 350.ms)
                                          .scaleXY(
                                            begin: 0.96,
                                            end: 1,
                                            curve: Curves.easeOutBack,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Expanded(
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: QuadrantCard(
                                        quadrant: MatrixQuadrant.delegate,
                                        tasks: tasks
                                            .where(
                                              (t) =>
                                                  t.quadrant ==
                                                  MatrixQuadrant.delegate,
                                            )
                                            .toList(),
                                        onToggle: (id) {
                                          HapticFeedback.lightImpact();
                                          ref
                                              .read(matrixProvider.notifier)
                                              .toggle(id);
                                        },
                                        onDelete: _deleteTask,
                                        onMove: _moveTask,
                                        onReorder: _reorderTask,
                                        onToggleFav: (id) => ref
                                            .read(matrixProvider.notifier)
                                            .toggleFav(id),
                                        onAddTapped: () => _showAdd(
                                          context,
                                          ref,
                                          MatrixQuadrant.delegate,
                                        ),
                                        onOpenDetails: (task) =>
                                            _openTaskDetails(
                                          context,
                                          ref,
                                          task,
                                        ),
                                        selectionMode: _selectionMode,
                                        metaFor: metaFor,
                                        pastDay: pastDay,
                                        selectedIds: _selectedIds,
                                        onSelectionToggle: _toggleSelection,
                                        onSelectionStart: _startSelection,
                                        onExpand: () => _openQuadrantExpanded(
                                          context,
                                          ref,
                                          MatrixQuadrant.delegate,
                                        ),
                                        title: matrixState.titleFor(
                                          MatrixQuadrant.delegate,
                                          s.isAr,
                                        ),
                                        color: matrixState
                                            .colorFor(MatrixQuadrant.delegate),
                                        onEditQuadrant: () => _editQuadrant(
                                          context,
                                          ref,
                                          MatrixQuadrant.delegate,
                                        ),
                                      )
                                          .animate(delay: 250.ms)
                                          .fadeIn(duration: 350.ms)
                                          .scaleXY(
                                            begin: 0.96,
                                            end: 1,
                                            curve: Curves.easeOutBack,
                                          ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: QuadrantCard(
                                        quadrant: MatrixQuadrant.eliminate,
                                        tasks: tasks
                                            .where(
                                              (t) =>
                                                  t.quadrant ==
                                                  MatrixQuadrant.eliminate,
                                            )
                                            .toList(),
                                        onToggle: (id) {
                                          HapticFeedback.lightImpact();
                                          ref
                                              .read(matrixProvider.notifier)
                                              .toggle(id);
                                        },
                                        onDelete: _deleteTask,
                                        onMove: _moveTask,
                                        onReorder: _reorderTask,
                                        onToggleFav: (id) => ref
                                            .read(matrixProvider.notifier)
                                            .toggleFav(id),
                                        onAddTapped: () => _showAdd(
                                          context,
                                          ref,
                                          MatrixQuadrant.eliminate,
                                        ),
                                        onOpenDetails: (task) =>
                                            _openTaskDetails(
                                          context,
                                          ref,
                                          task,
                                        ),
                                        selectionMode: _selectionMode,
                                        metaFor: metaFor,
                                        pastDay: pastDay,
                                        selectedIds: _selectedIds,
                                        onSelectionToggle: _toggleSelection,
                                        onSelectionStart: _startSelection,
                                        onExpand: () => _openQuadrantExpanded(
                                          context,
                                          ref,
                                          MatrixQuadrant.eliminate,
                                        ),
                                        title: matrixState.titleFor(
                                          MatrixQuadrant.eliminate,
                                          s.isAr,
                                        ),
                                        color: matrixState
                                            .colorFor(MatrixQuadrant.eliminate),
                                        onEditQuadrant: () => _editQuadrant(
                                          context,
                                          ref,
                                          MatrixQuadrant.eliminate,
                                        ),
                                      )
                                          .animate(delay: 300.ms)
                                          .fadeIn(duration: 350.ms)
                                          .scaleXY(
                                            begin: 0.96,
                                            end: 1,
                                            curve: Curves.easeOutBack,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (ref.watch(activeAppGuideLessonProvider) == AppGuideLesson.addTask)
            CoachMarkOverlay(
              targetKey: _addTaskCardKey,
              title: appGuideLessonCoachTitle(AppGuideLesson.addTask, s.isAr),
              body: appGuideLessonCoachBody(AppGuideLesson.addTask, s.isAr),
              onDismiss: () =>
                  ref.read(activeAppGuideLessonProvider.notifier).state = null,
            ),
        ],
      ),
    );
  }

  /// Opens the Add sheet for [quadrant], for [day] when given (today, from
  /// the Get Started card and the widget's quick add) and otherwise for the
  /// board's own add day ([_addDay]).
  ///
  /// When the sheet closes, a task that went somewhere this board is not
  /// showing is announced once ([_announceHiddenAdds]). Filing a task on a
  /// day nobody is looking at is exactly how tasks were once lost (see
  /// task_day.dart); saying where it went, with a way to go there, is what
  /// makes it safe.
  Future<void> _showAdd(
    BuildContext context,
    WidgetRef ref,
    MatrixQuadrant quadrant, {
    DateTime? day,
  }) async {
    unawaited(HapticFeedback.lightImpact());
    final addDay = day ?? _addDay();
    final added = <String>[];
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // Keeps the sheet's top clear of the status bar and notch. The bottom
      // inset is the sheet's own job: the card's outer margin adds MediaQuery
      // padding.bottom, so the footer button clears the gesture bar.
      useSafeArea: true,
      builder: (_) => AddTaskSheet(
        quadrant: quadrant,
        day: addDay,
        onAddOnDay: (
          title, {
          description,
          voiceNotes,
          reminderAts,
          reminderAnchorAt,
          alarm,
          required day,
        }) {
          HapticFeedback.mediumImpact();
          final task = ref.read(matrixProvider.notifier).add(
                title,
                quadrant,
                description: description,
                voiceNotes: voiceNotes ?? const [],
                reminderAts: reminderAts ?? const [],
                reminderAnchorAt: reminderAnchorAt,
                alarm: alarm ?? false,
                day: day,
              );
          if (task != null) added.add(task.id);
        },
      ),
    );
    if (!mounted || added.isEmpty) return;
    _announceHiddenAdds(added);
  }

  /// One snackbar when a task just added is not on the board showing now
  /// (added for a later day from Fav, for today from a past day's board, a
  /// non-star task under Fav...): «انضافت ليوم الأربعاء، 30 سبتمبر» with
  /// «عرض», which opens that day's board. Nothing when every added task is
  /// in view, which is the usual case.
  ///
  /// One bar for the whole sheet, naming the day of the LAST hidden task:
  /// a multi-add is almost always one day's list (the sheet's day is
  /// sticky), and a bar per task would only replace itself.
  void _announceHiddenAdds(List<String> ids) {
    final byId = {for (final t in ref.read(matrixProvider).tasks) t.id: t};
    MatrixTask? hidden;
    for (final id in ids) {
      final t = byId[id];
      if (t != null && !_isVisibleUnderFilter(t)) hidden = t;
    }
    if (hidden == null) return;
    final s = S.of(context);
    final day = taskDay(hidden);
    final message = day.isSameDayAs(_today)
        ? s.matrixAddedForToday
        : s.matrixAddedForDay(
            weekdayDateLabel(day, isAr: s.isAr, locale: s.isAr ? 'ar' : 'en'),
          );
    ScaffoldMessenger.of(context).showOne(
      SnackBar(
        content: Text(message),
        // Never pin the bar open. See AppSnackBar.
        persist: false,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: s.matrixShowDay,
          onPressed: () => _showDayFromSnackbar(day),
        ),
      ),
    );
  }

  /// «عرض»: that day's board. The bar rides on the root messenger, so it
  /// can be tapped over the expanded quadrant that the add was made from;
  /// that route is closed first, or the day would change underneath it.
  void _showDayFromSnackbar(DateTime day) {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) {
      Navigator.of(context).popUntil((r) => r == route);
    }
    _selectDay(day);
  }

  // Pencil icon on an existing task (see quadrant_card.dart's _TaskTile) —
  // the richer counterpart to _showAdd: editing title/description/voice on
  // something already in the matrix, plus Delete/Move (migrated here from
  // the old "..." menu). TaskDetailSheet only ever talks to callbacks, same
  // as QuadrantCard/_TaskTile below — it never touches matrixProvider
  // directly, so this screen stays the one place that owns provider access
  // for the whole feature.
  void _openTaskDetails(BuildContext context, WidgetRef ref, MatrixTask task) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // Keeps the sheet's top clear of the status bar and notch. The bottom
      // inset is the sheet's own job: the card's outer margin adds MediaQuery
      // padding.bottom, so the footer button clears the gesture bar.
      useSafeArea: true,
      builder: (_) => TaskDetailSheet(
        task: task,
        onRename: (id, title) =>
            ref.read(matrixProvider.notifier).rename(id, title),
        onUpdateDetails: (id, {description, clearDescription}) =>
            ref.read(matrixProvider.notifier).updateDetails(
                  id,
                  description: description,
                  clearDescription: clearDescription ?? false,
                ),
        onAddVoiceNote: (id, note) =>
            ref.read(matrixProvider.notifier).addVoiceNote(id, note),
        onRenameVoiceNote: (id, noteId, name) =>
            ref.read(matrixProvider.notifier).renameVoiceNote(id, noteId, name),
        onRemoveVoiceNote: (id, noteId) =>
            ref.read(matrixProvider.notifier).removeVoiceNote(id, noteId),
        onSetReminders: (id, reminderAts, {reminderAnchorAt, alarm}) =>
            ref.read(matrixProvider.notifier).setReminders(
                  id,
                  reminderAts,
                  reminderAnchorAt: reminderAnchorAt,
                  alarm: alarm,
                ),
        onDelete: () => _deleteTask(task.id),
        onMove: (q) => _moveTask(task.id, q),
      ),
    );
  }
}

// ─── Day navigator (the header) ─────────────────────────────────────────────

/// [previous][the day ⌄][next], where the page title used to be.
///
/// Copies the Habits page's week navigator (grid_screen_summary.dart's
/// _NavArrow and its title) so the two pages step through time the same
/// way: the same 40pt arrows, and the title a button that opens the month.
/// In a Row, so it mirrors with the language: in Arabic the previous-day
/// arrow sits on the right and points right, as the week navigator's does
/// (chevron_left/right mirror themselves under RTL).
///
/// One line whatever the language, width or text size: the title scales
/// down to fit rather than wrapping, because a two-line header would push
/// the whole board down on the phones with the least room. Taps only: the
/// Tasks tab swipes between pages, and a drag recognizer up here would
/// fight it.
///
/// The arrows hold still. The title's slot is as wide as the widest of
/// [slotTitles] (every weekday of the shown month, see the call) and the
/// title sits centred in it. Sized to each title alone, the next arrow
/// moved with every tap, by up to most of its own width between «الأحد»
/// and «الأربعاء», and a quick second tap landed on the title and opened
/// the month instead.
class _DayNavigator extends StatelessWidget {
  final String title;

  /// Titles the slot keeps room for; [title] is always one of them.
  final List<String> slotTitles;

  /// Fav, All or a chip is showing: the header still names the day the
  /// arrows step from, but quieter, because the board under it is not that
  /// day's.
  final bool dimmed;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onOpenMonth;

  const _DayNavigator({
    required this.title,
    this.slotTitles = const [],
    required this.dimmed,
    required this.onPrev,
    required this.onNext,
    required this.onOpenMonth,
  });

  static const _titleStyle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w800,
  );
  // The title's horizontal padding (6 a side), and the chevron after it
  // with its gap.
  static const double _slotChrome = 12 + 2 + 16;

  static final Map<String, double> _slotWidthCache = {};

  /// The slot width [slotTitles] need, measured in the style and text
  /// scale the title is drawn in. A narrower screen gets less: the slot is
  /// Flexible, and the title then scales down inside it.
  ///
  /// Cached: [slotTitles] is a whole year of titles (see the call), and the
  /// header rebuilds with every tick on the board, so each answer is kept
  /// per font, direction, text scale and title list, and the cache is
  /// dropped once it holds more than a handful of them.
  double _slotWidth(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.merge(_titleStyle);
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final titles = {title, ...slotTitles};
    final key = '${style.fontFamily}|$direction|${scaler.scale(100)}|'
        '${titles.join('|')}';
    final cached = _slotWidthCache[key];
    if (cached != null) return cached;
    if (_slotWidthCache.length > 16) _slotWidthCache.clear();
    var widest = 0.0;
    for (final t in titles) {
      final tp = TextPainter(
        text: TextSpan(text: t, style: style),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      if (tp.width > widest) widest = tp.width;
      tp.dispose();
    }
    return _slotWidthCache[key] = widest + _slotChrome;
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _DayArrow(
          icon: Icons.chevron_left_rounded,
          tooltip: s.matrixPrevDay,
          onTap: onPrev,
        ),
        const SizedBox(width: 4),
        Flexible(
          child: ConstrainedBox(
            // A minimum, not a fixed width: the Flexible above still caps
            // it at the room there is.
            constraints: BoxConstraints(minWidth: _slotWidth(context)),
            child: Semantics(
              button: true,
              label: title,
              hint: s.matrixOpenMonth,
              excludeSemantics: true,
              onTap: onOpenMonth,
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(GameSpacing.buttonRadius),
                child: InkWell(
                  borderRadius:
                      BorderRadius.circular(GameSpacing.buttonRadius),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onOpenMonth();
                  },
                  child: SizedBox(
                    height: 40,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedSwitcher(
                              duration: GameMotion.standard,
                              child: Text(
                                title,
                                key: ValueKey(title),
                                maxLines: 1,
                                softWrap: false,
                                style: _titleStyle.copyWith(
                                  color:
                                      dimmed ? gp.textSec : gp.textPrimary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 2),
                            // So the date reads as a control: without it
                            // the title looks like a caption between two
                            // arrows, and nobody tries tapping a caption.
                            Icon(
                              Icons.expand_more_rounded,
                              size: 16,
                              color: gp.textSec,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        _DayArrow(
          icon: Icons.chevron_right_rounded,
          tooltip: s.matrixNextDay,
          onTap: onNext,
        ),
      ],
    );
  }
}

/// grid_screen_summary.dart's _NavArrow, plus a name for screen readers.
class _DayArrow extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _DayArrow({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: gp.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GameSpacing.buttonRadius),
          side: BorderSide(color: gp.border, width: 0.5),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(GameSpacing.buttonRadius),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, color: gp.textSec, size: 24),
          ),
        ),
      ),
    );
  }
}

class _SelectionBar extends StatelessWidget {
  final int count;
  final VoidCallback onClear;
  final VoidCallback onDelete;

  const _SelectionBar({
    required this.count,
    required this.onClear,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: GameColors.gold.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: GameColors.gold.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close_rounded, size: 18, color: gp.textSec),
            onPressed: onClear,
          ),
          Expanded(
            child: Text(
              s.matrixSelectedCount(count),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: gp.textPrimary,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded, size: 17),
            label: Text(s.matrixDeleteSelected),
            style: TextButton.styleFrom(foregroundColor: GameColors.error),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 180.ms).slideY(begin: -0.15);
  }
}

// ─── Today/Fav/All filter toggle ────────────────────────────────────────────

/// Three plain client-side filters over one already-loaded task list — see
/// _MatrixFilter. Defaults to Today (see _MatrixScreenState._filter), which
/// still shows a brand-new board with nothing on it yet exactly as before;
/// switching to Fav or All never requires a network round trip.
class _MatrixFilterToggle extends StatelessWidget {
  final _MatrixFilter filter;
  final int favCount;
  final ValueChanged<_MatrixFilter> onChanged;

  /// True while a chip lens (carried-over or upcoming) is driving the board
  /// instead of [filter], or while the day lens shows a day other than
  /// today. Every segment then draws unselected, and «اليوم» is the way
  /// back to today.
  ///
  /// [filter] deliberately keeps its old value underneath, so backing out of
  /// a chip returns you to the segment you came from rather than dumping you
  /// on Today. But leaving Today painted gold while the board actually shows
  /// carried-over tasks makes the toggle assert something false about what
  /// you are looking at, and the two controls then disagree on screen.
  ///
  /// Highlighting All instead would be worse: All is a real segment with real
  /// contents, so the highlight would sit on a control that, when tapped,
  /// visibly changes the list it claims to already be showing. Blank is the
  /// honest state - "none of these three" is exactly the truth, the chip's own
  /// active border says which lens replaced them, and tapping any segment
  /// moves the highlight there and clears the chip in one obvious step.
  final bool lensOverridden;

  const _MatrixFilterToggle({
    required this.filter,
    required this.favCount,
    required this.onChanged,
    this.lensOverridden = false,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: gp.surfaceHL,
        borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
        border: Border.all(color: gp.border, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Default segment — today's own board. No count badge, unlike
          // Fav: the number would just restate what's already visible below
          // it, since this is the primary view rather than a narrowed one.
          _FilterSegment(
            active: !lensOverridden && filter == _MatrixFilter.today,
            onTap: () => onChanged(_MatrixFilter.today),
            child: Text(s.matrixToday),
          ),
          _FilterSegment(
            active: !lensOverridden && filter == _MatrixFilter.fav,
            onTap: () => onChanged(_MatrixFilter.fav),
            // Same star glyph used to flag a task on each row — ties this
            // filter visually to "my starred tasks" instead of reading like
            // a separate due-date/scheduling concept of its own.
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.star_rounded, size: 13),
                const SizedBox(width: 4),
                Text('${s.matrixFav} · $favCount'),
              ],
            ),
          ),
          _FilterSegment(
            active: !lensOverridden && filter == _MatrixFilter.all,
            onTap: () => onChanged(_MatrixFilter.all),
            child: Text(s.matrixAll),
          ),
        ],
      ),
    );
  }
}

// ─── Carried-over chip ──────────────────────────────────────────────────────

/// Sits beside the Today/Fav/All toggle, only when there's actually
/// something to show — a task left unfinished from before today is worth a
/// nudge, but an empty chip every single day would just be noise. Doubly
/// important now that Today (the default) doesn't include these by default:
/// this chip is what keeps them from actually disappearing. Tapping it
/// filters the board to exactly that set (see
/// _MatrixScreenState._carriedOverOnly); tapping again (or switching the
/// Today/Fav/All toggle) clears it.
class _CarriedOverChip extends StatelessWidget {
  final int count;
  final bool active;
  final VoidCallback onTap;

  const _CarriedOverChip({
    required this.count,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    // Not `const` — GameColors.iconStreak is a mutable `static Color`
    // (preset-driven), not a compile-time constant.
    const color = GameColors.iconStreak;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: GameMotion.standard,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: active ? color.withOpacity(0.18) : color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
            border: Border.all(
              color: color.withOpacity(active ? 0.6 : 0.3),
              width: active ? 1.2 : 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // The chip's wash and border keep the true colour; only the
              // glyph takes ink, because only the glyph has to be read.
              Icon(Icons.history_rounded, size: 13, color: gp.ink(color)),
              const SizedBox(width: 5),
              Text(
                s.matrixCarriedOverCount(count),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: gp.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// [_CarriedOverChip]'s forward-looking twin: open tasks planned for a day
/// that hasn't arrived (task_day.dart's isUpcoming), which today's board
/// deliberately holds back. Each is on its own day's board too, and the
/// month sheet dots that day.
///
/// Structurally identical to that chip on purpose. This screen already taught
/// the user that a counted pill beside the Today/Fav/All toggle means "there
/// are tasks over here that the board isn't showing you", and the fastest way
/// to make a second one legible is to make it obey the same grammar.
///
/// Blue rather than the carried-over orange, and [Icons.update_rounded]
/// rather than history_rounded: one points behind you and is faintly a
/// reproach, the other points ahead and is merely information. Colouring them
/// the same would say a task you scheduled on purpose is a task you are late
/// on.
class _UpcomingChip extends StatelessWidget {
  final int count;
  final bool active;
  final VoidCallback onTap;

  const _UpcomingChip({
    required this.count,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    const color = GameColors.iconXp;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: GameMotion.standard,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: active ? color.withOpacity(0.18) : color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
            border: Border.all(
              color: color.withOpacity(active ? 0.6 : 0.3),
              width: active ? 1.2 : 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // The chip's wash and border keep the true colour; only the
              // glyph takes ink, because only the glyph has to be read.
              Icon(Icons.update_rounded, size: 13, color: gp.ink(color)),
              const SizedBox(width: 5),
              Text(
                s.matrixUpcomingCount(count),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: gp.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterSegment extends StatelessWidget {
  final Widget child;
  final bool active;
  final VoidCallback onTap;

  const _FilterSegment({
    required this.child,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    // The pill below keeps the accent as its wash; the label takes ink.
    final color = active ? gp.goldInk : gp.textSec;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: GameMotion.relaxed,
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color:
                active ? GameColors.gold.withOpacity(0.16) : Colors.transparent,
            borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: GameColors.gold.withOpacity(0.18),
                      blurRadius: 8,
                    ),
                  ]
                : null,
          ),
          child: IconTheme.merge(
            data: IconThemeData(color: color, size: 13),
            child: DefaultTextStyle.merge(
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color,
              ),
              child: AnimatedScale(
                duration: GameMotion.relaxed,
                curve: Curves.easeOutBack,
                scale: active ? 1.0 : 0.96,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AxisLabel extends StatelessWidget {
  final String label;
  final IconData icon;
  const _AxisLabel({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    // Icon and label sized to match (was icon:11/text:9 — bigger than the
    // text it sits next to, which read as slightly heavy/unbalanced next
    // to such a small caption). Equal sizing plus a touch more breathing
    // room between them reads calmer at this scale.
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 10, color: gp.textTert),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: gp.textTert,
            // Tracking disconnects joined Arabic glyphs — the same guard
            // every other small-caps label in this feature already has.
            letterSpacing: S.of(context).isAr ? 0 : 1.0,
          ),
        ),
      ],
    );
  }
}

class _RotatedAxisLabel extends StatelessWidget {
  final String label;
  const _RotatedAxisLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Center(
      child: RotatedBox(
        // Always 3 (90° counter-clockwise), for BOTH directions — and this
        // has been gotten wrong once already, so here is the geometry: the
        // text's READING START moves with the rotation. Arabic starts at
        // its right edge; 90° CCW puts that edge at the TOP, so Arabic
        // already reads top-to-bottom (its convention) with no flip.
        // English starts at its left edge, which lands at the BOTTOM —
        // bottom-to-top, the Western book-spine convention. A directional
        // flip to quarterTurns 1 under RTL (tried, reviewed, reverted)
        // moves the Arabic start to the bottom and inverts it.
        quarterTurns: 3,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: gp.textTert,
            letterSpacing: S.of(context).isAr ? 0 : 1.2,
          ),
        ),
      ),
    );
  }
}

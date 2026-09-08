import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/datetime_ext.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../../core/utils/western_digits.dart';
import '../../../shared/widgets/history_demo_gate.dart';
import '../../habits/notifiers/custom_habits_notifier.dart'
    show allHabitsEverProvider;
import '../../premium/notifiers/premium_notifier.dart';
import '../models/square_state.dart';
import '../notifiers/grid_journal_notifier.dart';
import '../notifiers/note_index_notifier.dart';
import '../widgets/habit_note_block.dart';
import '../../../shared/widgets/month_picker_sheet.dart';

/// Read-only "browse everything I've ever written or skipped, later,
/// nicely" screen for the notes and Skipped/Failed/Bonus marks left from
/// Grid's own long-press square editor (see grid_screen.dart's
/// _CellEditorSheet, where they're actually set) — the exact gap
/// grid_journal_notifier.dart's own doc comment explains. Mirrors
/// NightReviewHistoryScreen's month-at-a-time browsing shape (same visual
/// language, same "this is for looking back, not editing a past day"
/// scope — no per-entry edit action here either), adapted from a per-day
/// calendar to a reverse-chronological list since a single day can carry
/// several of these (one per habit), which a one-cell-per-day calendar
/// can't represent cleanly the way it can a single daily mood.
class GridJournalScreen extends ConsumerStatefulWidget {
  const GridJournalScreen({super.key});

  @override
  ConsumerState<GridJournalScreen> createState() => _GridJournalScreenState();
}

/// What the journal is being narrowed to.
///
/// This used to be a bare `SquareState?`, which gave a screen called
/// «ملاحظات العادات» three STATE chips and no NOTE chip. The feed is mixed
/// on purpose (a note-less تخطّي, فشل or إنجاز إضافي mark is worth browsing
/// back to on its own, see isJournalWorthy), so the one filter the screen is
/// named after was the one filter it did not have.
enum _Lens {
  all,
  hasNote,
  skipped,
  failed,
  bonus;

  SquareState? get state => switch (this) {
        _Lens.skipped => SquareState.skipped,
        _Lens.failed => SquareState.failed,
        _Lens.bonus => SquareState.bonus,
        _ => null,
      };

  /// trim() because clearing a note used to store '' rather than deleting
  /// the key, so old days carry tombstones.
  bool matches(GridJournalEntry e) => switch (this) {
        _Lens.all => true,
        _Lens.hasNote => e.note.trim().isNotEmpty,
        _ => e.state == state,
      };

  String label(S s) => switch (this) {
        _Lens.all => s.gridJournalFilterAll,
        _Lens.hasNote => s.gridJournalFilterHasNote,
        _ => s.isAr ? state!.labelAr : state!.label,
      };

  /// A selected chip is readable because of its accent, so "All" and the new
  /// note chip take emerald, the app's own selected-state colour, rather
  /// than falling back to textSec and rendering as grey on grey.
  Color accent(bool dark) =>
      state?.accent(dark) ?? GameColors.emeraldInkFor(dark);
}

class _GridJournalScreenState extends ConsumerState<GridJournalScreen> {
  // null means "All" - transient UI-only filter, never persisted, same
  // treatment PlanPickerSheet's _expandedPlanId gives its own local-only
  // selection state.
  _Lens _filter = _Lens.all;

  // Same transient, never-persisted treatment as _filter above — search text
  // AND-combines with the state-type chip filter rather than replacing it,
  // so "Failed" + "fajr" narrows to failed Fajr entries specifically.
  final _searchController = TextEditingController();
  String _query = '';

  static const List<_Lens> _filterOptions = [
    _Lens.all,
    _Lens.hasNote,
    _Lens.skipped,
    _Lens.failed,
    _Lens.bonus,
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final isAr = s.isAr;
    final locale = Localizations.localeOf(context).languageCode;
    final journal = ref.watch(gridJournalProvider);
    // westernDate, not DateFormat.yMMMM directly: this header rendered
    // "أغسطس ٢٠٢٦" while every number under it — the 18/28 rates, the day
    // numbers, the counts — was ASCII. Arabic month name, Western year.
    final monthLabel = westernDate(journal.monthStart, 'MMMM y', locale);
    final habitById = {
      // allHabitsEverProvider, not habitListProvider: the active list drops
      // archived and paused habits, so a merely paused habit's notes were
      // being labelled «عادة محذوفة». The heatmap day sheet already resolves
      // names this way.
      for (final h in ref.watch(allHabitsEverProvider)) h.id: h,
    };
    // Months that actually hold writing, newest first, and only ones this
    // account may open. Newest first so the results read in the same
    // direction the month view does, and so the likeliest hit lands first.
    // A free account is told 3 and never teased with 30.
    final isPremium = ref.watch(premiumAccessProvider);
    final today = DateTime.now().effectiveDay;
    final searchableMonths = (ref.watch(noteIndexProvider).valueOrNull ??
            const <String, Set<int>>{})
        .keys
        .map(monthFromKey)
        .whereType<DateTime>()
        .where((m) => canBrowseHistoryMonth(
              monthStart: m,
              now: today,
              isPremium: isPremium,
            ))
        .toList()
      ..sort((a, b) => b.compareTo(a));

    // The all-months results when a walk is running or done, otherwise the
    // browsed month. The browsed month stays loaded underneath either way.
    final source = journal.allMonths ?? journal.entries;
    final stateFiltered = _filter == _Lens.all
        ? source
        : source.where(_filter.matches).toList();
    final query = _query.trim().toLowerCase();
    final visible = query.isEmpty
        ? stateFiltered
        : stateFiltered.where((e) {
            final name = (habitById[e.habitId]?.localName(isAr) ??
                    s.gridJournalDeletedHabit)
                .toLowerCase();
            return name.contains(query) || e.note.toLowerCase().contains(query);
          }).toList();
    // Same-day entries are already contiguous — grid_journal_notifier.dart
    // sorts newest-day-first — so one linear pass buckets them under a
    // single header each with no re-sort or key-based grouping needed.
    final groups = <({DateTime day, List<GridJournalEntry> entries})>[];
    for (final entry in visible) {
      if (groups.isNotEmpty && groups.last.day.isSameDayAs(entry.day)) {
        groups.last.entries.add(entry);
      } else {
        groups.add((day: entry.day, entries: [entry]));
      }
    }
    final hasActiveSearch = query.isNotEmpty || _filter != _Lens.all;

    return Scaffold(
      backgroundColor: gp.bg,
      appBar: AppBar(title: Text(s.gridJournalTitle)),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  _NavArrow(
                    icon: Icons.chevron_left_rounded,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      // Same 3-month free window as the heatmap and Night
                      // Review calendar — one consistent Premium history
                      // story. See canBrowseHistoryMonth.
                      final m = journal.monthStart;
                      final target = DateTime(m.year, m.month - 1, 1);
                      if (!canBrowseHistoryMonth(
                        monthStart: target,
                        now: DateTime.now().effectiveDay,
                        isPremium: ref.read(premiumAccessProvider),
                      )) {
                        showHistoryDemoGate(context);
                        return;
                      }
                      ref.read(gridJournalProvider.notifier).previousMonth();
                    },
                  ),
                  Expanded(
                    child: Center(
                      // Tap the month to pick one. The arrows move a month
                      // per tap and say nothing about how far back the
                      // journal goes; this title used to be a caption.
                      child: InkWell(
                        onTap: () => _pickMonth(context, ref, journal),
                        borderRadius:
                            BorderRadius.circular(GameSpacing.pillRadius),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 6),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: AnimatedSwitcher(
                                  duration: GameMotion.standard,
                                  child: Text(
                                    monthLabel,
                                    key: ValueKey(monthLabel),
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      color: gp.textPrimary,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(Icons.expand_more_rounded,
                                  size: 18, color: gp.textSec),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  _NavArrow(
                    icon: Icons.chevron_right_rounded,
                    enabled: journal.canGoForward,
                    onTap: journal.canGoForward
                        ? () {
                            HapticFeedback.selectionClick();
                            ref.read(gridJournalProvider.notifier).nextMonth();
                          }
                        : null,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
              child: TextField(
                selectionWidthStyle: GameTextStyles.selectionWidthStyle,
                controller: _searchController,
                textInputAction: TextInputAction.search,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: s.gridJournalSearchHint,
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                            // Clearing the query ends the walk with it: the
                            // results are only meaningful as an answer to a
                            // question that is no longer being asked.
                            ref
                                .read(gridJournalProvider.notifier)
                                .exitAllMonths();
                          },
                        ),
                ),
              ),
            ),
            // The scope of the search, whenever one is running.
            //
            // Persistent, NOT only shown when a month comes back empty. One
            // hit in September reads as "that is everything I ever wrote"
            // unless the screen says otherwise, and a reflections search that
            // quietly under-reports is worse than none.
            if (query.isNotEmpty && searchableMonths.isNotEmpty)
              _SearchScopeLine(
                allMonths: journal.isSearchingAllMonths,
                done: journal.searchedMonths,
                total: journal.totalSearchMonths,
                monthCount: searchableMonths.length,
                onSearchAll: () {
                  HapticFeedback.selectionClick();
                  ref
                      .read(gridJournalProvider.notifier)
                      .searchAllMonths(searchableMonths);
                },
                onBackToMonth: () {
                  HapticFeedback.selectionClick();
                  ref.read(gridJournalProvider.notifier).exitAllMonths();
                },
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              // ONE row, always, and never a scrolling one.
              //
              // Five chips whose widths depend entirely on how long the words
              // happen to be in the active language: «إنجاز إضافي» and
              // "Bonus" are not the same size. At natural size they need
              // about 435pt against the 370 a 402pt phone actually has, so
              // they cannot simply be made smaller and left at that: they
              // would fit this phone in Arabic and overflow the next one, or
              // the same phone in English.
              //
              // A horizontal ListView is the wrong answer, and was rejected
              // before: the chips that do not fit are simply invisible, with
              // no scrollbar and nothing to suggest there are more, so a
              // filter can exist and never be found. Wrapping to a second
              // line was the previous answer and is what this replaces.
              //
              // FittedBox is the one that keeps every promise. It lays the
              // row out at its natural size and only scales when it has to,
              // so the metrics below are what you see on a normal phone;
              // when the words are longer, the screen narrower or the system
              // font larger, the WHOLE row scales together. That keeps one
              // font size across all five chips (per-chip scaling would give
              // «الكل» and «فيها ملاحظة» visibly different text), keeps the
              // proportions deliberate, and above all never hides a chip.
              child: SizedBox(
                width: double.infinity,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  // Start, not centre: the row reads from the same edge as
                  // the search field above it in both directions.
                  alignment: AlignmentDirectional.centerStart,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 6,
                    children: [
                  for (final option in _filterOptions)
                    _FilterChip(
                      label: option.label(s),
                      // How many entries of this kind the month holds,
                      // counted before any filtering so the numbers don't
                      // move as you tap between them. Answers "is there
                      // anything under Failed this month" without making
                      // you tap Failed and find out — and makes an empty
                      // month legible as empty rather than as broken.
                      count: option == _Lens.all
                          ? source.length
                          : source.where(option.matches).length,
                      // The three state filters carry their own accent
                      // (Skipped amber, Failed red, Bonus teal), which is
                      // what makes a selected one readable at a glance.
                      // "All" had no accent and fell back to `textSec`, so
                      // the *default* selected chip rendered as grey on
                      // grey — the one chip that's selected on arrival read
                      // as the one chip that's disabled. GameColors.emerald
                      // is the app's own selected-state colour everywhere
                      // else (nav bar, choice chips).
                      color: option.accent(gp.dark),
                      selected: _filter == option,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _filter = option);
                      },
                    ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: journal.isLoading
                  ? Center(
                      child: CircularProgressIndicator(
                          color: GameColors.gold, strokeWidth: 2))
                  : RefreshIndicator(
                      onRefresh: () =>
                          ref.read(gridJournalProvider.notifier).refresh(),
                      child: visible.isEmpty
                          // Padded and given a glyph, rather than a bare
                          // sentence pinned 60pt from the top: with no
                          // horizontal padding the text ran edge to edge
                          // across the full width of the phone, which is
                          // both hard to read and the one place on screen
                          // that looked unfinished. Still a ListView so
                          // pull-to-refresh keeps working on an empty month.
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(32, 72, 32, 24),
                              children: [
                                Icon(
                                  hasActiveSearch
                                      ? Icons.search_off_rounded
                                      : Icons.edit_note_rounded,
                                  size: 34,
                                  color: gp.textTert.withOpacity(0.6),
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  hasActiveSearch
                                      ? s.gridJournalNoResults
                                      : s.gridJournalEmpty,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: 13,
                                      height: 1.5,
                                      color: gp.textTert),
                                ),
                              ],
                            )
                          : ListView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding:
                                  const EdgeInsets.fromLTRB(16, 4, 16, 24),
                              itemCount: groups.length,
                              itemBuilder: (_, gi) {
                                final group = groups[gi];
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _DayHeader(day: group.day, locale: locale),
                                    for (var i = 0;
                                        i < group.entries.length;
                                        i++) ...[
                                      if (i != 0) const SizedBox(height: 8),
                                      _JournalEntryCard(
                                        entry: group.entries[i],
                                        habitName: habitById[
                                                group.entries[i].habitId]
                                            ?.localName(isAr),
                                        isAr: isAr,
                                      )
                                          .animate(delay: (i * 30).ms)
                                          .fadeIn(duration: 220.ms),
                                    ],
                                  ],
                                );
                              },
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Month nav arrow ─────────────────────────────────────────────────────────
// Same small building block as NightReviewHistoryScreen's own _NavArrow -
// kept as its own private copy here rather than shared, matching how this
// codebase already treats other tiny per-screen widgets (e.g. Rooms' _Tag,
// duplicated rather than factored out for something this small).

/// Opens the month picker for Habit Notes and jumps to the choice.
///
/// The journal only holds months the person actually wrote in, so the
/// picker's range runs from the earliest recorded entry - which also makes
/// "how far back does this go" answerable, something two chevrons never
/// could.
Future<void> _pickMonth(
  BuildContext context,
  WidgetRef ref,
  GridJournalState journal,
) async {
  final now = DateTime.now().effectiveDay;
  final currentMonth = DateTime(now.year, now.month, 1);
  // The note index knows every month that holds writing, which is the one
  // thing the journal itself could never work out: it loads a month at a
  // time, so its floor used to be a literal guess at today minus 365 days
  // and every unvisited month rendered as "no story yet".
  final indexed = (ref.read(noteIndexProvider).valueOrNull ??
          const <String, Set<int>>{})
      .keys
      .map(monthFromKey)
      .whereType<DateTime>()
      .toSet();
  final earliestIndexed = indexed.isEmpty
      ? null
      : indexed.reduce((a, b) => a.isBefore(b) ? a : b);
  // Still floored by the visible month and the old year window, so a month
  // reached by arrowing never drops out of the picker just because nothing
  // was written in it.
  var earliest = journal.monthStart.isBefore(currentMonth)
      ? journal.monthStart
      : currentMonth.subtract(const Duration(days: 365));
  if (earliestIndexed != null && earliestIndexed.isBefore(earliest)) {
    earliest = earliestIndexed;
  }
  final picked = await showMonthPicker(
    context,
    months: monthsBetween(earliest, currentMonth),
    selected: journal.monthStart,
    isUnlocked: (month) => canBrowseHistoryMonth(
      monthStart: month,
      now: now,
      isPremium: ref.read(premiumAccessProvider),
    ),
    // Honest for every month now, not just the loaded one. The index is
    // day-level and note-only, so it cannot see a note-less تخطّي / فشل /
    // إنجاز إضافي mark; the loaded month still answers for itself, which
    // keeps the month you are looking at exactly as truthful as before.
    hasStory: (month) =>
        indexed.any((m) => m.isSameMonthAs(month)) ||
        (month.isSameMonthAs(journal.monthStart) && journal.entries.isNotEmpty),
  );
  if (picked == null || !context.mounted) return;
  ref.read(gridJournalProvider.notifier).goToMonth(picked);
}

class _NavArrow extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool enabled;
  const _NavArrow({required this.icon, this.onTap, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Opacity(
      opacity: enabled ? 1 : 0.3,
      child: Material(
        color: gp.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GameSpacing.buttonRadius),
          side: BorderSide(color: gp.border, width: 0.5),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(GameSpacing.buttonRadius),
          onTap: onTap,
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(icon, color: gp.textSec, size: 20),
          ),
        ),
      ),
    );
  }
}

// ─── Filter chip ──────────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;

  /// Entries of this kind in the visible month. Rendered as a small trailing
  /// number so the row doubles as a summary of what the month actually
  /// holds; a chip reading 0 is dimmed rather than hidden, because which
  /// kinds are *absent* is itself worth seeing.
  final int count;
  final VoidCallback onTap;
  const _FilterChip({
    required this.label,
    required this.color,
    required this.selected,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final empty = count == 0;
    final fg = selected
        ? color
        : empty
            ? gp.textTert
            : gp.textSec;
    return InkWell(
      borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
      onTap: onTap,
      child: AnimatedContainer(
        duration: GameMotion.quick,
        // Tightened from 12/8 so all five chips fit a 402pt phone at their
        // natural size, leaving the FittedBox above with nothing to do in the
        // common case. Anything smaller starts to read as a tag rather than
        // a control.
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.16) : gp.surface,
          borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
          border: Border.all(
            color: selected ? color.withOpacity(0.5) : gp.border,
            width: selected ? 1.2 : 0.5,
          ),
        ),
        // No `alignment:` here on purpose. Container documents that setting
        // it makes the box "expand to fill its parent" — invisible inside
        // the old fixed-height horizontal ListView, but under a Wrap (which
        // hands its children loose constraints) it made every chip claim the
        // full row width and stack one per line. The Row below is
        // mainAxisSize.min, which is what actually sizes the pill.
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              // Never wraps or ellipsises: the row's FittedBox is what
              // absorbs a size the chips cannot take, so a label losing its
              // own tail here would be a second, silent answer to the same
              // problem.
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              '$count',
              textDirection: TextDirection.ltr,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: fg.withOpacity(empty ? 0.55 : 0.75),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Journal entry card ─────────────────────────────────────────────────────

class _JournalEntryCard extends StatelessWidget {
  final GridJournalEntry entry;

  /// Null when the habit's since been deleted (see GridJournalEntry's own
  /// doc comment) - falls back to S.gridJournalDeletedHabit below.
  final String? habitName;
  final bool isAr;

  const _JournalEntryCard({
    required this.entry,
    required this.habitName,
    required this.isAr,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final accent = entry.state.accent(gp.dark);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        border: Border.all(color: gp.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: entry.state.glyph(
                      size: 18,
                      dark: gp.dark,
                      color: accent,
                      fallback: Icons.circle_outlined),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  habitName ?? s.gridJournalDeletedHabit,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: habitName == null ? gp.textTert : gp.textPrimary,
                    fontStyle:
                        habitName == null ? FontStyle.italic : FontStyle.normal,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
                ),
                child: Text(
                  isAr ? entry.state.labelAr : entry.state.label,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
          if (entry.note.isNotEmpty) ...[
            const SizedBox(height: 10),
            HabitNoteBlock(note: entry.note, day: entry.day),
          ],
        ],
      ),
    );
  }
}

/// The one line that tells the truth about what was searched.
///
/// It sits under the field for the whole time a query is active rather than
/// appearing only on zero results, because the dangerous case is the opposite
/// one: a search that DOES find something in this month, while four more hits
/// sit unread in March.
class _SearchScopeLine extends StatelessWidget {
  final bool allMonths;
  final int done;
  final int total;
  final int monthCount;
  final VoidCallback onSearchAll;
  final VoidCallback onBackToMonth;

  const _SearchScopeLine({
    required this.allMonths,
    required this.done,
    required this.total,
    required this.monthCount,
    required this.onSearchAll,
    required this.onBackToMonth,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final walking = allMonths && done < total;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Row(
        children: [
          if (walking) ...[
            SizedBox(
              width: 11,
              height: 11,
              child: CircularProgressIndicator(
                strokeWidth: 1.6,
                color: GameColors.emerald,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              allMonths
                  ? s.gridJournalSearchProgress(done, total)
                  : s.gridJournalSearchThisMonth,
              style: TextStyle(fontSize: 11.5, color: gp.textSec),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: allMonths ? onBackToMonth : onSearchAll,
            borderRadius: BorderRadius.circular(GameSpacing.chipRadius),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
              child: Text(
                allMonths
                    ? s.gridJournalSearchBackToMonth
                    : s.gridJournalSearchAllMonths(monthCount),
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  // The app's own selected-state colour, not gold: gold
                  // already means premium on this screen.
                  color: context.gp.emeraldInk,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Day header ──────────────────────────────────────────────────────────────

/// One label per calendar day above that day's entries — replaces each
/// card repeating its own full date (see _JournalEntryCard above). Entries
/// arrive pre-grouped by day already (see GridJournalScreen.build's
/// `groups`), so this only ever renders once per distinct day, not once
/// per entry.
class _DayHeader extends StatelessWidget {
  final DateTime day;
  final String locale;
  const _DayHeader({required this.day, required this.locale});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final label =
        day.isToday
            ? s.navToday
            // Arabic word order and comma, ASCII digits — this rendered
            // "الأحد, يوليو ١٩" directly under a month header that already
            // read "يوليو 2026".
            : weekdayDateLabel(day, isAr: s.isAr, locale: locale);
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 14, 2, 8),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w800,
          color: gp.textSec,
        ),
      ),
    );
  }
}

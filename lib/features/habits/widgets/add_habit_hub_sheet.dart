import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/app_guide_provider.dart';
import '../../../core/theme/game_theme.dart';
import '../../../shared/widgets/habit_limit_gate.dart';
import '../../rooms/notifiers/rooms_notifier.dart' show roomsControllerProvider;
import '../../../shared/widgets/overlay_notice.dart';
import '../../../core/extensions/datetime_ext.dart';
import '../notifiers/custom_habits_notifier.dart';
import '../notifiers/habit_resume_notifier.dart';
import 'add_habit_sheet.dart';
import 'habit_actions_sheet.dart';
import 'plan_picker_sheet.dart';
import '../catalog/islamic_habit_catalog.dart';
import '../../dashboard/notifiers/dashboard_notifier.dart';
import '../catalog/habit_plans.dart';

enum HubTab { plans, addGoal }

/// Single entry point for creating a habit: one sheet split into Plan /
/// Add Goal tabs, so a new user isn't asked to guess which button does
/// what before they've seen either. [initialTab] lets a specific CTA (e.g.
/// "Browse Plans") land on the tab it promised instead of always opening
/// cold on Add Goal.
void showAddHabitHub(
  BuildContext context,
  WidgetRef ref, {
  HubTab initialTab = HubTab.addGoal,
}) {
  // At the cap, this sheet normally short-circuits straight to the paywall.
  // The exception is an account with paused habits: this sheet is the only
  // place they are listed, so short-circuiting would hide them behind the
  // very limit they are the way out of, with no way to resume or delete
  // one. Letting the sheet open costs nothing, because every path that
  // actually adds a habit gates itself again — AddHabitSheet._save,
  // PlanPickerSheet's apply, and the Resume button below all call
  // canAddHabits at the moment of the add.
  if (!canAddHabits(ref) && ref.read(pausedHabitsProvider).isEmpty) {
    showHabitLimitGate(context, ref);
    return;
  }
  HapticFeedback.lightImpact();
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    useSafeArea: true,
    builder: (_) => AddHabitHub(initialTab: initialTab),
  );
}

class AddHabitHub extends ConsumerStatefulWidget {
  final HubTab initialTab;
  const AddHabitHub({super.key, this.initialTab = HubTab.addGoal});

  @override
  ConsumerState<AddHabitHub> createState() => _AddHabitHubState();
}

class _AddHabitHubState extends ConsumerState<AddHabitHub> {
  late HubTab _tab = widget.initialTab;

  /// Step the embedded Add Goal form is on (0 = What, 1 = When).
  ///
  /// Once it moves past the first step the Plans / Add Goal switcher is
  /// hidden: the user has already chosen, and leaving the pills up both adds
  /// noise above the form and invites a tap that would throw away what they
  /// just typed.
  int _addGoalStep = 0;

  /// True while the switcher should be on screen.
  bool get _showTabs => !(_tab == HubTab.addGoal && _addGoalStep > 0);

  // A one-time nudge explaining Plans vs. Add Goal — only for App Guide's
  // addHabit lesson, since that's the one moment someone genuinely hasn't
  // decided "custom" is what they want yet. Regular Add Habit taps never
  // set this, so it doesn't nag anyone who already knows the sheet.
  late bool _showTabHint =
      ref.read(activeAppGuideLessonProvider) == AppGuideLesson.addHabit;

  void _dismissTabHint() {
    if (_showTabHint) setState(() => _showTabHint = false);
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;
    // Chrome above the tab body: drag handle + title row + tab row + spacing.
    // +130 while the tab hint is showing, for the hint card's own height
    // (icon+title row, up to 2 lines of body text, Okay button, padding on
    // both the card and its own outer gap). Measured overflow at +70 was
    // 5.2px on one real device/locale — +130 leaves real margin rather than
    // just clearing that one data point, since text wrapping varies by
    // device font scale and Arabic vs. English string length.
    // Tab row is ~54pt including its vertical padding; when it is hidden the
    // body gets that space back.
    final tabRowHeight = _showTabs ? 0.0 : -54.0;
    final chromeHeight =
        (_showTabHint ? 150.0 + 130.0 : 150.0) + tabRowHeight;
    const minBodyHeight = 220.0;
    // Resting size (no keyboard) stays ~86% of the screen, same as before.
    // Once the keyboard opens, shrink to whatever room is left above it
    // instead, so the sheet — and the focused field inside it — never end
    // up pushed off the top of the screen or hidden behind the keyboard.
    final availableHeight = bottom > 0
        ? screenHeight - bottom - chromeHeight - 16
        : screenHeight * 0.86 - chromeHeight;
    final bodyHeight = availableHeight < minBodyHeight ? minBodyHeight : availableHeight;
    const keyboardAnim = Duration(milliseconds: 220);
    const keyboardCurve = Curves.easeOutCubic;

    final body = AnimatedContainer(
      duration: keyboardAnim,
      curve: keyboardCurve,
      height: bodyHeight,
      child: IndexedStack(
        index: _tab.index,
        children: [
          const PlanPickerSheet(embedded: true),
          AddHabitSheet(
            embedded: true,
            onStepChanged: (step) => setState(() => _addGoalStep = step),
          ),
        ],
      ),
    );

    // While the hint is up, neither pill reads as "selected" and the body
    // below stays blurred — an actual tap on one is what reveals it and
    // counts as choosing, rather than Add Goal quietly already being the
    // answer before anyone's looked at Plans.
    final tabRow = Row(
      children: [
        _TabPill(
          label: s.plansTab,
          selected: !_showTabHint && _tab == HubTab.plans,
          onTap: () {
            _dismissTabHint();
            setState(() {
              _tab = HubTab.plans;
              _addGoalStep = 0;
            });
          },
        ),
        const SizedBox(width: 8),
        _TabPill(
          label: s.addGoalTitle,
          selected: !_showTabHint && _tab == HubTab.addGoal,
          onTap: () {
            _dismissTabHint();
            setState(() => _tab = HubTab.addGoal);
          },
        ),
      ],
    );

    return AnimatedPadding(
      duration: keyboardAnim,
      curve: keyboardCurve,
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: BoxDecoration(
          color: gp.surfaceHigh,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: gp.border, width: 0.5),
        ),
        // Safety net on top of the chromeHeight estimate above, not a
        // replacement for it: if the guess is ever still off (a different
        // device's font scale, a locale whose strings wrap differently),
        // this turns what would be a hard RenderFlex overflow into a sheet
        // that just becomes scrollable by that many pixels instead. A
        // no-op when the estimate is right, since there's nothing to
        // scroll — the body's own embedded content keeps scrolling
        // internally exactly as before either way.
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
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
                    color: gp.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      s.hubTitle,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: gp.textPrimary,
                        fontFamily: GameTextStyles.fontFamily,
                        fontFamilyFallback: GameTextStyles.fontFallback,
                      ),
                    ),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => Navigator.pop(context),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(Icons.close_rounded, size: 20, color: gp.textSec),
                    ),
                  ),
                ],
              ),
            ),
            // Paused habits, above the tabs so they are visible from both:
            // someone opening this sheet to "get a habit" should meet the
            // one they already built and paused before they meet the
            // catalog. Renders nothing when nothing is paused, so the
            // common case is untouched.
            const _PausedHabitsSection(),
            // Plain tab row normally; during App Guide's addHabit lesson it
            // gets the exact same pulsing gold ring CoachMarkOverlay uses on
            // every other spotlighted target, so "these two buttons are the
            // choice" reads as part of the same guided tour rather than a
            // one-off style. Kept local (not the real CoachMarkOverlay
            // widget) since that one paints a full-screen scrim positioned
            // in global coordinates — wrong here, inside a bottom sheet
            // whose own bounds move with the keyboard.
            // Hidden entirely once Add Goal has moved on — see [_showTabs].
            if (!_showTabs)
              const SizedBox.shrink()
            else _showTabHint
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: GameColors.gold.withOpacity(0.9),
                          width: 2.2,
                        ),
                      ),
                      child: tabRow,
                    ),
                  )
                    .animate(onPlay: (c) => c.repeat(reverse: true))
                    .scaleXY(
                        begin: 1,
                        end: 1.03,
                        curve: Curves.easeInOut,
                        duration: 950.ms)
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: tabRow,
                  ),
            // Card below spells out the actual choice — same icon+title+body
            // layout and gold-bordered surface as CoachMarkOverlay's card,
            // with its own "Okay" button (a clear, positive acknowledgment
            // rather than a bare close icon) instead of Skip, since picking
            // either tab already counts as choosing.
            if (_showTabHint)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                  decoration: BoxDecoration(
                    // surfaceHL, not surfaceHigh — same reasoning as
                    // CoachMarkOverlay's card: this theme's dark surfaces
                    // sit close together in luminosity, so the lighter of
                    // the two plus a real shadow gives an actually
                    // legible lift above the blur behind it, translucent
                    // enough to still read as part of that same dimmed
                    // layer rather than a fully separate opaque card.
                    color: gp.surfaceHL.withOpacity(0.72),
                    borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
                    border: Border.all(color: GameColors.gold.withOpacity(0.5)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: Icon(Icons.touch_app_rounded,
                                size: 18, color: GameColors.gold),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              s.isAr
                                  ? 'اختر إحدى الطريقتين'
                                  : 'Choose one to continue',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                height: 1.3,
                                color: gp.textPrimary,
                                fontFamily: GameTextStyles.fontFamily,
                                fontFamilyFallback: GameTextStyles.fontFallback,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        s.isAr
                            ? 'خطط: حزمة جاهزة بضغطة واحدة. إضافة هدف: عادة مخصصة من عندك.'
                            : 'Plans: a ready-made bundle in one tap. Add Goal: your own custom habit.',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.45,
                          fontWeight: FontWeight.w500,
                          color: gp.textSec,
                          fontFamily: GameTextStyles.fontFamily,
                          fontFamilyFallback: GameTextStyles.fontFallback,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: GestureDetector(
                          onTap: _dismissTabHint,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 7),
                            decoration: BoxDecoration(
                              color: GameColors.gold.withOpacity(0.14),
                              borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
                              border: Border.all(color: GameColors.gold),
                            ),
                            child: Text(
                              s.isAr ? 'حسناً' : 'Okay',
                              // Not const — GameColors.gold is a mutable
                              // static Color, not a compile-time constant.
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: GameColors.gold,
                                fontFamily: GameTextStyles.fontFamily,
                                fontFamilyFallback: GameTextStyles.fontFallback,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
                    .animate()
                    .fadeIn(duration: 300.ms, delay: 150.ms)
                    .slideY(
                        begin: -0.12,
                        end: 0,
                        duration: 300.ms,
                        curve: Curves.easeOutCubic),
              ),
            const SizedBox(height: 12),
            // Real form stays mounted underneath (both tabs' state is
            // preserved either way) — while awaiting a choice it's just
            // frosted over and tap-blocked, a genuine "blur the rest" like
            // CoachMarkOverlay's scrim elsewhere, scoped to this sheet's own
            // body instead of the full screen. Picking a tab clears
            // _showTabHint and this reverts to the plain, interactive body.
            _showTabHint
                ? Stack(
                    children: [
                      body,
                      Positioned.fill(
                        child: ClipRect(
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                            child: Container(color: gp.bg.withOpacity(0.45)),
                          ),
                        ),
                      ),
                    ],
                  )
                : body,
          ],
          ),
        ),
      ).animate().slideY(begin: 0.06, duration: 260.ms, curve: Curves.easeOutCubic).fadeIn(duration: 200.ms),
    );
  }
}

// ─── Tab pill ───────────────────────────────────────────────────────────────

class _TabPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TabPill({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(GameSpacing.buttonRadius),
        onTap: onTap,
        child: AnimatedContainer(
          duration: GameMotion.quick,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? GameColors.gold.withOpacity(0.14) : Colors.transparent,
            borderRadius: BorderRadius.circular(GameSpacing.buttonRadius),
            border: Border.all(
              color: selected ? GameColors.gold : gp.border,
              width: selected ? 1.1 : 0.8,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              color: selected ? GameColors.gold : gp.textSec,
              fontFamily: GameTextStyles.fontFamily,
              fontFamilyFallback: GameTextStyles.fontFallback,
            ),
          ),
        ),
      ),
    );
  }
}


/// The resume list: every paused habit, newest pause first, each one tap
/// from being back on the board with its whole history attached.
///
/// Lives in the Add Habit hub rather than a Settings screen because that
/// is where the intent actually arrives — nobody opens Settings thinking
/// "I want to start doing قيام again". Scroll-capped so a long pause list
/// can never push the catalog off the sheet.
class _PausedHabitsSection extends ConsumerStatefulWidget {
  const _PausedHabitsSection();

  /// How many paused habits show before the rest collapse behind "Show
  /// all". Deliberately laid out inline rather than in a fixed-height
  /// scroller: this sheet already scrolls, and a nested scroll area both
  /// fights the sheet for the same drag and clips its last row mid-card,
  /// which reads as a rendering bug rather than as "there is more here".
  static const int _collapsedCount = 3;

  @override
  ConsumerState<_PausedHabitsSection> createState() =>
      _PausedHabitsSectionState();
}

class _PausedHabitsSectionState extends ConsumerState<_PausedHabitsSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final all = ref.watch(pausedHabitsProvider);
    if (all.isEmpty) return const SizedBox.shrink();
    final totals = ref.watch(dashboardProvider).habitTotalCompletions;
    // Booked return dates. Until now the ONLY place a booking was ever shown
    // was the six-second snackbar at the moment of pausing, so once it faded
    // there was nowhere in the app to see when a habit was coming back, check
    // that the date took, or notice one still armed after the free-tier cap
    // blocked it. This list is where somebody looks for a paused habit, so it
    // is where the date belongs.
    final resumeDates = ref.watch(habitResumeScheduleProvider);
    final overflows = all.length > _PausedHabitsSection._collapsedCount;
    final paused = (_expanded || !overflows)
        ? all
        : all.take(_PausedHabitsSection._collapsedCount).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.pause_circle_outline_rounded,
                  size: 14, color: gp.textTert),
              const SizedBox(width: 6),
              Text(
                s.habitPausedSection,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: gp.textTert,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < paused.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            Builder(
              builder: (context) {
                final habit = paused[i];
                final days = totals[habit.id] ?? 0;
                return Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                  decoration: BoxDecoration(
                    color: gp.surface,
                    borderRadius:
                        BorderRadius.circular(GameSpacing.buttonRadius),
                    border: Border.all(color: gp.border, width: 0.5),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              habit.localName(s.isAr),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: gp.textPrimary,
                              ),
                            ),
                            if (days > 0) ...[
                              const SizedBox(height: 2),
                              // The reason to resume rather than start
                              // over: the days are still there.
                              Text(
                                s.habitPausedDaysBadge(days),
                                style: TextStyle(
                                    fontSize: 11, color: gp.textSec),
                              ),
                            ],
                            if (resumeDates[habit.id] case final DateTime at) ...[
                              const SizedBox(height: 2),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.event_repeat_rounded,
                                      size: 11, color: GameColors.gold),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      s.resumesOnBadge(formatResumeDate(
                                          at, s.isAr,
                                          withTime: at.hour != kDayCutoffHour ||
                                              at.minute != 0)),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: GameColors.gold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          // Resuming puts a habit back on the active list,
                          // which is an add as far as the cap is concerned.
                          // Without this a free account could pause its way
                          // under the limit, add replacements, then resume
                          // everything and sit above the cap for good.
                          if (!canAddHabits(ref)) {
                            showHabitLimitGate(context, ref);
                            return;
                          }
                          HapticFeedback.selectionClick();
                          final name = habit.localName(s.isAr);
                          if (IslamicHabitCatalog.findById(habit.id) != null) {
                            ref
                                .read(activeCatalogProvider.notifier)
                                .toggle(habit.id);
                          } else {
                            ref
                                .read(customHabitsProvider.notifier)
                                .unarchive(habit.id);
                          }
                          // Root-overlay notice, not a SnackBar: this row
                          // lives inside a modal bottom sheet, and a
                          // ScaffoldMessenger SnackBar paints *behind*
                          // that sheet — the confirmation was being shown
                          // to nobody.
                          showOverlayNotice(
                            context,
                            s.habitResumedConfirmation(name),
                            icon: Icons.play_arrow_rounded,
                          );
                        },
                        style: TextButton.styleFrom(
                          minimumSize: const Size(44, 36),
                          padding:
                              const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        // Without this every row in the list reads as the
                        // same bare "Resume", so a screen-reader user
                        // cannot tell which habit they are about to bring
                        // back. Same for the trash button below.
                        child: Semantics(
                          label: [s.habitResume, habit.localName(s.isAr)]
                              .join(s.isAr ? '، ' : ', '),
                          child: Text(
                            s.habitResume,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: GameColors.gold,
                            ),
                          ),
                        ),
                      ),
                      // Custom habits only, same rule the long-press sheet
                      // follows: a preset "deleted" here would just
                      // reappear in Plans, so the button would be lying.
                      // Without this, the paused list is a one-way door —
                      // things can only ever be added to it, and clearing
                      // out an abandoned habit means resuming it onto the
                      // board first just to delete it from there.
                      if (IslamicHabitCatalog.findById(habit.id) == null)
                        IconButton(
                          onPressed: () async {
                            final name = habit.localName(s.isAr);
                            final ok = await confirmDeleteForever(
                              context,
                              habitName: name,
                            );
                            if (!ok || !context.mounted) return;
                            // No dialog about rooms here, unlike the Grid's
                            // delete: pause already unlinks, so a habit in
                            // this list is normally linked to nothing. The
                            // call still runs for rows archived by older
                            // builds, where a stale link would otherwise
                            // outlive the habit and stall that room.
                            ref
                                .read(roomsControllerProvider)
                                .unlinkHabitEverywhere(habit.id)
                                .ignore();
                            ref
                                .read(customHabitsProvider.notifier)
                                .deleteForever(habit.id);
                            showOverlayNotice(
                              context,
                              s.habitDeletedConfirmation(name),
                              icon: Icons.delete_outline_rounded,
                            );
                          },
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints(
                              minWidth: 40, minHeight: 40),
                          padding: EdgeInsets.zero,
                          tooltip: [
                            s.habitDeleteForever,
                            habit.localName(s.isAr),
                          ].join(s.isAr ? '، ' : ', '),
                          icon: Icon(Icons.delete_outline_rounded,
                              size: 18, color: gp.textTert),
                        ),
                    ],
                  ),
                );
              },
            ),
          ],
          if (overflows)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: () {
                  HapticFeedback.selectionClick();
                  setState(() => _expanded = !_expanded);
                },
                style: TextButton.styleFrom(
                  minimumSize: const Size(44, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  _expanded
                      ? s.habitPausedShowLess
                      : s.habitPausedShowAll(all.length),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: gp.textSec,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

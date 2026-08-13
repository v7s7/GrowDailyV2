import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/app_guide_provider.dart';
import '../../../core/theme/game_theme.dart';
import '../../../shared/widgets/habit_limit_gate.dart';
import '../notifiers/custom_habits_notifier.dart';
import 'add_habit_sheet.dart';
import 'plan_picker_sheet.dart';

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
  if (!canAddHabits(ref)) {
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
    final chromeHeight = _showTabHint ? 150.0 + 130.0 : 150.0;
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
        children: const [
          PlanPickerSheet(embedded: true),
          AddHabitSheet(embedded: true),
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
            setState(() => _tab = HubTab.plans);
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
            // Plain tab row normally; during App Guide's addHabit lesson it
            // gets the exact same pulsing gold ring CoachMarkOverlay uses on
            // every other spotlighted target, so "these two buttons are the
            // choice" reads as part of the same guided tour rather than a
            // one-off style. Kept local (not the real CoachMarkOverlay
            // widget) since that one paints a full-screen scrim positioned
            // in global coordinates — wrong here, inside a bottom sheet
            // whose own bounds move with the keyboard.
            _showTabHint
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

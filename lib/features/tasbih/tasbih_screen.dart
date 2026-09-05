import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/extensions/datetime_ext.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/services/local_store_service.dart';
import '../../core/theme/game_theme.dart';
import '../../core/utils/text_moderation.dart' show foldArabic;
import '../../core/utils/western_digits.dart';
import '../dashboard/notifiers/dashboard_notifier.dart';
import '../../shared/widgets/app_snackbar.dart';
import '../grid/models/square_state.dart';
import '../grid/notifiers/weekly_grid_notifier.dart';
import '../habits/catalog/islamic_habit_catalog.dart';
import '../habits/models/habit_model.dart';
import '../habits/notifiers/custom_habits_notifier.dart';
import '../rooms/notifiers/rooms_notifier.dart';

/// The tasbih (misbaha) counter — deliberately the simplest screen in the
/// app: tap anywhere in the counting area, a haptic per tap, a target
/// (33 / 99 / custom), a reset. No stored sets, no per-dhikr model, no
/// history; the whole feature is one screen of local state plus one
/// persisted preference (the last target).
///
/// The ONLY connection to the rest of the app is offer-shaped, copied from
/// the step-link philosophy (see step_auto_complete.dart): once the target
/// is reached, IF a dhikr-looking habit is scheduled today and not done, a
/// button offers to mark it — through the exact same canonical path a
/// lock-screen "Mark Done" takes (main.dart's notification-action handler
/// is the template), so a completion from here is indistinguishable from a
/// tap on the board. Nothing ever completes silently, and with no eligible
/// habit the screen is just a counter and never mentions habits at all.
class TasbihScreen extends ConsumerStatefulWidget {
  const TasbihScreen({super.key});

  @override
  ConsumerState<TasbihScreen> createState() => _TasbihScreenState();
}

/// One Hive map, one key. Deliberately not a model class.
const _kPrefsKey = 'tasbih_prefs_v1';

/// Whether a habit reads as a dhikr habit, generously but not recklessly:
/// the true catalog category first (custom habits collapse to `faith` in
/// storage, but the template in hand still carries `athkar` for presets),
/// then a name match on unambiguous dhikr words, folded through
/// [foldArabic] so hamza and diacritic spelling variants all land. The
/// bare root «ذكر» is deliberately absent — «تذكر» (remember) contains it
/// and is a common habit word in its own right. A false positive costs one
/// dismissible button; a false negative hides the offer from exactly the
/// person it was built for. Top-level and pure so the boundary is
/// unit-testable — see test/features/tasbih/dhikr_habit_test.dart.
bool looksLikeDhikrHabit({
  required HabitCategory category,
  required String name,
}) {
  if (category == HabitCategory.athkar) return true;
  final folded = foldArabic(name.toLowerCase());
  const words = [
    'اذكار', 'تسبيح', 'سبحه', 'استغفار',
    'athkar', 'adhkar', 'dhikr', 'zikr', 'tasbih', 'tasbeeh', 'istighfar',
  ];
  return words.any(folded.contains);
}

class _TasbihScreenState extends ConsumerState<TasbihScreen> {
  int _count = 0;
  int _target = 33;

  /// Habits marked done from THIS screen this visit, so the button can
  /// keep showing a "done" confirmation after the habit stops being
  /// eligible (completing it removes it from the eligible list, which
  /// would otherwise make the button vanish the instant it worked).
  final Set<String> _markedIds = {};

  @override
  void initState() {
    super.initState();
    LocalStoreService.getSettingsMap(_kPrefsKey).then((prefs) {
      final saved = prefs['target'];
      if (saved is int && saved > 0 && mounted) {
        setState(() => _target = saved);
      }
    });
  }

  void _increment() {
    setState(() => _count++);
    // A distinct, heavier pulse on the tap that lands the target; the
    // ordinary tap stays the light click every other tap in the app uses.
    if (_count == _target) {
      HapticFeedback.heavyImpact();
    } else {
      HapticFeedback.selectionClick();
    }
  }

  void _reset() {
    if (_count == 0) return;
    final prev = _count;
    HapticFeedback.selectionClick();
    setState(() => _count = 0);
    // One stray tap on تصفير at 87 of 99 must not cost the whole session,
    // and a confirmation dialog on every reset would punish the common
    // case. The app's own correction pattern instead: do it, offer تراجع.
    // showOne, not showSnackBar — see AppSnackBar for why queueing is
    // wrong for a bar carrying an Undo.
    final s = S.of(context);
    ScaffoldMessenger.of(context).showOne(
      SnackBar(
        content: Text(s.tasbihResetDone),
        // Never pin the bar open. See AppSnackBar.
        persist: false,
        action: SnackBarAction(
          label: s.undo,
          onPressed: () {
            if (mounted) setState(() => _count = prev);
          },
        ),
      ),
    );
  }

  void _setTarget(int value) {
    HapticFeedback.selectionClick();
    setState(() => _target = value);
    LocalStoreService.putSettingsMap(_kPrefsKey, {'target': value});
  }

  Future<void> _pickCustomTarget() async {
    final s = S.of(context);
    final controller = TextEditingController(text: '$_target');
    final picked = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.tasbihCustomTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s.tasbihCustomCancel),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(context, int.tryParse(controller.text)),
            child: Text(s.tasbihCustomSet),
          ),
        ],
      ),
    );
    if (picked != null && picked > 0) _setTarget(picked);
  }

  /// Dhikr habits owed today. Empty most of the time, and then the offer
  /// row simply does not exist.
  List<IslamicHabitTemplate> _eligibleHabits() {
    final dash = ref.watch(dashboardProvider);
    final today = DateTime.now().effectiveDay;
    return [
      for (final h in ref.watch(habitListProvider))
        if (h.goalType != GoalType.quit &&
            h.isScheduledFor(today) &&
            !dash.isCompleted(h.id, h.effectiveDailyTarget) &&
            looksLikeDhikrHabit(
              category: h.category,
              name: '${h.name} ${h.nameAr ?? ''}',
            ))
          h,
    ];
  }

  /// Mirrors main.dart's Mark Done branch line for line — same boost, same
  /// all-done predicate, same square mirroring, same room sync — so a
  /// completion from the tasbih is indistinguishable from a tap on the
  /// board. The dashboard is already loaded here (this screen is only
  /// reachable from the live grid), and completeHabit's own guards refuse
  /// a still-loading or failed account anyway.
  Future<void> _markHabit(IslamicHabitTemplate habit) async {
    unawaited(HapticFeedback.mediumImpact());
    final dashState = ref.read(dashboardProvider);
    final todayHabits = ref
        .read(habitListProvider)
        .where((h) => h.isScheduledFor(DateTime.now().effectiveDay))
        .map((h) => (id: h.id, frequencyTarget: h.effectiveDailyTarget));
    final isAr = Directionality.of(context) == TextDirection.rtl;
    final perDay = habit.effectiveDailyTarget;
    final mirroredBySingleTap =
        await ref.read(dashboardProvider.notifier).completeHabit(
              habitId: habit.id,
              scheduledWeekdays: habit.scheduledWeekdays.toSet(),
              xpReward: roomBoostedReward(ref, habit.id, habit.xpReward),
              goldReward: roomBoostedReward(ref, habit.id, habit.goldReward),
              frequencyTarget: perDay,
              allHabitsDoneAfter: willCompleteAllHabitsToday(
                state: dashState,
                todayHabits: todayHabits,
                habitId: habit.id,
                frequencyTarget: perDay,
              ),
              scheduledHabitCount: todayHabits.length,
              category: habit.category.name,
              habitName: habit.localName(isAr),
            );
    if (!mounted) return;
    final today = DateTime.now().effectiveDay;
    if (mirroredBySingleTap) {
      ref
          .read(weeklyGridProvider.notifier)
          .markCompleteFromHabit(habit.id, today);
      syncRoomToday(ref, habit.id, today);
    } else if (perDay > 1) {
      // A counted habit paints its square by hand, exactly like the
      // notification handler: isGridSyncable is false for every counted
      // habit on every tap, so without this the count moved but the board
      // and the day percentage did not.
      final done = ref.read(dashboardProvider).completions[habit.id] ?? 0;
      if (done > 0) {
        ref.read(weeklyGridProvider.notifier).markResultFromHabit(
              habit.id,
              today,
              done >= perDay ? SquareState.complete : SquareState.partial,
            );
        syncRoomToday(ref, habit.id, today);
      }
    }
    setState(() => _markedIds.add(habit.id));
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final isAr = Directionality.of(context) == TextDirection.rtl;
    final reached = _count >= _target;
    final eligible = reached ? _eligibleHabits() : const <IslamicHabitTemplate>[];
    final ringColor = reached ? GameColors.gold : GameColors.emerald;

    return Scaffold(
      backgroundColor: gp.bg,
      appBar: AppBar(title: Text(s.tasbihTitle)),
      body: SafeArea(
        child: Column(
          children: [
            // The counting surface. The whole area is one target on
            // purpose: nobody should have to look at the screen mid-dhikr
            // to find a button.
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _increment,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 240,
                        height: 240,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              width: 240,
                              height: 240,
                              child: TweenAnimationBuilder<double>(
                                tween: Tween(
                                  begin: 0,
                                  end: (_count / _target).clamp(0.0, 1.0),
                                ),
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeOut,
                                builder: (context, value, _) =>
                                    CircularProgressIndicator(
                                  value: value,
                                  strokeWidth: 10,
                                  strokeCap: StrokeCap.round,
                                  color: ringColor,
                                  backgroundColor: gp.border.withOpacity(0.5),
                                ),
                              ),
                            ),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Re-keyed on every count so the number
                                // lands with a small settle-down pulse per
                                // tap — the visual half of the haptic, so
                                // counting at speed reads as beads moving
                                // rather than a label being replaced.
                                Text(
                                  toWesternDigits('$_count'),
                                  key: ValueKey(_count),
                                  style: TextStyle(
                                    fontSize: 64,
                                    fontWeight: FontWeight.w900,
                                    color: gp.textPrimary,
                                    height: 1,
                                  ),
                                )
                                    .animate()
                                    .scale(
                                      begin: const Offset(1.14, 1.14),
                                      end: const Offset(1, 1),
                                      duration: 140.ms,
                                      curve: Curves.easeOut,
                                    ),
                                const SizedBox(height: 6),
                                Text(
                                  toWesternDigits('$_target'),
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: gp.textTert,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        s.tasbihTapHint,
                        style: TextStyle(fontSize: 13, color: gp.textTert),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // The one bridge to the rest of the app. Renders nothing at
            // all until the target is reached AND a dhikr habit is owed.
            for (final habit in eligible)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _markHabit(habit),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: Text(s.tasbihMarkHabit(habit.localName(isAr))),
                  ),
                ),
              ),
            for (final id in _markedIds)
              if (!eligible.any((h) => h.id == id))
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_circle_rounded,
                        size: 16,
                        color: GameColors.emerald,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        s.tasbihMarked,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: GameColors.emerald,
                        ),
                      ),
                    ],
                  ),
                ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
              child: Row(
                children: [
                  for (final t in const [33, 99])
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: _TargetChip(
                        label: toWesternDigits('$t'),
                        selected: _target == t,
                        onTap: () => _setTarget(t),
                      ),
                    ),
                  _TargetChip(
                    label: const [33, 99].contains(_target)
                        ? s.tasbihCustom
                        : '${s.tasbihCustom} · ${toWesternDigits('$_target')}',
                    selected: !const [33, 99].contains(_target),
                    onTap: _pickCustomTarget,
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: _count == 0 ? null : _reset,
                    tooltip: s.tasbihReset,
                    icon: const Icon(Icons.replay_rounded),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TargetChip extends StatelessWidget {
  const _TargetChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Material(
      color: selected
          ? GameColors.emerald.withOpacity(gp.dark ? 0.22 : 0.14)
          : gp.surface,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? GameColors.emerald : gp.border,
              width: selected ? 1.2 : 0.5,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected ? GameColors.emerald : gp.textSec,
            ),
          ),
        ),
      ),
    );
  }
}

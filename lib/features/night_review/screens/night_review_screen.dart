import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/datetime_ext.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../achievements/models/achievement_model.dart';
import '../../dashboard/notifiers/dashboard_notifier.dart';
import '../../grid/models/square_state.dart';
import '../../grid/notifiers/weekly_grid_notifier.dart';
import '../../habits/notifiers/custom_habits_notifier.dart';
import '../models/mood.dart';
import '../notifiers/night_review_notifier.dart';

/// The evening counterpart to the morning IntentionScreen: pick a mood,
/// write a short reflection, and see the day distilled into the numbers
/// that matter — XP earned, green squares colored, and the streak they
/// protected. "How many green squares did I earn today?"
class NightReviewScreen extends ConsumerStatefulWidget {
  const NightReviewScreen({super.key});

  @override
  ConsumerState<NightReviewScreen> createState() => _NightReviewScreenState();
}

class _NightReviewScreenState extends ConsumerState<NightReviewScreen> {
  final _reflectionCtrl = TextEditingController();
  bool _hydrated = false;

  @override
  void dispose() {
    _reflectionCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    HapticFeedback.mediumImpact();
    ref.read(nightReviewProvider.notifier).setReflection(_reflectionCtrl.text);
    final ok = await ref.read(nightReviewProvider.notifier).save();
    if (!context.mounted) return;
    final s = S.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? s.nightReviewSaved : s.errGeneric),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final review = ref.watch(nightReviewProvider);

    if (!_hydrated && !review.isLoading) {
      _reflectionCtrl.text = review.reflection;
      _hydrated = true;
    }

    final habits = ref.watch(habitListProvider);
    final dash = ref.watch(dashboardProvider);
    final grid = ref.watch(weeklyGridProvider);
    final today = DateTime.now();

    var gridXpToday = 0;
    var greenToday = 0;
    final todayRow = grid.states[today.toDateKey()];
    if (todayRow != null) {
      for (final h in habits) {
        final sq = todayRow[h.id] ?? SquareState.none;
        gridXpToday += sq.xpValue;
        if (sq.isGreen) greenToday++;
      }
    }
    var habitListXpToday = 0;
    for (final h in habits) {
      habitListXpToday += (dash.completions[h.id] ?? 0) * h.xpReward;
    }
    final totalXpToday = gridXpToday + habitListXpToday;

    return Scaffold(
      backgroundColor: gp.bg,
      appBar: AppBar(title: Text(s.nightReviewTitle)),
      body: SafeArea(
        child: review.isLoading
            ? const Center(
                child: CircularProgressIndicator(
                    color: GameColors.gold, strokeWidth: 2))
            : SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: GameColors.xpBlue.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.nightlight_round,
                              color: GameColors.xpBlue, size: 22),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s.nightReviewPromptTitle,
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: gp.textPrimary,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                s.nightReviewPromptDesc,
                                style: TextStyle(
                                    fontSize: 12.5,
                                    color: gp.textSec,
                                    height: 1.35),
                              ),
                            ],
                          ),
                        ),
                        if (review.saved)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: GameColors.emerald.withOpacity(0.14),
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: Text(
                              s.nightReviewDoneBadge,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: GameColors.emerald,
                              ),
                            ),
                          ),
                      ],
                    ).animate().fadeIn(duration: 350.ms),
                    const SizedBox(height: 28),
                    Text(
                      s.nightReviewMoodQuestion.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: gp.textSec,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        for (final mood in Mood.values)
                          _MoodButton(
                            mood: mood,
                            selected: review.mood == mood,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              ref
                                  .read(nightReviewProvider.notifier)
                                  .setMood(mood);
                            },
                          ),
                      ],
                    ).animate(delay: 80.ms).fadeIn().slideY(begin: 0.1),
                    const SizedBox(height: 28),
                    Text(
                      s.nightReviewReflectionLabel,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: gp.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _reflectionCtrl,
                      maxLines: 4,
                      minLines: 3,
                      style: TextStyle(fontSize: 14, color: gp.textPrimary),
                      decoration: InputDecoration(
                        hintText: s.nightReviewReflectionHint,
                      ),
                    ).animate(delay: 140.ms).fadeIn(),
                    const SizedBox(height: 28),
                    Text(
                      s.nightReviewSummaryTitle.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: gp.textSec,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: gp.surface,
                        borderRadius:
                            BorderRadius.circular(GameSpacing.cardRadius),
                        border: Border.all(color: gp.border, width: 0.5),
                      ),
                      child: Row(
                        children: [
                          _SummaryStat(
                            icon: Icons.bolt_rounded,
                            color: GameColors.xpBlue,
                            value: '$totalXpToday',
                            label: s.nightReviewXpEarned,
                          ),
                          _SummaryDivider(),
                          _SummaryStat(
                            icon: Icons.grid_view_rounded,
                            color: GameColors.emerald,
                            value: '$greenToday',
                            label: s.nightReviewGreenSquares,
                          ),
                          _SummaryDivider(),
                          _SummaryStat(
                            icon: Icons.local_fire_department_rounded,
                            color: GameColors.streakOrange,
                            value: '${dash.streak}',
                            label: s.nightReviewStreak,
                          ),
                          _SummaryDivider(),
                          _SummaryStat(
                            icon: Icons.emoji_events_rounded,
                            color: GameColors.gold,
                            value:
                                '${dash.unlockedAchievements.length}/${AchievementCatalog.all.length}',
                            label: s.achievements,
                          ),
                        ],
                      ),
                    ).animate(delay: 200.ms).fadeIn().slideY(begin: 0.08),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed:
                            review.mood == null ? null : _save,
                        child: Text(s.nightReviewSave),
                      ),
                    ).animate(delay: 260.ms).fadeIn(),
                    if (review.saved) ...[
                      const SizedBox(height: 10),
                      Text(
                        s.nightReviewEditedHint,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11, color: gp.textTert),
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}

class _MoodButton extends StatelessWidget {
  final Mood mood;
  final bool selected;
  final VoidCallback onTap;
  const _MoodButton(
      {required this.mood, required this.selected, required this.onTap});

  /// Each mood gets its own tinted Material face — icon-based, not emoji.
  (IconData, Color) get _visual => switch (mood) {
        Mood.great =>
          (Icons.sentiment_very_satisfied_rounded, GameColors.emerald),
        Mood.good => (Icons.sentiment_satisfied_rounded, GameColors.xpBlue),
        Mood.neutral => (Icons.sentiment_neutral_rounded, GameColors.warning),
        Mood.sad =>
          (Icons.sentiment_dissatisfied_rounded, GameColors.streakOrange),
        Mood.exhausted =>
          (Icons.sentiment_very_dissatisfied_rounded, GameColors.error),
      };

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final (icon, color) = _visual;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedScale(
            scale: selected ? 1.12 : 1.0,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutBack,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: selected ? color.withOpacity(0.16) : gp.surface,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? color : gp.border,
                  width: selected ? 1.6 : 0.5,
                ),
              ),
              alignment: Alignment.center,
              child: Icon(
                icon,
                size: 30,
                color: selected ? color : gp.textSec,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            mood.label(s.isAr),
            style: TextStyle(
              fontSize: 10,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
              color: selected ? color : gp.textTert,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  const _SummaryStat({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: gp.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 9, color: gp.textTert),
          ),
        ],
      ),
    );
  }
}

class _SummaryDivider extends StatelessWidget {
  const _SummaryDivider();

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Container(
      width: 0.5,
      height: 40,
      color: gp.border,
      margin: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}

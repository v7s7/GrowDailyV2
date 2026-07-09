import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../achievements/models/achievement_model.dart';
import '../../dashboard/notifiers/dashboard_notifier.dart';

/// Full achievement catalog — pushed from Profile's "Achievements" row so
/// the grid (a dozen-plus cards) doesn't have to live inline on Profile.
/// Unlocked achievements sort first; nothing here needs the "preview +
/// view all" collapse Profile used to do, since this screen has nothing
/// else competing for space.
class AchievementsScreen extends ConsumerWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final state = ref.watch(dashboardProvider);
    final unlockedIds = state.unlockedAchievements;
    final sorted = [
      ...AchievementCatalog.all.where((a) => unlockedIds.contains(a.id)),
      ...AchievementCatalog.all.where((a) => !unlockedIds.contains(a.id)),
    ];

    return Scaffold(
      backgroundColor: gp.bg,
      appBar: AppBar(
        backgroundColor: gp.bg,
        surfaceTintColor: Colors.transparent,
        title: Text(s.achievementsRowTitle,
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: gp.textPrimary)),
      ),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
                child: Container(
                  height: 130,
                  width: double.infinity,
                  color: const Color(0xFFFEFAF0),
                  child: Image.asset(
                    'assets/images/achievement_celebration_burst.png',
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                  ),
                ),
              ),
            ).animate().fadeIn(duration: 400.ms),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Row(
                children: [
                  Text(s.achievements,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: gp.textSec,
                          letterSpacing: 1.5)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: GameColors.gold.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      '${unlockedIds.length} / ${AchievementCatalog.all.length}',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: GameColors.gold),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 0.78,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) => _AchievementCard(
                  achievement: sorted[i],
                  isUnlocked: unlockedIds.contains(sorted[i].id),
                  state: state,
                ).animate(delay: (i * 35).ms).fadeIn(duration: 300.ms).slideY(begin: 0.08),
                childCount: sorted.length,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Achievement Card ─────────────────────────────────────────────────────────

class _AchievementCard extends StatelessWidget {
  final AchievementModel achievement;
  final bool isUnlocked;
  final DashboardState state;
  const _AchievementCard(
      {required this.achievement,
      required this.isUnlocked,
      required this.state});

  Color get _color => switch (achievement.rarity) {
        AchievementRarity.common => GameColors.rarityCommon,
        AchievementRarity.uncommon => GameColors.rarityUncommon,
        AchievementRarity.rare => GameColors.rarityRare,
        AchievementRarity.epic => GameColors.rarityEpic,
        AchievementRarity.legendary => GameColors.rarityLegendary,
      };

  IconData get _icon => switch (achievement.trigger) {
        AchievementTrigger.streak =>
          Icons.local_fire_department_rounded,
        AchievementTrigger.level => Icons.bolt_rounded,
        AchievementTrigger.totalCompletions =>
          Icons.check_circle_rounded,
        AchievementTrigger.habitMastery => Icons.menu_book_rounded,
        AchievementTrigger.greenSquares => Icons.grid_view_rounded,
        _ => Icons.stars_rounded,
      };

  double get _progress => switch (achievement.trigger) {
        AchievementTrigger.streak =>
          (state.streak / achievement.threshold).clamp(0.0, 1.0),
        AchievementTrigger.level =>
          (state.level / achievement.threshold).clamp(0.0, 1.0),
        AchievementTrigger.totalCompletions =>
          (state.totalCompletions / achievement.threshold)
              .clamp(0.0, 1.0),
        AchievementTrigger.greenSquares =>
          (state.totalGreenSquares / achievement.threshold).clamp(0.0, 1.0),
        AchievementTrigger.habitMastery =>
          ((state.categoryCompletions[achievement.targetCategory] ?? 0) /
                  achievement.threshold)
              .clamp(0.0, 1.0),
        _ => 0.0,
      };

  int get _current => switch (achievement.trigger) {
        AchievementTrigger.streak => state.streak,
        AchievementTrigger.level => state.level,
        AchievementTrigger.totalCompletions => state.totalCompletions,
        AchievementTrigger.greenSquares => state.totalGreenSquares,
        AchievementTrigger.habitMastery =>
          state.categoryCompletions[achievement.targetCategory] ?? 0,
        _ => 0,
      };

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final c = _color;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        border: Border.all(
          color: isUnlocked ? c.withOpacity(0.5) : gp.border,
          width: isUnlocked ? 1 : 0.5,
        ),
      ),
      child: Opacity(
        opacity: isUnlocked ? 1.0 : 0.55,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: (isUnlocked ? c : gp.textTert)
                        .withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(_icon,
                      size: 18,
                      color: isUnlocked ? c : gp.textTert),
                ),
                const Spacer(),
                if (isUnlocked)
                  Icon(Icons.verified_rounded, size: 16, color: c),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              achievement.name,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: gp.textPrimary,
                  height: 1.25),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              s.isAr
                  ? achievement.rarity.localizedName(true)
                  : achievement.rarity.localizedName(false).toUpperCase(),
              style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: c,
                  // Same reasoning as the milestone-celebration fix: wide
                  // letter-spacing breaks Arabic cursive letter-joining.
                  letterSpacing: s.isAr ? 0 : 1.2),
            ),
            const SizedBox(height: 10),
            if (isUnlocked)
              Row(children: [
                if (achievement.xpReward > 0) ...[
                  Icon(Icons.bolt_rounded,
                      size: 11, color: GameColors.xpBlue),
                  const SizedBox(width: 2),
                  Text('+${achievement.xpReward}',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: GameColors.xpBlue)),
                  const SizedBox(width: 8),
                ],
                if (achievement.goldReward > 0) ...[
                  Icon(Icons.toll_rounded,
                      size: 11, color: GameColors.gold),
                  const SizedBox(width: 2),
                  Text('+${achievement.goldReward}',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: GameColors.gold)),
                ],
              ])
            else ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(100),
                child: LinearProgressIndicator(
                  value: _progress,
                  backgroundColor: gp.border,
                  valueColor:
                      AlwaysStoppedAnimation(c.withOpacity(0.5)),
                  minHeight: 3,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '$_current / ${achievement.threshold}',
                style: TextStyle(
                    fontSize: 10,
                    color: gp.textTert,
                    fontWeight: FontWeight.w500),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

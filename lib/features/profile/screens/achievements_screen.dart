import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../achievements/models/achievement_model.dart';
import '../../achievements/widgets/achievement_medal.dart';
import '../../dashboard/notifiers/dashboard_notifier.dart';

/// Full achievement catalog — pushed from Profile's "Achievements" row so
/// the family ladders (five cards, each a full bronze-to-platinum climb)
/// don't have to live inline on Profile.
///
/// Redesigned from a flat 2-column grid of 20 same-ish cards into five
/// family cards, each showing all four medals in one row — the flat grid
/// answered "what have I unlocked", but never "what's actually next and
/// how far away is it" without opening every single card's own progress
/// bar one at a time. A family card answers both at a glance: the medal
/// row shows the whole climb, and the text underneath names exactly what
/// the next rung costs.
class AchievementsScreen extends ConsumerWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final state = ref.watch(dashboardProvider);
    final unlockedIds = state.unlockedAchievements;
    final families = AchievementCatalog.families;

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
            sliver: SliverList.separated(
              itemCount: families.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) => _FamilyCard(
                family: families[i],
                tiers: AchievementCatalog.tiersFor(families[i].id),
                unlockedIds: unlockedIds,
                state: state,
              ).animate(delay: (i * 60).ms).fadeIn(duration: 320.ms).slideY(begin: 0.06),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Family ladder card ───────────────────────────────────────────────────

class _FamilyCard extends StatelessWidget {
  final AchievementFamily family;
  final List<AchievementModel> tiers; // bronze → platinum, length 4
  final List<String> unlockedIds;
  final DashboardState state;

  const _FamilyCard({
    required this.family,
    required this.tiers,
    required this.unlockedIds,
    required this.state,
  });

  int _currentFor(AchievementModel a) => switch (a.trigger) {
        AchievementTrigger.streak => state.streak,
        AchievementTrigger.level => state.level,
        AchievementTrigger.totalCompletions => state.totalCompletions,
        AchievementTrigger.greenSquares => state.totalGreenSquares,
        AchievementTrigger.habitMastery =>
          state.categoryCompletions[a.targetCategory] ?? 0,
        AchievementTrigger.special => 0,
      };

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final isAr = s.isAr;
    final unlockedCount = tiers.where((t) => unlockedIds.contains(t.id)).length;
    // The tier the card's text focuses on: the next locked one, or the
    // last (platinum) tier once every rung is climbed — there's always
    // something to show, never a dead "nothing to say" state.
    final activeTier = unlockedCount < tiers.length
        ? tiers[unlockedCount]
        : tiers.last;
    final mastered = unlockedCount == tiers.length;
    final current = _currentFor(activeTier);
    final progress = (current / activeTier.threshold).clamp(0.0, 1.0);
    final activeColor = switch (activeTier.tier) {
      AchievementTier.bronze => GameColors.tierBronze,
      AchievementTier.silver => GameColors.tierSilver,
      AchievementTier.gold => GameColors.tierGold,
      AchievementTier.platinum => GameColors.tierPlatinum,
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        border: Border.all(
          color: mastered ? activeColor.withOpacity(0.45) : gp.border,
          width: mastered ? 1 : 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(family.icon, size: 16, color: gp.textSec),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  family.localTitle(isAr),
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: gp.textPrimary),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: (mastered ? activeColor : gp.textTert)
                      .withOpacity(0.15),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  '$unlockedCount/${tiers.length}',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: mastered ? activeColor : gp.textSec),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final tier in tiers)
                AchievementMedal(
                  tier: tier.tier,
                  icon: achievementIconFor(tier.trigger),
                  size: 50,
                  state: unlockedIds.contains(tier.id)
                      ? MedalState.unlocked
                      : tier.id == activeTier.id
                          ? MedalState.inProgress
                          : MedalState.locked,
                  progress: tier.id == activeTier.id ? progress : 0,
                ),
            ],
          ),
          const SizedBox(height: 14),
          Container(height: 0.5, color: gp.border),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      activeTier.tier.localizedName(isAr).toUpperCase(),
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: activeColor,
                          letterSpacing: isAr ? 0 : 1.2),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      activeTier.localName(isAr),
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: gp.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      activeTier.localDescription(isAr),
                      style: TextStyle(fontSize: 11.5, color: gp.textSec),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (mastered)
                Icon(Icons.verified_rounded, size: 20, color: activeColor)
              else
                Text(
                  '$current / ${activeTier.threshold}',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: gp.textSec),
                ),
            ],
          ),
          if (!mastered) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(100),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: gp.border,
                valueColor: AlwaysStoppedAnimation(activeColor.withOpacity(0.7)),
                minHeight: 4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../../core/utils/bidi_fraction.dart';
import '../../achievements/models/achievement_model.dart';
import '../../achievements/widgets/achievement_medal.dart';
import '../../achievements/widgets/tier_detail_sheet.dart';
import '../../achievements/widgets/tier_palette.dart';
import '../../dashboard/notifiers/dashboard_notifier.dart';

/// Full achievement catalog — pushed from Profile's "Achievements" row so
/// the family ladders (five cards, each a full bronze-to-platinum climb)
/// don't have to live inline on Profile.
///
/// The screen is organised around one question — *what do I do next* — and
/// answers it three times at decreasing zoom:
///
///  1. the trophy case, "how far in am I overall, and in which metals";
///  2. the Next-up spotlight, "of all twenty, this is the single closest
///     one and here is exactly how much is left";
///  3. the five family ladders, "here is every climb and where I am on it".
///
/// Replaces a layout whose first 130 vertical points were a decorative
/// clip-art PNG (a star and confetti, `BoxFit.cover`-cropped from a 583 KB
/// 955x883 image into a wide strip) that said nothing about this account,
/// followed by a section header repeating the word already in the app bar —
/// `S.achievements` and `S.achievementsRowTitle` are both 'الإنجازات' in
/// Arabic. Both are gone; the space they held is now the summary that
/// earns it.
///
/// Every tier is also reachable now: each of the twenty medals opens
/// [showTierDetailSheet]. Before, only the single *active* tier of each
/// family was ever named on screen, so what Gold or Platinum actually
/// required — the thing worth aiming at — was unreadable until you'd
/// already earned the two rungs below it.
class AchievementsScreen extends ConsumerWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final state = ref.watch(dashboardProvider);
    final unlockedIds = state.unlockedAchievements;
    final stats = state.achievementStats;
    final families = AchievementCatalog.families;
    final total = AchievementCatalog.all.length;

    // The one locked achievement closest to done, across every family —
    // ranked by fraction-of-threshold rather than by raw remaining count so
    // "6 of 25" outranks "96 of 2000". Null once everything is unlocked.
    final spotlight = AchievementCatalog.locked(unlockedIds)
        .where((a) => a.trigger != AchievementTrigger.special)
        .fold<AchievementModel?>(
      null,
      (best, a) => best == null ||
              stats.progressFor(a) > stats.progressFor(best)
          ? a
          : best,
    );

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
              padding: const EdgeInsets.fromLTRB(
                  GameSpacing.lg, GameSpacing.sm, GameSpacing.lg, 0),
              child: _TrophyCase(unlockedIds: unlockedIds, total: total)
                  .animate()
                  .fadeIn(duration: 360.ms)
                  .slideY(begin: 0.08, curve: Curves.easeOutCubic),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  GameSpacing.lg, GameSpacing.md, GameSpacing.lg, 0),
              child: _NextUpCard(spotlight: spotlight, stats: stats)
                  .animate(delay: 90.ms)
                  .fadeIn(duration: 360.ms)
                  .slideY(begin: 0.08, curve: Curves.easeOutCubic),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(GameSpacing.lg, GameSpacing.xl,
                GameSpacing.lg, GameSpacing.sm),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  Icon(Icons.touch_app_rounded, size: 13, color: gp.textTert),
                  const SizedBox(width: 6),
                  Text(s.achievementsTapTierHint,
                      style: TextStyle(fontSize: 11.5, color: gp.textTert)),
                ],
              ).animate(delay: 160.ms).fadeIn(duration: 320.ms),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
                GameSpacing.lg, 0, GameSpacing.lg, GameSpacing.xxl),
            sliver: SliverList.separated(
              itemCount: families.length,
              separatorBuilder: (_, __) => const SizedBox(height: GameSpacing.md),
              itemBuilder: (context, i) => _FamilyCard(
                family: families[i],
                tiers: AchievementCatalog.tiersFor(families[i].id),
                unlockedIds: unlockedIds,
                stats: stats,
              )
                  .animate(delay: (200 + i * 70).ms)
                  .fadeIn(duration: 340.ms)
                  .slideY(begin: 0.08, curve: Curves.easeOutCubic),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Trophy case header ───────────────────────────────────────────────────

/// Total earned, the four per-tier tallies, and one overall bar.
class _TrophyCase extends StatelessWidget {
  final List<String> unlockedIds;
  final int total;

  const _TrophyCase({required this.unlockedIds, required this.total});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final earned = unlockedIds.length;
    final counts = AchievementCatalog.tierCounts(unlockedIds);
    final ratio = total == 0 ? 0.0 : earned / total;

    return Container(
      padding: const EdgeInsets.all(GameSpacing.lg),
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        border: Border.all(color: gp.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Count-up rather than a static number — the one place on the
              // screen where a running total is the headline, so it's worth
              // the beat of motion.
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: earned.toDouble()),
                duration: 700.ms,
                curve: Curves.easeOutCubic,
                builder: (_, v, __) => Text(
                  '${v.round()}',
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                      fontSize: 34,
                      height: 1,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1,
                      color: gp.textPrimary),
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '/$total',
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: gp.textTert),
                ),
              ),
              const SizedBox(width: GameSpacing.md),
              Expanded(
                child: Text(
                  s.achievementsMedalsEarned,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: gp.textSec),
                ),
              ),
              if (earned == total)
                Icon(Icons.workspace_premium_rounded,
                    size: 24, color: TierPalette.from(
                        context, AchievementTier.platinum).ink),
            ],
          ),
          const SizedBox(height: GameSpacing.md),
          AchievementProgressBar(value: ratio, color: gp.textSec, height: 6),
          const SizedBox(height: GameSpacing.lg),
          Row(
            children: [
              for (final tier in AchievementTier.values) ...[
                Expanded(
                  child: _TierTally(tier: tier, count: counts[tier] ?? 0),
                ),
                if (tier != AchievementTier.platinum)
                  const SizedBox(width: GameSpacing.sm),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// One "🥉 2" cell of the trophy case's tier tally row.
class _TierTally extends StatelessWidget {
  final AchievementTier tier;
  final int count;

  const _TierTally({required this.tier, required this.count});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final p = TierPalette.from(context, tier);
    final has = count > 0;

    return Semantics(
      label: '${tier.localizedName(s.isAr)}: $count',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: GameSpacing.sm),
        decoration: BoxDecoration(
          color: has ? p.ink.withOpacity(0.10) : gp.textTert.withOpacity(0.06),
          borderRadius: BorderRadius.circular(GameSpacing.buttonRadius),
        ),
        child: Column(
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: has
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [p.shine, p.base, p.deep],
                        stops: const [0.0, 0.55, 1.0],
                      )
                    : null,
                color: has ? null : gp.textTert.withOpacity(0.18),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              '$count',
              textDirection: TextDirection.ltr,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  color: has ? p.ink : gp.textTert),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Next-up spotlight ────────────────────────────────────────────────────

/// The single closest locked achievement, with the number that actually
/// answers "what do I do next" — how many are *left*, not how many are done.
class _NextUpCard extends StatelessWidget {
  final AchievementModel? spotlight;
  final AchievementStats stats;

  const _NextUpCard({required this.spotlight, required this.stats});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final isAr = s.isAr;
    final a = spotlight;

    if (a == null) {
      return Container(
        padding: const EdgeInsets.all(GameSpacing.lg),
        decoration: BoxDecoration(
          color: gp.surface,
          borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
          border: Border.all(
              color: TierPalette.from(context, AchievementTier.platinum)
                  .ink
                  .withOpacity(0.4)),
        ),
        child: Row(
          children: [
            Icon(Icons.workspace_premium_rounded,
                size: 22,
                color: TierPalette.from(context, AchievementTier.platinum).ink),
            const SizedBox(width: GameSpacing.md),
            Expanded(
              child: Text(s.achievementsAllDone,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: gp.textPrimary)),
            ),
          ],
        ),
      );
    }

    final p = TierPalette.from(context, a.tier);
    final current = stats.currentFor(a);
    final progress = stats.progressFor(a);
    final remaining = (a.threshold - current).clamp(0, a.threshold);

    return _Pressable(
      onTap: () => showTierDetailSheet(context, a, stats, unlocked: false),
      child: Container(
        padding: const EdgeInsets.all(GameSpacing.lg),
        decoration: BoxDecoration(
          color: gp.surface,
          borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
          border: Border.all(color: p.ink.withOpacity(0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.flag_rounded, size: 13, color: p.ink),
                const SizedBox(width: 6),
                Text(
                  s.achievementsNextUp,
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: p.ink,
                      letterSpacing: isAr ? 0 : 1.2),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: GameSpacing.sm, vertical: 3),
                  decoration: BoxDecoration(
                    color: p.ink.withOpacity(0.14),
                    borderRadius:
                        BorderRadius.circular(GameSpacing.pillRadius),
                  ),
                  child: Text(
                    s.achievementsRemaining(remaining),
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: p.ink),
                  ),
                ),
              ],
            ),
            const SizedBox(height: GameSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                AchievementMedal(
                  tier: a.tier,
                  icon: achievementIconFor(a.trigger),
                  size: 54,
                  state: MedalState.inProgress,
                  progress: progress,
                  semanticLabel: medalSemanticLabel(
                    achievement: a,
                    state: MedalState.inProgress,
                    current: current,
                    isAr: isAr,
                  ),
                ),
                const SizedBox(width: GameSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        a.localName(isAr),
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: gp.textPrimary),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        a.localDescription(isAr),
                        style: TextStyle(fontSize: 12, color: gp.textSec),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: GameSpacing.md),
            AchievementProgressBar(value: progress, color: p.ink),
            const SizedBox(height: 6),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Text(
                progressFraction(current, a.threshold),
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: gp.textTert),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Family ladder card ───────────────────────────────────────────────────

class _FamilyCard extends StatelessWidget {
  final AchievementFamily family;
  final List<AchievementModel> tiers; // bronze → platinum, length 4
  final List<String> unlockedIds;
  final AchievementStats stats;

  const _FamilyCard({
    required this.family,
    required this.tiers,
    required this.unlockedIds,
    required this.stats,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final isAr = s.isAr;
    final unlockedCount = tiers.where((t) => unlockedIds.contains(t.id)).length;

    // The tier the card's text focuses on: the next locked one, or the last
    // (platinum) rung once every one is climbed — there's always something
    // to show, never a dead "nothing to say" state. Resolved by identity
    // via the catalog rather than by indexing `tiers[unlockedCount]`, which
    // silently describes the wrong rung whenever the ladder has a gap in it
    // — see AchievementCatalog.nextLockedIn.
    final next = AchievementCatalog.nextLockedIn(family.id, unlockedIds);
    final mastered = next == null;
    final activeTier = next ?? tiers.last;
    final p = TierPalette.from(context, activeTier.tier);
    final current = stats.currentFor(activeTier);
    final progress = stats.progressFor(activeTier);

    return Container(
      padding: const EdgeInsets.all(GameSpacing.lg),
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        border: Border.all(
          color: mastered ? p.ink.withOpacity(0.45) : gp.border,
          width: mastered ? 1 : 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(family.icon, size: 16, color: mastered ? p.ink : gp.textSec),
              const SizedBox(width: GameSpacing.sm),
              Expanded(
                child: Text(
                  family.localTitle(isAr),
                  style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: gp.textPrimary),
                ),
              ),
              if (mastered) ...[
                Icon(Icons.verified_rounded, size: 16, color: p.ink),
                const SizedBox(width: 5),
              ],
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: (mastered ? p.ink : gp.textTert).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
                ),
                child: Text(
                  // Tight form, no spaces: the spaced variant needs the bidi
                  // isolate to survive an RTL paragraph, the tight one is a
                  // single numeric run and doesn't (see bidi_fraction.dart).
                  progressFraction(unlockedCount, tiers.length,
                      separator: '/'),
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: mastered ? p.ink : gp.textSec),
                ),
              ),
            ],
          ),
          const SizedBox(height: GameSpacing.lg),
          // Every slot is AchievementMedal.slotFor(50) wide whatever state
          // it's in, so the four medals sit on the same pitch in every card
          // — the in-progress ring used to make its own slot 8pt wider and
          // shove the whole row out of alignment.
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final tier in tiers)
                _LadderMedal(
                  achievement: tier,
                  isUnlocked: unlockedIds.contains(tier.id),
                  isNext: tier.id == activeTier.id && !mastered,
                  stats: stats,
                ),
            ],
          ),
          const SizedBox(height: GameSpacing.lg),
          Container(height: 0.5, color: gp.border),
          const SizedBox(height: GameSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mastered
                          ? s.achievementsMastered.toUpperCase()
                          : activeTier.tier.localizedName(isAr).toUpperCase(),
                      style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: p.ink,
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
              const SizedBox(width: GameSpacing.md),
              if (mastered)
                Icon(Icons.workspace_premium_rounded, size: 20, color: p.ink)
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      progressFraction(current, activeTier.threshold),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: gp.textSec),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      s.achievementsRemaining(
                          (activeTier.threshold - current)
                              .clamp(0, activeTier.threshold)),
                      style: TextStyle(fontSize: 10.5, color: gp.textTert),
                    ),
                  ],
                ),
            ],
          ),
          if (!mastered) ...[
            const SizedBox(height: GameSpacing.sm),
            AchievementProgressBar(value: progress, color: p.ink),
          ],
        ],
      ),
    );
  }
}

/// One tappable rung of a family ladder.
class _LadderMedal extends StatelessWidget {
  final AchievementModel achievement;
  final bool isUnlocked;
  final bool isNext;
  final AchievementStats stats;

  const _LadderMedal({
    required this.achievement,
    required this.isUnlocked,
    required this.isNext,
    required this.stats,
  });

  @override
  Widget build(BuildContext context) {
    final isAr = S.of(context).isAr;
    final state = isUnlocked
        ? MedalState.unlocked
        : isNext
            ? MedalState.inProgress
            : MedalState.locked;
    final current = stats.currentFor(achievement);

    return _Pressable(
      onTap: () => showTierDetailSheet(context, achievement, stats,
          unlocked: isUnlocked),
      child: AchievementMedal(
        tier: achievement.tier,
        icon: achievementIconFor(achievement.trigger),
        size: 50,
        state: state,
        progress: isNext ? stats.progressFor(achievement) : 0,
        semanticLabel: medalSemanticLabel(
          achievement: achievement,
          state: state,
          current: current,
          isAr: isAr,
        ),
      ),
    );
  }
}

// ─── Shared bits ──────────────────────────────────────────────────────────

/// Tap target with a small scale-down press response.
///
/// A plain InkWell splash reads wrong on a circular medal sitting on a
/// card — it paints a rectangle behind it — so the feedback is the medal
/// itself dipping instead.
class _Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const _Pressable({required this.child, required this.onTap});

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        child: AnimatedScale(
          scale: _down ? 0.94 : 1,
          duration: GameMotion.quick,
          curve: Curves.easeOut,
          child: widget.child,
        ),
      );
}

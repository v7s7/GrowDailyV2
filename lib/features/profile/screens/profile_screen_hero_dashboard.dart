part of 'profile_screen.dart';


// ─── Hero Header ─────────────────────────────────────────────────────────────

class _HeroHeader extends ConsumerWidget {
  final DashboardState state;
  final String displayName;
  const _HeroHeader({required this.state, required this.displayName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final charState = ref.watch(characterProvider);
    // Level Prestige System: a separate cosmetic lane from the character/
    // accessory closet above — see PrestigeState's own doc comment. Reads
    // only state.level (already in scope, already loaded) to resolve which
    // tier is showing; equipping a different unlocked tier happens in
    // PrestigePickerSheet, opened from the title chip below.
    final prestigeTier =
        ref.watch(prestigeProvider).displayedTier(state.level);
    // Only tint the card once a tier beyond the base "Seeker" (Level 1,
    // everyone's default) is showing — an untinted card for a brand-new
    // account keeps this feeling like a genuine milestone, not a color
    // that's just always been there.
    final showsPrestigeTint = prestigeTier.minLevel > 1;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        border: Border.all(
          color: showsPrestigeTint
              ? prestigeTier.color.withOpacity(0.45)
              : gp.border,
          width: showsPrestigeTint ? 1 : 0.5,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
            onTap: () {
              HapticFeedback.selectionClick();
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const CharacterClosetScreen()),
              );
            },
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                // Decorative ring framing the character portrait - echoes
                // the level badge's ring below so the avatar isn't just
                // floating on the card with nothing behind it.
                SizedBox(
                  width: 116,
                  height: 116,
                  child: CustomPaint(
                    painter: _RingPainter(
                      progress: state.levelProgress,
                      trackColor: gp.border,
                      arcColor: GameColors.gold,
                      strokeWidth: 4,
                    ),
                  ),
                ),
                if (!charState.isLoading)
                  CharacterAvatar(
                    character: charState.character,
                    accessory: charState.equippedAccessory,
                    height: 116,
                  )
                else
                  const SizedBox(width: 84, height: 116),
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: gp.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: gp.border, width: 0.5),
                    ),
                    child: Icon(Icons.edit_rounded,
                        size: 12, color: gp.textSec),
                  ),
                ),
                // Level badge pinned at the character's feet instead of
                // sitting in its own same-size ring beside the avatar - one
                // hero visual instead of two same-weight circles competing
                // for attention. Reuses _RingPainter as-is, just smaller.
                Positioned(
                  bottom: -10,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: SizedBox(
                      width: 46,
                      height: 46,
                      child: CustomPaint(
                        painter: _RingPainter(
                          progress: state.levelProgress,
                          trackColor: gp.border,
                          arcColor: GameColors.gold,
                          strokeWidth: 3.5,
                        ),
                        child: Container(
                          margin: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: gp.surface,
                            shape: BoxShape.circle,
                            border: Border.all(color: gp.border, width: 0.5),
                          ),
                          child: Center(
                            child: Text(
                              '${state.level}',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                color: GameColors.gold,
                                height: 1,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          InkWell(
            borderRadius: BorderRadius.circular(GameSpacing.chipRadius),
            onTap: () => showEditNameSheet(context, ref, displayName),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Flexible (not a bare Text) so a long name truncates
                  // with an ellipsis instead of overflowing past the card
                  // edge on narrower phones — the pencil icon next to it
                  // always stays visible either way.
                  Flexible(
                    child: Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: gp.textPrimary,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.edit_rounded, size: 15, color: gp.textTert),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          InkWell(
            borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
            onTap: () => showPrestigePicker(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: prestigeTier.color.withOpacity(0.14),
                borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
                border: Border.all(color: prestigeTier.color.withOpacity(0.35), width: 0.5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(prestigeTier.icon, size: 12, color: prestigeTier.color),
                  const SizedBox(width: 5),
                  Text(
                    prestigeTier.title(S.of(context).isAr),
                    style: TextStyle(
                        fontSize: 11.5, fontWeight: FontWeight.w800, color: prestigeTier.color),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                S.of(context).isAr
                    ? 'XP للمستوى ${state.level + 1}'
                    : 'XP to Level ${state.level + 1}',
                style: TextStyle(
                    fontSize: 12,
                    color: gp.textSec,
                    fontWeight: FontWeight.w500),
              ),
              Text(
                '${state.currentLevelXp} / ${state.xpToNext}',
                style: TextStyle(
                    fontSize: 12,
                    color: gp.textPrimary,
                    fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Forced LTR regardless of app language - a progress bar that
          // fills right-to-left in Arabic reads as draining, not filling,
          // so this one direction stays fixed while the label row above
          // it still flips normally with the locale.
          Directionality(
            textDirection: TextDirection.ltr,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
              child: LinearProgressIndicator(
                value: state.levelProgress,
                backgroundColor: gp.border,
                valueColor:
                    AlwaysStoppedAnimation(GameColors.gold),
                minHeight: 7,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Ring Painter ─────────────────────────────────────────────────────────────

class _RingPainter extends CustomPainter {
  final double progress;
  final Color trackColor;
  final Color arcColor;
  final double strokeWidth;
  const _RingPainter(
      {required this.progress,
      required this.trackColor,
      required this.arcColor,
      this.strokeWidth = 6});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - strokeWidth - 1;
    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final arc = Paint()
      ..color = arcColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, track);
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -pi / 2,
        progress * 2 * pi,
        false,
        arc,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.arcColor != arcColor ||
      old.strokeWidth != strokeWidth;
}

// ─── Stats Row ────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  final DashboardState state;
  const _StatsRow({required this.state});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Row(
      children: [
        _StatCell(
            icon: Icons.local_fire_department_rounded,
            color: GameColors.iconStreak,
            value: '${state.streak}',
            label: s.streak,
            infoTitle: s.statInfoStreakTitle,
            infoDescription: s.statInfoStreakDesc),
        const SizedBox(width: 8),
        _StatCell(
            icon: Icons.emoji_events_rounded,
            color: GameColors.iconGold,
            value: '${state.longestStreak}',
            label: s.best,
            infoTitle: s.statInfoBestTitle,
            infoDescription: s.statInfoBestDesc),
        const SizedBox(width: 8),
        _StatCell(
            icon: Icons.check_circle_rounded,
            color: GameColors.iconSuccess,
            value: '${state.totalCompletions}',
            label: s.total,
            infoTitle: s.statInfoTotalTitle,
            infoDescription: s.statInfoTotalDesc),
        const SizedBox(width: 8),
        _StatCell(
            icon: Icons.toll_rounded,
            color: GameColors.iconGold,
            value: '${state.gold}',
            label: s.gold,
            infoTitle: s.statInfoGoldTitle,
            infoDescription: s.statInfoGoldDesc),
        const SizedBox(width: 8),
        _StatCell(
            icon: Icons.bolt_rounded,
            color: GameColors.iconXp,
            value: '${state.cumulativeXp}',
            label: s.totalXp,
            infoTitle: s.statInfoXpTitle,
            infoDescription: s.statInfoXpDesc),
      ],
    );
  }
}

class _StatCell extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  // What this stat means, in plain language - passed straight through to
  // showStatInfoSheet on tap, alongside this same icon/color/value, so the
  // popup reads as "here's what your 12 means" rather than a generic
  // dictionary entry. See stat_info_sheet.dart.
  final String infoTitle;
  final String infoDescription;
  const _StatCell(
      {required this.icon,
      required this.color,
      required this.value,
      required this.label,
      required this.infoTitle,
      required this.infoDescription});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(GameSpacing.chipRadius),
        onTap: () => showStatInfoSheet(
          context,
          icon: icon,
          color: color,
          value: value,
          title: infoTitle,
          description: infoDescription,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: gp.surface,
            borderRadius: BorderRadius.circular(GameSpacing.chipRadius),
            border: Border.all(color: gp.border, width: 0.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(height: 6),
              Text(
                value,
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: gp.textPrimary,
                    height: 1,
                    letterSpacing: -0.5),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w600,
                    color: gp.textTert,
                    letterSpacing: 1.2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Dashboard (today's nudges) ────────────────────────────────────────────

/// The streak-at-risk banner, night-review prompt, and Friday recap card
/// used to sit above the grid on the Grid screen, pushing the habit squares
/// — the whole point of that screen — below the fold. They live here now
/// instead: Grid stays laser-focused on the squares, and Profile becomes
/// the place for "how's my week going" nudges.
///
/// Each child below still gates its own visibility exactly as it did on
/// Grid (evening hour, unsaved review, Friday + non-zero week). This
/// wrapper re-checks those same conditions so the "OVERVIEW" header itself
/// never renders over an empty column on a day none of them have anything
/// to say — which, by design, is most days.
class _DashboardSection extends ConsumerWidget {
  const _DashboardSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dash = ref.watch(dashboardProvider);
    final grid = ref.watch(weeklyGridProvider);
    final habits = ref.watch(habitListProvider);
    final review = ref.watch(nightReviewProvider);
    final today = DateTime.now().effectiveDay;
    final isEvening = DateTime.now().hour >= 18;

    final showStreak = isEvening &&
        dash.streak > 0 &&
        habits.isNotEmpty &&
        !grid.isLoading &&
        !dash.streakEarnedToday;
    final showNightReview = !review.isLoading && !review.saved && isEvening;

    // Mirrors WeeklyRecapCard's own zero-data gate exactly, so this section
    // never shows a header over a recap card that would silently render
    // nothing (e.g. a brand-new user's very first Friday).
    final showRecap = () {
      if (today.weekday != DateTime.friday || habits.isEmpty) return false;
      final recap = computeWeeklyRecap(
        dailyGreenCounts: dash.dailyGreenCounts,
        weekStart: startOfGridWeek(today),
      );
      return recap.thisWeekTotal != 0 || recap.lastWeekTotal != 0;
    }();

    if (!showStreak && !showNightReview && !showRecap) {
      return const SizedBox.shrink();
    }

    final gp = context.gp;
    final s = S.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 28, 16, 0),
          child: Text(s.profileDashboardSection,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: gp.textSec,
                  letterSpacing: 1.5)),
        ),
        if (showStreak) const _StreakAtRiskBanner(),
        if (showNightReview) const _NightReviewPromptCard(),
        if (showRecap) const WeeklyRecapCard(),
      ],
    );
  }
}

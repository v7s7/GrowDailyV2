part of 'profile_screen.dart';


/// The retention loop's most important message: from 6pm, if the user has a
/// live streak and hasn't finished today's habits yet (streak means a full
/// 100% day — see [DashboardState.streakEarnedToday]), warn them warmly.
/// Disappears the moment today's streak point is earned.
class _StreakAtRiskBanner extends ConsumerWidget {
  const _StreakAtRiskBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dash = ref.watch(dashboardProvider);
    final grid = ref.watch(weeklyGridProvider);
    final habits = ref.watch(habitListProvider);

    final isEvening = DateTime.now().hour >= 18;
    if (!isEvening ||
        dash.streak <= 0 ||
        habits.isEmpty ||
        grid.isLoading ||
        dash.streakEarnedToday) {
      return const SizedBox.shrink();
    }

    final gp = context.gp;
    final s = S.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: GameColors.iconStreak.withOpacity(gp.dark ? 0.10 : 0.08),
          borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
          border:
              Border.all(color: GameColors.iconStreak.withOpacity(0.4)),
        ),
        child: Row(
          children: [
            Icon(Icons.local_fire_department_rounded,
                    color: GameColors.iconStreak, size: 26)
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .scaleXY(
                  begin: 0.88,
                  end: 1.05,
                  duration: 900.ms,
                  curve: Curves.easeInOut,
                ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.streakAtRiskTitle(dash.streak),
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: GameColors.iconStreak,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    s.streakAtRiskBody,
                    style: TextStyle(fontSize: 12, color: gp.textSec),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.08);
  }
}

/// A gentle evening nudge toward Night Review — visible any time after 6pm
/// until tonight's check-in is saved. Dismissible via the Grid header's moon
/// icon at any hour; this card just makes the invitation hard to miss when
/// it matters most.
class _NightReviewPromptCard extends ConsumerWidget {
  const _NightReviewPromptCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final review = ref.watch(nightReviewProvider);
    final isEvening = DateTime.now().hour >= 18;
    if (review.isLoading || review.saved || !isEvening) {
      return const SizedBox.shrink();
    }
    final gp = context.gp;
    final s = S.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          Navigator.pushNamed(context, '/night-review');
        },
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: gp.surface,
            borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
            border: Border.all(color: GameColors.iconXp.withOpacity(0.22)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: GameColors.iconXp.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(GameSpacing.buttonRadius),
                ),
                child: Icon(Icons.auto_stories_rounded,
                    color: GameColors.iconXp),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.nightReviewPromptTitle,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: gp.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      s.nightReviewPromptDesc,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: gp.textSec),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: GameColors.iconXp),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.08);
  }
}

// ─── Profile Links (Achievements, Progress & Streak) ──────────────────────────

/// Six tap-through rows in two labeled groups. "Explore": Dashboard
/// (Progress + Achievements + Habit Insights, merged — see
/// ProgressHubScreen's doc comment), Closet, and Rooms. "Your Story":
/// Journey, Life Timeline, and Monthly Story - three different lenses on
/// the same habit history, similar-sounding enough that they get their own
/// header plus a one-line subtitle each rather than sitting unlabeled in
/// the same list as Dashboard/Closet/Rooms.
class _ProfileLinksSection extends ConsumerWidget {
  final int streak;

  const _ProfileLinksSection({
    required this.streak,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    // Guests never have rooms (they require an account - see
    // RoomsHubScreen's own gate), so this stays 0 and the badge below just
    // never shows for them rather than needing a separate guest branch here.
    final roomCount = ref.watch(myRoomCodesProvider).valueOrNull?.length ?? 0;

    final isAr = s.isAr;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // "استكشف" / Explore — Dashboard, Closet, Rooms. Split from the
        // history trio below (was one flat list of six under a header that
        // just repeated this screen's own "Profile" title) so each group's
        // label actually tells you something the page title didn't.
        Text(isAr ? 'استكشف' : 'Explore',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: gp.textSec,
                letterSpacing: 1.5)),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: gp.surface,
            borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
            border: Border.all(color: gp.border, width: 0.5),
          ),
          child: Column(
            children: [
              // Dashboard — merged Achievements + Habit Insights + Progress
              // & Streak into one destination (see ProgressHubScreen's doc
              // comment for why). Shows for everyone; the gold PRO chip is
              // the same honest signposting the old standalone Habit
              // Insights row used, since Premium content still lives one
              // tap inside. Icon is neutral now, not gold - the PRO chip
              // and streak count already mark this row as different, so a
              // one-off gold icon was just an unexplained inconsistency
              // next to five gray ones.
              InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const ProgressHubScreen()),
                  );
                },
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(GameSpacing.cardRadius),
                  topRight: Radius.circular(GameSpacing.cardRadius),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Icon(Icons.dashboard_rounded,
                          size: 20, color: gp.textSec),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(s.progressTitle,
                            style: TextStyle(
                                fontSize: 15,
                                color: gp.textPrimary,
                                fontWeight: FontWeight.w500)),
                      ),
                      Icon(Icons.local_fire_department_rounded,
                          size: 15, color: GameColors.iconStreak),
                      const SizedBox(width: 3),
                      Text('$streak',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: gp.textSec)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: GameColors.gold.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
                        ),
                        child: Text(
                          'PRO',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: GameColors.gold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(Icons.chevron_right_rounded,
                          size: 18, color: gp.textTert),
                    ],
                  ),
                ),
              ),
              Container(height: 0.5, color: gp.divider),
              InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const CharacterClosetScreen()),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Icon(Icons.checkroom_rounded,
                          size: 20, color: gp.textSec),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(s.closetProfileRow,
                            style: TextStyle(
                                fontSize: 15,
                                color: gp.textPrimary,
                                fontWeight: FontWeight.w500)),
                      ),
                      Icon(Icons.chevron_right_rounded,
                          size: 18, color: gp.textTert),
                    ],
                  ),
                ),
              ),
              Container(height: 0.5, color: gp.divider),
              // Rooms: group challenges with friends - a room's own screen
              // handles the guest-account gate itself (see
              // RoomsHubScreen._GuestGate), so this row is always tappable
              // regardless of sign-in state, same as every other row here.
              // Icon switched from a trophy (reads as "achievements",
              // overlapping with Dashboard above) to people, since this
              // row is specifically about friends, not scores.
              InkWell(
                // Stable across rebuilds via roomsRowKeyProvider (a plain
                // Riverpod Provider, cached for the app's lifetime) since
                // this widget itself is a ConsumerWidget with no State
                // object to hold a GlobalKey field on — see that provider's
                // own doc comment. Lets App Guide's "Join a Room" lesson
                // circle this exact row from ProfileScreen's CoachMarkOverlay.
                key: ref.watch(roomsRowKeyProvider),
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const RoomsHubScreen()),
                  );
                },
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(GameSpacing.cardRadius),
                  bottomRight: Radius.circular(GameSpacing.cardRadius),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Icon(Icons.groups_rounded,
                          size: 20, color: gp.textSec),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(s.roomsTitle,
                            style: TextStyle(
                                fontSize: 15,
                                color: gp.textPrimary,
                                fontWeight: FontWeight.w500)),
                      ),
                      if (roomCount > 0) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: GameColors.gold.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
                            border: Border.all(
                                color: GameColors.gold.withOpacity(0.3),
                                width: 0.5),
                          ),
                          child: Text(
                            '$roomCount',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: GameColors.gold),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Icon(Icons.chevron_right_rounded,
                          size: 18, color: gp.textTert),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // "قصتك" / Your Story — Journey, Life Timeline, and Monthly Story
        // are three different lenses on the same habit history, which read
        // as near-duplicates when they're unlabeled rows in a longer flat
        // list. Grouping them under one header, plus a one-line subtitle
        // on each, says what tells them apart before you have to tap in.
        Text(isAr ? 'قصتك' : 'Your Story',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: gp.textSec,
                letterSpacing: 1.5)),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: gp.surface,
            borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
            border: Border.all(color: gp.border, width: 0.5),
          ),
          child: Column(
            children: [
              // Journey: the narrative counterpart to Dashboard's numbers —
              // see JourneyScreen's own doc comment.
              InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const JourneyScreen()),
                  );
                },
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(GameSpacing.cardRadius),
                  topRight: Radius.circular(GameSpacing.cardRadius),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Icon(Icons.route_rounded, size: 20, color: gp.textSec),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.journeyTitle,
                                style: TextStyle(
                                    fontSize: 15,
                                    color: gp.textPrimary,
                                    fontWeight: FontWeight.w500)),
                            const SizedBox(height: 1),
                            Text(
                              isAr
                                  ? 'قصة عاداتك يوماً بيوم'
                                  : 'Your habits, day by day',
                              style:
                                  TextStyle(fontSize: 11, color: gp.textTert),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded,
                          size: 18, color: gp.textTert),
                    ],
                  ),
                ),
              ),
              Container(height: 0.5, color: gp.divider),
              // Life Timeline: the zoomed-out year-at-a-glance counterpart —
              // see LifeTimelineScreen's own doc comment.
              InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const LifeTimelineScreen()),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_view_month_rounded,
                          size: 20, color: gp.textSec),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.lifeTimelineTitle,
                                style: TextStyle(
                                    fontSize: 15,
                                    color: gp.textPrimary,
                                    fontWeight: FontWeight.w500)),
                            const SizedBox(height: 1),
                            Text(
                              isAr
                                  ? 'عامك كاملاً بلمحة واحدة'
                                  : 'Your whole year at a glance',
                              style:
                                  TextStyle(fontSize: 11, color: gp.textTert),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded,
                          size: 18, color: gp.textTert),
                    ],
                  ),
                ),
              ),
              Container(height: 0.5, color: gp.divider),
              // Monthly Story: shareable month-in-review — see
              // MonthlyStoryScreen's own doc comment. Last row, so this is
              // the one that carries the bottom corner radius now.
              InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const MonthlyStoryScreen()),
                  );
                },
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(GameSpacing.cardRadius),
                  bottomRight: Radius.circular(GameSpacing.cardRadius),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Icon(Icons.auto_stories_rounded,
                          size: 20, color: gp.textSec),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.monthlyStoryTitle,
                                style: TextStyle(
                                    fontSize: 15,
                                    color: gp.textPrimary,
                                    fontWeight: FontWeight.w500)),
                            const SizedBox(height: 1),
                            Text(
                              isAr
                                  ? 'ملخص شهري قابل للمشاركة'
                                  : 'A shareable monthly recap',
                              style:
                                  TextStyle(fontSize: 11, color: gp.textTert),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded,
                          size: 18, color: gp.textTert),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Settings ─────────────────────────────────────────────────────────────────

/// Opens the language picker sheet from Settings — same [LanguageOptionCard]
/// rows as the first-launch picker, just presented as a sheet since the
/// locale is already known here.
void _showLanguageSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    // See add_habit_hub_sheet.dart's showAddHabitHub for why every bottom
    // sheet in this app should set this: without it, the sheet's bottom
    // edge renders flush with the literal screen edge instead of clearing
    // the home-indicator bar, so content near the bottom sits in a
    // different spot device to device.
    useSafeArea: true,
    builder: (ctx) => const _LanguageSheet(),
  );
}

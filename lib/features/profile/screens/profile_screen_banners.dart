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

    // Runs through to the 6am cutoff, not to midnight - see isDayClosing.
    // The streak this warns about does not expire at 00:00, so neither
    // does the warning: someone still up at 1am has five hours left to
    // save it, and that is exactly who the cutoff exists for.
    final isEvening = DateTime.now().isDayClosing;
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
    // Same wrapped window as the streak card above. NightReviewNotifier
    // already keys tonight's entry by effectiveDay, so at 1am the review
    // this offers is still the current day's - the prompt used to vanish
    // at midnight while the thing it opens stayed open.
    final isEvening = DateTime.now().isDayClosing;
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

/// Three tap-through rows in one unlabeled card: Progress (Progress +
/// Achievements + Habit Insights, merged — see ProgressHubScreen's doc
/// comment), Rooms, and Monthly Story.
///
/// This was six rows under two headers. The headers and subtitles existed to
/// tell near-duplicates apart — Journey, Life Timeline and Monthly Story are
/// three lenses on one `milestoneEventsProvider`, and Character Closet was
/// the same destination as the hero avatar on the same scroll. Removing the
/// duplicates removed the need to label anything: what is left is your
/// numbers, your people, and your month, which no one needs a header to
/// distinguish. See the comment inside build() for the full reasoning.
class _ProfileLinksSection extends ConsumerWidget {
  const _ProfileLinksSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    // Guests never have rooms (they require an account - see
    // RoomsHubScreen's own gate), so this stays 0 and the badge below just
    // never shows for them rather than needing a separate guest branch here.
    final roomCount = ref.watch(myRoomCodesProvider).valueOrNull?.length ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // One card, three rows, no section headers.
        //
        // This was six rows under two headers ("Explore" and "Your Story"),
        // and the grouping was doing real work — three of those six were
        // near-duplicates of each other, so they needed labels and subtitles
        // to be told apart. The fix was to stop shipping the duplicates
        // rather than to keep labelling them: Journey, Life Timeline and
        // Monthly Story all read the same milestoneEventsProvider, and Life
        // Timeline re-rendered the Progress Heatmap's own day-square grid
        // with a copy of its colour scale. Character Closet went too — the
        // hero avatar directly above opens exactly that screen already.
        //
        // What survives is three rows that share nothing: your numbers
        // (Progress), your people (Rooms), your month (Monthly Story). Three
        // rows that are obviously different need no header to separate them,
        // and no subtitle to disambiguate them, which is why both are gone.
        //
        // JourneyScreen and LifeTimelineScreen are left on disk, unwired —
        // deleting the files is a separate decision from removing the doors.
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
                      // No flame+streak and no PRO chip here any more. The
                      // streak is the very first _StatCell about 200px above
                      // this row, so repeating it made the row look like it
                      // was reporting something new when it was echoing. The
                      // PRO chip advertised a lock on a screen that is free —
                      // the only Premium content behind it is already
                      // signposted where it actually applies, inside
                      // InsightsScreen.
                      Icon(Icons.chevron_right_rounded,
                          size: 18, color: gp.textTert),
                    ],
                  ),
                ),
              ),
              Container(height: 0.5, color: gp.divider),
              // The Character Closet row used to sit here. It opened exactly
              // the same screen as the hero avatar a few hundred pixels above
              // it on this very scroll (see _HeroHeader's InkWell) — one
              // destination behind two doors on one page, which is the single
              // clearest kind of clutter to remove.
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
                // No corner radius: this is the middle row now that Monthly
                // Story has joined the same card below it.
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
              Container(height: 0.5, color: gp.divider),
              // Monthly Story: shareable month-in-review — see
              // MonthlyStoryScreen's own doc comment. No longer the last
              // row (Year Record sits under it now), so no corner radius.
              InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const MonthlyStoryScreen()),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Icon(Icons.auto_stories_rounded,
                          size: 20, color: gp.textSec),
                      const SizedBox(width: 12),
                      // Subtitle dropped: it existed only to tell this row
                      // apart from Journey and Life Timeline, which are gone.
                      // Three rows this different need no explaining, and it
                      // makes all three rows one shape.
                      Expanded(
                        child: Text(s.monthlyStoryTitle,
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
              // Year Record: every habit's own year of history as a heat
              // strip — see YearRecordScreen. Last row, so this one carries
              // the bottom corner radius.
              InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const YearRecordScreen()),
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
                      Icon(Icons.calendar_view_month_rounded,
                          size: 20, color: gp.textSec),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(s.yearRecordTitle,
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

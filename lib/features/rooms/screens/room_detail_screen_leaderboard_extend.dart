part of 'room_detail_screen.dart';


/// Contribution strip for one participant, reusing the exact same
/// [heatColor] tiers the main Grid heatmap screen uses so the visual
/// language matches everywhere green history shows up. Each cell's shade is
/// proportional to that day's credit (see RoomParticipant. creditFor)
/// rather than plain binary - a day with only some linked habits done shows
/// a visibly lighter partial shade instead of looking identical to a day
/// with none done, so multi-habit progress reads at a glance instead of only
/// ever showing as all-or-nothing. Shares [heatmapLevelFor] (rooms_
/// notifier.dart) with the widget's own much-shorter per-participant
/// heatmap push (see RoomRaceRow.heatmap) - same credit-to-shade mapping
/// everywhere this idea shows up, in-app or on a Home Screen widget.
///
/// Wraps onto as many lines as it takes rather than scrolling sideways.
/// This used to be a single horizontally-scrolling row capped at the most
/// recent 30 days, which meant a room longer than that hid its own history
/// behind a gesture nothing on screen advertised: the row simply looked
/// finished at its left edge, and the days before it - most of a 90-day
/// room - were invisible unless you happened to try dragging it. A whole
/// room's history laid out at once is also just the more honest picture of
/// a race, and it matches how the Grid itself presents a period: a block you
/// read, not a reel you scrub.
///
/// Flowing instead of scrolling also puts the cells in calendar order in
/// both languages for free - [Wrap] follows the ambient [Directionality], so
/// the oldest day starts the first line (top-right in Arabic, top-left in
/// English) and today ends the last one.
class _MiniHeatmapStrip extends StatelessWidget {
  final RoomModel room;
  final RoomParticipant participant;
  const _MiniHeatmapStrip({required this.room, required this.participant});

  /// Ceiling for an OPEN-ENDED room only ([RoomDuration.open] - "runs until
  /// people leave"). A fixed-length room draws every one of its days: its
  /// length is a number the leader chose up front, so it can't surprise
  /// anyone, and seeing the whole thing is the entire point.
  ///
  /// An open room has no such bound - left running it would add a line every
  /// few weeks forever, growing every participant's card without limit. The
  /// old code capped this at 30 for the same reason, just in the other
  /// dimension (an unbounded *row*). Roughly a season of history, three or
  /// four lines at typical phone widths.
  static const int _maxOpenRoomDays = 90;
  static const double _cell = 9;
  static const double _gap = 2.5;

  @override
  Widget build(BuildContext context) {
    final dark = context.gp.dark;
    // Their own window, so a late joiner's strip starts the day they joined
    // rather than showing weeks of grey for a room they weren't in yet.
    final elapsed = participant.daysElapsedIn(room);
    final totalDays = room.duration == RoomDuration.open
        ? elapsed.clamp(1, _maxOpenRoomDays)
        : elapsed;
    final last = room.lastCountedDay;
    final days = List.generate(
      totalDays,
      (i) => last.subtract(Duration(days: totalDays - 1 - i)),
    );
    return Wrap(
      spacing: _gap,
      runSpacing: _gap,
      children: [
        for (final day in days)
          Container(
            width: _cell,
            height: _cell,
            decoration: BoxDecoration(
              // Plain creditFor shading, no special case for any habit
              // type: a day you did the habit is a whole done day, so
              // it lands on the top emerald tier in full colour, and a
              // day you didn't is gray. A multi-habit day part-done
              // shades in between, which is the only fraction here.
              color: heatColor(
                  heatmapLevelFor(participant.creditFor(day.toDateKey())),
                  dark),
              borderRadius: BorderRadius.circular(2.5),
              // isRealToday, not isToday: purely the "today" marker —
              // see DateTimeGameExt.isRealToday's doc comment.
              border: day.isRealToday
                  ? Border.all(color: GameColors.gold, width: 1)
                  : null,
            ),
          ),
      ],
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  final int rank;
  final RoomParticipant participant;
  final RoomModel room;
  final bool isYou;
  final bool isLeader;

  const _LeaderboardRow({
    required this.rank,
    required this.participant,
    required this.room,
    required this.isYou,
    required this.isLeader,
  });

  Color? get _medalColor => switch (rank) {
        1 => GameColors.gold,
        2 => const Color(0xFFB0B7C3),
        3 => const Color(0xFFC98A4B),
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final ratio = participant.progressRatio(room);
    final character = CharacterCatalog.findByIdOrDefault(participant.characterId);
    final accessory = AccessoryCatalog.findById(participant.accessoryId);
    // Same "nothing to show off yet" restraint as the Profile hero header's
    // own showsPrestigeTint - a null tier (doc from before this field
    // existed, self-heals on that person's next sync) and the base
    // "Seeker" tier both render nothing here rather than a chip everyone
    // would have from day one.
    final prestigeTier = PrestigeCatalog.findById(participant.prestigeTierId);
    final medalColor = _medalColor;
    final showDetails = isYou || !participant.hideDetails;
    final streak = participant.currentStreak(room);
    final names =
        participant.linkedHabitNames.where((n) => n.trim().isNotEmpty).toList();

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isYou ? GameColors.gold.withOpacity(0.06) : gp.surface,
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        border: Border.all(
          color: isYou ? GameColors.gold.withOpacity(0.35) : gp.border,
          width: isYou ? 1 : 0.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 22,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: rank == 1
                  ? Icon(Icons.emoji_events_rounded, size: 20, color: GameColors.gold)
                  : Text(
                      '$rank',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: medalColor ?? gp.textTert,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 6),
          CharacterAvatar(character: character, accessory: accessory, height: 42),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        participant.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w800, color: gp.textPrimary),
                      ),
                    ),
                    if (isYou) ...[
                      const SizedBox(width: 6),
                      _Tag(label: s.roomYouLabel, color: GameColors.gold),
                    ],
                    if (isLeader) ...[
                      const SizedBox(width: 6),
                      _Tag(label: s.roomLeaderLabel, color: gp.textSec),
                    ],
                  ],
                ),
                // Inline null-check (not a separate bool) so Dart actually
                // promotes prestigeTier to non-null for the _PrestigeChip
                // call below - a bool computed from the same check earlier
                // doesn't carry that promotion through on its own.
                if (prestigeTier != null && prestigeTier.minLevel > 1) ...[
                  const SizedBox(height: 4),
                  _PrestigeChip(tier: prestigeTier),
                ],
                if (showDetails && names.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    names.join(', '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: gp.textSec),
                  ),
                ],
                const SizedBox(height: 7),
                _MiniHeatmapStrip(room: room, participant: participant),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
                        child: LinearProgressIndicator(
                          value: ratio,
                          backgroundColor: gp.border,
                          valueColor: AlwaysStoppedAnimation(medalColor ?? GameColors.gold),
                          minHeight: 6,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Visible regardless of hideDetails, same as the heatmap
                    // and progress bar above - it's a count, not which habit
                    // is behind it, so there's nothing to hide here.
                    //
                    // Pinned LTR and grouped in its own Row: a flame plus its
                    // number is one badge, not prose, and letting Arabic's
                    // right-to-left flow reorder it separated the digit from
                    // the flame it belongs to (it read as part of the day
                    // count sitting next to it instead). The day count below
                    // deliberately does NOT get this treatment - "2 من 2" IS
                    // Arabic prose and has to follow the ambient direction.
                    if (streak >= 1) ...[
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.local_fire_department_rounded,
                                size: 12, color: GameColors.iconStreak),
                            const SizedBox(width: 2),
                            Text(
                              '$streak',
                              style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  color: GameColors.iconStreak),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 9),
                    ],
                    Text(
                      s.roomDayCount(participant.daysCompleted(room),
                          participant.daysElapsedIn(room)),
                      style: TextStyle(fontSize: 10.5, color: gp.textTert),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('${(ratio * 100).round()}%',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: gp.textPrimary)),
          ),
        ],
      ),
    );
  }
}

/// Small inline warning row - see [_MyPlanCard]'s hasDeletedLink check, the
/// only current user of this.
class _WarningRow extends StatelessWidget {
  final String text;
  const _WarningRow({required this.text});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: GameColors.error.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: GameColors.error.withOpacity(0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 15, color: GameColors.error),
          const SizedBox(width: 7),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 11, color: gp.textSec, height: 1.35)),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final Color color;
  const _Tag({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

/// This person's Level Prestige title (see prestige_tier.dart) - identical
/// icon/pill/color treatment to the chip on the Profile hero header
/// (profile_screen_hero_dashboard.dart), just reused here so a title looks
/// like the same badge wherever it's seen, not a lookalike invented twice.
class _PrestigeChip extends StatelessWidget {
  final PrestigeTier tier;
  const _PrestigeChip({required this.tier});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tier.color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
        border: Border.all(color: tier.color.withOpacity(0.35), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(tier.icon, size: 11, color: tier.color),
          const SizedBox(width: 4),
          Text(
            tier.title(S.of(context).isAr),
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: tier.color),
          ),
        ],
      ),
    );
  }
}

/// Leader-only sheet for picking a fresh length for a fixed-duration room -
/// same 7/14/30/90/open-ended/Custom choices CreateRoomSheet's own duration
/// chips offer, so extending feels like the same decision as creating one,
/// not a new control to learn. Pops the picked length in days, or 0 for
/// open-ended (never a real day count, so it's a safe stand-in) - popping
/// plain `null` is reserved for "dismissed without picking anything" (the
/// default result of swiping the sheet away), which
/// _RoomDetailScreenState._confirmExtend relies on to tell "chose
/// open-ended" and "changed their mind" apart.
///
/// Stateful (unlike every option here except Custom, which pops immediately
/// on tap) only because Custom needs somewhere to hold its typed-but-not-
/// yet-applied text between keystrokes - see [_ExtendRoomSheetState].
class _ExtendRoomSheet extends StatefulWidget {
  const _ExtendRoomSheet();

  @override
  State<_ExtendRoomSheet> createState() => _ExtendRoomSheetState();
}

class _ExtendRoomSheetState extends State<_ExtendRoomSheet> {
  static const List<int> _dayOptions = [7, 14, 30, 90];

  bool _customSelected = false;
  final _customCtrl = TextEditingController();

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  /// Mirrors CreateRoomSheet's own _customDurationDays getter - see
  /// RoomModel.parseCustomRoomDurationDays for exactly what counts as valid.
  int? get _customDays => parseCustomRoomDurationDays(_customCtrl.text);

  /// Wired to both the field's keyboard "done" action and the checkmark
  /// button beside it, so there are two equally-discoverable ways to
  /// confirm - a no-op while [_customDays] is invalid, same as the
  /// checkmark button disabling itself in that state.
  void _applyCustom() {
    final days = _customDays;
    if (days == null) return;
    HapticFeedback.selectionClick();
    Navigator.pop(context, days);
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        decoration: BoxDecoration(
          color: gp.surfaceHigh,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: gp.border, width: 0.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: gp.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(s.roomExtendTitle,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: gp.textPrimary)),
            const SizedBox(height: 6),
            Text(s.roomExtendBody,
                style: TextStyle(fontSize: 12.5, color: gp.textSec, height: 1.35)),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final days in _dayOptions)
                  _ExtendOptionChip(
                    label: s.daysCount(days),
                    onTap: () => Navigator.pop(context, days),
                  ),
                _ExtendOptionChip(
                  label: s.roomDurationOpenEnded,
                  onTap: () => Navigator.pop(context, 0),
                ),
                _ExtendOptionChip(
                  label: s.roomDurationCustomOption,
                  selected: _customSelected,
                  onTap: () => setState(() => _customSelected = true),
                ),
              ],
            ),
            if (_customSelected) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _customCtrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _applyCustom(),
                decoration: InputDecoration(
                  labelText: s.roomDurationCustomHint,
                  helperText: s.roomDurationCustomRange,
                  errorText: _customCtrl.text.trim().isEmpty || _customDays != null
                      ? null
                      : s.roomDurationCustomInvalid,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.check_circle_rounded),
                    // IconButton only ever applies `color` while enabled -
                    // disabledColor has to be set explicitly too, or Flutter
                    // falls back to its own theme grey instead of this app's
                    // textTert the moment the field is empty/invalid.
                    color: GameColors.gold,
                    disabledColor: gp.textTert,
                    onPressed: _customDays != null ? _applyCustom : null,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One immediate-action duration choice - tapping pops [onTap]'s value right
/// away for every option except Custom (see [_ExtendRoomSheetState]), which
/// is why [selected] defaults to false and only Custom's instance ever
/// passes true: every other chip here has no "currently chosen" look of its
/// own, it's a one-shot action, not a persisted pick. Sized to the same
/// minimum 44x44 tap target as CreateRoomSheet's _DurationChip so the two
/// sheets' pills feel identical regardless of which screen they're on.
class _ExtendOptionChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ExtendOptionChip({
    required this.label,
    this.selected = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return InkWell(
      borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? GameColors.gold.withOpacity(0.14) : gp.surface,
          borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
          border: Border.all(
            color: selected ? GameColors.gold : gp.border,
            width: selected ? 1.1 : 0.8,
          ),
        ),
        child: Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                color: selected ? GameColors.gold : gp.textPrimary)),
      ),
    );
  }
}

/// The leaderboard itself, showing the top [_initialRows] and hiding the
/// rest behind a "show all" tap.
///
/// A room has no member cap, so this list is however long the room is — and
/// each row draws an avatar plus a full contribution heatmap. A 200-person
/// room built every one of those on first paint, for a screen where almost
/// nobody scrolls past the first handful.
///
/// The one row that always renders regardless of rank is your own. Being
/// 150th is exactly when you most need to see where you stand, and a plain
/// top-20 cut would have hidden the only row that is actually about you. It
/// appears in its true rank position when it falls inside the visible slice,
/// and pinned below the fold with a divider when it doesn't.
class _LeaderboardList extends StatefulWidget {
  final List<RoomParticipant> sorted;
  final RoomModel room;
  final String? myUid;
  const _LeaderboardList({
    required this.sorted,
    required this.room,
    required this.myUid,
  });

  @override
  State<_LeaderboardList> createState() => _LeaderboardListState();
}

class _LeaderboardListState extends State<_LeaderboardList> {
  static const int _initialRows = 20;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final sorted = widget.sorted;
    final showAll = _expanded || sorted.length <= _initialRows;
    final visibleCount = showAll ? sorted.length : _initialRows;

    Widget rowAt(int i) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _LeaderboardRow(
            rank: i + 1,
            participant: sorted[i],
            room: widget.room,
            isYou: sorted[i].uid == widget.myUid,
            isLeader: sorted[i].uid == widget.room.createdBy,
          ),
        );

    final myIndex =
        sorted.indexWhere((p) => p.uid == widget.myUid);
    final myRowIsHidden = !showAll && myIndex >= visibleCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < visibleCount; i++) rowAt(i),
        if (myRowIsHidden) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(child: Divider(color: gp.border, height: 1)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text('⋯',
                      style: TextStyle(fontSize: 15, color: gp.textTert)),
                ),
                Expanded(child: Divider(color: gp.border, height: 1)),
              ],
            ),
          ),
          rowAt(myIndex),
        ],
        if (!showAll)
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 4),
            child: TextButton(
              onPressed: () {
                HapticFeedback.selectionClick();
                setState(() => _expanded = true);
              },
              child: Text(s.roomShowAllMembers(sorted.length)),
            ),
          ),
      ],
    );
  }
}

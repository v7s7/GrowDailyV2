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
/// Laid out as WEEK COLUMNS — the GitHub-contribution-graph form — instead
/// of the free-flowing [Wrap] this used to be. The old wrap broke lines
/// wherever the card width happened to land (19 cells, then 9), so the
/// same weekday never lined up twice, week boundaries were invisible, and
/// "when did this start / which day is which" was unanswerable without
/// counting cells. Each column here is one calendar week aligned to the
/// same Saturday start the Grid itself uses (startOfGridWeek), Saturday on
/// top through Friday at the bottom — so a vertical slice is a week, a
/// horizontal slice is "every Saturday", gaps and recoveries read the way
/// they do on the Grid, and the first column IS the start of the race.
/// Columns follow the ambient [Directionality] (a [Wrap] of columns), so
/// weeks run right-to-left in Arabic exactly like the Grid's days do, and
/// a room longer than one line of columns folds onto the next line rather
/// than hiding behind an unadvertised sideways scroll.
class _MiniHeatmapStrip extends StatelessWidget {
  final RoomModel room;
  final RoomParticipant participant;

  /// Only used to word the calendar's first-day note in the second person
  /// ("your first day") rather than the third. Nothing else in the strip
  /// varies by whose row it is.
  final bool isYou;

  /// Draws the week-of-month number over every column. Driven by one toggle
  /// above the whole leaderboard (see _LeaderboardListState), never per-row.
  ///
  /// NOT named `showDetails`: _LeaderboardRow.build already declares a local
  /// of that name for the room's privacy flag ("hide my habit names"), and
  /// the field was being silently shadowed by it — every row got the privacy
  /// value instead of the toggle, so the numbers showed on your own row
  /// (isYou) regardless of the switch and never on a member who'd hidden
  /// their details.
  final bool showWeekNumbers;

  const _MiniHeatmapStrip({
    required this.room,
    required this.participant,
    required this.isYou,
    required this.showWeekNumbers,
  });

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

  /// 12pt cells on a 15pt pitch, up from 9 on 11.5.
  ///
  /// The strip is `IntrinsicWidth`-centred inside a full-width card, so at
  /// the old size a 20-day room drew three columns — about 35pt of grid —
  /// floating in ~270pt of empty card. It read as an afterthought rather
  /// than as this participant's record. The extra 3pt per cell is spent on
  /// width that was already there and doing nothing; a 15pt pitch still
  /// fits ~18 columns (four months) on one line at phone widths before any
  /// wrapping kicks in.
  static const double _cell = 12;
  static const double _gap = 3;

  /// Width reserved beside the grid for a pinned cell label, and the width
  /// those labels are laid out at. One constant so the inset and the label
  /// can never disagree — if they do, the label clips.
  static const double _labelInset = 64;

  /// Fixed, theme-independent marker tones for the first cell — deliberately
  /// NOT GameColors.*, permanently. Same rule as the icon*/tier*Shine consts
  /// in game_theme.dart: "this colour must survive all 11 presets".
  ///
  /// Every accent in this app is preset-derived (theme_preset.dart), and the
  /// day-1 marker has to stay legible on a cell whose fill is ALSO preset-
  /// derived. Those two facts collide: in navy, emerald is #2E59CF and xpBlue
  /// is #2C56C9 — 1.05:1, invisible. baby_blue is #2E94CF vs #47A3D9, 1.20:1.
  ///
  /// That is structural, not a bad pick of accent. Across 11 presets × 5
  /// credit levels × 2 modes this cell renders on 110 distinct fills whose
  /// luminances run continuously with no gap wider than ~0.045, so the best
  /// POSSIBLE single fixed colour — any hue, optimally placed — still bottoms
  /// out near 1.42:1 against some preset. One tone cannot work here. Two can:
  /// white and near-black bracket the whole range, so whatever the fill is
  /// doing, one of them is far from it.
  ///
  /// Do not "fix" these back to a GameColors accent. That silently
  /// reintroduces the navy collision in exactly one preset out of eleven.
  static const Color _markInk = Color(0xFF0B0E12);
  static const Color _markPaper = Color(0xFFFFFFFF);

  /// (outer, inner) marker tones. The OUTER ring is painted outside the cell
  /// and therefore lands on the CARD — a known extreme in each mode, never
  /// worse than ~15:1. The INNER hairline is the opposite tone, ~19:1 from
  /// the outer one, and it is what separates the marker from a bright fill.
  static (Color, Color) _markTones(bool dark) =>
      dark ? (_markPaper, _markInk) : (_markInk, _markPaper);

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
    // Between midnight and the flex cutoff (see DateTimeGameExt.effectiveDay)
    // the REAL calendar day is already ahead of lastCountedDay — the phone
    // says Saturday while the room still counts (and credits) Friday for the
    // late sleepers. Without this, the strip had no Saturday cell at all
    // until 6 AM, so the calendar looked stuck on yesterday. Appending the
    // real day as a DISPLAY-ONLY cell gives the new square at midnight; it
    // carries the isRealToday ring, renders empty (no credit read for it),
    // and contributes nothing to any score — daysElapsedIn/creditFor still
    // stop at lastCountedDay, which is the whole flex-hours contract. Only
    // for a room that hasn't ended: a finished room's history is final.
    final realToday = DateTime.now().startOfDay;
    if (!room.isEnded && realToday.isAfter(last)) days.add(realToday);

    // Align to the Grid's Saturday-start weeks: pad invisible slots before
    // the first day so every date lands on its true weekday row (Sat=0 at
    // the top through Fri=6 at the bottom — same (weekday+1)%7 mapping
    // matrix_history_screen.dart's calendar uses).
    final lead = (days.first.weekday + 1) % 7;
    final slots = lead + days.length;
    final weekCount = (slots + 6) ~/ 7;

    final gp = context.gp;
    final s = S.of(context);
    final monthFmt = DateFormat('MMM', s.isAr ? 'ar' : 'en');

    // First day actually drawn in week column [w], or null for a column
    // made entirely of padding. Used to decide where a month label goes.
    DateTime? firstDayOf(int w) {
      for (var r = 0; r < 7; r++) {
        final i = w * 7 + r - lead;
        if (i >= 0 && i < days.length) return days[i];
      }
      return null;
    }

    // Columns where a new month begins — used only to widen the gap there,
    // so the months read as groups. The label itself is a single centred
    // title above the grid (below): a name floating over one 9pt column
    // pointed at nothing in particular and read as debris, which is exactly
    // what it looked like.
    List<int> columnsWithFirstOfMonth() {
      final out = <int>[];
      for (var w = 0; w < weekCount; w++) {
        for (var r = 0; r < 7; r++) {
          final i = w * 7 + r - lead;
          if (i >= 0 && i < days.length && days[i].day == 1) {
            out.add(w);
            break;
          }
        }
      }
      return out;
    }

    final monthStarts = columnsWithFirstOfMonth();

    /// Week-of-month for every column: 1 for the first week of a month, then
    /// 2, 3… restarting at each month boundary.
    ///
    /// Columns run chronologically, which under RTL means the newest is on
    /// the left — so a five-week month reads "5 4 3 2 1" across the screen
    /// and a four-week one reads "4 3 2 1", which is exactly the shape this
    /// row is meant to have.
    ///
    /// The month a column *belongs to* is the month of its first real day,
    /// so a week straddling the 31st and the 1st counts as the older month
    /// and the new month's numbering starts on the next column. That keeps
    /// every month's run of numbers unbroken rather than showing two 1s.
    final weekIndex = List<int>.filled(weekCount, 0);
    {
      var counter = 0;
      int? currentMonth;
      for (var w = 0; w < weekCount; w++) {
        final first = firstDayOf(w);
        if (first == null) {
          weekIndex[w] = 0; // all-padding column: nothing to number
          continue;
        }
        if (currentMonth != first.month) {
          currentMonth = first.month;
          counter = 1;
        } else {
          counter++;
        }
        weekIndex[w] = counter;
      }
    }

    // One title for the whole strip, naming the span rather than a single
    // month — a room that started 28 July and runs into August is showing
    // both, and labelling it just "أغسطس" quietly misdescribes the first
    // four columns.
    final firstMonth = monthFmt.format(days.first);
    final lastMonth = monthFmt.format(days.last);
    final monthTitle =
        firstMonth == lastMonth ? firstMonth : '$firstMonth – $lastMonth';

    // The whole strip is the tap target, and the only one. Its rendered
    // height (11pt label slot + 7 cells + 6 gaps ≈ 89pt) and full card width
    // clear HIG's 44pt several times over, which no individual 9pt cell can
    // ever do — see _ParticipantCalendarSheet's doc comment for why per-day
    // tapping is not solvable here at any size.
    //
    // Plain onTap, deliberately: it loses the gesture arena to a vertical
    // drag, so the enclosing ListView still scrolls and pull-to-refresh
    // still works. onPanDown/onLongPress would each steal that.
    return Semantics(
      button: true,
      label: s.roomStripOpenCalendar,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          showModalBottomSheet<void>(
            context: context,
            backgroundColor: Colors.transparent,
            isScrollControlled: true,
            builder: (_) => _ParticipantCalendarSheet(
              room: room,
              participant: participant,
              isYou: isYou,
            ),
          );
        },
        child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Reserved room for the "البداية" label, which is pinned to the
        // leading side of column 0. The grid is start-aligned, so in Arabic
        // column 0 sits hard against the card's right edge and that label
        // had nowhere to go — it clipped. Insetting the grid by the label's
        // own width guarantees the space instead of hoping the card is wide
        // enough, and costs nothing visually: the strip is a few columns
        // wide inside a full-width card either way.
        Padding(
          padding: const EdgeInsetsDirectional.only(start: _labelInset),
          child: LayoutBuilder(
          builder: (context, constraints) {
            // How many columns fit on one line.
            final perRun = ((constraints.maxWidth + _gap) / (_cell + _gap))
                .floor()
                .clamp(1, weekCount);

            // IntrinsicWidth so the Column is exactly as wide as its widest
            // run — which is what lets the title centre over the SQUARES
            // rather than over the card, the thing that made it look
            // randomly placed before.
            return IntrinsicWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    monthTitle,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: gp.textTert,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 5),
                  for (var run = 0; run * perRun < weekCount; run++) ...[
                    if (run > 0) const SizedBox(height: _gap * 2),
                    // Row, not Wrap — it follows the ambient Directionality,
                    // so weeks still run right-to-left in Arabic.
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var c = 0;
                            c < perRun && run * perRun + c < weekCount;
                            c++) ...[
                          // A wider gap wherever a new month begins, so the
                          // months read as groups. A gap and not a rule: the
                          // columns are 9pt and a divider would out-weigh
                          // the cells it separates.
                          if (c > 0)
                            SizedBox(
                              // A month boundary now gets 5x the ordinary
                              // gap (15pt vs 3pt), up from 3.5x. At the old
                              // ratio, with cells grown to 12pt, the month
                              // break was narrower than a cell and stopped
                              // reading as a break at all — the whole strip
                              // looked like one undifferentiated run. The
                              // gap has to beat the cell width to separate
                              // groups of cells.
                              width: monthStarts.contains(run * perRun + c)
                                  ? _gap * 5
                                  : _gap,
                            ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (showWeekNumbers) ...[
                                SizedBox(
                                  width: _cell,
                                  child: Text(
                                    // 0 means a column made entirely of
                                    // padding — there's no week there to
                                    // number, but the slot still has to
                                    // occupy its height or this column's
                                    // squares would sit higher than its
                                    // neighbours'.
                                    weekIndex[run * perRun + c] == 0
                                        ? ''
                                        : '${weekIndex[run * perRun + c]}',
                                    textAlign: TextAlign.center,
                                    textDirection: TextDirection.ltr,
                                    style: TextStyle(
                                      fontSize: 9,
                                      height: 1,
                                      fontWeight: FontWeight.w700,
                                      color: gp.textTert,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 3),
                              ],
                              for (var r = 0; r < 7; r++) ...[
                                if (r > 0) const SizedBox(height: _gap),
                                _cellFor(run * perRun * 7 + c * 7 + r - lead,
                                    days, dark, s, gp.textPrimary),
                              ],
                            ],
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            );
          },
          ),
        ),
      ],
        ),
      ),
    );
  }

  /// One day cell — or an invisible placeholder for the slots before the
  /// window starts / after it ends, kept full-size so every column is the
  /// same height and each row stays one straight weekday line.
  /// A label pinned beside a marked cell, rendered from inside a
  /// [Stack] with `Clip.none` so it costs the grid no layout at all — the
  /// cell still measures 9pt and every week column stays the same height.
  ///
  /// [towardsStart] puts it on the leading side (the right, in Arabic).
  /// Day 1 is always column 0 and today is always the last column, so each
  /// label sits on the grid's own outer edge and never crosses the cells.
  Widget _cellLabel(String text, Color color, bool towardsStart) {
    final label = Align(
      alignment: towardsStart
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: Text(
        text,
        softWrap: false,
        // No `height:` override. A line-height of 1.0 crops Arabic — its
        // glyphs carry more above and below the baseline than Latin does,
        // so a line box the size of the font clips the tops and tails off
        // letters like ي and م. The font's own default leaves room for them.
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
    // Real breathing room between the text and the cell it names. At 4pt
    // the two touched and read as one smudged object rather than a label
    // and its subject.
    const gapFromCell = 7.0;
    // Taller than the 9pt cell, and centred on it. Constraining the box to
    // the cell's own height was the other half of the cropping: 9pt is less
    // than one line of 9.5pt Arabic needs, so the text was clipped top and
    // bottom no matter what the style said. Overflowing is free here — the
    // parent Stack is Clip.none and the box costs no layout either way.
    const labelHeight = 18.0;
    const topOffset = (_cell - labelHeight) / 2;
    return towardsStart
        ? PositionedDirectional(
            start: -(_labelInset + gapFromCell),
            top: topOffset,
            height: labelHeight,
            width: _labelInset,
            child: label)
        : PositionedDirectional(
            end: -(_labelInset + gapFromCell),
            top: topOffset,
            height: labelHeight,
            width: _labelInset,
            child: label);
  }

  /// [startLabelColour] is the card's own foreground — passed in rather
  /// than read from a palette here, because the palette type is private to
  /// game_theme.dart and this isn't a build method with a context.
  Widget _cellFor(int index, List<DateTime> days, bool dark, S s,
      Color startLabelColour) {
    if (index < 0 || index >= days.length) {
      return const SizedBox(width: _cell, height: _cell);
    }
    final day = days[index];
    final key = day.toDateKey();
    // A day the quota (or a named-weekday schedule) asked nothing of
    // them. It scores as finished — see RoomParticipant.isRestDay —
    // but drawing it in the same full emerald as a day they actually
    // trained is what made this strip look like it disagreed with the
    // Grid: four workouts a week rendered as a solid week here and as
    // four squares there. An outline says "nothing was owed" without
    // claiming credit the person didn't earn, and without touching
    // what the day is worth.
    // Colour answers one question only: did they do the habit that
    // day. So a rest day reads empty, exactly like the Grid square
    // for it, and four workouts a week draw four cells in both
    // places. It still SCORES as finished — see
    // RoomParticipant.isRestDay and creditFor — so the row's
    // percentage and streak are unchanged and will sit higher than a
    // plain count of the coloured cells. That gap is deliberate: the
    // strip is a record of what was done, the percentage is a measure
    // of what was owed, and a flexible quota is exactly the case
    // where those two stop being the same number.
    final credit =
        participant.isRestDay(key) ? 0.0 : participant.creditFor(key);
    final isStart = index == 0;
    // isRealToday, not isToday: purely the "today" marker — see
    // DateTimeGameExt.isRealToday's doc comment.
    final isToday = day.isRealToday;
    final (outer, inner) = _markTones(dark);

    final cell = Container(
      width: _cell,
      height: _cell,
      decoration: BoxDecoration(
        // Unchanged, and deliberately still the ONLY thing answering "was the
        // habit done that day" — see the rest-day comment above. The markers
        // below are built entirely from shadows (outside the box) plus a 1pt
        // inset hairline, so they RING the fill rather than replace it, and
        // this strip keeps agreeing with the Grid square for the same day.
        color: heatColor(heatmapLevelFor(credit), dark),
        borderRadius: BorderRadius.circular(2.5),
        // Order matters: shadows paint in list order, then the fill, then the
        // border. blurRadius 0 installs no MaskFilter, so the second shadow
        // is a crisp 1pt outline rather than a smudge. spreadRadius grows it
        // OUTSIDE the 9pt box — zero fill area consumed and zero layout cost,
        // which is what stops this marker multiplying by participant count.
        // Offset.zero means no directionality, so it is identical under RTL.
        boxShadow: (isStart || isToday)
            ? [
                BoxShadow(
                  color: outer.withOpacity(0.38),
                  blurRadius: 2.4,
                  spreadRadius: 0.4,
                ),
                BoxShadow(color: outer, blurRadius: 0, spreadRadius: 1.0),
              ]
            : null,
        // Today keeps gold — it means "today" everywhere in this app. Day 1
        // takes the achromatic hairline, the one tone that cannot collide
        // with any preset.
        border: isToday
            ? Border.all(color: GameColors.gold, width: 1)
            : isStart
                ? Border.all(color: inner, width: 1)
                : null,
      ),
    );

    if (!isStart && !isToday) return cell;

    // The labels that replaced the legend row underneath the strip. That row
    // spelled out "البداية" once, far from the cell it described, and
    // repeated the room's start date a third time on the screen. Naming each
    // marked cell where it actually sits says the same thing in less space
    // and without the indirection.
    //
    // Clip.none matters: the labels are positioned outside the 9pt cell and
    // must not be clipped to it. They also cost no layout — the Stack sizes
    // to the cell alone.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        cell,
        if (isStart)
          // textPrimary, not one of the marker tones. The halo needs two
          // hardcoded extremes to survive every preset *on top of a cell*,
          // but a label sits on the CARD, where the palette's own foreground
          // is legible by definition — and reusing the ink tone there meant
          // near-black text on a near-black card in dark mode.
          // Always carries its date, not only for a late joiner. "Start"
          // alone names the cell but says nothing you couldn't already see;
          // the date answers the question the marker actually raises.
          //
          // MM/dd — month first, zero-padded — and identical in both
          // languages. "28/7" left it ambiguous which half was the month,
          // and the ambiguity is worse in Arabic: a date is a single
          // left-to-right numeric run even inside RTL text, so the leading
          // number stays on the left there too. Putting the month first
          // means the left-hand number is the month in every language, and
          // zero-padding keeps every label the same width.
          _cellLabel(
            // Built from parts, not DateFormat('MM/dd'). intl returns the
            // ASCII "07/28" for `ar` (probed, not assumed) yet this label
            // rendered ٠٧/٢٨ on device, next to Western numbers everywhere
            // else on the card — the substitution happens at render, so
            // normalising the *string* can't fix it. Plain interpolation is
            // what the Grid's day numbers and the 14-day chart's axis both
            // use, and neither has ever shown this.
            '${s.roomStripStart} '
            '${days.first.month.toString().padLeft(2, '0')}/'
            '${days.first.day.toString().padLeft(2, '0')}',
            startLabelColour,
            true,
          ),
        // Only when they are different cells: a one-day-old room makes today
        // day 1, and two labels on one 9pt square would overlap illegibly.
        // Gold, matching this cell's own ring, so the label and the marker
        // it names are visibly the same thing.
        if (isToday && !isStart)
          _cellLabel(s.progressToday, GameColors.gold, false),
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

  /// Passed straight through to this row's strip — see
  /// [_MiniHeatmapStrip.showWeekNumbers] for why it's one flag for the whole
  /// board, and why it is not called `showDetails`.
  final bool showWeekNumbers;

  const _LeaderboardRow({
    required this.rank,
    required this.participant,
    required this.room,
    required this.isYou,
    required this.isLeader,
    required this.showWeekNumbers,
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
    // findById, NOT findByIdOrDefault. On someone else's row an unknown id
    // must stay unknown: the OrDefault variant returns male1, a character a
    // member may genuinely have chosen, so a participant whose avatar we
    // don't actually know would render as a specific real person's look with
    // nothing marking it as a guess — two rows could show the same face, and
    // one of them would be wrong. Null draws a neutral silhouette instead.
    final character = CharacterCatalog.findById(participant.characterId);
    final accessory = AccessoryCatalog.findById(participant.accessoryId);
    // Same "nothing to show off yet" restraint as the Profile hero header's
    // own showsPrestigeTint - a null tier (doc from before this field
    // existed, self-heals on that person's next sync) and the base
    // "Seeker" tier both render nothing here rather than a chip everyone
    // would have from day one.
    final prestigeTier = PrestigeCatalog.findById(participant.prestigeTierId);
    final medalColor = _medalColor;
    final streak = participant.currentStreak(room);
    // Habit names are worth showing on someone else's row only in an 'own'
    // room, where each member links a habit of their own choosing and the
    // names genuinely differ. A 'shared' room clones one leader-curated plan
    // to everyone (see RoomHabitMode), so the name is identical for every
    // participant AND already printed in the header and the today card —
    // three copies of one fact, once per row.
    //
    // hideDetails is the privacy half: joining a plan with a friend to
    // compete on consistency alone, without publishing what you're actually
    // working on. Your own row always shows your own names — there is nobody
    // to hide them from.
    final showDetails = isYou || !participant.hideDetails;
    final names = room.habitMode == RoomHabitMode.own
        ? participant.linkedHabitNames
            .where((n) => n.trim().isNotEmpty)
            .toList()
        : const <String>[];

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
                  ? Icon(Icons.emoji_events_rounded,
                      size: 20, color: GameColors.gold)
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
          // A silhouette, not a stand-in character. Deliberately a plain
          // Material glyph so it can't be confused with any of the six real
          // options — "we don't know this yet" reads as exactly that, and
          // self-heals the moment that member's next progress sync writes
          // their real characterId (see RoomsController._profileFields).
          if (character == null)
            SizedBox(
              height: 42,
              width: 30,
              child: Center(
                child: Icon(Icons.person_rounded,
                    size: 26, color: gp.textTert.withOpacity(0.6)),
              ),
            )
          else
            CharacterAvatar(
                character: character, accessory: accessory, height: 42),
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
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: gp.textPrimary),
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
                _MiniHeatmapStrip(
                  room: room,
                  participant: participant,
                  isYou: isYou,
                  showWeekNumbers: showWeekNumbers,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius:
                            BorderRadius.circular(GameSpacing.pillRadius),
                        child: LinearProgressIndicator(
                          value: ratio,
                          backgroundColor: gp.border,
                          valueColor: AlwaysStoppedAnimation(
                              medalColor ?? GameColors.gold),
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
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: gp.textPrimary)),
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
                style:
                    TextStyle(fontSize: 11, color: gp.textSec, height: 1.35)),
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
          style: TextStyle(
              fontSize: 9.5, fontWeight: FontWeight.w700, color: color)),
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
            style: TextStyle(
                fontSize: 10.5, fontWeight: FontWeight.w800, color: tier.color),
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
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: gp.textPrimary)),
            const SizedBox(height: 6),
            Text(s.roomExtendBody,
                style:
                    TextStyle(fontSize: 12.5, color: gp.textSec, height: 1.35)),
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
                  errorText:
                      _customCtrl.text.trim().isEmpty || _customDays != null
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

  /// One switch for every strip on the board. Local and transient, never
  /// persisted — same treatment [_expanded] above gets, and the same reason:
  /// it's a way of looking at this screen right now, not a preference.
  bool _showDetails = false;

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
            showWeekNumbers: _showDetails,
          ),
        );

    final myIndex = sorted.indexWhere((p) => p.uid == widget.myUid);
    final myRowIsHidden = !showAll && myIndex >= visibleCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Sits above every strip, not inside one. A control inside a card
        // whose whole body is already a tap target (the strip opens the
        // calendar sheet) is a gesture fight; up here it's unambiguous, and
        // one switch keeps every row showing the same thing.
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _showDetails = !_showDetails);
              },
              // A filled-vs-outlined pill, not Icons.toggle_on/off_rounded.
              // Those two glyphs are directional, so Flutter auto-mirrors
              // them under RTL and the on and off states end up looking
              // nearly identical in Arabic — the switch appeared not to
              // respond even when the state had flipped. Fill is not
              // directional and carries the state on its own.
              child: AnimatedContainer(
                duration: GameMotion.quick,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: _showDetails
                      ? GameColors.emerald.withOpacity(0.16)
                      : Colors.transparent,
                  borderRadius:
                      BorderRadius.circular(GameSpacing.pillRadius),
                  border: Border.all(
                    color: _showDetails
                        ? GameColors.emerald.withOpacity(0.55)
                        : gp.border,
                    width: _showDetails ? 1.2 : 0.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _showDetails
                          ? Icons.check_circle_rounded
                          : Icons.circle_outlined,
                      size: 15,
                      color: _showDetails ? GameColors.emerald : gp.textTert,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      s.roomStripDetails,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _showDetails
                            ? GameColors.emerald
                            : gp.textSec,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
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

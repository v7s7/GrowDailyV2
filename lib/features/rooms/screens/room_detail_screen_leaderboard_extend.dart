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
/// The opaque fill for one cell of a participant's strip.
///
/// Opaque on purpose, and that is the whole reason this exists. Every heat
/// tone is translucent (see heatColor: emerald at 0.30 to 0.92), and the
/// البداية / اليوم markers are drawn as a BoxShadow with a spreadRadius —
/// which is a FILLED rounded rect, not a hollow ring, so it lands behind
/// the whole cell rather than only around it. A translucent fill then
/// composited over that plate instead of over the card, and the marked day
/// rendered a different colour from an unmarked day with identical credit:
/// a half-done first day washed out to pale "white green", a missed first
/// day (transparent fill) came out a solid white square, and a rest day
/// nearly so. Blending here means the plate can only ever show as the ring
/// it was meant to be.
///
/// [backdrop] must be the opaque colour actually behind the cell, so that
/// an UNMARKED cell is pixel-identical to what it drew before — see
/// _MiniHeatmapStrip._cellBackdrop, which resolves the gold-tinted "you"
/// card separately from everyone else's.
///
/// Pure and top-level so the invariant is testable without building the
/// whole room screen: same credit must give the same colour whether or not
/// the day happens to carry a marker.
Color roomStripCellFill({
  required double credit,
  required bool isRest,
  required bool isMissed,
  required bool dark,
  required Color backdrop,
  bool isDeclaredRest = false,
}) {
  // Order matters. A day the member deliberately stood down is checked
  // before the miss arm, because تخطّي is a choice somebody made and a miss
  // is the absence of one, and drawing them the same is precisely the thing
  // the personal reports stopped doing.
  //
  // GOLD, not emerald: the same tone the reports paint a rest with (see
  // report_sections.dart's MatrixCellState.rest), so the two surfaces name
  // the same act the same way. The emerald above is the STRUCTURAL rest,
  // a day where nothing was owed at all, which is a different fact.
  //
  // The fill does not change what the day SCORES. A declared rest still
  // earns whatever creditFor says it earned, which is nothing. See
  // RoomParticipant.dailyRestedCount for why that wall exists.
  final tone = isDeclaredRest
      ? GameColors.gold.withOpacity(0.16)
      : isRest
          ? GameColors.emerald.withOpacity(0.13)
          : isMissed
              ? Colors.transparent
              : heatColor(heatmapLevelFor(credit), dark);
  return Color.alphaBlend(tone, backdrop);
}

class _MiniHeatmapStrip extends StatelessWidget {
  final RoomModel room;
  final RoomParticipant participant;

  /// Only used to word the calendar's first-day note in the second person
  /// ("your first day") rather than the third. Nothing else in the strip
  /// varies by whose row it is.
  final bool isYou;

  const _MiniHeatmapStrip({
    required this.room,
    required this.participant,
    required this.isYou,
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
  static const double _cell = 15;
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
  /// The "week closed short" bar tone. A fixed literal, NOT GameColors.gold,
  /// for the same reason _markInk/_markPaper below are literals: every accent
  /// in this app is preset-derived, and in the green presets `gold` resolves
  /// to very nearly the same teal as `emerald` — so a short week and a
  /// perfect one drew the identical bar and the summary said nothing at all.
  /// This has to stay distinguishable from the emerald in all 11 presets,
  /// which only a fixed hue can promise.
  static const Color _weekShort = Color(0xFFD9A441);

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
    final backdrop = _cellBackdrop(context);
    // Their own window, so a late joiner's strip starts the day they joined
    // rather than showing weeks of grey for a room they weren't in yet.
    // The CALENDAR span, not the scored day count. Those two stopped being
    // the same number once pauses existed: daysElapsedIn deliberately
    // excludes paused days, so deriving the window from it made the strip
    // start N days late and never draw the room's real first days — the
    // البداية ring landed on the wrong square and the visible cells no
    // longer matched the denominator beside them. Paused days stay in the
    // window and simply paint nothing (see _cellFor).
    final windowStart = participant.countedStartIn(room);
    final last = room.lastCountedDay;
    final span = last.difference(windowStart).inDays + 1;
    final totalDays = room.duration == RoomDuration.open
        ? span.clamp(1, _maxOpenRoomDays)
        : (span < 1 ? 1 : span);
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

    // Weekday rows that no day of this room actually lands on are not drawn.
    //
    // The grid reserves all seven Sat–Fri rows so a horizontal slice means
    // "every Saturday", which is right for a room of any length — except a
    // very short one, where it is mostly emptiness. A room that began on a
    // Friday and is four days old fills exactly four cells: one alone on the
    // bottom row of the first column, three at the top of the second, and
    // three entirely blank rows between them. The squares read as scattered
    // debris and the البداية marker, pinned to that lone first cell, floated
    // far below everything with nothing beside it.
    //
    // Dropping the unused rows collapses that gap without touching the
    // meaning of the ones that remain: each is still one weekday, columns
    // are still weeks, and every day the room has drawn stays exactly where
    // its weekday puts it. For any room two weeks or longer every row is
    // used, so this changes nothing at all there.
    final usedRows = <int>[];
    for (var r = 0; r < 7; r++) {
      for (var w = 0; w < weekCount; w++) {
        final i = w * 7 + r - lead;
        if (i >= 0 && i < days.length) {
          usedRows.add(r);
          break;
        }
      }
    }

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

    // Dead since the single strip-wide title was replaced by per-column
    // month segments (_monthSegments), which label each column run with
    // its own month instead of naming the whole span once. Removed rather
    // than left dangling: it still formatted two dates on every rebuild of
    // every row.

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
        onTap: () => showParticipantSheet(
          context,
          room: room,
          participant: participant,
          isYou: isYou,
        ),
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
                  final perRun =
                      ((constraints.maxWidth + _gap) / (_cell + _gap))
                          .floor()
                          .clamp(1, weekCount);

                  // IntrinsicWidth so the Column is exactly as wide as its widest
                  // run — which is what lets the title centre over the SQUARES
                  // rather than over the card, the thing that made it look
                  // randomly placed before.
                  return IntrinsicWidth(
                    child: Column(
                      children: [
                        for (var run = 0; run * perRun < weekCount; run++) ...[
                          if (run > 0) const SizedBox(height: _gap * 2),
                          // The merged-header band: one label per month,
                          // centred over exactly the columns that belong to
                          // it and no others — the spreadsheet shape, where
                          // "أغسطس" spans its own five week columns and stops.
                          //
                          // Replaces a single "يوليو – أغسطس" centred over
                          // everything, which named a span without saying
                          // where one month ended, so the week numbers under
                          // it (they restart at 1 each month) looked like a
                          // counter resetting for no reason. Segment widths
                          // are derived from the very same _cell/_gap
                          // constants the row below uses, so the header can
                          // never drift out of alignment with its columns.
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final seg in _monthSegments(
                                run,
                                perRun,
                                weekCount,
                                firstDayOf,
                                monthFmt,
                              )) ...[
                                if (seg.leadingBreak)
                                  const SizedBox(width: _gap * 5),
                                SizedBox(
                                  width:
                                      seg.span * _cell + (seg.span - 1) * _gap,
                                  // Centred over its own columns, and allowed
                                  // to spill past them rather than truncate.
                                  // A month that only owns one 15pt column —
                                  // the tail of the month a room started in —
                                  // cannot fit "يوليو" and was rendering as
                                  // "يو…", which names nothing. The overflow
                                  // lands in the wider month-break gap beside
                                  // it, and the neighbouring label is centred
                                  // over three or more columns, so the two
                                  // never reach each other.
                                  child: Text(
                                    seg.label,
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    softWrap: false,
                                    overflow: TextOverflow.visible,
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w700,
                                      color: gp.textTert,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          // Row, not Wrap — it follows the ambient
                          // Directionality, so column 0 (the oldest week, and
                          // therefore the first month) sits hard against the
                          // RIGHT edge in Arabic and time runs right to left,
                          // the same way the Grid's days do.
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (var c = 0;
                                  c < perRun && run * perRun + c < weekCount;
                                  c++) ...[
                                if (c > 0)
                                  SizedBox(
                                    width:
                                        monthStarts.contains(run * perRun + c)
                                            ? _gap * 5
                                            : _gap,
                                  ),
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: _cell,
                                      child: Text(
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
                                    const SizedBox(height: 2),
                                    // How the week went, in the one channel a
                                    // 12pt column has room for: green once
                                    // every day in it is settled, amber for a
                                    // closed week that fell short, faint while
                                    // it is still running. Reads the same
                                    // creditFor the percentage reads, so it
                                    // can never contradict the number at the
                                    // top of the card.
                                    Container(
                                      width: _cell,
                                      height: 2.5,
                                      decoration: BoxDecoration(
                                        color: _weekTone(
                                          run * perRun + c,
                                          lead,
                                          days,
                                          gp.border,
                                        ),
                                        borderRadius:
                                            BorderRadius.circular(1.5),
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    for (var ri = 0;
                                        ri < usedRows.length;
                                        ri++) ...[
                                      if (ri > 0) const SizedBox(height: _gap),
                                      _cellFor(
                                        run * perRun * 7 +
                                            c * 7 +
                                            usedRows[ri] -
                                            lead,
                                        days,
                                        dark,
                                        s,
                                        gp.textPrimary,
                                        backdrop,
                                      ),
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
            child: label,
          )
        : PositionedDirectional(
            end: -(_labelInset + gapFromCell),
            top: topOffset,
            height: labelHeight,
            width: _labelInset,
            child: label,
          );
  }

  /// [startLabelColour] is the card's own foreground — passed in rather
  /// than read from a palette here, because the palette type is private to
  /// game_theme.dart and this isn't a build method with a context.
  /// The colour of one week column's summary bar.
  ///
  /// Answers "how did this week go" in the one channel a 12pt column has
  /// room for. Green once every day in the week is settled — done, or a rest
  /// day that owed nothing; amber for a closed week that fell short; grey
  /// while the week is still running, because nothing is lost yet.
  ///
  /// Deliberately reads the same creditFor the percentage reads, rather than
  /// counting coloured squares, so the bar can never contradict the number
  /// at the top of the card the way a square count does.
  Color _weekTone(int w, int lead, List<DateTime> days, Color neutral) {
    var settled = 0;
    var real = 0;
    var open = false;
    for (var r = 0; r < 7; r++) {
      final i = w * 7 + r - lead;
      if (i < 0 || i >= days.length) continue;
      final day = days[i];
      if (day.isAfter(room.lastCountedDay)) continue;
      real++;
      if (participant.creditFor(day.toDateKey()) >= 1.0) settled++;
      if (!_weekIsClosed(day)) open = true;
    }
    if (real == 0) return neutral;
    if (settled == real) return GameColors.emerald;
    return open ? neutral : _weekShort;
  }

  /// The month labels for one run of week columns, each with how many
  /// columns it spans.
  ///
  /// [leadingBreak] marks a segment that follows a month change, so the
  /// header inserts the same wider gap the column row inserts there
  /// (monthStarts → `_gap * 5`). Deriving both from the same rule is what
  /// keeps a label centred over its own weeks instead of drifting a few
  /// points off as the strip gets longer.
  ///
  /// A column made entirely of padding has no first day and therefore no
  /// month of its own; it joins whatever segment precedes it rather than
  /// starting a new one, so a week straddling a month boundary never
  /// produces a stray one-column header.
  List<({String label, int span, bool leadingBreak})> _monthSegments(
    int run,
    int perRun,
    int weekCount,
    DateTime? Function(int) firstDayOf,
    DateFormat monthFmt,
  ) {
    final out = <({String label, int span, bool leadingBreak})>[];
    for (var c = 0; c < perRun && run * perRun + c < weekCount; c++) {
      final first = firstDayOf(run * perRun + c);
      final label = first == null ? null : monthFmt.format(first);
      if (out.isEmpty || (label != null && label != out.last.label)) {
        out.add(
          (
            label: label ?? (out.isEmpty ? '' : out.last.label),
            span: 1,
            leadingBreak: out.isNotEmpty,
          ),
        );
      } else {
        final last = out.removeLast();
        out.add(
          (
            label: last.label,
            span: last.span + 1,
            leadingBreak: last.leadingBreak,
          ),
        );
      }
    }
    return out;
  }

  /// Whether a day with no credit is genuinely lost, and can be crossed out.
  ///
  /// Today is never marked — it is still doable, and a square un-ticked in
  /// the Grid five seconds ago shouldn't turn red while the person is still
  /// working on it.
  ///
  /// Past days split on the habit's own rule, because "you can still save
  /// this" only means something for a weekly quota. A DAILY habit's
  /// yesterday is simply gone: uncheck it in the Grid and it is a miss the
  /// moment the day ends, so it is crossed out immediately — which is what
  /// makes the room agree with the Grid square the user just changed.
  /// A QUOTA habit's yesterday is different: while its week is open, every
  /// un-done day is only provisionally owed, and finishing the week converts
  /// them all back into rest days. Crossing those out live would condemn
  /// days the person is about to rescue, so the quota case waits for the
  /// week to close.
  bool _missIsFinal(DateTime day) {
    if (day.isRealToday || day.isAfter(room.lastCountedDay)) return false;
    final onQuota = participant.countedHabitIds.any(
      (id) =>
          participant.ruleFor(id, day.toDateKey())?.frequencyType ==
          HabitFrequencyType.weekly,
    );
    return onQuota ? _weekIsClosed(day) : true;
  }

  /// Whether the Saturday week containing [day] has finished counting.
  ///
  /// The quota grader only settles a week once it is over: while a week is
  /// still running and its target isn't met yet, *every* elapsed day in it is
  /// treated as answerable, so an un-done day reads as a miss even though
  /// finishing the week would turn it back into a rest day. Nothing is
  /// actually lost until the week closes, so nothing is crossed out until
  /// then either. Mirrors isQuotaWeekClosed in rooms_notifier.dart.
  bool _weekIsClosed(DateTime day) => day.startOfDisplayWeek
      .add(const Duration(days: 6))
      .isBefore(room.lastCountedDay);

  /// The opaque colour sitting immediately behind a cell.
  ///
  /// Needed because every heat tone is semi-transparent (see heatColor:
  /// emerald at 0.30-0.92) and the البداية/اليوم markers paint a SOLID
  /// ring behind the cell. A spreadRadius BoxShadow is a filled rounded
  /// rect, not a hollow ring, so it lands under the whole cell and the
  /// translucent fill then composited over WHITE instead of over the card:
  /// day one of a half-done day rendered as a washed-out pale green that
  /// did not match its own heat level, and a first day that was a MISS
  /// (transparent fill) rendered as a solid white square. Compositing the
  /// fill against this first makes it opaque, so the ring stays a ring.
  ///
  /// Computed rather than assumed: the "you" card is a translucent gold
  /// over the page, not gp.surface, so blending everything against
  /// gp.surface would tint your own row differently from everyone else's.
  Color _cellBackdrop(BuildContext context) {
    final gp = context.gp;
    return isYou
        ? Color.alphaBlend(GameColors.gold.withOpacity(0.06), gp.bg)
        : gp.surface;
  }

  Widget _cellFor(
    int index,
    List<DateTime> days,
    bool dark,
    S s,
    Color startLabelColour,
    Color backdrop,
  ) {
    if (index < 0 || index >= days.length) {
      return const SizedBox(width: _cell, height: _cell);
    }
    final day = days[index];
    final key = day.toDateKey();
    // Dead time between an ending and an extension draws nothing: the room
    // did not exist those days, so they are neither a miss nor a rest day,
    // and they are excluded from the score too (RoomModel.pausedSpans).
    //
    // A blank placeholder, NOT a removal from `days`. The column maths below
    // is `w * 7 + r - lead`, which only holds while `days` is a contiguous
    // calendar run — dropping days from the middle would slide every later
    // cell onto the wrong weekday row and quietly destroy the one property
    // the week-column layout exists for. So the gap stays in the list and
    // simply paints nothing, which also reads correctly: a visible break
    // where the room was paused.
    if (room.isPausedOn(key)) {
      return const SizedBox(width: _cell, height: _cell);
    }
    // Four states, not two, and the reason is that "empty" used to mean
    // both "nothing was owed" and "you missed it".
    //
    // A rest day — the quota or a named-weekday schedule asked nothing of
    // them — scores a full 1.0 (RoomParticipant.isRestDay, creditFor). It
    // used to paint empty so the strip would match the Grid square for the
    // same day. That made the strip honest about *training* and silent
    // about *scoring*, and the visible cost was a card reading 76% above a
    // row of squares that plainly didn't add up to 76%. It now paints as a
    // faint outline: clearly credited, clearly not a session, distinct from
    // both a full square and a miss.
    //
    // A missed day gets a red cross — but only once its week is closed.
    // Inside a running week every not-yet-done day is technically "owed"
    // (see the quota grader: an open week under target makes every elapsed
    // day answerable), so crossing them out live would condemn days the
    // person can still rescue by finishing the week. Until the week ends
    // they stay neutral.
    final isRest = participant.isRestDay(key);
    final credit = participant.creditFor(key);
    // A declared rest is settled the instant it is marked, so it bypasses the
    // _missIsFinal week gate entirely: there is nothing left to rescue on a
    // day somebody has already said they are resting.
    final isDeclaredRest = participant.isDeclaredRest(key);
    final isMissed =
        !isRest && !isDeclaredRest && credit <= 0 && _missIsFinal(day);
    final isStart = index == 0;
    // isRealToday, not isToday: purely the "today" marker — see
    // DateTimeGameExt.isRealToday's doc comment.
    final isToday = day.isRealToday;
    final (outer, inner) = _markTones(dark);

    final cell = Container(
      width: _cell,
      height: _cell,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        // A rest day is a tinted outline, a miss is a red wash, and anything
        // actually done keeps the heat ramp it has always used — so this
        // strip still agrees with the Grid square on the one question the
        // ramp answers ("how much did you do"), while no longer drawing
        // "nothing was owed" and "you missed it" as the same empty box.
        // A miss is an outline and a mark, not a red block. Filled, a month
        // of missed days turned the whole card into a red wall that read as
        // an error state rather than as a record — and on a daily habit,
        // where every single day is owed, that is most of the strip. Kept
        // faint enough to recede and specific enough to count.
        color: roomStripCellFill(
          credit: credit,
          isRest: isRest,
          isMissed: isMissed,
          isDeclaredRest: isDeclaredRest,
          dark: dark,
          backdrop: backdrop,
        ),
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
                BoxShadow(color: outer, spreadRadius: 1.0),
              ]
            : null,
        // Today keeps gold — it means "today" everywhere in this app. Day 1
        // takes the achromatic hairline, the one tone that cannot collide
        // with any preset.
        border: isToday
            ? Border.all(color: GameColors.gold)
            : isStart
                ? Border.all(color: inner)
                : isRest
                    ? Border.all(
                        color: GameColors.emerald.withOpacity(0.42),
                      )
                    : isMissed
                        ? Border.all(
                            color: GameColors.error.withOpacity(0.34),
                          )
                        : null,
      ),
      // A cross, not just a red box: at 12pt the tint alone is easy to read
      // as "some other shade of done", and the mark is what makes a miss
      // unmistakable at a glance. CustomPaint rather than a glyph so it
      // scales with the cell and needs no font metrics.
      child: isMissed
          ? CustomPaint(
              size: const Size(_cell * 0.46, _cell * 0.46),
              painter: _MissCrossPainter(GameColors.error.withOpacity(0.62)),
            )
          : null,
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

/// The × on a missed day. Two strokes with rounded caps, inset so they never
/// touch the cell's own 1pt border — at 12pt a cross drawn corner to corner
/// reads as a filled box rather than a mark.
class _MissCrossPainter extends CustomPainter {
  final Color color;

  const _MissCrossPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset.zero, Offset(size.width, size.height), paint);
    canvas.drawLine(Offset(size.width, 0), Offset(0, size.height), paint);
  }

  @override
  bool shouldRepaint(_MissCrossPainter old) => old.color != color;
}

class _LeaderboardRow extends ConsumerWidget {
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

  /// How demanding this member's plan is — "4× a week", "Daily", or a count
  /// when their linked habits don't agree.
  ///
  /// Read from the room's FROZEN rule, not the habit's current settings,
  /// because the frozen rule is what the percentage beside it is actually
  /// computed from. Showing the live value would put a number next to a
  /// percentage that disagrees with it, which is the same class of silent
  /// mismatch that made one member read 57% for the same work another read
  /// 76% for.
  ///
  /// Multi-habit plans are handled by deduping: three habits all at 4x read
  /// as one "4× a week", while a genuinely mixed plan names the count rather
  /// than pick a winner and mislead.
  ///
  /// Null when nothing is linked, or when no rule has been recorded yet —
  /// better to show nothing than to guess a cadence.
  String? _cadenceLabel(S s) {
    final today = DateTime.now().effectiveDay.toDateKey();
    final labels = <String>{};
    for (final id in participant.countedHabitIds) {
      final rule = participant.ruleFor(id, today);
      if (rule == null) continue;
      labels.add(
        rule.frequencyType == HabitFrequencyType.weekly
            ? s.roomCadenceWeekly(rule.frequencyTarget)
            : s.roomCadenceDaily,
      );
    }
    if (labels.isEmpty) return null;
    if (labels.length == 1) return labels.first;
    return s.roomCadenceMixed(participant.countedHabitIds.length);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

    final card = Container(
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
                  ? Icon(
                      Icons.emoji_events_rounded,
                      size: 20,
                      color: GameColors.gold,
                    )
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
                child: Icon(
                  Icons.person_rounded,
                  size: 26,
                  color: gp.textTert.withOpacity(0.6),
                ),
              ),
            )
          else
            CharacterAvatar(
              character: character,
              accessory: accessory,
              height: 42,
            ),
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
                          color: gp.textPrimary,
                        ),
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
                    // Inline null-check (not a separate bool) so Dart
                    // actually promotes prestigeTier to non-null for the
                    // _PrestigeChip call - a bool computed from the same
                    // check earlier doesn't carry that promotion through.
                    //
                    // On the name's own row rather than stacked under it.
                    // The chip is short and the row had spare width, while
                    // the second line cost every card ~20pt of height that
                    // the history grid underneath wanted far more. The name
                    // stays Flexible so it ellipsizes before the badges do —
                    // the badges are the part you scan, the full name is
                    // recoverable by opening the row.
                    if (prestigeTier != null && prestigeTier.minLevel > 1) ...[
                      const SizedBox(width: 6),
                      _PrestigeChip(tier: prestigeTier),
                    ],
                    // Report/block, on everyone but yourself. An explicit
                    // control rather than a long-press: the card body is
                    // already a tap target (it opens the calendar), and a
                    // moderation affordance nobody can find satisfies
                    // neither an upset user nor App Review guideline 1.2.
                    if (!isYou) ...[
                      const SizedBox(width: 2),
                      SizedBox(
                        width: 30,
                        height: 30,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          iconSize: 17,
                          color: gp.textTert,
                          tooltip: s.roomMemberActions,
                          icon: const Icon(Icons.more_horiz_rounded),
                          onPressed: () => showMemberOptions(
                            context,
                            ref: ref,
                            roomCode: room.code,
                            memberUid: participant.uid,
                            memberName: participant.displayName,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
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
                            medalColor ?? GameColors.gold,
                          ),
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
                            const Icon(
                              Icons.local_fire_department_rounded,
                              size: 12,
                              color: GameColors.iconStreak,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              '$streak',
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: GameColors.iconStreak,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 9),
                    ],
                    Text(
                      s.roomDayCount(
                        participant.daysCompleted(room),
                        participant.daysElapsedIn(room),
                      ),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${(ratio * 100).round()}%',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: gp.textPrimary,
                  ),
                ),
                // Directly under the number it explains. Two members in one
                // room can be graded on different terms — a 4x/week quota
                // turns its untrained days into full credit, a daily habit
                // never does — so identical effort can print very different
                // percentages. Without the cadence beside it that gap looks
                // arbitrary; with it, it's just the plan.
                // Deliberately NOT behind hideDetails, unlike the
                // habit-name chips. That flag hides WHAT someone is working
                // on, which is private; this is HOW HARD their plan is,
                // which is the denominator of a number already on public
                // display. Hiding it protects nothing — the percentage is
                // still there — it only makes the gap between two members
                // unexplainable, which is the exact confusion this badge
                // exists to remove.
                Builder(
                  builder: (_) {
                    final label = _cadenceLabel(s);
                    if (label == null) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: gp.textTert,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );

    // The WHOLE card opens the member, not only the strip inside it.
    //
    // The strip has been the tap target since it was written, for a reason of
    // its own: its 9pt cells can never be tapped individually, so it routes to
    // a full-size surface. But that left the two things a person actually aims
    // at, the name and the face, doing nothing at all. You tap someone to find
    // out about them, and the app ignored you.
    //
    // Plain onTap, for the same reason the strip uses one: it loses the
    // gesture arena to a vertical drag, so the enclosing list still scrolls
    // and pull-to-refresh still works. The strip's own detector and the "..."
    // actions button both sit inside this one and still take their own taps,
    // because a child claims the arena before its ancestor does.
    return GestureDetector(
      onTap: () => showParticipantSheet(
        context,
        room: room,
        participant: participant,
        isYou: isYou,
      ),
      child: card,
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
          const Icon(Icons.warning_amber_rounded,
              size: 15, color: GameColors.error),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 11, color: gp.textSec, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens one member's sheet.
///
/// Shared by the whole leaderboard card and by the contribution strip inside
/// it, so the two can never drift into opening different things, and so the
/// strip's own long-standing tap keeps behaving exactly as before.
void showParticipantSheet(
  BuildContext context, {
  required RoomModel room,
  required RoomParticipant participant,
  required bool isYou,
}) {
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
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
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
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: tier.color,
            ),
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
            Text(
              s.roomExtendTitle,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: gp.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              s.roomExtendBody,
              style: TextStyle(fontSize: 12.5, color: gp.textSec, height: 1.35),
            ),
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
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
            color: selected ? GameColors.gold : gp.textPrimary,
          ),
        ),
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
class _LeaderboardList extends ConsumerStatefulWidget {
  final List<RoomParticipant> sorted;
  final RoomModel room;
  final String? myUid;
  const _LeaderboardList({
    required this.sorted,
    required this.room,
    required this.myUid,
  });

  @override
  ConsumerState<_LeaderboardList> createState() => _LeaderboardListState();
}

class _LeaderboardListState extends ConsumerState<_LeaderboardList> {
  static const int _initialRows = 20;
  bool _expanded = false;
  /// Lets someone look past their own block without undoing it — the same
  /// escape hatch every "hidden content" affordance needs, and the reason
  /// blocking here can stay a view filter rather than a destructive act.
  bool _showBlocked = false;

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final blocked = ref.watch(blockedMembersProvider);
    // Ranks are computed BEFORE filtering, deliberately: blocking someone
    // hides their row, it does not promote you past them. A leaderboard
    // that silently renumbered itself per viewer would make blocking a way
    // to fake your own standing.
    final all = widget.sorted;
    final hiddenCount =
        blocked.isEmpty ? 0 : all.where((p) => blocked.contains(p.uid)).length;
    final sorted = (blocked.isEmpty || _showBlocked)
        ? all
        : all.where((p) => !blocked.contains(p.uid)).toList();
    final showAll = _expanded || sorted.length <= _initialRows;
    final visibleCount = showAll ? sorted.length : _initialRows;

    Widget rowAt(int i) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _LeaderboardRow(
            rank: all.indexOf(sorted[i]) + 1,
            participant: sorted[i],
            room: widget.room,
            isYou: sorted[i].uid == widget.myUid,
            isLeader: sorted[i].uid == widget.room.createdBy,
          ),
        );

    final myIndex = sorted.indexWhere((p) => p.uid == widget.myUid);
    final myRowIsHidden = !showAll && myIndex >= visibleCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hiddenCount > 0) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(Icons.block_rounded, size: 13, color: gp.textTert),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    s.roomBlockedHidden(hiddenCount),
                    style: TextStyle(fontSize: 11.5, color: gp.textTert),
                  ),
                ),
                TextButton(
                  onPressed: () =>
                      setState(() => _showBlocked = !_showBlocked),
                  child: Text(_showBlocked
                      ? s.roomCancel
                      : s.roomBlockedShow),
                ),
              ],
            ),
          ),
        ],
        // Sits above every strip, not inside one. A control inside a card
        // whose whole body is already a tap target (the strip opens the
        // calendar sheet) is a gesture fight; up here it's unambiguous, and
        // one switch keeps every row showing the same thing.
        for (var i = 0; i < visibleCount; i++) rowAt(i),
        if (myRowIsHidden) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(child: Divider(color: gp.border, height: 1)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    '⋯',
                    style: TextStyle(fontSize: 15, color: gp.textTert),
                  ),
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

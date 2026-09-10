part of 'room_detail_screen.dart';

/// One participant's room history as a real calendar — the surface the
/// contribution strip opens into.
///
/// This exists because the strip's cells are 9pt and can never be tapped. A
/// 9pt cell is roughly a fifth of HIG's 44pt minimum and a quarter of
/// Material's 48dp, and WCAG 2.2's spacing exception doesn't rescue it
/// either: at an 11.5pt pitch a 24px circle centred on any cell overlaps all
/// four of its neighbours. It also sits inside a vertical ListView, which
/// would win most of those gestures on touch slop alone. Every product that
/// draws a contribution graph on a phone solves this the same way — GitHub,
/// Apple Fitness, Duolingo, Streaks all route you through a larger control
/// to a full-size surface — so the strip is one tap target and the day is
/// chosen here, where a cell is ~40pt square.
///
/// Reads nothing new: the fills come from the same [heatColor] /
/// [heatmapLevelFor] pair the strip and the Grid heatmap already share, so
/// a day is the same colour in all three places.
class _ParticipantCalendarSheet extends StatefulWidget {
  final RoomModel room;
  final RoomParticipant participant;
  final bool isYou;

  const _ParticipantCalendarSheet({
    required this.room,
    required this.participant,
    required this.isYou,
  });

  @override
  State<_ParticipantCalendarSheet> createState() =>
      _ParticipantCalendarSheetState();
}

class _ParticipantCalendarSheetState extends State<_ParticipantCalendarSheet> {
  late DateTime _month;
  DateTime? _selected;

  /// This participant's own first counted day — for a late joiner that's the
  /// day they joined, not the room's start, which is exactly the distinction
  /// the strip's "البداية" marker makes.
  late final DateTime _firstDay;
  late final DateTime _lastDay;

  @override
  void initState() {
    super.initState();
    _lastDay = widget.room.lastCountedDay;
    // countedStartIn, not lastCountedDay minus daysElapsedIn: the latter
    // excludes paused days, so after an extension it placed _firstDay days
    // late and dimmed the room's real opening days as "outside your window"
    // even though they are graded.
    _firstDay = widget.participant.countedStartIn(widget.room);
    // Opens on the month containing the most recent activity rather than on
    // the room's first month — with a 90-day room those differ, and the end
    // is what someone checking a leaderboard is asking about.
    _month = DateTime(_lastDay.year, _lastDay.month);
  }

  bool get _canGoBack =>
      _month.isAfter(DateTime(_firstDay.year, _firstDay.month));
  bool get _canGoForward =>
      _month.isBefore(DateTime(_lastDay.year, _lastDay.month));

  /// Null for any day outside this participant's window — those cells draw
  /// as dimmed numbers with no fill, so the month keeps its true shape
  /// without implying there's history behind days there is none for.
  Color? _fillFor(DateTime day, bool dark) {
    if (day.isBefore(_firstDay) || day.isAfter(_lastDay)) return null;
    final key = day.toDateKey();
    // A day the whole room was paused is not this member's day to answer
    // for, and neither is a day their whole plan stood down: nothing was
    // asked and nothing was earned. Both take the neutral tone the strip's
    // dash sits on (roomStripCellFill's isStoodDown arm), not the emerald of
    // a structural rest (which is credited) and not the heat ramp's level-0,
    // which is byte-identical to a miss. The paused day used to return null
    // here and draw as a bare number, the same hole the strip used to leave.
    if (widget.room.isPausedOn(key) ||
        widget.participant.isStoodDownOn(key)) {
      return (dark ? Colors.white : Colors.black).withOpacity(0.07);
    }
    // A deliberate تخطّي gets the same gold the strip and the personal
    // reports give it, so one act has one colour everywhere. It does NOT
    // change what the day scored, which is still nothing.
    if (widget.participant.isDeclaredRest(key)) {
      return GameColors.gold.withOpacity(0.16);
    }
    // A STRUCTURAL rest - the quota or a named-weekday schedule asked nothing
    // of them - gets the faint emerald the leaderboard strip already paints it
    // (see roomStripCellFill's isRest arm in
    // room_detail_screen_leaderboard_extend.dart), not a collapse to 0.0.
    //
    // Collapsing to 0.0 sent it through heatmapLevelFor -> level 0 ->
    // SquareState.none.fill, which is byte-identical to a miss. So the cell
    // was drawn as "you missed this" while _statusFor beside it returned
    // roomCalendarRestDay, and _statusFor's own comment claims the word and
    // the colour can never describe two different things about one square.
    // They did, on every rest day, which is most of the week for a 4x quota.
    if (widget.participant.isRestDay(key)) {
      return roomStripRestTone();
    }
    return heatColor(
      heatmapLevelFor(widget.participant.creditFor(key)),
      dark,
    );
  }

  /// Start and today, ringed the same way the strip rings them, so the two
  /// surfaces agree about which day is which.
  BoxBorder? _markerFor(DateTime day) {
    if (day.isRealToday) {
      return Border.all(color: GameColors.gold, width: 1.6);
    }
    if (day.isSameDayAs(_firstDay)) {
      return Border.all(color: context.gp.textPrimary, width: 1.6);
    }
    return null;
  }

  /// Whether the day has a score to show at all: inside this member's own
  /// window, and neither paused by the room nor stood down by them. Those
  /// two are answered by a reason, not a fraction, exactly as [_statusFor]
  /// answers them, and computing 0/0 for either would put a number on a day
  /// nobody was asked about.
  bool _isScoredDay(DateTime day) {
    if (day.isBefore(_firstDay) || day.isAfter(_lastDay)) return false;
    final key = day.toDateKey();
    return !widget.room.isPausedOn(key) &&
        !widget.participant.isStoodDownOn(key);
  }

  String _statusFor(DateTime day, S s) {
    final key = day.toDateKey();
    // Same precedence as _fillFor above, so the word and the colour can
    // never describe two different things about one square.
    if (widget.room.isPausedOn(key)) return s.roomCalendarPaused;
    if (widget.participant.isStoodDownOn(key)) {
      return s.roomCalendarHabitPaused;
    }
    if (widget.participant.isRestDay(key)) return s.roomCalendarRestDay;
    if (widget.participant.isDeclaredRest(key)) {
      return s.roomCalendarStoodDown;
    }
    final credit = widget.participant.creditFor(key);
    if (credit >= 1.0) return s.roomCalendarDone;
    if (credit > 0) return s.roomCalendarPartial;
    // Nothing done YET is not the same as missed. Under the overlapping-day
    // window a day stays markable until kDayCutoffHour the next morning, and
    // the strip already refuses to cross one out before then. This used to
    // call the same day "لم يُنجز" ten hours early.
    if (!roomDayIsClosedAt(day, DateTime.now())) {
      return s.roomCalendarStillOpen;
    }
    return s.roomCalendarMissed;
  }

  /// Whether [day] can still be marked: today, or yesterday before the
  /// cutoff. The card draws an unearned but still-open day in a neutral tone
  /// rather than the red of a miss.
  bool _isOpenDay(DateTime day) =>
      !roomDayIsClosedAt(day, DateTime.now());

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final dark = gp.dark;
    final selected = _selected;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        20 + MediaQuery.of(context).padding.bottom,
      ),
      child: Container(
        // Capped and scrollable. The header below is deliberately tall (the
        // character is the point of opening a member), and a Column with
        // mainAxisSize.min will happily overflow a short phone in landscape
        // or at a large text size rather than scroll.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.86,
        ),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        decoration: BoxDecoration(
          color: gp.surfaceHigh,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: gp.border),
        ),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: gp.border,
                  borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Who this is, before what they did.
            //
            // The sheet used to open on a bare "تقويم m7md" and a grid of
            // squares, which answers "when" without ever answering "who".
            // Opening a person's row is the one moment their identity is the
            // subject, and the room already carries everything needed to say
            // it: their chosen character and accessory, their title, and the
            // three numbers the leaderboard row is ranked on. None of it
            // costs a read.
            _ParticipantHeader(
              room: widget.room,
              participant: widget.participant,
              isYou: widget.isYou,
            ),
            const SizedBox(height: 4),
            CalendarMonthHeader(
              month: _month,
              canGoBack: _canGoBack,
              canGoForward: _canGoForward,
              onBack: () {
                HapticFeedback.selectionClick();
                setState(
                    () => _month = DateTime(_month.year, _month.month - 1));
              },
              onForward: () {
                HapticFeedback.selectionClick();
                setState(
                    () => _month = DateTime(_month.year, _month.month + 1));
              },
            ),
            const SizedBox(height: 6),
            const CalendarWeekdayHeaderRow(),
            const SizedBox(height: 6),
            CalendarMonthGrid(
              month: _month,
              selected: _selected,
              fillFor: (d) => _fillFor(d, dark),
              markerFor: _markerFor,
              onTapDay: (d) {
                HapticFeedback.selectionClick();
                setState(() => _selected = d);
              },
            ),
            const SizedBox(height: 12),
            // The answer to "which day is that". Appears only once a day has
            // been tapped, so the sheet opens as a clean calendar rather than
            // with a placeholder nobody asked for.
            AnimatedSize(
              duration: GameMotion.quick,
              curve: Curves.easeOut,
              child: selected == null
                  ? const SizedBox(width: double.infinity)
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _DayScoreCard(
                          room: widget.room,
                          participant: widget.participant,
                          day: selected,
                          status: _statusFor(selected, s),
                          tone: _fillFor(selected, dark),
                          scored: _isScoredDay(selected),
                          stillOpen: _isOpenDay(selected),
                        ),
                        // The day-1 note. Its own banded row rather than
                        // another word in the status line, because it says
                        // something different in kind: the status describes
                        // what happened that day, this says where the whole
                        // record begins. Only appears on that one day, so it
                        // costs nothing on the other thirty.
                        if (selected.isSameDayAs(_firstDay)) ...[
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 9),
                            decoration: BoxDecoration(
                              color: gp.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: gp.textPrimary.withOpacity(0.35)),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.flag_rounded,
                                    size: 14, color: gp.textPrimary),
                                const SizedBox(width: 7),
                                Expanded(
                                  child: Text(
                                    widget.isYou
                                        ? s.roomCalendarFirstDayNote
                                        : s.roomCalendarFirstDayNoteOther,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: gp.textPrimary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}


/// The tapped day, as a score rather than a verdict.
///
/// A day used to answer with one word. "أُنجز" says whether, never how much,
/// and says nothing at all about which habit: on a three-habit plan the same
/// word covered a day where everything was done and a day where the fraction
/// happened to round kindly. "It should show a score like 1/1 for train, 0/1
/// for walk, and if the train gives him 0.5 show that with the done mark"
/// (Aziz, 2026-09-10).
///
/// It reads as a receipt: one line per habit carrying what that habit ADDED
/// to the day (+1, +0.5, 0), and a sum underneath. The first cut printed the
/// day's fraction at the top AND repeated it on the habit's own row, which on
/// a one-habit plan is the same number twice ("you show it 1/1 twice" - Aziz,
/// same day). So the sum now appears only when more than one habit
/// contributed to it; with one habit, its row is the total.
///
/// Everything here is read through [roomDayBreakdown], which reads the same
/// accessors the leaderboard ranks on. Nothing is recomputed locally, so this
/// card cannot drift away from the percentage that opened it.
class _DayScoreCard extends StatelessWidget {
  final RoomModel room;
  final RoomParticipant participant;
  final DateTime day;

  /// The one-word verdict, still shown: it names the KIND of day (paused,
  /// stood down, rested, still open) in the cases a fraction cannot.
  final String status;

  /// The day's own cell colour, so the pill and the square agree.
  final Color? tone;

  /// False for a day outside this member's window, a paused room day, or one
  /// they stood down. Those get the header and nothing else.
  final bool scored;

  /// Whether the day can still be marked (today, or yesterday before the
  /// cutoff). An empty day that is still open is drawn in a neutral tone: it
  /// has not been failed, it has not finished.
  final bool stillOpen;

  const _DayScoreCard({
    required this.room,
    required this.participant,
    required this.day,
    required this.status,
    required this.tone,
    required this.scored,
    required this.stillOpen,
  });

  /// 1, or 2.5. Trailing zeros dropped, because "2.0 / 3" reads like a
  /// measurement rather than a count of habits.
  static String _count(double v) => v == v.roundToDouble()
      ? v.toInt().toString()
      : v.toStringAsFixed(1);

  /// The square whose colour and glyph stand for an outcome. Reusing
  /// [SquareState] rather than inventing a second vocabulary: a جزئي is the
  /// same half-disc here as it is on the Grid.
  static SquareState _mark(RoomSlotOutcome outcome) => switch (outcome) {
        RoomSlotOutcome.done => SquareState.complete,
        RoomSlotOutcome.partial => SquareState.partial,
        RoomSlotOutcome.missed => SquareState.failed,
        RoomSlotOutcome.rest => SquareState.skipped,
        RoomSlotOutcome.declined => SquareState.none,
      };

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final b = scored
        ? roomDayBreakdown(
            room: room,
            participant: participant,
            dateKey: day.toDateKey(),
          )
        : null;
    final rows = b?.slots ?? const <RoomSlotDay>[];
    // Declined slots are listed but score nothing, so they cannot make a day
    // need a sum line.
    final contributing =
        rows.where((r) => r.outcome != RoomSlotOutcome.declined).length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 12),
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: gp.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _header(context, s),
          if (b != null) ...[
            if (rows.isNotEmpty) ...[
              const SizedBox(height: 11),
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                // Printed shares are rounded ACROSS the set, so what is on
                // screen adds up to the percentage beside it.
                _slotRow(
                  context,
                  rows[i],
                  s,
                  roundedShares([for (final r in rows) r.share])[i],
                ),
              ],
            ],
            if (b.asksNothing) ...[
              // Named rows already say "راحة" on every line; without them the
              // day still owes an explanation for having no score at all.
              if (rows.isEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  s.roomCalendarNothingAsked,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: gp.textSec,
                  ),
                ),
              ],
            ] else if (rows.isEmpty) ...[
              // The room could not say which habit did what (a mixed day, or
              // an 'own'-mode room). The day's own fraction leads, then the
              // same arithmetic grouped rather than named.
              const SizedBox(height: 10),
              _dayFraction(context, b, s),
              const SizedBox(height: 8),
              _bar(context, b),
              if (b.groups.isNotEmpty) ...[
                const SizedBox(height: 11),
                Divider(height: 1, thickness: 1, color: gp.divider),
                const SizedBox(height: 10),
                _groups(context, b, s),
              ],
            ] else if (contributing > 1) ...[
              const SizedBox(height: 11),
              Divider(height: 1, thickness: 1, color: gp.divider),
              const SizedBox(height: 10),
              _total(context, b, s),
              const SizedBox(height: 8),
              _bar(context, b),
            ],
          ],
        ],
      ),
    );
  }

  Widget _header(BuildContext context, S s) {
    final gp = context.gp;
    final locale = Localizations.localeOf(context).languageCode;
    return Row(
      children: [
        Icon(Icons.event_rounded, size: 14, color: gp.textTert),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            // weekdayDateLabel, not DateFormat directly. The raw pattern
            // rendered "الأربعاء ٢ سبتمبر" in Arabic-Indic digits while
            // every other number on this card and in the calendar above it
            // — the day numbers, the score, the percentage — stayed ASCII
            // (Aziz, 2026-09-10: "the number is not correct in arabic").
            // Latin digits everywhere is the house rule, and this helper is
            // where the app already settled it; it also brings the Arabic
            // comma, which the bare pattern was dropping.
            weekdayDateLabel(day, isAr: locale == 'ar', locale: locale),
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: gp.textPrimary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: tone ?? gp.surfaceHL,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: gp.border),
          ),
          child: Text(
            status,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: gp.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  /// A mark's colour as TEXT, which is not the same question as its colour
  /// as a glyph inside its own tinted square.
  ///
  /// [SquareState.accent] returns the RAW GameColors.warning / .error for
  /// جزئي and فشل, and both are light enough that they fail contrast as text
  /// on a cream light-mode surface. GameColors' own note says the raw pair
  /// "stay for fills"; the palette already carries [_GamePalette.warningInk]
  /// and [_GamePalette.errorInk] for exactly this use.
  static Color _inkFor(BuildContext context, SquareState mark) {
    final gp = context.gp;
    return switch (mark) {
      SquareState.partial => gp.warningInk,
      SquareState.failed => gp.errorInk,
      _ => mark.accent(gp.dark),
    };
  }

  /// The colour of the fraction and the bar. Red only for a day that is
  /// actually over with nothing on it.
  Color _ink(BuildContext context, RoomDayBreakdown b) {
    final gp = context.gp;
    if (b.ratio >= 1) return _inkFor(context, SquareState.complete);
    if (b.credited > 0) return _inkFor(context, SquareState.partial);
    if (stillOpen) return gp.textTert;
    return _inkFor(context, SquareState.failed);
  }

  /// The day's own fraction, large. Used only when the habits cannot be named
  /// — otherwise the rows carry the detail and [_total] sums them.
  Widget _dayFraction(BuildContext context, RoomDayBreakdown b, S s) {
    final gp = context.gp;
    final ink = _ink(context, b);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          _count(b.credited),
          textDirection: TextDirection.ltr,
          style: TextStyle(
            fontSize: 25,
            fontWeight: FontWeight.w900,
            height: 1,
            color: ink,
          ),
        ),
        Text(
          ' / ${b.scheduled}',
          textDirection: TextDirection.ltr,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: gp.textSec,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            s.roomCalendarDayScore,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: gp.textTert,
            ),
          ),
        ),
        Text(
          '${(b.ratio * 100).round()}%',
          textDirection: TextDirection.ltr,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: ink,
          ),
        ),
      ],
    );
  }

  /// The sum of the rows above it.
  Widget _total(BuildContext context, RoomDayBreakdown b, S s) {
    final gp = context.gp;
    final ink = _ink(context, b);
    return Row(
      children: [
        Expanded(
          child: Text(
            s.roomCalendarTotal,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: gp.textSec,
            ),
          ),
        ),
        Text(
          '${_count(b.credited)} / ${b.scheduled}',
          textDirection: TextDirection.ltr,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: ink,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${(b.ratio * 100).round()}%',
          textDirection: TextDirection.ltr,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: gp.textTert,
          ),
        ),
      ],
    );
  }

  Widget _bar(BuildContext context, RoomDayBreakdown b) {
    final gp = context.gp;
    final ink = _ink(context, b);
    return SizedBox(
      height: 7,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(color: gp.textPrimary.withOpacity(0.08)),
            ),
            // centerStart, not the default centre: in Arabic the bar has to
            // grow from the right edge, and an unaligned FractionallySizedBox
            // would float the fill in the middle of the track.
            FractionallySizedBox(
              alignment: AlignmentDirectional.centerStart,
              widthFactor: b.ratio.clamp(0.0, 1.0),
              heightFactor: 1,
              child: ColoredBox(color: ink),
            ),
          ],
        ),
      ),
    );
  }

  /// A share of the day, as text: +0.5 when two habits split it, +0.33 when
  /// three do, half of that for a جزئي.
  ///
  /// This used to print a flat +1 for every completed habit, which is a count
  /// of habits rather than the arithmetic behind the percentage beside it.
  /// Aziz's correction (2026-09-10): "if room started with 2 habit the info
  /// should be +0.5 +0.5, so we know that this is how it being counted".
  static String _share(double v) {
    if (v <= 0) return '0';
    final text = v.toStringAsFixed(2);
    final trimmed = text.endsWith('0') ? text.substring(0, text.length - 1) : text;
    return '+$trimmed';
  }

  /// What one habit ADDED to the day.
  String _contribution(RoomSlotDay slot, S s, double printedShare) =>
      switch (slot.outcome) {
        RoomSlotOutcome.done ||
        RoomSlotOutcome.partial =>
          _share(printedShare),
        RoomSlotOutcome.missed => '0',
        RoomSlotOutcome.rest => s.roomCalendarChipRest,
        RoomSlotOutcome.declined => s.roomCalendarSlotDeclined,
      };

  Widget _slotRow(
      BuildContext context, RoomSlotDay slot, S s, double printedShare) {
    final gp = context.gp;
    final dark = gp.dark;
    // An empty square, not a red one, while the day can still be marked: the
    // ✗ is a verdict and the day has not reached one yet.
    final mark = slot.outcome == RoomSlotOutcome.missed && stillOpen
        ? SquareState.none
        : _mark(slot.outcome);
    final scores = slot.outcome == RoomSlotOutcome.done ||
        slot.outcome == RoomSlotOutcome.partial;
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: mark.fill(dark),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: mark.border(dark)),
          ),
          child: mark.icon == null
              ? null
              : Icon(mark.icon, size: 13, color: mark.accent(dark)),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            slot.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: slot.outcome == RoomSlotOutcome.declined
                  ? gp.textTert
                  : gp.textPrimary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          _contribution(slot, s, printedShare),
          textDirection: scores ? TextDirection.ltr : null,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w900,
            color: scores ? _inkFor(context, mark) : gp.textTert,
          ),
        ),
      ],
    );
  }

  /// The same outcomes and the same arithmetic, grouped instead of named —
  /// the fallback for a day whose counts do not say which habit was which.
  ///
  /// This replaced a row of bare count chips. The chips were honest but said
  /// nothing about how the percentage above them was reached, which was the
  /// whole of Aziz's complaint about this card.
  Widget _groups(BuildContext context, RoomDayBreakdown b, S s) {
    final label = {
      RoomSlotOutcome.done: s.roomCalendarChipDone,
      RoomSlotOutcome.partial: s.roomCalendarChipPartial,
      RoomSlotOutcome.missed: s.roomCalendarChipMissed,
      RoomSlotOutcome.rest: s.roomCalendarChipRest,
      RoomSlotOutcome.declined: s.roomCalendarSlotDeclined,
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < b.groups.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _groupRow(
            context,
            b.groups[i],
            label[b.groups[i].outcome] ?? '',
            roundedShares([for (final g in b.groups) g.share])[i],
          ),
        ],
      ],
    );
  }

  Widget _groupRow(BuildContext context, RoomSlotGroup g, String label,
      double printedShare) {
    final gp = context.gp;
    final dark = gp.dark;
    final mark = g.outcome == RoomSlotOutcome.missed && stillOpen
        ? SquareState.none
        : _mark(g.outcome);
    final scores = g.share > 0;
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: mark.fill(dark),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: mark.border(dark)),
          ),
          child: mark.icon == null
              ? null
              : Icon(mark.icon, size: 13, color: mark.accent(dark)),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            '$label ${g.count}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: gp.textPrimary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          scores ? _share(printedShare) : '0',
          textDirection: scores ? TextDirection.ltr : null,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w900,
            color: scores ? _inkFor(context, mark) : gp.textTert,
          ),
        ),
      ],
    );
  }
}


/// The identity and the score at the top of a member's sheet.
///
/// Every figure here is read through the SAME accessor the leaderboard row
/// ranks on: progressRatio, daysCompleted/daysElapsedIn and currentStreak. A
/// second way of computing any of them would eventually disagree with the row
/// that opened this sheet, and two numbers for one fact on two surfaces is the
/// bug this codebase has already paid for more than once.
class _ParticipantHeader extends StatelessWidget {
  final RoomModel room;
  final RoomParticipant participant;
  final bool isYou;

  const _ParticipantHeader({
    required this.room,
    required this.participant,
    required this.isYou,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);

    // findById, NOT findByIdOrDefault, for the same reason _LeaderboardRow
    // documents: OrDefault returns a real character somebody may genuinely
    // have chosen, so an unknown id would render as a specific person's look
    // with nothing marking it a guess. A neutral silhouette says "not known
    // yet" and self-heals on that member's next sync.
    final character = CharacterCatalog.findById(participant.characterId);
    final accessory = AccessoryCatalog.findById(participant.accessoryId);
    final prestige = PrestigeCatalog.findById(participant.prestigeTierId);

    // The room score, the number this member was placed by, and the day
    // count that produces it - the same fraction, so «٣.٥ من ٩» and the
    // percent beside it can never disagree. How much of the plan they carry
    // is captioned under the scoreboard when it is not all of it, which is
    // the only case the two numbers differ from the member's own. See
    // RoomParticipant.roomProgressRatio.
    final ratio = participant.roomProgressRatio(room);
    final done = participant.roomDaysCompleted(room);
    // roomDaysElapsedIn, not daysElapsedIn: the room score's own denominator.
    // The two used to be the same number for anyone who never went away, and
    // are not any more — a day this member's own plan asked nothing of, but
    // an unlinked slot did, leaves their own denominator and stays in the
    // room's. Pairing the room numerator with the personal denominator would
    // print a fraction that disagreed with the percent right beside it.
    final elapsed = participant.roomDaysElapsedIn(room);
    final ownPercent = (participant.progressRatio(room) * 100).round();
    final coverage = participant.planCoverageIn(room);
    final carriesPartOfPlan =
        coverage != null && coverage.linked < coverage.total;
    final streak = participant.currentStreak(room);

    // Your own sheet is gold, everyone else's is the grid's green. The same
    // two-colour split the leaderboard card already uses to mark your row.
    final accent = isYou ? GameColors.gold : GameColors.emerald;

    // The privacy half, copied from the row rather than reinvented: joining a
    // room to compete on consistency without publishing what you are working
    // on. Your own sheet always shows your own names, since there is nobody to
    // hide them from.
    final showDetails = isYou || !participant.hideDetails;
    final names = showDetails
        ? participant.linkedHabitNames
            .where((n) => n.trim().isNotEmpty)
            .toList()
        : const <String>[];

    return Column(
      children: [
        // ── The character, at the size the character deserves ────────────
        //
        // Opening a member is the one moment another person is the subject,
        // and they picked this look on purpose. At 56pt it was a bullet point
        // next to their name; at 132 with a glow behind it, it is the reason
        // you opened the sheet. The glow is a radial fade rather than a solid
        // disc so nothing has a hard edge to fight the artwork's own outline.
        SizedBox(
          height: 168,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 176,
                height: 176,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      accent.withOpacity(0.20),
                      accent.withOpacity(0.06),
                      accent.withOpacity(0),
                    ],
                    stops: const [0, 0.55, 1],
                  ),
                ),
              ),
              if (character == null)
                Icon(Icons.person_rounded,
                    size: 88, color: gp.textTert.withOpacity(0.55))
              else
                CharacterAvatar(
                  character: character,
                  accessory: accessory,
                  height: 132,
                ),
            ],
          ),
        )
            .animate()
            // Rises and settles rather than popping: the sheet is already
            // sliding up, so the character arriving a beat later reads as
            // them stepping forward inside it.
            .fadeIn(duration: 260.ms)
            .scale(
              begin: const Offset(0.88, 0.88),
              end: const Offset(1, 1),
              duration: 420.ms,
              curve: Curves.easeOutBack,
            ),
        const SizedBox(height: 6),
        // ── Who they are ─────────────────────────────────────────────────
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          runSpacing: 6,
          children: [
            Text(
              participant.displayName,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: gp.textPrimary,
              ),
            ),
            if (isYou) _Tag(label: s.roomYouLabel, color: GameColors.gold),
            if (participant.uid == room.createdBy)
              _Tag(label: s.roomLeaderLabel, color: gp.textSec),
            // Every rank shows here too, for the same reason the leaderboard
            // row now shows them all: this sheet is opened FROM that row, so
            // a stamp on the row and nothing here would read as the sheet
            // having lost it. This one is a Wrap, so the extra chip costs a
            // line at worst, never an overflow.
            if (prestige != null) _PrestigeChip(tier: prestige),
          ],
        ).animate(delay: 90.ms).fadeIn(duration: 240.ms).moveY(begin: 6, end: 0),
        if (names.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            names.join('، '),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: gp.textSec),
          ).animate(delay: 130.ms).fadeIn(duration: 240.ms),
        ],
        const SizedBox(height: 14),
        // ── What they have done ──────────────────────────────────────────
        //
        // One container rather than three loose columns, so the numbers read
        // as a single scoreboard instead of three unrelated facts.
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: gp.dark
                ? Colors.white.withOpacity(0.04)
                : Colors.black.withOpacity(0.03),
            borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
            border: Border.all(color: gp.border, width: 0.5),
          ),
          child: Row(
            children: [
              _HeaderStat(
                value: '${(ratio * 100).round()}%',
                label: s.reportsRate,
                color: GameColors.emerald,
              ),
              _StatDivider(color: gp.border),
              _HeaderStat(
                value: s.roomDayCount(done, elapsed),
                label: s.roomStatDays,
                color: gp.textPrimary,
              ),
              _StatDivider(color: gp.border),
              _HeaderStat(
                value: '$streak',
                label: s.habitStatsCurrentStreak,
                color: context.gp.iconStreak,
              ),
            ],
          ),
        ).animate(delay: 170.ms).fadeIn(duration: 260.ms).moveY(begin: 8, end: 0),
        if (carriesPartOfPlan) ...[
          const SizedBox(height: 8),
          Text(
            // roomOwnRate only when it differs from the score above it, the
            // contract its own doc states and the leaderboard row already
            // keeps. Without the guard this sheet printed «المرتبطة: 52%»
            // directly under «نسبة الإنجاز 52%»: the same number twice under
            // two labels, which is the confusion the caption exists to
            // prevent. Reachable with no odd data at all, since a slot added
            // in the last three days is asked of nobody yet, so every
            // unresolved member's room score still equals their own.
            [
              s.roomPlanCoverage(coverage.linked, coverage.total),
              if (ownPercent != (ratio * 100).round()) s.roomOwnRate(ownPercent),
            ].join(' · '),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: gp.textTert),
          ).animate(delay: 220.ms).fadeIn(duration: 260.ms),
        ],
      ],
    );
  }
}

/// A hairline between two figures in the scoreboard.
class _StatDivider extends StatelessWidget {
  final Color color;
  const _StatDivider({required this.color});

  @override
  Widget build(BuildContext context) =>
      Container(width: 0.5, height: 26, color: color);
}

/// One of the three figures under a member's name.
class _HeaderStat extends StatelessWidget {
  final String value;
  final String label;
  final Color color;

  const _HeaderStat({
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Expanded(
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10.5, color: gp.textSec),
          ),
        ],
      ),
    );
  }
}

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
    // for. The strip paints it blank; this sheet used to paint it as a miss
    // and then label it لم يُنجز beside it.
    if (widget.room.isPausedOn(key)) return null;
    // A deliberate تخطّي gets the same gold the strip and the personal
    // reports give it, so one act has one colour everywhere. It does NOT
    // change what the day scored, which is still nothing.
    if (widget.participant.isDeclaredRest(key)) {
      return GameColors.gold.withOpacity(0.16);
    }
    final credit = widget.participant.isRestDay(key)
        ? 0.0
        : widget.participant.creditFor(key);
    return heatColor(heatmapLevelFor(credit), dark);
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

  String _statusFor(DateTime day, S s) {
    final key = day.toDateKey();
    // Same precedence as _fillFor above, so the word and the colour can
    // never describe two different things about one square.
    if (widget.room.isPausedOn(key)) return s.roomCalendarPaused;
    if (widget.participant.isRestDay(key)) return s.roomCalendarRestDay;
    if (widget.participant.isDeclaredRest(key)) {
      return s.roomCalendarStoodDown;
    }
    final credit = widget.participant.creditFor(key);
    if (credit >= 1.0) return s.roomCalendarDone;
    if (credit > 0) return s.roomCalendarPartial;
    return s.roomCalendarMissed;
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final dark = gp.dark;
    final locale = Localizations.localeOf(context).languageCode;
    final selected = _selected;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        20 + MediaQuery.of(context).padding.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        decoration: BoxDecoration(
          color: gp.surfaceHigh,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: gp.border),
        ),
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
            Text(
              s.roomCalendarTitle(widget.participant.displayName),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: gp.textPrimary,
              ),
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
                        Row(
                          children: [
                            Icon(Icons.event_rounded,
                                size: 14, color: gp.textTert),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                DateFormat('EEEE d MMMM', locale)
                                    .format(selected),
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: gp.textPrimary,
                                ),
                              ),
                            ),
                            Text(
                              _statusFor(selected, s),
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: gp.textSec,
                              ),
                            ),
                          ],
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
    );
  }
}

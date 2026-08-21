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
      ),
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

    final ratio = participant.progressRatio(room);
    final done = participant.daysCompleted(room);
    final elapsed = participant.daysElapsedIn(room);
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
            // Same level-1 restraint the row and the Profile card both use: a
            // base tier is not something to show off, so it renders nothing
            // rather than a chip everybody would have from day one.
            if (prestige != null && prestige.minLevel > 1)
              _PrestigeChip(tier: prestige),
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
                color: GameColors.iconStreak,
              ),
            ],
          ),
        ).animate(delay: 170.ms).fadeIn(duration: 260.ms).moveY(begin: 8, end: 0),
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

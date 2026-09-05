import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../../core/utils/western_digits.dart';
import '../../grid/models/square_state.dart';
import '../../milestones/reports/day_score.dart';

/// How much of the recent past the chart covers.
///
/// Three, not two, because أسبوعين is the window the card shipped with and
/// the one the rest of the app calls "recent" (roomRaceHeatmapDays mirrors
/// the same 14). Week is for reading the last few days closely; month is for
/// seeing a shape.
///
/// Nothing longer. Not because a longer window would be hard to draw, but
/// because `historyFloorFor` returns null by construction for any window
/// shorter than about two months, so 7/14/30 are exactly the windows that
/// need no premium wall and no muted days. A 90-day segment would be free in
/// July and walled in December with nothing on screen to explain why. The
/// honest home for a longer look is التقارير, which already has month and
/// year tabs and a period stepper.
enum ProgressRange {
  week(7),
  fortnight(14),
  month(30);

  final int days;
  const ProgressRange(this.days);
}

/// The one place a day index becomes an x, and an x becomes a day index.
///
/// It exists because the mirror can be half-applied. Canvas coordinates are
/// always literal left-to-right pixels no matter the locale, so the painter
/// has to flip its own geometry, while the tap handler has to flip the
/// incoming hit. When those were two separate expressions, removing the flip
/// from the painter alone left a chart drawn one way and read the other:
/// every tap opens the wrong day, nothing crashes, and nothing on screen
/// says so. A test can catch that only if it inspects painted geometry.
///
/// Routing both through [mirror] makes it structurally impossible instead:
/// there is one flip, so it is either applied to both or to neither, and
/// "neither" is what the tap tests in day_score_chart_test.dart already
/// fail on. Same reason year_strip.dart keeps YearStripPainter's index
/// mirror and yearStripDayAt's `1 - dxFraction` in one file, one step
/// further along.
class DayAxis {
  final double width;
  final int count;

  /// Oldest day at the START of the reading direction, today at the end:
  /// left-to-right in English, right-to-left in Arabic. Matches the Grid's
  /// week header and the reports matrix, which both run newest toward the
  /// leading edge.
  final bool isRtl;

  const DayAxis({
    required this.width,
    required this.count,
    required this.isRtl,
  });

  double get columnWidth => width / count;

  /// THE flip. Every x in this file passes through here.
  double mirror(double x) => isRtl ? width - x : x;

  /// Where day [i]'s point sits: the centre of its own slot, which is also
  /// where the label Row centres its text, so the two line up.
  double center(int i) => mirror(columnWidth * (i + 0.5));

  /// Which day a hit at [dx] belongs to. floor, not round: an index taken
  /// against (count - 1), or rounded, still lands on the right day at both
  /// edges and is wrong for every column in between.
  int indexAt(double dx) =>
      ((mirror(dx)) / columnWidth).floor().clamp(0, count - 1);
}

/// The score line on ProgressHubScreen: one point per day at the
/// number of habits finished, over a faint band showing what each day
/// actually owed.
///
/// ── Why a line, and why the band ───────────────────────────────────────
/// The mark used to be bars scaled against the window's own best day, with
/// no denominator at all, so a fortnight of 1s and 2s drew exactly like a
/// fortnight of 8s and 9s and "how much of what I owed" was unanswerable.
/// The band is the denominator made visible: the gap between the line and
/// the top of the band is the part of the day that was asked for and did
/// not happen.
///
/// Both are measured in HABITS on one shared axis, never as a rate. With
/// rate as the height a 3-of-3 day towers over a 9-of-10 day, which inverts
/// the shape the chart exists to show.
class DayScoreChart extends StatefulWidget {
  final List<DayScore> scores;

  /// Index of the day drawn as "today", or null when the window ends in the
  /// past. Never derived here: the caller already resolved today through
  /// effectiveDay and this widget must not re-derive it off DateTime.now()
  /// and land a day out between midnight and the 10:00 cutoff.
  final int? todayIndex;

  final void Function(DayScore score) onDayTap;

  /// While the mirror is still loading, every day's CREDIT is unknown but
  /// its OWED is already known (it comes from the habit list, which is in
  /// memory). Drawing the line anyway would put a flat zero across the whole
  /// fortnight for as long as the read takes, which reads as "you did
  /// nothing" rather than "not loaded yet". So the band is drawn and the
  /// line is withheld: the chart says what it knows and nothing more.
  final bool isLoading;

  static const double _plotHeight = 96;

  const DayScoreChart({
    super.key,
    required this.scores,
    required this.todayIndex,
    required this.onDayTap,
    this.isLoading = false,
  });

  @override
  State<DayScoreChart> createState() => _DayScoreChartState();
}

class _DayScoreChartState extends State<DayScoreChart> {
  /// The day the readout is describing. Null means "nobody has scrubbed
  /// yet", which resolves to today, so the readout is never blank and never
  /// has to reserve space for text it might not have.
  ///
  /// Sticky after a drag ends on purpose. Scrubbing to a day and having the
  /// readout snap back to today the moment you lift your finger means you
  /// cannot actually read it, which defeats the point.
  ///
  /// Not carried across a range switch: the AnimatedSwitcher in
  /// _ProgressReportShell keys its child by range, so this State is
  /// discarded and rebuilt, and index 20 does not mean the same day in a
  /// month that it did in a fortnight.
  int? _selected;

  void _select(int index, {required bool haptic}) {
    if (index == _selected) return;
    if (haptic) HapticFeedback.selectionClick();
    setState(() => _selected = index);
  }

  @override
  Widget build(BuildContext context) {
    final scores = widget.scores;
    final todayIndex = widget.todayIndex;
    final isLoading = widget.isLoading;
    if (scores.isEmpty) return const SizedBox.shrink();
    final gp = context.gp;
    final s = S.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    // Clamped rather than trusted: a refresh can hand back a shorter list
    // while a stale index is held here.
    final selected =
        (_selected ?? todayIndex ?? scores.length - 1).clamp(0, scores.length - 1);

    // ── This axis mirrors, and the tap index mirrors WITH it ───────────
    // Oldest day at the start of the reading direction, today at the end:
    // left-to-right in English, right-to-left in Arabic. It used to be
    // pinned LTR on the argument that a chronological plot reads "later to
    // the right" in every locale. On this app that was wrong in a way you
    // can see: the Grid's week header runs Saturday-on-the-right and the
    // reports matrix runs newest-column-leftmost, so under Arabic the chart
    // was the ONE time surface where moving left meant going back while
    // everywhere else moving left meant going forward.
    //
    // THE PAIR THAT MUST STAY IN STEP: the painter's [DayScoreLinePainter
    // .isRtl] mirrors the plotted x, and the tap handler below mirrors the
    // hit x. Change one without the other and every tap silently opens the
    // wrong day, which is exactly why year_strip.dart keeps YearStripPainter's
    // index mirror and yearStripDayAt's `1 - dxFraction` in one file. The
    // label Rows need no such care: they are plain Flutter Rows and mirror
    // themselves. Tests in day_score_chart_test.dart assert both ends in
    // both directions.
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    return LayoutBuilder(
      builder: (context, constraints) {
        final axis = DayAxis(
          width: constraints.maxWidth,
          count: scores.length,
          isRtl: isRtl,
        );
        final columnWidth = axis.columnWidth;

        // ── How dense the two label rows are allowed to get ──────────────
        // Driven by the measured column width, never by the day count, so
        // the same rules hold on a 320pt phone and on a tablet.
        //
        // The done-count row is dropped entirely once a column is too
        // narrow to hold two digits (a month is about 11pt per column at
        // phone width). Thinning it instead would leave numbers hovering
        // over some points and not others, which reads as missing data
        // rather than as a sampled axis. The shape carries the month; the
        // exact figure for any one day is one tap away, and the week and
        // fortnight windows both keep every number.
        final showCounts = columnWidth >= 15;
        // Day numbers thin out instead, because an axis with no labels at
        // all cannot be read. Counted BACK from today so today is always
        // labelled, whatever the step lands on.
        final labelStep = (20 / columnWidth).ceil().clamp(1, scores.length);

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── The readout ────────────────────────────────────────────
            // Outside the gesture area on purpose: it is the ONE place the
            // exact date and the exact count are always spelled out, and at
            // a month's density it is the only place, because an 11pt
            // column cannot hold a two-digit number and the day labels have
            // thinned to every other one. Reading it must not require
            // holding a finger on the chart and covering it up.
            _ScrubReadout(
              score: scores[selected],
              isToday: selected == todayIndex,
              locale: locale,
              isLoading: isLoading,
              onOpen: () {
                HapticFeedback.selectionClick();
                widget.onDayTap(scores[selected]);
              },
            ),
            const SizedBox(height: 10),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              // Tap still opens the day in full, exactly as it did before
              // the scrubber existed.
              //
              // onTapUp, NOT onTapDown, and that is the difference between
              // this working and being unusable. BaseTapGestureRecognizer
              // fires onTapDown from didExceedDeadline as well as from
              // acceptGesture, so a finger resting for kPressTimeout (100ms)
              // before it starts moving gets a down callback even though the
              // horizontal drag goes on to win the arena. With the sheet on
              // onTapDown, every unhurried scrub opened a modal over the
              // chart it was scrubbing. onTapUp only fires when the tap
              // actually wins, which is exactly the intent.
              onTapUp: (details) {
                final index = axis.indexAt(details.localPosition.dx);
                _select(index, haptic: false);
                HapticFeedback.selectionClick();
                widget.onDayTap(scores[index]);
              },
              // HORIZONTAL, never onPan: a pan recogniser wins the arena
              // against the ListView this card sits in, so scrubbing would
              // stop the page scrolling vertically. Horizontal loses that
              // fight correctly, which is what lets a drag down the screen
              // still scroll while a drag across the chart still scrubs.
              onHorizontalDragStart: (d) =>
                  _select(axis.indexAt(d.localPosition.dx), haptic: true),
              onHorizontalDragUpdate: (d) =>
                  _select(axis.indexAt(d.localPosition.dx), haptic: true),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
              // Exact values above the curve. A shape with no anchoring
              // numbers is hard to actually read, which is the lesson
              // _WeekdayWaveChart already recorded when it lost the bar
              // version's per-day figures.
              if (showCounts)
                Row(
                  children: [
                    for (var i = 0; i < scores.length; i++)
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            // Plain interpolation, never DateFormat: routed
                            // through intl this axis rendered Arabic-Indic
                            // digits directly above the ASCII day numbers on
                            // the same columns, two numeral systems in one
                            // column. Verified on device in Arabic.
                            isLoading ? '' : '${scores[i].done}',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: i == todayIndex
                                  ? GameColors.gold
                                  : scores[i].done > 0
                                      ? gp.textPrimary
                                      : gp.textTert,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              const SizedBox(height: 6),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                // 320, not the 450 this shipped with: on a range switch the
                // line grows INSIDE a 260ms fade-and-scale, and a grow that
                // outlasts the fade by 190ms reads as the chart still
                // settling after the transition has visibly finished.
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                builder: (context, t, _) => SizedBox(
                  height: DayScoreChart._plotHeight,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: DayScoreLinePainter(
                      scores: scores,
                      todayIndex: todayIndex,
                      progress: t,
                      showLine: !isLoading,
                      isRtl: isRtl,
                      selectedIndex: selected,
                      lineColor: GameColors.success,
                      todayColor: GameColors.gold,
                      restColor: SquareState.skipped.accent,
                      failedColor: GameColors.warning,
                      // The relative tint, never gp.surfaceHL: every
                      // preset's surface-highlight is green-leaning and a
                      // green band behind a green line reads as partly
                      // done before anything is drawn.
                      bandColor: gp.dark
                          ? Colors.white.withOpacity(0.055)
                          : Colors.black.withOpacity(0.05),
                      baselineColor: gp.border,
                      silentColor: gp.textTert,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  for (var i = 0; i < scores.length; i++)
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          (scores.length - 1 - i) % labelStep == 0
                              ? '${scores[i].day.day}'
                              : '',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: i == todayIndex
                                ? FontWeight.w800
                                : FontWeight.w600,
                            color: i == todayIndex
                                ? GameColors.gold
                                : gp.textTert,
                          ),
                        ),
                      ),
                    ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The one row that always spells out, in words and digits, which day the
/// chart is talking about and how it went.
///
/// It exists because of the month. At 30 days a column is about 11pt, too
/// narrow for a two-digit count, so the per-day numbers are dropped and the
/// day labels thin to every other one; without this row a month is a shape
/// with nothing to read off it. Rather than build a second thing for the
/// month alone, this is present at every range, which also means the
/// scrubber behaves identically wherever you use it.
///
/// Always populated, defaulting to today, so the row never appears and
/// disappears and the card never changes height under a finger.
///
/// The whole row is a button onto the same day sheet a tap on the chart
/// opens. That matters most at a month's density, where an 11pt tap target
/// is a coin toss between two neighbouring days: scrub until the readout
/// says the day you meant, then open it from here.
class _ScrubReadout extends StatelessWidget {
  final DayScore score;
  final bool isToday;
  final String locale;
  final bool isLoading;
  final VoidCallback onOpen;

  const _ScrubReadout({
    required this.score,
    required this.isToday,
    required this.locale,
    required this.isLoading,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final accent = isToday ? GameColors.gold : GameColors.success;

    // Three sentences, because a day that owed nothing and a day that owed
    // something and got none of it are different facts. Never "0 من 0".
    final value = score.owed > 0
        ? s.progressScoreFraction(score.done, score.owed)
        : score.rested > 0
            ? s.progressRestedShort
            : s.progressNothingDueShort;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(GameSpacing.buttonRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(GameSpacing.buttonRadius),
        onTap: isLoading ? null : onOpen,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  // The full weekday and date, never "اليوم" or "أمس". The
                  // format has to stay put while a finger drags across it:
                  // a label that switches shape on two days out of thirty
                  // reads as a glitch mid-scrub, and the gold dot already
                  // says which day is today.
                  isLoading
                      ? ''
                      : weekdayDateLabel(
                          score.day,
                          isAr: s.isAr,
                          locale: locale,
                        ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: gp.textSec,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                isLoading ? '' : value,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: score.owed > 0 ? accent : gp.textTert,
                ),
              ),
              const SizedBox(width: 4),
              // chevron_right_rounded is declared matchTextDirection: true,
              // so it flips itself in Arabic off the ambient Directionality.
              // Passing a textDirection here would be redundant, and every
              // other chevron in this file and in profile_screen_banners
              // leaves it off for the same reason.
              Icon(Icons.chevron_right_rounded, size: 18, color: gp.textTert),
            ],
          ),
        ),
      ),
    );
  }
}

/// Public only so a widget test can drive it directly; nothing outside this
/// file and its test should construct one.
class DayScoreLinePainter extends CustomPainter {
  final List<DayScore> scores;
  final int? todayIndex;

  /// 0..1 grow-in factor. Scales the plotted heights off the baseline so
  /// the line rises into place, matching the 400ms easeOutCubic the bars
  /// this replaced used.
  final double progress;

  /// False while the mirror is loading: band and baseline only. See
  /// [DayScoreChart.isLoading].
  final bool showLine;

  /// The day the readout is describing, marked with a guide line and a
  /// ring so the number in the readout is visibly tied to a point on the
  /// chart rather than floating above it.
  final int selectedIndex;

  /// Whether the ambient reading direction is right-to-left. Canvas
  /// coordinates are always literal left-to-right pixels no matter the
  /// locale, so unlike the label Rows above the plot this has to mirror
  /// itself. Must stay in step with the tap handler in [DayScoreChart].
  final bool isRtl;

  final Color lineColor;
  final Color todayColor;
  final Color restColor;
  final Color failedColor;
  final Color bandColor;
  final Color baselineColor;
  final Color silentColor;

  const DayScoreLinePainter({
    required this.scores,
    required this.todayIndex,
    required this.progress,
    required this.showLine,
    required this.isRtl,
    required this.selectedIndex,
    required this.lineColor,
    required this.todayColor,
    required this.restColor,
    required this.failedColor,
    required this.bandColor,
    required this.baselineColor,
    required this.silentColor,
  });

  /// The shared ceiling, in habits: the tallest thing the window has to
  /// draw, whether that is an obligation or an achievement.
  ///
  /// Peak-relative rather than a fixed ceiling, which is the house rule
  /// (_WeekdayWavePainter documents why a fixed one flattens every low
  /// window into an unreadable line along the bottom). Safe to rescale here
  /// in a way it would not be for a bare rate chart, because the band
  /// rescales with the line: the relationship the reader is actually
  /// reading, how close the line sits to the top of the band, is invariant.
  ///
  /// Includes credit as well as owed so a day that beat its obligation
  /// (a quota habit done on a day it did not owe) still fits on the canvas.
  static double axisMaxOf(List<DayScore> scores) {
    var max = 1.0;
    for (final score in scores) {
      final owed = score.owed.toDouble();
      if (owed > max) max = owed;
      if (score.credit > max) max = score.credit;
    }
    return max;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (scores.isEmpty) return;
    final axisMax = axisMaxOf(scores);
    final axis =
        DayAxis(width: size.width, count: scores.length, isRtl: isRtl);
    final columnWidth = axis.columnWidth;
    const top = 8.0;
    final baseline = size.height - 10;
    final plotHeight = baseline - top;

    double yOf(double value) =>
        baseline - (value / axisMax).clamp(0.0, 1.0) * plotHeight * progress;
    double mirrorX(double x) => axis.mirror(x);
    double xOf(int i) => axis.center(i);

    // Marks get smaller as the window gets longer: at 30 days a 3.4pt dot
    // on an 11pt column nearly touches its neighbours and the line reads as
    // a string of beads. Derived from the column width rather than from the
    // day count so it is right at any screen size, tablet included.
    final dotRadius = (columnWidth * 0.16).clamp(2.0, 3.4);
    final strokeWidth = (columnWidth * 0.11).clamp(1.8, 2.6);

    // ── The band: what each day owed ──────────────────────────────────
    // Stepped, not smoothed. An obligation is a flat fact for the whole of
    // its day and changes at midnight; drawing it as a curve would invent
    // fractional habits between days and imply the ceiling drifted.
    //
    // Clamped to the LINE's own span, first point to last, rather than to
    // the canvas. Each day's step still centres on its own point, so the
    // two end steps are half width. Drawn edge to edge instead, the band
    // overhung the line by half a column at each end and the outermost step
    // sat under no point at all, which reads as a rendering slip rather
    // than as the day it belongs to. Verified on device.
    //
    // Clamped in UNMIRRORED space and mirrored after, so the arithmetic
    // reads the same in both directions; the path simply walks the other
    // way round, which a fill does not care about.
    final firstX = columnWidth * 0.5;
    final lastX = columnWidth * (scores.length - 0.5);
    final band = Path()..moveTo(mirrorX(firstX), baseline);
    for (var i = 0; i < scores.length; i++) {
      final y = yOf(scores[i].owed.toDouble());
      final segStart = (columnWidth * i).clamp(firstX, lastX);
      final segEnd = (columnWidth * (i + 1)).clamp(firstX, lastX);
      band
        ..lineTo(mirrorX(segStart), y)
        ..lineTo(mirrorX(segEnd), y);
    }
    band
      ..lineTo(mirrorX(lastX), baseline)
      ..close();
    canvas.drawPath(band, Paint()..color = bandColor);

    canvas.drawLine(
      Offset(0, baseline),
      Offset(size.width, baseline),
      Paint()
        ..color = baselineColor
        ..strokeWidth = 0.7,
    );

    if (!showLine) return;

    final points = <Offset>[
      for (var i = 0; i < scores.length; i++)
        Offset(xOf(i), yOf(scores[i].credit)),
    ];

    // Area under the line, then the line itself. Same midX cubic
    // _WeekdayWavePainter uses: because both control points share the
    // endpoints' own y values, the curve can never overshoot below the
    // baseline or above the band on a steep drop.
    Path curveThrough(List<Offset> pts) {
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (var i = 1; i < pts.length; i++) {
        final prev = pts[i - 1];
        final next = pts[i];
        final midX = (prev.dx + next.dx) / 2;
        path.cubicTo(midX, prev.dy, midX, next.dy, next.dx, next.dy);
      }
      return path;
    }

    final fill = curveThrough(points)
      ..lineTo(points.last.dx, baseline)
      ..lineTo(points.first.dx, baseline)
      ..close();
    canvas.drawPath(fill, Paint()..color = lineColor.withOpacity(0.13));

    canvas.drawPath(
      curveThrough(points),
      Paint()
        ..color = lineColor
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Under the points, over the fill: a guide the dots sit on top of, so
    // scrubbing never hides the value being read.
    if (selectedIndex >= 0 && selectedIndex < points.length) {
      final x = points[selectedIndex].dx;
      canvas.drawLine(
        Offset(x, top),
        Offset(x, baseline),
        Paint()
          ..color = (selectedIndex == todayIndex ? todayColor : lineColor)
              .withOpacity(0.28)
          ..strokeWidth = 1.2,
      );
    }

    for (var i = 0; i < scores.length; i++) {
      _paintPoint(
        canvas,
        points[i],
        scores[i],
        i == todayIndex,
        baseline,
        dotRadius.toDouble(),
        isSelected: i == selectedIndex,
      );
    }
  }

  void _paintPoint(
    Canvas canvas,
    Offset point,
    DayScore score,
    bool isToday,
    double baseline,
    double dotRadius, {
    required bool isSelected,
  }) {
    final accent = isToday ? todayColor : lineColor;

    // Drawn for EVERY kind of day, including the silent and rested ones
    // that return early below, because a scrub that skips over a day
    // without acknowledging it reads as the chart having lost the finger.
    if (isSelected) {
      canvas.drawCircle(
        point,
        dotRadius * 2.4,
        Paint()
          ..color = accent.withOpacity(0.9)
          ..strokeWidth = 1.4
          ..style = PaintingStyle.stroke,
      );
    }

    // A day that asked for nothing and recorded nothing is absence, not a
    // zero: before the first habit existed, or a Wednesday for a habit set
    // that only runs Mon and Thu. Drawing it as a solid dot on the floor
    // would be the chart accusing someone of a day nobody was owed.
    if (score.isSilent && score.credit == 0) {
      canvas.drawCircle(
        point,
        dotRadius * 0.6,
        Paint()..color = silentColor.withOpacity(0.45),
      );
      return;
    }

    // A stand-down is a choice, so it gets تخطّي's own colour rather than a
    // hole. Note this disagrees on purpose with the home screen's إنجاز
    // اليوم ring, which scores an all-rested day as FULL
    // (WeeklyGridState.todayCompletionRatio). Both are defensible: the ring
    // answers "is there anything left to do today", this answers "how much
    // did this day ask of you". Do not "fix" one to match the other without
    // deciding which question each screen is asking.
    if (score.owed == 0 && score.rested > 0) {
      canvas.drawCircle(
          point, dotRadius, Paint()..color = restColor.withOpacity(0.75));
      return;
    }

    // Every obligation discharged. Consecutive perfect days grow haloes
    // that visually merge into a band, the same read _HeatCell gives a
    // perfect run. The halo is the point's OWN colour, so it survives the
    // gold today-point and all eleven presets; a fixed gold ring would
    // vanish on exactly the day it matters most.
    if (score.isPerfect) {
      canvas.drawCircle(
          point, dotRadius * 2.06, Paint()..color = accent.withOpacity(0.22));
    }

    if (score.credit == 0) {
      // Zero, on purpose. Hollow so it is legible as a real recorded point
      // sitting on the floor rather than a gap in the series, which is the
      // same reason the bars this replaced kept a 3pt sliver for a zero day.
      canvas.drawCircle(
        point,
        dotRadius * 0.88,
        Paint()
          ..color = accent.withOpacity(0.85)
          ..strokeWidth = dotRadius * 0.47
          ..style = PaintingStyle.stroke,
      );
    } else {
      canvas.drawCircle(
          point, isToday ? dotRadius * 1.3 : dotRadius, Paint()..color = accent);
    }

    // فشل is a state this app deliberately keeps distinct from an empty
    // square, and the line alone cannot say it: both score zero credit.
    // The tick sits in the margin BELOW the baseline, never inside the
    // plot, where the area fill would swallow it.
    if (score.failed > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(point.dx, baseline + 5),
            width: 6,
            height: 2.5,
          ),
          const Radius.circular(1.25),
        ),
        Paint()..color = failedColor,
      );
    }
  }

  @override
  bool shouldRepaint(DayScoreLinePainter old) =>
      old.progress != progress ||
      old.showLine != showLine ||
      old.isRtl != isRtl ||
      old.selectedIndex != selectedIndex ||
      old.todayIndex != todayIndex ||
      old.lineColor != lineColor ||
      old.bandColor != bandColor ||
      !identical(old.scores, scores);
}

/// The glyph for one habit's mark in the day sheet's habit list.
///
/// Lives here, as a pure top-level function, for one reason: it was keyed on
/// the day's COMPLETION COUNT instead of the mark, so a habit finished by
/// painting a green square on the Grid (which records no count) drew the
/// same hollow circle as a habit that was never touched. A day the header
/// correctly called «تم إنجاز 3 من 6» listed three green habits with one
/// checkmark between them. That is the same tap-count-versus-square split
/// the chart itself was rebuilt to end, and it came back in the row icons
/// because nothing could test them while they were buried in a private
/// widget's switch.
///
/// Never returns the empty glyph for a mark that earned anything.
IconData markRowIcon(SquareState mark) => switch (mark) {
      SquareState.skipped => Icons.next_plan_outlined,
      SquareState.failed => Icons.cancel_outlined,
      SquareState.bonus => Icons.auto_awesome_rounded,
      SquareState.complete => Icons.check_circle_rounded,
      // A hard 50/50 split disc, the glyph SquareState itself picked for
      // جزئي precisely so a half day can never render as an empty one.
      SquareState.partial => Icons.contrast_rounded,
      SquareState.none => Icons.radio_button_unchecked_rounded,
    };

/// The empty-state glyph, named so a test can assert nothing earned reaches it.
const IconData kUnmarkedRowIcon = Icons.radio_button_unchecked_rounded;

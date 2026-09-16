import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show NumberFormat;

import '../../../core/extensions/datetime_ext.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/services/health_steps_service.dart';
import '../../../core/theme/game_theme.dart';
import '../../grid/models/square_state.dart';
import '../step_auto_complete.dart';

/// Reads one day fresh from Health. [refreshStepsFor] in the app; a fake in
/// tests, which have no health store to ask.
typedef StepsDayReader = Future<HealthStepsRangeOutcome> Function(
  WidgetRef ref,
  DateTime day,
);

/// The exact step count of one day, at the top of the sheet a held Grid
/// square opens for a linked walking habit.
///
/// The board draws the short form ("8.4k") inside the square; this is where
/// somebody checks the real number, and it has to be the number the Health
/// app shows for that day: "it should match the health app 100%" (Aziz,
/// 2026-09-16). So it does not trust the log. The day is read fresh the
/// moment the card appears, through the same query the board's counts come
/// from (see HealthStepsService.stepsForDays), and the result is recorded, so
/// the square behind the sheet follows the card rather than disagreeing with
/// it. The stored count shows while that read is out, which on iOS is a few
/// milliseconds, so the card does not flash an empty state first.
///
/// What it will not do is show a zero it cannot stand behind. A day already
/// measured keeps its number against a zero read (the rule in stepsMapWith),
/// a read that fails for a passing reason with nothing stored hides the card
/// rather than inventing a figure, and an Android refusal says so in words.
class StepsDayCard extends ConsumerStatefulWidget {
  final DateTime day;
  final int goal;
  final StepsDayReader? read;

  const StepsDayCard({
    super.key,
    required this.day,
    required this.goal,
    this.read,
  });

  @override
  ConsumerState<StepsDayCard> createState() => _StepsDayCardState();
}

class _StepsDayCardState extends ConsumerState<StepsDayCard> {
  bool _reading = true;
  HealthStepsFailure? _failure;

  @override
  void initState() {
    super.initState();
    // After the first frame: the read ends by writing stepsByDayProvider, and
    // a provider must not change while the sheet is still being built.
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    final read = widget.read ?? (ref, day) => refreshStepsFor(ref, day, 1);
    final outcome = await read(ref, widget.day);
    if (!mounted) return;
    setState(() {
      _reading = false;
      _failure = outcome.failure;
    });
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final dark = gp.dark;
    final s = S.of(context);
    final isHealthConnect = HealthStepsService.usesHealthConnect;
    // By date only. Falling back to stepsTodayProvider for today put
    // yesterday's count on today's card in the minutes after midnight, before
    // the first read of the new day (see readStepsToday).
    final steps = ref.watch(stepsByDayProvider)[widget.day.toDateKey()];

    // Health Connect refusing, which only Android can say (see
    // HealthStepsFailure.permissionDenied). A passing failure with nothing
    // stored has no number worth a card at all.
    final refusal = steps != null
        ? null
        : switch (_failure) {
            HealthStepsFailure.permissionDenied => s.stepsLinkBlocked,
            HealthStepsFailure.notSupported => s.stepsLinkNoProvider,
            _ => null,
          };
    if (steps == null &&
        refusal == null &&
        _failure == HealthStepsFailure.unavailable) {
      return const SizedBox.shrink();
    }

    final grouped = NumberFormat.decimalPattern('en');
    // Still reading, with nothing stored: a quiet placeholder rather than a
    // zero. A finished read with nothing stored IS a zero (zeros are never
    // stored, see stepsMapWith), and says so.
    final number = steps != null
        ? grouped.format(steps)
        : (_reading ? '…' : '0');
    final earned = stepSquareFor(steps: steps ?? 0, goal: widget.goal);
    // The bar speaks the board's colours: amber short of the goal, the green
    // square's green at it, the blue square's blue past 120 percent.
    final barColor = switch (earned) {
      SquareState.bonus => SquareState.bonus.accent(dark),
      SquareState.complete => SquareState.complete.accent(dark),
      _ => SquareState.partial.levelLine(dark),
    };
    final share =
        widget.goal <= 0 ? 0.0 : ((steps ?? 0) / widget.goal).clamp(0.0, 1.0);

    return Semantics(
      container: true,
      label: [
        if (steps != null) s.stepsWalkedLine(steps, widget.goal),
        if (refusal != null) refusal
        else s.stepsSourceLine(isHealthConnect: isHealthConnect),
      ].join(s.isAr ? '، ' : ', '),
      child: ExcludeSemantics(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          decoration: BoxDecoration(
            color: gp.surface,
            borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
            border: Border.all(color: gp.border, width: 0.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  if (refusal == null) ...[
                    Text(
                      number,
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                        fontSize: 28,
                        height: 1.1,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color: steps == null && _reading
                            ? gp.textTert
                            : gp.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      s.stepsUnit,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: gp.textSec,
                      ),
                    ),
                  ],
                  const Spacer(),
                  Text(
                    s.stepsGoalShort(grouped.format(widget.goal)),
                    style: TextStyle(fontSize: 12, color: gp.textSec),
                  ),
                ],
              ),
              if (refusal == null) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
                  child: SizedBox(
                    height: 6,
                    child: ColoredBox(
                      color: gp.surfaceHL,
                      // centerStart: the bar fills from the right in Arabic,
                      // the way the sentence beside it reads.
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: FractionallySizedBox(
                          widthFactor: share,
                          heightFactor: 1,
                          child: AnimatedContainer(
                            duration: GameMotion.standard,
                            curve: Curves.easeOut,
                            decoration: BoxDecoration(
                              color: barColor,
                              borderRadius: BorderRadius.circular(
                                GameSpacing.pillRadius,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (refusal == null) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Icon(
                        Icons.favorite_rounded,
                        size: 12,
                        color: gp.textTert,
                      ),
                    ),
                    const SizedBox(width: 5),
                  ],
                  Expanded(
                    child: Text(
                      refusal ??
                          s.stepsSourceLine(isHealthConnect: isHealthConnect),
                      style: TextStyle(
                        fontSize: refusal == null ? 11 : 12,
                        height: 1.35,
                        color: refusal == null ? gp.textTert : gp.textSec,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

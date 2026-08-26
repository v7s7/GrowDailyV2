import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/extensions/datetime_ext.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../notifiers/habit_resume_notifier.dart';

/// The answer to "لي متى؟", asked once, at the moment of pausing.
///
/// [at] null with [confirmed] true is the deliberate manual pause, which is
/// the default and the first option: the habit stays away until it is
/// resumed by hand, exactly as pausing has always worked. A date means the
/// habit books its own way back.
///
/// [confirmed] false means the sheet was dismissed, which must not pause
/// anything. That distinction is the whole reason this is a record rather
/// than a bare `DateTime?`: "no date" and "no thanks" are different answers
/// and were previously impossible to tell apart.
/// [withTime] says whether the hour is meaningful — true only for a custom
/// pick. A preset resolves to the start of a day and carries no chosen time,
/// so a confirmation that printed "· back Tuesday, 6:00 AM" would show a moment
/// nobody selected. The snackbar reads this to decide whether to say the time.
typedef PauseUntilChoice = ({bool confirmed, DateTime? at, bool withTime});

/// Asks when a habit should come back, offering three shortcuts and a real
/// date-and-time picker.
///
/// Nothing here is required. Confirming on the preselected option is one
/// extra tap over the old flow and produces the identical result, which is
/// the deal: manual stays the default, and a return date is available to
/// anyone who already knows theirs.
Future<PauseUntilChoice> showPauseUntilSheet(
  BuildContext context, {
  required String habitName,
}) async {
  HapticFeedback.mediumImpact();
  final result = await showModalBottomSheet<PauseUntilChoice>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _PauseUntilSheet(habitName: habitName),
  );
  return result ?? (confirmed: false, at: null, withTime: false);
}

class _PauseUntilSheet extends StatefulWidget {
  final String habitName;
  const _PauseUntilSheet({required this.habitName});

  @override
  State<_PauseUntilSheet> createState() => _PauseUntilSheetState();
}

class _PauseUntilSheetState extends State<_PauseUntilSheet> {
  /// null is "I decide", the default. A preset resolves to a date only on
  /// confirm, so a sheet left open past midnight cannot book yesterday.
  ResumePreset? _preset;
  DateTime? _custom;

  bool get _isManual => _preset == null && _custom == null;

  DateTime? _resolve() {
    if (_custom != null) return _custom;
    return _preset?.dateFrom(DateTime.now());
  }

  Future<void> _pickCustom() async {
    HapticFeedback.selectionClick();
    final now = DateTime.now();
    final today = now.effectiveDay;
    final date = await showDatePicker(
      context: context,
      // Tomorrow at the earliest: a habit booked back today is just a habit
      // that was never paused, and the picker should not offer a date that
      // resolves to a no-op.
      initialDate: today.add(const Duration(days: 7)),
      firstDate: today.add(const Duration(days: 1)),
      lastDate: DateTime(today.year + 2, today.month, today.day),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 6, minute: 0),
    );
    if (!mounted) return;
    setState(() {
      _preset = null;
      // A cancelled time picker keeps the date and defaults to the start of
      // it — kDayCutoffHour (6am), NOT midnight. 00:00 belongs to the previous
      // effective day (see ResumePreset.dateFrom), so between midnight and 6am
      // firstDate resolves to the real current date and a 00:00 default would
      // book a moment already in the past, auto-resuming the habit at once as
      // though it had never been paused. The cutoff hour is the first instant
      // of the chosen day and always sits in the future here.
      _custom = DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? kDayCutoffHour,
        time?.minute ?? 0,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        decoration: BoxDecoration(
          color: gp.surfaceHigh,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: gp.border,
                  borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
                ),
              ),
            ),
            Text(
              s.pauseUntilTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: gp.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              s.pauseUntilSubtitle(widget.habitName),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: gp.textSec, height: 1.35),
            ),
            const SizedBox(height: 16),
            // Five options plus a title and two buttons do not fit every
            // screen: a short one overflowed this Column by under a pixel,
            // which is invisible in the simulator and a striped error bar in
            // a widget test. Scrolling the options rather than the whole
            // sheet keeps Pause reachable without a scroll, which is the one
            // control that must never be below the fold.
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Choice(
                      label: s.pauseUntilManual,
                      subtitle: s.pauseUntilManualHint,
                      selected: _isManual,
                      onTap: () => setState(() {
                        _preset = null;
                        _custom = null;
                      }),
                    ),
                    for (final preset in ResumePreset.values)
                      _Choice(
                        label: s.pauseUntilPreset(preset.name),
                        subtitle: s.pauseUntilOn(formatResumeDate(
                            preset.dateFrom(DateTime.now()), s.isAr)),
                        selected: _custom == null && _preset == preset,
                        onTap: () => setState(() {
                          _preset = preset;
                          _custom = null;
                        }),
                      ),
                    _Choice(
                      label: s.pauseUntilCustom,
                      subtitle: _custom == null
                          ? s.pauseUntilCustomHint
                          : s.pauseUntilOn(formatResumeDate(_custom!, s.isAr,
                              withTime: true)),
                      selected: _custom != null,
                      onTap: _pickCustom,
                      trailing:
                          Icon(Icons.event_rounded, size: 18, color: gp.textSec),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 46,
              child: FilledButton(
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  Navigator.pop<PauseUntilChoice>(
                    context,
                    // Only a custom pick carries a meaningful time; a preset
                    // lands on the day's start with no chosen hour.
                    (confirmed: true, at: _resolve(), withTime: _custom != null),
                  );
                },
                child: Text(s.habitPause),
              ),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.pop<PauseUntilChoice>(
                context,
                (confirmed: false, at: null, withTime: false),
              ),
              child: Text(s.habitActionsCancel,
                  style: TextStyle(fontSize: 13, color: gp.textSec)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  final Widget? trailing;
  const _Choice({
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final tint = selected ? GameColors.gold : gp.border;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: GameMotion.quick,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? GameColors.gold.withOpacity(0.10)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
            border: Border.all(color: tint, width: selected ? 1.4 : 1),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 18,
                color: selected ? GameColors.gold : gp.textTert,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: gp.textPrimary)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 11.5, color: gp.textSec, height: 1.3)),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

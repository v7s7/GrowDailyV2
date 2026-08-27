import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../../shared/widgets/choice_chip_grid.dart';
import '../../matrix/widgets/custom_offset_sheet.dart'
    show ReminderUnit, splitOffsetUnit;
import '../models/habit_cue.dart';

/// The largest shift a habit reminder can carry, in minutes.
///
/// Twelve hours, which is the point where a shift stops being a shift. Past
/// it you are not asking to be nudged early about a habit at 8:00, you are
/// asking for a habit at a different time — and the row's own picker is the
/// control for that. It also keeps the reminder inside the same day as the
/// occurrence it belongs to, which is what makes "the 1st reminder" and "the
/// 2nd reminder" mean anything.
const int kMaxHabitOffsetMinutes = 12 * 60;

/// Ask for one habit reminder's shift: before or after, how many, of what.
///
/// Returns the signed minutes (negative before, positive after), or null if
/// the sheet was dismissed without confirming — so a caller can tell "they
/// chose zero" from "they backed out", which a bare int could not.
///
/// The same three-control shape as the task sheet this borrows from
/// (custom_offset_sheet.dart): direction, then number, then unit, reading
/// top to bottom as one sentence. Deliberately NOT that sheet itself — a task
/// collects a SET of offsets from one anchor, with add/remove, a premium
/// stack limit and a live "which day" preview. A habit occurrence has exactly
/// one shift, so every one of those affordances would be answering a question
/// nobody asked here.
///
/// Two units, not three. A task can sit days out, so days is a real answer
/// there; a habit repeats every day, so "2 days before" lands on the same
/// clock time it started from and means nothing. Offering it would be
/// offering a no-op.
Future<int?> showHabitOffsetSheet(
  BuildContext context, {
  required int current,
  required TimeOfDay? anchor,
}) {
  HapticFeedback.selectionClick();
  return showModalBottomSheet<int>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _HabitOffsetSheet(current: current, anchor: anchor),
  );
}

class _HabitOffsetSheet extends StatefulWidget {
  final int current;
  final TimeOfDay? anchor;
  const _HabitOffsetSheet({required this.current, required this.anchor});

  @override
  State<_HabitOffsetSheet> createState() => _HabitOffsetSheetState();
}

class _HabitOffsetSheetState extends State<_HabitOffsetSheet> {
  late final TextEditingController _ctrl;
  late bool _isAfter;
  late ReminderUnit _unit;

  @override
  void initState() {
    super.initState();
    // Seeded from whatever the row already carries, split back into the
    // largest unit that divides it evenly — so reopening on "2 hours before"
    // shows 2 and Hours rather than 120 and Minutes. Same helper the task
    // sheet uses, so the two can never disagree about which unit a value is.
    _isAfter = widget.current > 0;
    final (value, unit) = splitOffsetUnit(widget.current.abs());
    // Minutes on a fresh sheet. splitOffsetUnit(0) answers DAYS — zero divides
    // evenly by everything, so the largest unit wins — which would open the
    // most common case (a few minutes early) on the wrong unit and quietly
    // multiply whatever was typed by sixty.
    _unit = widget.current == 0
        ? ReminderUnit.minutes
        : unit == ReminderUnit.days
            ? ReminderUnit.hours
            : unit;
    _ctrl = TextEditingController(
      text: widget.current == 0 ? '' : '$value',
    );
    _ctrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// The signed value the field currently describes, or null when there is
  /// nothing usable in it yet.
  int? get _pending {
    final raw = int.tryParse(_ctrl.text.trim());
    if (raw == null || raw <= 0) return null;
    final minutes = raw * _unit.inMinutes;
    if (minutes > kMaxHabitOffsetMinutes) return null;
    return _isAfter ? minutes : -minutes;
  }

  /// Why the current entry cannot be used, or null when it can.
  String? _blocked(S s) {
    final raw = int.tryParse(_ctrl.text.trim());
    if (raw == null || raw <= 0) return null;
    if (raw * _unit.inMinutes > kMaxHabitOffsetMinutes) {
      return s.habitOffsetTooLarge;
    }
    return null;
  }

  /// Where the reminder actually lands. Wraps at midnight, which a shift on
  /// an early-morning or late-night occurrence genuinely does.
  String? _resolved(S s) {
    final anchor = widget.anchor;
    final pending = _pending;
    if (anchor == null || pending == null) return null;
    final total = (anchor.hour * 60 + anchor.minute + pending) % (24 * 60);
    final m = total < 0 ? total + 24 * 60 : total;
    return HabitCue.time(m ~/ 60, m % 60).labelForLocale(s.isAr);
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final blocked = _blocked(s);
    final resolved = _resolved(s);
    final accent = GameColors.gold;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        decoration: BoxDecoration(
          color: gp.bg,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(GameSpacing.cardRadius),
          ),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
              const SizedBox(height: 16),
              Text(
                s.customReminderTitle,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: gp.textPrimary,
                ),
              ),
              if (widget.anchor != null) ...[
                const SizedBox(height: 4),
                Text(
                  s.habitOffsetFromTime(
                    HabitCue.time(widget.anchor!.hour, widget.anchor!.minute)
                        .labelForLocale(s.isAr),
                  ),
                  style: TextStyle(fontSize: 11.5, color: gp.textTert),
                ),
              ],
              const SizedBox(height: 14),
              // Direction first: it changes what the number means, so the
              // sheet reads as one sentence downward — before or after, how
              // many, of what.
              ChoiceChipGrid(
                columns: 2,
                items: [
                  PlainChoiceChip(
                    selected: !_isAfter,
                    label: s.offsetBeforeLabel,
                    selectedColor: accent,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _isAfter = false);
                    },
                  ),
                  PlainChoiceChip(
                    selected: _isAfter,
                    label: s.offsetAfterLabel,
                    selectedColor: accent,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _isAfter = true);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _ctrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _confirm(),
                textAlign: TextAlign.center,
                cursorColor: accent,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
                decoration: InputDecoration(
                  hintText: s.customReminderValueHint,
                  hintStyle: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: gp.textTert,
                  ),
                  filled: true,
                  fillColor: gp.surface,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: gp.border.withOpacity(0.8)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: gp.border.withOpacity(0.8)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: accent, width: 1.2),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ChoiceChipGrid(
                columns: 2,
                items: [
                  for (final u in const [
                    ReminderUnit.minutes,
                    ReminderUnit.hours,
                  ])
                    PlainChoiceChip(
                      selected: _unit == u,
                      label: u == ReminderUnit.minutes
                          ? s.unitMinutes
                          : s.unitHours,
                      selectedColor: accent,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _unit = u);
                      },
                    ),
                ],
              ),
              // The answer, live. Typing "2" under Hours shows the clock time
              // it lands on, so nobody has to do the arithmetic themselves to
              // find out what they are about to set.
              if (resolved != null || blocked != null) ...[
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      blocked == null
                          ? Icons.notifications_active_rounded
                          : Icons.error_outline_rounded,
                      size: 14,
                      color: blocked == null ? accent : GameColors.error,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        blocked ?? s.remindAtTimePreview(resolved!),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: blocked == null
                              ? gp.textPrimary
                              : GameColors.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              FilledButton(
                onPressed: _pending == null ? null : _confirm,
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: GameColors.onGold,
                  minimumSize: const Size(double.infinity, 48),
                ),
                child: Text(s.customReminderAdd),
              ),
              // The way back to no shift at all, without having to know that
              // clearing the field and confirming would do it (it would not —
              // an empty field disables the button).
              const SizedBox(height: 6),
              TextButton(
                onPressed: () => Navigator.of(context).pop(0),
                style: TextButton.styleFrom(
                  foregroundColor: gp.textSec,
                  minimumSize: const Size(double.infinity, 44),
                ),
                child: Text(s.leadAtTime),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirm() {
    final pending = _pending;
    if (pending == null) return;
    HapticFeedback.selectionClick();
    Navigator.of(context).pop(pending);
  }
}

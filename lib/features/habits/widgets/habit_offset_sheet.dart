import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/l10n/reminder_copy.dart'
    show countedOffsetPhrase, kReminderOffsetPresets, reminderOffsetLabel;
import '../../../core/theme/game_theme.dart';
import '../../../core/utils/western_digits.dart';
import '../../../shared/widgets/choice_chip_grid.dart';
import '../../matrix/widgets/custom_offset_sheet.dart'
    show ReminderUnit, formatOffsetVerbose, splitOffsetUnit;
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
///
/// [presets] adds the quick chips (في الوقت, 5, 10, 15, 30, ساعة) above
/// the number field and returns the moment one is tapped; the field stays
/// for anything else. That is the sheet the reminder rows in AddHabitSheet
/// open, so a person never has to type to move a reminder by a quarter
/// hour. [current] may be null there: a row being added has no value yet.
///
/// [leanAfter] is the side a reminder with no side of its own opens on: one
/// on time, or one being added. Add Habit passes it for a prayer habit, from
/// the side its other reminders are on or the side last chosen here, so one
/// tap on 15 lands on the side the person has been using. This sheet is the
/// one place a prayer reminder's side is chosen. A reminder that already
/// has a shift always opens on its own side, whatever the lean.
///
/// [editing] says the sheet was opened on a reminder that exists, and the
/// button says so: «حفظ» there, «إضافة» only when a reminder is being added.
///
/// [anchorName] names what the shift is measured from, the prayer («الفجر»),
/// so the subtitle can say it even before a location gives it a time.
Future<int?> showHabitOffsetSheet(
  BuildContext context, {
  required int? current,
  required TimeOfDay? anchor,
  bool presets = false,
  bool leanAfter = false,
  bool editing = false,
  String? anchorName,
}) {
  HapticFeedback.selectionClick();
  return showModalBottomSheet<int>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _HabitOffsetSheet(
      current: current,
      anchor: anchor,
      presets: presets,
      leanAfter: leanAfter,
      editing: editing,
      anchorName: anchorName,
    ),
  );
}

/// One habit reminder as the sentence its row in Add Habit shows.
///
/// With a [prayer] (its label, «الفجر») the row names the prayer and the
/// side in one line: «في وقت الفجر», «قبل الفجر بـ15 دقيقة», «بعد المغرب
/// بساعة». It used to say only «قبل ١٥ دقيقة», under a lit «بعد» chip on the
/// same screen, and nothing on it said before WHAT.
///
/// The amount is counted by [countedOffsetPhrase], the function the
/// notification itself counts with, so the row and the reminder that fires
/// can never disagree about «دقيقتين» against «2 دقائق». Its digits are then
/// made Latin, the app's rule for anything on screen; the notification copy
/// keeps its own.
///
/// Without a prayer (a picked clock time) the row keeps the words it always
/// had, «في الوقت» or [formatOffsetVerbose]'s «قبل 15 دقيقة», with Latin
/// digits too. The time beside it and the sheet it opens were made Latin,
/// and the shared phrase left alone drew «قبل ١٥ دقيقة» next to «7:15 ص» in
/// one row.
String habitReminderSentence(int offset, S s, {String? prayer}) {
  if (prayer == null) {
    return offset == 0
        ? s.leadAtTime
        : toWesternDigits(formatOffsetVerbose(offset, s.isAr, s));
  }
  if (offset == 0) return s.habitReminderAtPrayer(prayer);
  final amount = toWesternDigits(countedOffsetPhrase(offset.abs(), s.isAr));
  return offset < 0
      ? s.habitReminderBeforePrayer(prayer, amount)
      : s.habitReminderAfterPrayer(prayer, amount);
}

class _HabitOffsetSheet extends StatefulWidget {
  final int? current;
  final TimeOfDay? anchor;
  final bool presets;
  final bool leanAfter;
  final bool editing;
  final String? anchorName;
  const _HabitOffsetSheet({
    required this.current,
    required this.anchor,
    required this.presets,
    required this.leanAfter,
    required this.editing,
    required this.anchorName,
  });

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
    final current = widget.current ?? 0;
    // A shift carries its own side. Only a reminder with none (on time, or
    // one being added) takes the lean Add Habit passes (see leanAfter).
    _isAfter = current > 0 || (current == 0 && widget.leanAfter);
    final (value, unit) = splitOffsetUnit(current.abs());
    // Minutes on a fresh sheet. splitOffsetUnit(0) answers DAYS — zero divides
    // evenly by everything, so the largest unit wins — which would open the
    // most common case (a few minutes early) on the wrong unit and quietly
    // multiply whatever was typed by sixty.
    _unit = current == 0
        ? ReminderUnit.minutes
        : unit == ReminderUnit.days
            ? ReminderUnit.hours
            : unit;
    // A preset value is a chip below, so the field starts empty for it and
    // only a hand-typed value comes back into the field.
    final typed = current != 0 &&
        !(widget.presets && kReminderOffsetPresets.contains(current.abs()));
    _ctrl = TextEditingController(text: typed ? '$value' : '');
    _ctrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// The preset the reminder being edited already has, by amount: 0 for
  /// «في الوقت», 15 for 15 before or after, null for a typed value or a
  /// reminder being added. By amount rather than by signed value, which is
  /// what keeps the chip lit through a flip of قبل and بعد.
  int? get _litPreset {
    final current = widget.current;
    if (!widget.presets || current == null) return null;
    final amount = current.abs();
    return amount == 0 || kReminderOffsetPresets.contains(amount)
        ? amount
        : null;
  }

  /// The signed value the sheet currently describes, or null when there is
  /// nothing usable in it yet.
  ///
  /// A typed number wins. With the field empty, a lit amount stands in, so
  /// flipping 15 before to بعد keeps 15, shows where 15 after lands and lets
  /// «حفظ» save it (Aziz, 2026-09-11), exactly as a typed 45 always behaved.
  /// It used to read the field alone, which is empty for every preset, so
  /// the flip unlit the amount and left the button dead. «في الوقت» has no
  /// side to flip and stays a tap on its own chip.
  int? get _pending {
    if (_ctrl.text.trim().isEmpty) {
      final lit = _litPreset;
      return lit == null || lit == 0 ? null : _signed(lit);
    }
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

  /// The anchor as a clock label, «4:03 ص», or null with no anchor. Built
  /// the way [_resolved] builds its time, so the subtitle and the preview
  /// never draw the same minute in two digit sets.
  String? _anchorLabel(S s) {
    final anchor = widget.anchor;
    return anchor == null
        ? null
        : HabitCue.time(anchor.hour, anchor.minute).labelForLocale(s.isAr);
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
        padding: EdgeInsets.fromLTRB(
          20,
          10,
          20,
          20 + MediaQuery.of(context).padding.bottom,
        ),
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
                widget.presets ? s.remindMeSection : s.customReminderTitle,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: gp.textPrimary,
                ),
              ),
              // A prayer is named even before a location gives it a time:
              // the shift is from Fajr whether or not Fajr has a clock yet.
              if (widget.anchorName != null || widget.anchor != null) ...[
                const SizedBox(height: 4),
                Text(
                  widget.anchorName != null
                      ? s.habitOffsetFromPrayer(
                          widget.anchorName!,
                          time: _anchorLabel(s),
                        )
                      : s.habitOffsetFromTime(_anchorLabel(s)!),
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
              if (widget.presets) ...[
                // One tap picks and closes. «في الوقت» belongs to neither
                // direction, so it is a chip rather than a third toggle
                // cell, the shape the old inline grid had.
                ChoiceChipGrid(
                  columns: 3,
                  items: [
                    PlainChoiceChip(
                      selected: _litPreset == 0,
                      label: s.leadAtTime,
                      selectedColor: accent,
                      onTap: () => _pick(0),
                    ),
                    for (final m in kReminderOffsetPresets)
                      PlainChoiceChip(
                        // By amount, so it stays lit through a flip.
                        selected: _litPreset == m,
                        // Latin digits, the rule for anything on screen. The
                        // shared label keeps its own for the Tasks picker.
                        label: toWesternDigits(reminderOffsetLabel(m, s.isAr)),
                        selectedColor: accent,
                        onTap: () => _pick(_signed(m)),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  s.leadCustomOption,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: gp.textTert,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              TextField(
                selectionWidthStyle: GameTextStyles.selectionWidthStyle,
                controller: _ctrl,
                // With chips above, the keyboard waits for a tap on the
                // field instead of covering the chips as the sheet opens.
                autofocus: !widget.presets,
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
                      color: blocked == null ? accent : context.gp.errorInk,
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
                              : context.gp.errorInk,
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
                // «إضافة» on an edit read as adding a second reminder.
                child: Text(
                  widget.editing ? s.habitOffsetSave : s.customReminderAdd,
                ),
              ),
              // The way back to no shift at all, without having to know that
              // clearing the field and confirming would do it (it would not —
              // an empty field disables the button).
              const SizedBox(height: 6),
              if (!widget.presets)
              TextButton(
                onPressed: () => _pick(0),
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
    _pick(pending);
  }

  int _signed(int magnitude) => _isAfter ? magnitude : -magnitude;

  void _pick(int signed) {
    HapticFeedback.selectionClick();
    Navigator.of(context).pop(signed);
  }
}

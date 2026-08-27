import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/extensions/datetime_ext.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/l10n/reminder_copy.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/theme/game_theme.dart';
import '../../../core/utils/western_digits.dart';
import '../../../shared/widgets/choice_chip_grid.dart';
import '../models/matrix_task.dart';
import '../../../shared/widgets/overlay_notice.dart';
import 'custom_offset_sheet.dart';

// arabicDigits moved to core/l10n/reminder_copy.dart, so notification copy
// can reach it without importing a widget file. Re-exported because this is
// where profile_screen.dart and the offset sheet have always imported it
// from, and it still belongs beside [ReminderRow], which is what it exists
// for: a time rendered inside an Arabic run picks up Arabic-Indic digits
// from the font, so a bare chip number next to it has to be converted by
// hand or the two disagree on screen.
export '../../../core/l10n/reminder_copy.dart' show arabicDigits;

/// Formats [dt] for display on [ReminderRow] / anywhere else a task's
/// reminder needs a human label — "Today · 5:00 PM" / "Tomorrow · 9:00 AM"
/// / "Jul 18 · 9:00 AM". [now] defaults to the real clock but is
/// overridable so this stays a pure, deterministic function for
/// test/matrix_reminder_test.dart rather than something that has to mock
/// DateTime.now().
///
/// Deliberately keyed off the *real* calendar day (DateTimeGameExt.
/// isSameDayAs), not MatrixTask's own effectiveDay/carried-over concept —
/// a reminder fires at a real wall-clock moment, so "Today" here means
/// what the device's clock says today is, same reasoning as
/// DateTimeGameExt.isRealToday.
///
/// Genuinely public now, not just test-visible: [ReminderRow], the preview
/// line, and the custom-offset sheet's added-reminder chips all need the
/// same "which day, what time" phrasing, and a day-scale offset makes the
/// day half load-bearing — two reminders 48 hours apart otherwise render as
/// the identical clock time.
String formatReminderMoment(DateTime dt, bool isAr, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final locale = isAr ? 'ar' : 'en';
  final time = DateFormat('h:mm a', locale).format(dt);
  if (dt.isSameDayAs(today)) {
    return isAr ? 'اليوم · $time' : 'Today · $time';
  }
  if (dt.isSameDayAs(today.add(const Duration(days: 1)))) {
    return isAr ? 'غدًا · $time' : 'Tomorrow · $time';
  }
  final date = DateFormat('MMM d', locale).format(dt);
  return '$date · $time';
}

/// Offsets (in minutes) a task's extra reminders can sit at, relative to its
/// anchor. Mirrors Add Habit's `_offsetPresets` in spirit — same question,
/// "how long before or after?" — but unsigned here, because direction is a
/// separate two-chip toggle the user sets once and then applies to as many
/// offsets as they like.
/// Five, which together with the custom field makes six cells on a
/// 3-column grid: two complete rows with no ragged gap.
const kReminderOffsetPresets = <int>[5, 10, 15, 30, 60];

/// Every moment a task will nudge at: the anchor itself, plus one reminder
/// per selected offset.
///
/// The anchor is always included — it's the time the user actually picked,
/// and both TickTick and Todoist treat "at the time" as a reminder in its
/// own right rather than something you have to ask for separately. Offsets
/// are signed: negative is before, positive is after.
List<DateTime> remindersFor({
  required DateTime? anchor,
  required Set<int> offsets,
}) {
  if (anchor == null) return const [];
  return MatrixTask.normalizeReminders([
    anchor,
    for (final o in offsets) anchor.add(Duration(minutes: o)),
  ]);
}

/// Inverse of [remindersFor], for reopening a task whose reminders were
/// saved on a previous visit.
///
/// Takes the anchor as an input rather than guessing it, which is the whole
/// fix: the arithmetic genuinely cannot be inverted, so an earlier version
/// that assumed `reminders.last` was the anchor reframed every "after" stack
/// on reopen. A 12:00 anchor with a +15 offset came back claiming 12:15 was
/// the moment you'd picked and 12:00 was a warning about it — the same
/// alarms telling a story the user never wrote. Which entry was really
/// chosen now lives on the task (MatrixTask.reminderAnchorAt), and
/// MatrixTask.resolveAnchor supplies the old `reminders.last` guess only for
/// tasks saved before that field existed.
///
/// The anchor's own entry contributes no offset (it would be zero), so a
/// task with a single reminder comes back with an empty set.
Set<int> offsetsFrom({
  required DateTime? anchor,
  required List<DateTime> reminders,
}) {
  if (anchor == null) return <int>{};
  return {
    for (final r in reminders)
      if (r.difference(anchor).inMinutes != 0) r.difference(anchor).inMinutes,
  };
}

/// Arabic-Indic digits (٠-٩) mapped to plain ASCII, so [int.tryParse] can
/// read a number typed on an Arabic keypad. Mirrors room_model.dart's
/// `_normalizeDigits` and HabitCue's equivalent — a user who types ٤٥ into
/// the minutes field must get 45, not a silent no-op.
String normalizeArabicDigits(String input) => toWesternDigits(input);

/// Chip label for an offset: the number for minutes, a word for the hours,
/// since "120" reads worse than "ساعتان" at a glance. Direction comes from
/// the قبل/بعد toggle above the grid, not from the label.
@visibleForTesting
String reminderOffsetLabel(int minutes, bool isAr) {
  if (minutes == 60) return isAr ? 'ساعة' : '1 hour';
  if (minutes == 120) return isAr ? 'ساعتان' : '2 hours';
  return isAr ? arabicDigits(minutes) : '$minutes';
}

/// Two native dialogs (date, then time), not one bespoke combined widget —
/// this app has no custom date+time picker anywhere yet, and
/// showDatePicker/showTimePicker back to back is the same interaction a
/// user already knows from Settings' quiet-hours pickers
/// (notification_settings_screen.dart's _TimeRow) and Add Habit's time step
/// (add_habit_sheet.dart's _pickTime). Introducing a third, bespoke
/// combined picker just for this one row isn't worth the inconsistency.
///
/// A task reminder is an absolute, one-off moment (see MatrixTask.
/// reminderAt's doc comment) rather than a recurring wall-clock time, which
/// is exactly why this asks for a full date *and* time instead of just a
/// TimeOfDay the way habit reminders do — a Matrix task can sit carried
/// over for days (see MatrixScreen._carriedOverOnly), so "remind me" has to
/// be able to point at a day other than today or tomorrow.
///
/// Returns null if the user backs out of either dialog, or if the combined
/// result isn't actually in the future — a plain SnackBar explains the
/// second case rather than silently discarding it, but either way the
/// caller can treat null as "nothing changed," same as a cancelled
/// showTimePicker anywhere else in this app.
Future<DateTime?> pickReminderMoment(
  BuildContext context, {
  DateTime? initial,
}) async {
  final now = DateTime.now();
  // ONE moment drives both pickers, so the date and the time can never
  // disagree. They used to be derived separately: the date defaulted to
  // today while the time defaulted to now + 1 hour, so any task added
  // after 23:00 offered today at 00:30 — a moment already in the past,
  // which the guard below then rejected. The user was left to work out on
  // their own that they had to advance the date by a day.
  final suggested = initial != null && initial.isAfter(now)
      ? initial
      : now.add(const Duration(hours: 1));
  final date = await showDatePicker(
    context: context,
    initialDate: suggested,
    firstDate: now,
    lastDate: now.add(const Duration(days: 365)),
  );
  if (date == null || !context.mounted) return null;

  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(suggested),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
      child: child!,
    ),
  );
  if (time == null || !context.mounted) return null;

  final picked =
      DateTime(date.year, date.month, date.day, time.hour, time.minute);
  if (!picked.isAfter(DateTime.now())) {
    // Overlay, not SnackBar: both host sheets are modals, so the SnackBar
    // version of this message drew behind them — the user picked a past
    // time, both dialogs closed, and the row still said "set a reminder"
    // with no visible explanation of why.
    showOverlayNotice(
      context,
      S.of(context).matrixReminderPast,
      icon: Icons.history_toggle_off_rounded,
    );
    return null;
  }
  return picked;
}

/// Display + tap target for a task's reminder — "Set a reminder" when
/// unset, or the formatted moment plus a clear (×) button once one's
/// picked. Purely a dumb display widget driven by callbacks, same shape as
/// MicRecordButton/VoiceNoteRow (add_task_sheet.dart / voice_note_player.
/// dart): it never calls [pickReminderMoment] or NotificationService
/// itself, so AddTaskSheet (which can't persist anything yet — the task
/// doesn't exist) and TaskDetailSheet (which persists immediately, see its
/// own reminder handler) can each decide what picking or clearing actually
/// does, exactly like every other control shared between those two sheets.
class ReminderRow extends StatelessWidget {
  final DateTime? value;
  final Color color;
  final bool isAr;
  final VoidCallback onTap;
  final VoidCallback onClear;

  const ReminderRow({
    super.key,
    required this.value,
    required this.color,
    required this.isAr,
    required this.onTap,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final set = value != null;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: gp.surfaceHL,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: gp.border, width: 0.5),
        ),
        child: Row(
          children: [
            Icon(
              Icons.notifications_outlined,
              size: 18,
              color: set ? color : gp.textTert,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                set
                    ? formatReminderMoment(value!, isAr)
                    : s.matrixReminderLabel,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: set ? FontWeight.w700 : FontWeight.w600,
                  color: set ? gp.textPrimary : gp.textTert,
                ),
              ),
            ),
            if (set)
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  onClear();
                },
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child:
                      Icon(Icons.close_rounded, size: 16, color: gp.textTert),
                ),
              )
            else
              Icon(Icons.chevron_right_rounded, size: 18, color: gp.textTert),
          ],
        ),
      ),
    );
  }
}

/// A task's whole reminder set: one anchor time, plus any number of
/// offsets before or after it.
///
/// Modelled deliberately on Add Habit's "Remind me" section — the same
/// [ChoiceChipGrid], the same before/after toggle, the same custom-minutes
/// escape hatch — because both screens ask the identical question and a
/// user who has learned one shouldn't have to learn the other. The
/// difference is that offsets here are *multi*-select: a task can nudge at
/// 4:00, 4:30 and 5:00, where a habit fires once.
///
/// Flow is anchor-first by design. Tapping an unset reminder goes straight
/// to the date+time picker, because when the thing happens is the one piece
/// of information only the user has; everything after that is arithmetic
/// the app can do for them. Until an anchor exists there is nothing for
/// "before" or "after" to mean, so the offsets don't appear at all.
///
/// Same dumb-display contract as [ReminderRow]: it never calls
/// [pickReminderMoment], NotificationService, or the premium providers
/// itself. The sheets own all of that.
class ReminderPicker extends StatefulWidget {
  /// The moment everything else is relative to — usually the thing being
  /// remembered (the 5pm meeting), not a warning about it. Null means no
  /// reminders at all, which is most tasks.
  final DateTime? anchorAt;

  /// Signed minutes: negative before the anchor, positive after. The same
  /// convention Add Habit's `reminderOffsetMinutes` uses, so the two
  /// features can't disagree about what a negative number means.
  final Set<int> offsets;

  final Color color;
  final bool isAr;

  /// False on the free tier once an anchor exists. Matches Todoist and
  /// TickTick, which both give one reminder per task away and charge for
  /// the stack. The chips stay visible and tappable either way — tapping
  /// one just opens the upsell instead of selecting it, so the feature is
  /// discoverable rather than invisible.
  final bool canStack;

  final VoidCallback onPickAnchor;
  final VoidCallback onClear;
  final void Function(int signedMinutes) onToggleOffset;
  final VoidCallback onLocked;

  const ReminderPicker({
    super.key,
    required this.anchorAt,
    required this.offsets,
    required this.color,
    required this.isAr,
    required this.canStack,
    required this.onPickAnchor,
    required this.onClear,
    required this.onToggleOffset,
    required this.onLocked,
  });

  @override
  State<ReminderPicker> createState() => _ReminderPickerState();
}

class _ReminderPickerState extends State<ReminderPicker> {
  /// Offsets the task carries that no preset chip stands for — a hand-typed
  /// 45, or a day-scale one.
  ///
  /// No direction filter, unlike the version that had a قبل/بعد toggle: with
  /// signed presets there is no "current tab" for an offset to fall outside
  /// of, so every reminder the task holds has a chip, always. That filter was
  /// the reason a stored offset could vanish from the grid entirely while
  /// still being scheduled.
  ///
  /// Which direction the offset chips currently mean.
  ///
  /// Seeded from the task's own offsets rather than hardcoded to "before",
  /// and that is half the bug this screen had. The old initialiser was a
  /// plain `= false`, so a task built entirely out of "after" offsets
  /// reopened on the قبل tab with an empty-looking grid — every chip it
  /// actually had was in the other tab.
  ///
  /// It went unnoticed because the *other* half of the bug hid it: the
  /// anchor used to be re-guessed as the last reminder on reopen, which
  /// forced every reconstructed offset negative, so everything really was
  /// "before" and the wrong default happened to look right. Now that the
  /// anchor is stored and an after-ladder comes back as an after-ladder
  /// (see offsetsFrom), this has to read the data or it lands on the wrong
  /// tab. The two fixes only work together.
  ///
  /// Ties and empties go to "before": a reminder about a thing almost
  /// always wants to arrive ahead of it.
  late bool _isAfter = _initialIsAfter();

  bool _initialIsAfter() {
    final offsets = widget.offsets;
    if (offsets.isEmpty) return false;
    return offsets.every((o) => !o.isNegative);
  }

  int _signed(int minutes) => _isAfter ? minutes : -minutes;

  /// Offsets belonging to the *current* tab that no preset chip stands for
  /// — a hand-typed value like 45, or a day-scale one.
  ///
  /// Scoped to the direction on purpose: قبل and بعد read as two tabs, so a
  /// "2 days after" chip sitting under a selected قبل would contradict the
  /// tab it's in. Anything in the other direction is still scheduled and
  /// still listed in the preview line below; switching tabs brings it back
  /// into view, and the custom sheet lists every direction at once.
  List<int> get _unlistedOffsets {
    final out = widget.offsets
        .where((o) => o.isNegative != _isAfter)
        .where((o) => !kReminderOffsetPresets.contains(o.abs()))
        .toList()
      ..sort();
    return out;
  }

  /// The counted, unit-aware form — "يومين", not "٢٨٨٠".
  ///
  /// No direction word: [_unlistedOffsets] only ever yields offsets matching
  /// the selected tab, so every chip on screen already shares the قبل/بعد
  /// above them — printing it on each one would just repeat the tab.
  String _unlistedLabel(S s, int offset) =>
      formatOffsetVerbose(offset, widget.isAr, s, withDirection: false);

  /// Whether an offset would still land in the future. An offset that has
  /// already elapsed can be previewed and stored but will never be
  /// scheduled (see MatrixNotifier.futureTaskReminders), so offering it
  /// would promise a nudge that silently never arrives.
  bool _isReachable(int signedMinutes) {
    final at = widget.anchorAt?.add(Duration(minutes: signedMinutes));
    return at != null && at.isAfter(DateTime.now());
  }

  /// Why the last tap didn't do anything, shown inline under the grid.
  ///
  /// Inline rather than a SnackBar, because this widget lives inside a
  /// showModalBottomSheet and the ScaffoldMessenger is *behind* that sheet —
  /// a SnackBar posted from here is drawn under the sheet and never seen.
  /// The custom-offset sheet already learned this the hard way and states it
  /// in its own source; the two rejections reachable from this grid (the
  /// slot ceiling, an offset that has already elapsed) were still answering
  /// with nothing at all.
  String? _notice;
  Timer? _noticeTimer;

  void _showNotice(String message) {
    setState(() => _notice = message);
    _noticeTimer?.cancel();
    // Roughly a SnackBar's dwell. Cleared rather than left in place so the
    // section doesn't accumulate a permanent scolding line.
    _noticeTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _notice = null);
    });
  }

  @override
  void dispose() {
    _noticeTimer?.cancel();
    super.dispose();
  }

  void _toggle(int minutes) {
    final s = S.of(context);
    final signed = _signed(minutes);
    // Deselecting is always allowed, whatever the entitlement says. The
    // premium gate is on *adding* — see kFreeTaskReminders' doc comment,
    // which promises a task keeps the reminders it already has if a
    // subscription lapses. Gating removal too would strand someone with an
    // inherited stack they can only clear wholesale, never trim.
    if (widget.offsets.contains(signed)) {
      HapticFeedback.selectionClick();
      widget.onToggleOffset(signed);
      return;
    }
    if (!widget.canStack) {
      widget.onLocked();
      return;
    }
    // The anchor occupies a slot too, so this is the same arithmetic the
    // host sheets do before they persist. Checked here as well because here
    // is where the tap happens and so here is where it can be explained.
    if (widget.offsets.length + 1 >=
        NotificationService.kMaxTaskReminderSlots) {
      HapticFeedback.lightImpact();
      _showNotice(s.matrixReminderMaxReached);
      return;
    }
    if (!_isReachable(signed)) {
      HapticFeedback.lightImpact();
      _showNotice(s.matrixReminderOffsetPast);
      return;
    }
    HapticFeedback.selectionClick();
    widget.onToggleOffset(signed);
  }

  /// Opens the custom-offset sheet — a number, its unit, and the list of
  /// what's already set, none of which fits beside the grid on a phone.
  ///
  /// Everything the sheet changes is applied through
  /// [ReminderPicker.onToggleOffset] as it happens rather than handed back
  /// on close, so dismissing it can never lose an entry.
  void _openCustomSheet() {
    final anchor = widget.anchorAt;
    if (anchor == null) return;
    showCustomOffsetSheet(
      context,
      anchor: anchor,
      offsets: widget.offsets,
      // Seeds the sheet with whatever direction the grid is showing, so
      // opening it doesn't silently flip what a typed "45" would mean.
      isAfter: _isAfter,
      color: widget.color,
      isAr: widget.isAr,
      // A closure over `widget`, not the bool: the sheet outlives this
      // build, and `widget` is always the current one, so the answer stays
      // live for as long as the sheet is open. Our own parents already
      // re-supply canStack via ref.watch, so this is the only frozen link.
      canStack: () => widget.canStack,
      onToggle: widget.onToggleOffset,
      // The sheet owns the direction while it's open, and the grid adopts
      // whatever it ends on, so the offsets you just created are the ones in
      // view when you come back.
      onDirectionChanged: (after) => setState(() => _isAfter = after),
      onLocked: widget.onLocked,
      maxOffsets: NotificationService.kMaxTaskReminderSlots,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final gp = context.gp;
    final anchor = widget.anchorAt;
    if (anchor == null) {
      return ReminderRow(
        value: null,
        color: widget.color,
        isAr: widget.isAr,
        onTap: widget.onPickAnchor,
        onClear: () {},
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ReminderRow(
          value: anchor,
          color: widget.color,
          isAr: widget.isAr,
          onTap: widget.onPickAnchor,
          onClear: widget.onClear,
        ),
        const SizedBox(height: 14),
        // Named "extra reminders", not just "remind me": the row above is
        // already a reminder, and without saying so these chips read as if
        // they replace it rather than add to it. The hint spells out that
        // more than one can be picked — a multi-select grid is otherwise
        // indistinguishable from the single-choice ones used everywhere
        // else in this app.
        Text(
          s.matrixExtraRemindersSection,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: context.gp.textTert,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          s.matrixExtraRemindersHint,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: context.gp.textTert.withOpacity(0.75),
          ),
        ),
        const SizedBox(height: 8),
        ChoiceChipGrid(
          columns: 2,
          items: [
            PlainChoiceChip(
              selected: !_isAfter,
              label: s.offsetBeforeLabel,
              selectedColor: widget.color,
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _isAfter = false);
              },
            ),
            PlainChoiceChip(
              selected: _isAfter,
              label: s.offsetAfterLabel,
              selectedColor: widget.color,
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _isAfter = true);
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Multi-select, unlike every other ChoiceChipGrid in the app: each
        // chip is an independent on/off, because the whole point is picking
        // several at once. Selection is read back off `offsets` rather than
        // held locally, so the chips can't drift out of step with the
        // reminders actually stored on the task.
        //
        // Five presets plus the custom field: six cells on three columns,
        // two complete rows in the default state. Any offset the presets
        // don't cover is appended as its own chip.
        //
        // Unreachable offsets (an hour's lead on something 20 minutes away)
        // are dimmed rather than hidden, so the grid keeps its shape
        // instead of reflowing under the user's finger as time passes.
        ChoiceChipGrid(
          columns: 3,
          items: [
            for (final m in kReminderOffsetPresets)
              _OffsetChip(
                selected: widget.offsets.contains(_signed(m)),
                reachable: _isReachable(_signed(m)),
                label: reminderOffsetLabel(m, widget.isAr),
                semanticsLabel: formatOffsetVerbose(_signed(m), widget.isAr, s),
                color: widget.color,
                onTap: () => _toggle(m),
              ),
            for (final o in _unlistedOffsets)
              _OffsetChip(
                selected: true,
                reachable: true,
                label: _unlistedLabel(s, o),
                semanticsLabel: formatOffsetVerbose(o, widget.isAr, s),
                color: widget.color,
                onTap: () {
                  HapticFeedback.selectionClick();
                  widget.onToggleOffset(o);
                },
              ),
            // The custom cell opens a sheet rather than being an inline
            // field: entering a value needs a number *and* a unit *and* a
            // way to review what's already there, which is three controls
            // more than this row can hold on a phone.
            PlainChoiceChip(
              selected: false,
              label: s.leadCustomOption,
              selectedColor: widget.color,
              onTap: _openCustomSheet,
            ),
          ],
        ),
        if (_notice != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 13, color: gp.textTert),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _notice!,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: gp.textTert,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        _ReminderPreview(
          anchor: anchor,
          offsets: widget.offsets,
          color: widget.color,
          isAr: widget.isAr,
          // Opens the same sheet the "مخصص" cell does. Once a task carries
          // four or five reminders this line wraps into a dense run of
          // times, and it's precisely then that someone wants to look at
          // what they've set and drop one — the sheet lists them as
          // labelled rows with remove buttons.
          onTap: _openCustomSheet,
        ),
      ],
    );
  }
}

/// A preset offset. Wraps [PlainChoiceChip] purely to add the dimmed state
/// for an offset whose moment has already passed — selection styling,
/// geometry and motion all still come from the shared chip, so this can't
/// drift from Add Habit's.
///
/// Dimmed but still tappable, deliberately. It used to be wrapped in an
/// IgnorePointer, so a user setting a reminder ten minutes out saw the
/// longer leads greyed and could not find out why — the tap simply did
/// nothing. Letting it through means [_ReminderPickerState._toggle] gets to
/// say "that time has already passed" instead of the chip silently
/// swallowing the press. Marked disabled for assistive tech either way,
/// since 0.35 opacity conveys nothing to a screen reader.
///
/// An already-selected chip never dims: it represents a reminder the task
/// genuinely has, and greying it out would imply it isn't real while also
/// making it look unremovable.
class _OffsetChip extends StatelessWidget {
  final bool selected;
  final bool reachable;
  final String label;
  final String semanticsLabel;
  final Color color;
  final VoidCallback onTap;

  const _OffsetChip({
    required this.selected,
    required this.reachable,
    required this.label,
    required this.semanticsLabel,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final chip = PlainChoiceChip(
      selected: selected,
      label: label,
      semanticsLabel: semanticsLabel,
      selectedColor: color,
      onTap: onTap,
    );
    if (selected || reachable) return chip;
    return Semantics(
      enabled: false,
      child: Opacity(opacity: 0.35, child: chip),
    );
  }
}

/// The arithmetic, done. Lists every moment the task will actually fire at,
/// in order, so the user never has to work out what "30 before" lands on —
/// which is the whole reason the offsets are worth offering.
///
/// Hidden when there's only the anchor: the row directly above already
/// shows that time, and repeating it would read as a second reminder.
class _ReminderPreview extends StatelessWidget {
  final DateTime anchor;
  final Set<int> offsets;
  final Color color;
  final bool isAr;
  final VoidCallback onTap;

  const _ReminderPreview({
    required this.anchor,
    required this.offsets,
    required this.color,
    required this.isAr,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final all = remindersFor(anchor: anchor, offsets: offsets);
    if (all.length <= 1) return const SizedBox.shrink();
    // formatReminderMoment, not a bare time: once day-scale offsets exist a
    // stack can span dates, and "10:31 AM · 10:31 AM" for two reminders two
    // days apart is worse than no preview at all. This carries Today /
    // Tomorrow / a date, so every entry is distinguishable.
    String label(DateTime d) => formatReminderMoment(d, isAr);
    return Semantics(
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.notifications_active_rounded, size: 14, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  all.map(label).join('   ·   '),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: context.gp.textSec,
                    height: 1.35,
                  ),
                ),
              ),
              // A quiet affordance — without it the summary looks like a
              // caption, and nobody discovers that it opens anything.
              Padding(
                padding: const EdgeInsets.only(top: 1),
                // chevron_right, same as ReminderRow's — Flutter mirrors it
                // under RTL, so hardcoding "left" here would point the wrong
                // way in the language this screen is mostly used in.
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: context.gp.textTert,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

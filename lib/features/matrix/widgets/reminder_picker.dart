import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/extensions/datetime_ext.dart';
import '../../../core/utils/western_digits.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/theme/game_theme.dart';
import '../../../shared/widgets/choice_chip_grid.dart';
import '../models/matrix_task.dart';
import 'custom_offset_sheet.dart';

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
/// Takes the latest reminder as the anchor, which is right for every stack
/// built out of "before" offsets — the overwhelmingly common shape, and the
/// one the direction toggle defaults to. A stack that used "after" offsets
/// comes back reframed (its last alarm becomes the anchor, the rest read as
/// "before"), but the set of moments is preserved exactly: a round trip
/// never loses or moves a reminder, it only relabels one. The alternative —
/// persisting the anchor as its own field — buys tidier labels for the rare
/// case at the cost of another schema migration, which isn't worth it.
({DateTime? anchor, Set<int> offsets}) splitReminders(
  List<DateTime> reminders,
) {
  if (reminders.isEmpty) return (anchor: null, offsets: <int>{});
  final anchor = reminders.last;
  return (
    anchor: anchor,
    offsets: {
      for (final r in reminders.take(reminders.length - 1))
        r.difference(anchor).inMinutes,
    },
  );
}

/// Arabic-Indic digits (٠-٩) mapped to plain ASCII, so [int.tryParse] can
/// read a number typed on an Arabic keypad. Mirrors room_model.dart's
/// `_normalizeDigits` and HabitCue's equivalent — a user who types ٤٥ into
/// the minutes field must get 45, not a silent no-op.
String normalizeArabicDigits(String input) => toWesternDigits(input);

/// Western digits → Arabic-Indic codepoints. See [reminderOffsetLabel] for
/// why a chip has to do this by hand.
String arabicDigits(int n) => n
    .toString()
    .split('')
    .map((d) => String.fromCharCode(d.codeUnitAt(0) + 0x0660 - 0x30))
    .join();

/// Chip label for an offset: the number for minutes, a word for the hours,
/// since "120" reads worse than "ساعتان" at a glance.
///
/// Under `ar` the number is converted to Arabic-Indic codepoints, and the
/// reason is font shaping rather than number formatting — which is worth
/// spelling out, because two previous attempts here got it wrong in
/// opposite directions.
///
/// intl produces ASCII either way: `DateFormat('h:mm a', 'ar')` returns the
/// string "9:20 م", and `NumberFormat.decimalPattern('ar')` returns "15".
/// But [ReminderRow] renders its time *inside* an Arabic run ("اليوم · 9:20
/// ص"), where the font applies Arabic contextual digit substitution and the
/// user sees ٩:٢٠. A chip's label is a bare "15" with no Arabic context, so
/// the same font leaves it Western. Two identical ASCII strings, two
/// different glyph sets on screen, side by side.
///
/// So matching the row means matching what's *rendered*, not what intl
/// returns — hence the explicit conversion. Formatting the number through
/// NumberFormat looks more principled and does nothing at all here; don't
/// swap it back.
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
  final date = await showDatePicker(
    context: context,
    initialDate: initial != null && initial.isAfter(now) ? initial : now,
    firstDate: now,
    lastDate: now.add(const Duration(days: 365)),
  );
  if (date == null || !context.mounted) return null;

  final time = await showTimePicker(
    context: context,
    initialTime: initial != null
        ? TimeOfDay(hour: initial.hour, minute: initial.minute)
        : TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
      child: child!,
    ),
  );
  if (time == null || !context.mounted) return null;

  final picked =
      DateTime(date.year, date.month, date.day, time.hour, time.minute);
  if (!picked.isAfter(DateTime.now())) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(S.of(context).matrixReminderPast)),
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
                set ? formatReminderMoment(value!, isAr) : s.matrixReminderLabel,
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
  /// Which direction the offset chips currently mean. Defaults to "before":
  /// a reminder about a thing almost always wants to arrive ahead of it,
  /// and it's the direction every stack in the feature's motivating example
  /// (3:00, 3:30, 4:00 for a 5pm meeting) uses.
  bool _isAfter = false;

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
  /// Shares [formatOffsetVerbose] with the sheet that creates these, so a
  /// value reads identically in both places. An earlier version built the
  /// label from [reminderOffsetLabel], which only knows how to name 60 and
  /// 120 minutes; every other multi-hour value came out as a raw minute
  /// count nobody could interpret at a glance.
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

  void _toggle(int minutes) {
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
    if (!_isReachable(signed)) return;
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
      canStack: widget.canStack,
      onToggle: widget.onToggleOffset,
      // The sheet owns the direction while it's open, and the grid adopts
      // whatever it ends on: switch to بعد in the sheet, add a couple, and
      // the tab behind is already بعد when you come back — so the offsets
      // you just created are the ones in view. Reported on every change
      // rather than on close, so a swipe-dismiss lands the same as tapping
      // Done.
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
        // Five presets plus the custom field: six cells on three columns,
        // two complete rows in the default state. Any offset the presets
        // don't cover — a hand-typed value, or one left over from the other
        // direction after the toggle was flipped — is appended as its own
        // chip, so every reminder the task carries stays visible and
        // removable instead of existing only in the preview line.
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
                color: widget.color,
                onTap: () => _toggle(m),
              ),
            for (final o in _unlistedOffsets)
              _OffsetChip(
                selected: true,
                reachable: true,
                label: _unlistedLabel(s, o),
                color: widget.color,
                onTap: () {
                  HapticFeedback.selectionClick();
                  widget.onToggleOffset(o);
                },
              ),
            // The custom cell opens a sheet rather than being an inline
            // field: entering a value needs a number *and* a unit *and* a
            // way to review what's already there, which is three controls
            // more than this row can hold on a phone. Keeping it a plain
            // chip also keeps the grid six uniform cells.
            PlainChoiceChip(
              selected: false,
              label: s.leadCustomOption,
              selectedColor: widget.color,
              onTap: _openCustomSheet,
            ),
          ],
        ),
        _ReminderPreview(
          anchor: anchor,
          offsets: widget.offsets,
          color: widget.color,
          isAr: widget.isAr,
          // Opens the same sheet the "مخصص" cell does. Once a task carries
          // four or five reminders this line wraps into a dense run of
          // times that's readable only with effort — and it's precisely
          // then that someone wants to look at what they've set and drop
          // one. The sheet already lists them as labelled rows with remove
          // buttons, so the summary is the natural way in rather than a
          // dead end you have to know to route around.
          onTap: _openCustomSheet,
        ),
      ],
    );
  }
}

/// A preset offset. Wraps [PlainChoiceChip] purely to add the dimmed,
/// untappable state for an offset whose moment has already passed —
/// selection styling, geometry and motion all still come from the shared
/// chip, so this can't drift from Add Habit's.
///
/// An already-selected chip never dims: it represents a reminder the task
/// genuinely has, and greying it out would imply it isn't real while also
/// making it look unremovable.
class _OffsetChip extends StatelessWidget {
  final bool selected;
  final bool reachable;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _OffsetChip({
    required this.selected,
    required this.reachable,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final chip = PlainChoiceChip(
      selected: selected,
      label: label,
      selectedColor: color,
      onTap: onTap,
    );
    if (selected || reachable) return chip;
    return Opacity(opacity: 0.35, child: IgnorePointer(child: chip));
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
    final label = (DateTime d) => formatReminderMoment(d, isAr);
    return InkWell(
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
              child: Icon(Icons.chevron_right_rounded,
                  size: 16, color: context.gp.textTert),
            ),
          ],
        ),
      ),
    );
  }
}

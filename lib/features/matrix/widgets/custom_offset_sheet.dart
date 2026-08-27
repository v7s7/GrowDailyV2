import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/l10n/reminder_copy.dart';
import '../../../core/theme/game_theme.dart';
import '../../../shared/widgets/choice_chip_grid.dart';
import 'reminder_picker.dart' show normalizeArabicDigits, formatReminderMoment;

// ReminderUnit and splitOffsetUnit moved to core/l10n/reminder_copy.dart,
// where the notification copy can reach them without importing a widget
// file. Re-exported so this file's existing importers (and the tests that
// reach them through it) don't have to care that they moved.
export '../../../core/l10n/reminder_copy.dart'
    show ReminderUnit, splitOffsetUnit;

/// Black or white on [background], whichever the eye can actually read.
///
/// The sheet's buttons are filled with the *quadrant's* colour, which spans
/// a wide range across the four quadrants and every theme preset — a deep
/// blue "Schedule" and a warm amber "Delegate" cannot share one foreground.
/// 0.1791 is the luminance where black and white give exactly equal WCAG
/// contrast; above it black wins, below it white does. Same crossover and
/// same reasoning as GameColors.onEmerald / onGold.
Color _onFill(Color background) =>
    background.computeLuminance() > 0.1791 ? Colors.black : Colors.white;

/// "15 minutes before" / "قبل ١٥ دقيقة" — the counted, human form of a
/// signed offset. [formatOffsetCompact] is the same fact abbreviated to fit
/// a chip; this is the form that has room to spell itself out.
///
/// Word order follows each language rather than one shared template.
/// English trails the preposition ("15 minutes before"); Arabic *leads* with
/// it ("قبل ١٥ دقيقة"). Building both from one "$n $noun $direction" mould
/// produced "١٥ دقيقة قبل", which is not word order any Arabic speaker
/// would use — the giveaway that a string was assembled by an English
/// speaker and translated word-by-word.
///
/// Arabic also counts properly: singular for one, dual for two, plural for
/// 3–10, and back to singular from 11 up. The dual and the counted noun
/// both follow a preposition here, so they take the genitive — "قبل
/// دقيقتين", not "قبل دقيقتان".
///
/// [withDirection] drops the preposition for callers whose surrounding UI
/// already establishes it — this sheet's own added-chip list sits under a
/// قبل/بعد toggle, so repeating the direction on each entry would just echo
/// the control above them.
String formatOffsetVerbose(
  int signedMinutes,
  bool isAr,
  S s, {
  bool withDirection = true,
}) {
  // The counting itself lives in core/l10n/reminder_copy.dart, because the
  // notification that fires for an offset has to count it the same way the
  // chip that set it did.
  final counted = countedOffsetPhrase(signedMinutes.abs(), isAr);

  final direction =
      signedMinutes.isNegative ? s.offsetBeforeLabel : s.offsetAfterLabel;

  if (!isAr) {
    // Lowercased: the shared string is capitalised because it labels a chip
    // on its own, but here it's the tail of a phrase — "1 day Before" reads
    // like a bug.
    return withDirection ? '$counted ${direction.toLowerCase()}' : counted;
  }
  return withDirection ? '$direction $counted' : counted;
}

/// The same fact as [formatOffsetVerbose], squeezed to fit a chip: "15m
/// before" / "قبل ١٥ د".
///
/// Every offset chip states its own direction, which is what let the قبل/بعد
/// toggle be deleted — a toggle is modal state the user has to remember
/// being in, and worse, flipping it silently changed what the *already
/// selected* chips were reporting. Self-labelling chips have no mode, so
/// there is nothing to remember and nothing to get wrong.
///
/// Compactness is the whole constraint: these sit in a 3-column grid whose
/// cells are ~98pt on a 375pt phone, so the unit is abbreviated ("m"/"د")
/// rather than counted. Arabic keeps its natural noun for one and two —
/// "قبل ساعة" is both shorter *and* better than "قبل ١ س" — and only falls
/// back to digits-plus-abbreviation from three up, where the counted plural
/// ("٣٠ دقائق") would no longer fit.
///
/// Word order per language, exactly as [formatOffsetVerbose] documents:
/// Arabic leads with the preposition, English trails it.
String formatOffsetCompact(int signedMinutes, bool isAr, S s) {
  final direction =
      signedMinutes.isNegative ? s.offsetBeforeLabel : s.offsetAfterLabel;
  final counted = _magnitudeCompact(signedMinutes.abs(), isAr);
  return isAr ? '$direction $counted' : '$counted ${direction.toLowerCase()}';
}

/// The size of an offset with no direction on it: "١٥", "٦٠", "٩٠ د", "يوم".
///
/// For chips whose group header already states both the direction *and* the
/// unit, so repeating either on the chip is exactly the redundancy the
/// grouped layout exists to remove — and repeating it is what forced 13pt
/// type into a 36pt cell.
///
/// Anything up to an hour renders as a bare number, because the header says
/// "دقائق" and a 60 sitting beside a 30 means what the header says it means.
/// Past an hour the header's unit no longer covers the value, so it carries
/// its own: a hand-typed −1440 reads "يوم", never "١٤٤٠".
String formatOffsetMagnitude(int signedMinutes, bool isAr, S s) {
  final magnitude = signedMinutes.abs();
  if (magnitude <= ReminderUnit.hours.inMinutes) {
    return isAr ? arabicDigits(magnitude) : '$magnitude';
  }
  return _magnitudeCompact(magnitude, isAr);
}

/// Shared by [formatOffsetCompact] and [formatOffsetMagnitude] so a chip and
/// the list row under it can never name the same offset two ways.
String _magnitudeCompact(int magnitude, bool isAr) {
  final (value, unit) = splitOffsetUnit(magnitude);
  if (!isAr) {
    const abbr = {
      ReminderUnit.minutes: 'm',
      ReminderUnit.hours: 'h',
      ReminderUnit.days: 'd',
    };
    return '$value${abbr[unit]!}';
  }
  const arabicForms = {
    // singular, genitive dual, abbreviation
    ReminderUnit.minutes: ('دقيقة', 'دقيقتين', 'د'),
    ReminderUnit.hours: ('ساعة', 'ساعتين', 'س'),
    ReminderUnit.days: ('يوم', 'يومين', 'ي'),
  };
  final (one, two, short) = arabicForms[unit]!;
  return switch (value) {
    1 => one,
    2 => two,
    _ => '${arabicDigits(value)} $short',
  };
}

/// Enter a reminder offset in whatever unit suits it, add as many as you
/// like, and remove any of them — without leaving the task sheet.
///
/// A sheet rather than more controls inline: entering a value needs a
/// number *and* a unit *and* a direction, which is three controls competing
/// for one row on a phone. Bottom sheets exist for exactly this —
/// contextual detail without losing the screen behind it — and it keeps the
/// grid behind at nine uniform cells.
///
/// [offsets] is the task's live set; every add/remove is applied through
/// [onToggle] immediately rather than batched behind a Save, so dismissing
/// the sheet can never lose work and there's no "are you sure" to answer.
Future<void> showCustomOffsetSheet(
  BuildContext context, {
  required DateTime anchor,
  required Set<int> offsets,
  required bool isAfter,
  required Color color,
  required bool isAr,
  /// A CALLBACK, not a bool, and that is the point.
  ///
  /// It was a bool captured once in the modal route's builder closure, which
  /// froze the paywall: the Add button's own lock is a purchase funnel, and a
  /// customer who bought Premium from it came back to this still-mounted
  /// sheet where Add kept showing the paywall for a limit they no longer had.
  /// Asking at tap time costs nothing and keeps this sheet Riverpod-free, per
  /// ReminderPicker's dumb-display contract.
  required bool Function() canStack,
  required void Function(int signedMinutes) onToggle,

  /// Fired on every direction change, not just on close, so a swipe-dismiss
  /// leaves the grid on the same tab a Done tap would have.
  required void Function(bool isAfter) onDirectionChanged,
  required VoidCallback onLocked,
  required int maxOffsets,
}) {
  HapticFeedback.selectionClick();
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    // Matches the sheets this opens on top of. Without it a tall added-chip
    // list can push this sheet's own title under the notch.
    useSafeArea: true,
    builder: (_) => _CustomOffsetSheet(
      anchor: anchor,
      initialOffsets: offsets,
      initialIsAfter: isAfter,
      color: color,
      isAr: isAr,
      canStack: canStack,
      onToggle: onToggle,
      onDirectionChanged: onDirectionChanged,
      onLocked: onLocked,
      maxOffsets: maxOffsets,
    ),
  );
}

class _CustomOffsetSheet extends StatefulWidget {
  final DateTime anchor;
  final Set<int> initialOffsets;
  final bool initialIsAfter;
  final Color color;
  final bool isAr;
  final bool Function() canStack;
  final void Function(int signedMinutes) onToggle;
  final void Function(bool isAfter) onDirectionChanged;
  final VoidCallback onLocked;
  final int maxOffsets;

  const _CustomOffsetSheet({
    required this.anchor,
    required this.initialOffsets,
    required this.initialIsAfter,
    required this.color,
    required this.isAr,
    required this.canStack,
    required this.onToggle,
    required this.onDirectionChanged,
    required this.onLocked,
    required this.maxOffsets,
  });

  @override
  State<_CustomOffsetSheet> createState() => _CustomOffsetSheetState();
}

class _CustomOffsetSheetState extends State<_CustomOffsetSheet> {
  final _ctrl = TextEditingController();

  late bool _isAfter = widget.initialIsAfter;
  late Set<int> _offsets = Set.of(widget.initialOffsets);
  ReminderUnit _unit = ReminderUnit.minutes;

  @override
  void initState() {
    super.initState();
    // Drives the live preview and the Add button's enabled state.
    _ctrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  int? get _typedValue {
    final parsed = int.tryParse(normalizeArabicDigits(_ctrl.text).trim());
    return (parsed == null || parsed <= 0) ? null : parsed;
  }

  /// The signed minutes the current entry would produce, or null if nothing
  /// usable is typed.
  int? get _pendingOffset {
    final value = _typedValue;
    if (value == null) return null;
    final magnitude = value * _unit.inMinutes;
    return _isAfter ? magnitude : -magnitude;
  }

  DateTime? get _pendingAt {
    final offset = _pendingOffset;
    return offset == null ? null : widget.anchor.add(Duration(minutes: offset));
  }

  /// Why the current entry can't be added, or null if it can. Returning the
  /// reason rather than a bare bool lets the sheet say *which* rule is in
  /// the way instead of just greying the button out.
  String? _blockReason(S s) {
    final offset = _pendingOffset;
    if (offset == null) return null;
    if (_offsets.contains(offset)) return s.customReminderAlreadyAdded;
    if (!_pendingAt!.isAfter(DateTime.now())) return s.matrixReminderPast;
    if (_offsets.length + 1 >= widget.maxOffsets) {
      return s.matrixReminderMaxReached;
    }
    return null;
  }

  void _add(S s) {
    final offset = _pendingOffset;
    if (offset == null) return;
    if (!widget.canStack()) {
      widget.onLocked();
      return;
    }
    // Unreachable in practice — build disables the button whenever
    // _blockReason is non-null — but kept so the rule lives in one place
    // and a future caller can't bypass it.
    if (_blockReason(s) != null) return;
    HapticFeedback.selectionClick();
    widget.onToggle(offset);
    setState(() {
      _offsets = {..._offsets, offset};
      _ctrl.clear();
    });
    FocusScope.of(context).unfocus();
  }

  void _remove(int offset) {
    HapticFeedback.lightImpact();
    // Removal is never gated — see ReminderPicker._toggle for why an
    // entitlement lapse must not strand a stack the user can't trim.
    widget.onToggle(offset);
    setState(() => _offsets = {..._offsets}..remove(offset));
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final pendingAt = _pendingAt;
    // Computed here, not on tap: a modal sheet swallows SnackBars (the
    // ScaffoldMessenger lives behind it), so a rejected Add showed the user
    // nothing at all — a dead button and no explanation. Saying why up
    // front, and disabling Add to match, means the rule is visible before
    // it's hit rather than silently enforced after.
    final blocked = _blockReason(s);
    final sorted = _offsets.toList()..sort();

    return Padding(
      // Lifts the sheet clear of the keyboard, which is up the whole time
      // the number field has focus — without this the Add button and the
      // preview sit underneath it.
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
          color: gp.surfaceHigh,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
              const SizedBox(height: 14),
              // Direction first: it changes what the number means, so it
              // reads top-to-bottom as one sentence — before/after, how
              // many, of what.
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
                      widget.onDirectionChanged(false);
                    },
                  ),
                  PlainChoiceChip(
                    selected: _isAfter,
                    label: s.offsetAfterLabel,
                    selectedColor: widget.color,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _isAfter = true);
                      widget.onDirectionChanged(true);
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
                onSubmitted: (_) => _add(s),
                textAlign: TextAlign.center,
                cursorColor: widget.color,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: widget.color,
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
                    borderSide: BorderSide(color: widget.color, width: 1.2),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ChoiceChipGrid(
                columns: 3,
                items: [
                  for (final u in ReminderUnit.values)
                    PlainChoiceChip(
                      selected: _unit == u,
                      label: switch (u) {
                        ReminderUnit.minutes => s.unitMinutes,
                        ReminderUnit.hours => s.unitHours,
                        ReminderUnit.days => s.unitDays,
                      },
                      selectedColor: widget.color,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _unit = u);
                      },
                    ),
                ],
              ),
              // The answer, live. Typing "2" under Hours shows the actual
              // clock time it lands on, so nobody has to do the arithmetic
              // to find out what they're about to add.
              if (pendingAt != null) ...[
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      blocked == null
                          ? Icons.notifications_active_rounded
                          : Icons.error_outline_rounded,
                      size: 14,
                      color: blocked == null ? widget.color : GameColors.error,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        blocked ?? formatReminderMoment(pendingAt, widget.isAr),
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
                onPressed: (_pendingOffset == null || blocked != null)
                    ? null
                    : () => _add(s),
                style: FilledButton.styleFrom(
                  backgroundColor: widget.color,
                  foregroundColor: _onFill(widget.color),
                  minimumSize: const Size(double.infinity, 48),
                ),
                child: Text(s.customReminderAdd),
              ),
              const SizedBox(height: 18),
              Text(
                s.customReminderAdded,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: gp.textTert,
                ),
              ),
              const SizedBox(height: 8),
              if (sorted.isEmpty)
                Text(
                  s.customReminderEmpty,
                  style: TextStyle(fontSize: 12.5, color: gp.textTert),
                )
              else
                // Every offset the task carries, not just the ones added
                // here — this is the one place all of them are listed, so
                // it's also the place to remove any of them.
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final o in sorted)
                      _AddedChip(
                        label: formatOffsetVerbose(o, widget.isAr, s),
                        // Day/date, not just a clock time: with day-scale
                        // offsets two rows can share a time and differ only
                        // by date, and "10:31 AM" twice explains nothing.
                        time: formatReminderMoment(
                          widget.anchor.add(Duration(minutes: o)),
                          widget.isAr,
                        ),
                        color: widget.color,
                        onRemove: () => _remove(o),
                      ),
                  ],
                ),
              const SizedBox(height: 16),
              // Filled, not a bare text button: it's the way out of a modal
              // that has no other dismiss control beyond a swipe, so it
              // should read as a real button rather than a label.
              FilledButton(
                onPressed: () => Navigator.pop(context),
                style: FilledButton.styleFrom(
                  backgroundColor: widget.color,
                  foregroundColor: _onFill(widget.color),
                  minimumSize: const Size(double.infinity, 48),
                ),
                child: Text(s.matrixDone),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// An added offset: what it means in words, the clock time it lands on, and
/// an × to drop it. The trailing remove icon is the input-chip convention —
/// anything a user added, they must be able to take back from the same
/// place.
class _AddedChip extends StatelessWidget {
  final String label;
  final String time;
  final Color color;
  final VoidCallback onRemove;

  const _AddedChip({
    required this.label,
    required this.time,
    required this.color,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Container(
      padding: const EdgeInsetsDirectional.only(
        start: 12,
        end: 6,
        top: 7,
        bottom: 7,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
        border: Border.all(color: color.withOpacity(0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            time,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: gp.textSec,
            ),
          ),
          const SizedBox(width: 2),
          GestureDetector(
            onTap: onRemove,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              // Padding, not a bigger icon: keeps the tap target at the 44pt
              // guidance without making the × visually shout.
              padding: const EdgeInsets.all(6),
              child: Icon(Icons.close_rounded, size: 14, color: gp.textTert),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../../shared/widgets/habit_limit_gate.dart';
import '../../habits/catalog/islamic_habit_catalog.dart';
import '../../habits/notifiers/custom_habits_notifier.dart';
import '../models/room_model.dart';
import '../notifiers/habit_name_match.dart';
import '../notifiers/rooms_notifier.dart';

/// Bottom sheet: resolves every shared-plan slot [mine] hasn't linked yet
/// (see RoomsController.resolvePlanHabit) — the catch-up version of
/// JoinRoomSheet's own plan-review step, shown only for whichever slot(s)
/// were added to [room] *after* this participant already joined/last
/// resolved, never the whole plan again. Same per-row shape (an existing
/// habit, or "Add as new") as the join flow, so resolving a late addition
/// never looks or works differently from resolving the original plan — see
/// _MyPlanCard's banner for where this gets opened from.
Future<void> showResolveNewHabitsSheet(
  BuildContext context, {
  required RoomModel room,
  required RoomParticipant mine,
}) {
  HapticFeedback.selectionClick();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    useSafeArea: true,
    builder: (_) => _ResolveNewHabitsSheet(room: room, mine: mine),
  );
}

class _ResolveNewHabitsSheet extends ConsumerStatefulWidget {
  final RoomModel room;
  final RoomParticipant mine;
  const _ResolveNewHabitsSheet({required this.room, required this.mine});

  @override
  ConsumerState<_ResolveNewHabitsSheet> createState() =>
      _ResolveNewHabitsSheetState();
}

class _ResolveNewHabitsSheetState
    extends ConsumerState<_ResolveNewHabitsSheet> {
  // The first not-yet-linked slot - see RoomParticipant.linkedHabitIds' own
  // doc comment on the 1:1 positional correspondence with
  // RoomModel.sharedHabits this relies on.
  int get _startIndex => widget.mine.linkedHabitIds.length;

  List<RoomHabitTemplate> get _pending {
    final templates = widget.room.sharedHabits;
    if (_startIndex >= templates.length) return const [];
    return templates.sublist(_startIndex);
  }

  late List<String?> _resolutions;

  /// Per pending row, the habits that fit it equally well when there are
  /// two or more (see suggestPlanMatches): that row opens on nothing and
  /// names them.
  late List<List<String>> _torn;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final myHabits = ref.read(habitListProvider);
    // The whole pending plan is matched at once (suggestPlanMatches): the
    // surest pair is settled first, a habit is never suggested for two rows,
    // and a row torn between two habits opens on neither. Habits another
    // slot holds or held are off the table from the start: resolvePlanHabit
    // refuses them (see _optionsFor). A slot the leader has removed is never
    // asked about: it is resolved as a skip, which only holds its place
    // (every array here is positional, so the live slots after it need it
    // filled first), and it is not drawn as a row. See
    // RoomParticipant.pendingPlanSlotsIn.
    final pending = _pending;
    final matches = suggestPlanMatches(
      [for (final t in pending) t.isRemoved ? null : t.name],
      myHabits,
      taken: widget.mine.habitsHeldBySlotsOtherThan(null),
    );
    _resolutions = [
      for (var i = 0; i < pending.length; i++)
        pending[i].isRemoved ? kDeclinedSlot : matches[i].habitId,
    ];
    _torn = [for (final m in matches) m.tornBetween];
  }

  /// The habits row [row] may be linked to: never one another slot holds or
  /// held (RoomParticipant.habitsHeldBySlotsOtherThan, the guard
  /// resolvePlanHabit enforces), and never one another row here has picked,
  /// which it would refuse as a repeat. A habit the controller would refuse
  /// is never offered, so picking cannot make the save fail.
  List<IslamicHabitTemplate> _optionsFor(
    int row,
    List<IslamicHabitTemplate> myHabits,
  ) {
    final held = widget.mine.habitsHeldBySlotsOtherThan(null);
    final pickedElsewhere = {
      for (var j = 0; j < _resolutions.length; j++)
        if (j != row && _resolutions[j] != null) _resolutions[j]!,
    };
    return [
      for (final h in myHabits)
        if (!held.contains(h.id) && !pickedElsewhere.contains(h.id)) h,
    ];
  }

  Future<void> _save() async {
    if (_isSaving || _pending.isEmpty) return;
    // Same paywall JoinRoomSheet._join already enforces for its own
    // "Add as new" resolutions - a guest or free account resolving one of
    // these slots to a brand-new habit (rather than an existing one) still
    // has to fit the account's cap. Checked before any writes so a blocked
    // save never partially resolves some rows and not others.
    // Only rows resolving to a brand-new habit count against the cap - a row
    // linked to an existing habit creates nothing, and a SKIPPED row (see
    // kDeclinedSlot) creates nothing either, so neither is gated.
    final newHabitCount =
        _resolutions.where((r) => r == null).length;
    if (newHabitCount > 0 &&
        !canAddHabits(ref, additionalCount: newHabitCount)) {
      showHabitLimitGate(context, ref);
      return;
    }
    setState(() => _isSaving = true);
    HapticFeedback.mediumImpact();
    final s = S.of(context);
    final controller = ref.read(roomsControllerProvider);
    // Sequential and awaited, not parallel - both resolvePlanHabit and
    // declineSharedHabit carry the same defensive "must be exactly the next
    // slot" check, so each call has to see the previous one's write landed.
    //
    // A refusal stops the loop. The rows offer nothing the controller
    // refuses (_optionsFor), so one means the sheet is out of date: the plan
    // or this member's links changed since it opened, and the rows after it
    // were worked out for slots that may no longer be next in line. The
    // sheet used to carry on and close as if it had saved. It now stops,
    // closes and says so, and the banner is still there to open a fresh one.
    var saved = true;
    for (var i = 0; i < _pending.length && saved; i++) {
      saved = _resolutions[i] == kDeclinedSlot
          ? await controller.declineSharedHabit(widget.room, _startIndex + i)
          : await controller.resolvePlanHabit(
              widget.room,
              _startIndex + i,
              existingHabitId: _resolutions[i],
            );
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    if (!saved) {
      messenger.showOne(
        SnackBar(
          content: Text(s.roomRelinkFailed),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final myHabits = ref.watch(habitListProvider);
    final pending = _pending;
    // Rows for the slots still in the plan only (see initState).
    final shownRows = [
      for (var i = 0; i < pending.length; i++)
        if (!pending[i].isRemoved) i,
    ];

    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
      decoration: BoxDecoration(
        color: gp.surfaceHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: gp.border, width: 0.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 4),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: gp.border, borderRadius: BorderRadius.circular(2)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
            child: Text(s.roomResolveHabitsSheetTitle,
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800, color: gp.textPrimary)),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (n, i) in shownRows.indexed) ...[
                    if (n != 0) const SizedBox(height: 10),
                    _NewHabitRow(
                      templateName: pending[i].name,
                      myHabits: _optionsFor(i, myHabits),
                      tornIds: i < _torn.length ? _torn[i] : const [],
                      value: i < _resolutions.length ? _resolutions[i] : null,
                      onChanged: (id) => setState(() => _resolutions[i] = id),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
                20, 10, 20, 20 + MediaQuery.of(context).padding.bottom),
            child: FilledButton(
              // shownRows, not pending: a sheet whose only pending slots are
              // removed ones draws no rows, and its button has nothing to
              // save. Both entry points already refuse to open it then.
              onPressed: shownRows.isEmpty || _isSaving ? null : _save,
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    )
                  : Text(s.roomNewHabitBannerAction),
            ),
          ),
        ],
      ),
    );
  }
}

/// One row per pending template - structurally the same dropdown
/// (existing habit, or "Add as new") as JoinRoomSheet's own _PlanReviewRow,
/// kept as its own copy here rather than shared, matching how every other
/// small widget in this feature is scoped (see _OwnHabitMultiField's own
/// doc comment in join_room_sheet.dart for the same reasoning).
class _NewHabitRow extends StatelessWidget {
  final String templateName;
  final List<IslamicHabitTemplate> myHabits;

  /// The habits this row fits equally (see suggestPlanMatches): listed first
  /// in the dropdown, and named under the row until one is picked.
  final List<String> tornIds;
  final String? value;
  final ValueChanged<String?> onChanged;
  const _NewHabitRow({
    required this.templateName,
    required this.myHabits,
    this.tornIds = const [],
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    // kDeclinedSlot is a real selectable value here (the skip option), not a
    // habit id, so it has to pass this "is this still a habit I own" guard
    // rather than being silently reset to null / "Add as new".
    final resolvedValue = value == kDeclinedSlot ||
            (value != null && myHabits.any((h) => h.id == value))
        ? value
        : null;
    // Torn between two or more habits: they go first, and the row says so
    // until one is picked (see suggestPlanMatches).
    final torn = [
      for (final h in myHabits)
        if (tornIds.contains(h.id)) h,
    ];
    final ordered = [
      ...torn,
      for (final h in myHabits)
        if (!tornIds.contains(h.id)) h,
    ];
    final showTorn = resolvedValue == null && torn.length > 1;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(GameSpacing.buttonRadius),
        border: Border.all(color: GameColors.gold.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.flag_rounded, size: 15, color: context.gp.goldInk),
              const SizedBox(width: 8),
              Expanded(
                flex: 4,
                child: Text(templateName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w700, color: gp.textPrimary)),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 5,
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: resolvedValue,
                    isExpanded: true,
                    isDense: true,
                    hint: Text(s.roomPlanAddAsNew,
                        style: TextStyle(fontSize: 12, color: context.gp.goldInk)),
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text(s.roomPlanAddAsNew,
                            style: TextStyle(fontSize: 12, color: context.gp.goldInk)),
                      ),
                      ...ordered.map((h) => DropdownMenuItem<String?>(
                            value: h.id,
                            child: Text(s.roomPlanLinkExisting(h.name),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          )),
                      // "No thanks" - the slot holds its position in the shared
                      // plan but counts for nothing either way (see
                      // kDeclinedSlot / RoomsController.declineSharedHabit).
                      // Last in the list, and visually muted, so it reads as the
                      // opt-out rather than a peer of the real choices.
                      DropdownMenuItem<String?>(
                        value: kDeclinedSlot,
                        child: Text(s.roomSkipSharedHabit,
                            style: TextStyle(fontSize: 12, color: gp.textTert)),
                      ),
                    ],
                    onChanged: onChanged,
                  ),
                ),
              ),
            ],
          ),
          if (showTorn)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 23, bottom: 6),
              child: Text(
                s.roomPlanTornHint(
                    torn.map((h) => h.name).join(s.isAr ? '، ' : ', ')),
                style: TextStyle(
                    fontSize: 11, height: 1.35, color: context.gp.goldInk),
              ),
            ),
        ],
      ),
    );
  }
}

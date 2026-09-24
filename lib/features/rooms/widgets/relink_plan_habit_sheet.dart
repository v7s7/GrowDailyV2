import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../habits/catalog/islamic_habit_catalog.dart';
import '../../habits/notifiers/custom_habits_notifier.dart';
import '../models/room_model.dart';
import '../notifiers/habit_name_match.dart' show habitNameMatchScore;
import '../notifiers/rooms_notifier.dart';

/// Bottom sheet: change which of this member's habits fills shared slot
/// [slot] of [room] (Aziz, 2026-09-25: "edit the connection if one make
/// mistake"). Opened by tapping the habit's chip on the room's plan card.
///
/// Lists the habits that may fill it: never the one already there, and
/// never one another slot holds or has held (see
/// RoomParticipant.habitsHeldBySlotsOtherThan, the same guard
/// RoomsController.relinkPlanHabit enforces). The habits whose names are
/// closest to the room's habit come first (habitNameMatchScore), the rest
/// in the person's own order.
///
/// Picking one asks once, saying what changes: from today the new habit
/// counts, and past days stay as they were played (the rule a skip and a
/// removal already follow). Nothing is written until that is confirmed.
Future<void> showRelinkPlanHabitSheet(
  BuildContext context, {
  required RoomModel room,
  required RoomParticipant mine,
  required int slot,
}) {
  HapticFeedback.selectionClick();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    useSafeArea: true,
    builder: (_) => _RelinkPlanHabitSheet(room: room, mine: mine, slot: slot),
  );
}

/// Whether tapping slot [slot]'s chip opens the sheet: a linked, live slot
/// of a shared plan whose room has started and not ended, the only kind
/// RoomsController.relinkPlanHabit accepts. Not in the lobby, nor before
/// the first day: nothing has counted, and the controller refuses there.
bool relinkSheetOpensFor(
  RoomModel room,
  RoomParticipant mine,
  int slot, {
  DateTime? now,
}) {
  final clock = now ?? DateTime.now();
  return room.habitMode == RoomHabitMode.shared &&
      room.hasStartedAt(clock) &&
      !room.isEndedAt(clock) &&
      slot >= 0 &&
      slot < mine.linkedHabitIds.length &&
      slot < room.sharedHabits.length &&
      mine.linkedHabitIds[slot] != kDeclinedSlot &&
      !room.sharedHabits[slot].isRemoved;
}

/// The habits [slot] may be changed to, closest names first. Pure, for the
/// sheet and its test.
@visibleForTesting
List<IslamicHabitTemplate> relinkCandidates({
  required RoomModel room,
  required RoomParticipant mine,
  required int slot,
  required List<IslamicHabitTemplate> myHabits,
}) {
  if (slot < 0 || slot >= mine.linkedHabitIds.length) return const [];
  final current = mine.linkedHabitIds[slot];
  final held = mine.habitsHeldBySlotsOtherThan(slot);
  final open = [
    for (final h in myHabits)
      if (h.id != current && !held.contains(h.id)) h,
  ];
  final slotName =
      slot < room.sharedHabits.length ? room.sharedHabits[slot].name : '';
  final score = {for (final h in open) h.id: habitNameMatchScore(slotName, h.name)};
  // A stable sort: equal scores keep the person's own order.
  final indexed = open.asMap().entries.toList()
    ..sort((a, b) {
      final byScore = score[b.value.id]!.compareTo(score[a.value.id]!);
      return byScore != 0 ? byScore : a.key.compareTo(b.key);
    });
  return [for (final e in indexed) e.value];
}

class _RelinkPlanHabitSheet extends ConsumerStatefulWidget {
  final RoomModel room;
  final RoomParticipant mine;
  final int slot;
  const _RelinkPlanHabitSheet({
    required this.room,
    required this.mine,
    required this.slot,
  });

  @override
  ConsumerState<_RelinkPlanHabitSheet> createState() =>
      _RelinkPlanHabitSheetState();
}

class _RelinkPlanHabitSheetState extends ConsumerState<_RelinkPlanHabitSheet> {
  bool _saving = false;

  String get _slotName => widget.slot < widget.room.sharedHabits.length
      ? widget.room.sharedHabits[widget.slot].name
      : '';

  String get _currentName => widget.slot < widget.mine.linkedHabitNames.length
      ? widget.mine.linkedHabitNames[widget.slot]
      : '';

  Future<void> _pick(IslamicHabitTemplate habit) async {
    if (_saving) return;
    HapticFeedback.selectionClick();
    final s = S.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.roomRelinkTitle),
        content: Text(s.roomRelinkConfirm(habit.name, _currentName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(s.roomCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(s.roomRelinkAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    final ok = await ref
        .read(roomsControllerProvider)
        .relinkPlanHabit(widget.room, widget.slot, habit.id);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showOne(
      SnackBar(
        content: Text(ok ? s.roomRelinkDone(habit.name) : s.roomRelinkFailed),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final habits = relinkCandidates(
      room: widget.room,
      mine: widget.mine,
      slot: widget.slot,
      myHabits: ref.watch(habitListProvider),
    );

    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
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
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
            child: Text(s.roomRelinkTitle,
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800, color: gp.textPrimary)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(s.roomRelinkHint(_slotName, _currentName),
                style: TextStyle(fontSize: 12, color: gp.textSec, height: 1.35)),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                  20, 4, 20, 24 + MediaQuery.of(context).padding.bottom),
              child: habits.isEmpty
                  ? Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: gp.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: gp.border, width: 0.5),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline_rounded,
                              size: 16, color: gp.textTert),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(s.roomRelinkNone,
                                style: TextStyle(fontSize: 12.5, color: gp.textSec)),
                          ),
                        ],
                      ),
                    )
                  : Container(
                      decoration: BoxDecoration(
                        color: gp.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: gp.border, width: 0.5),
                      ),
                      child: Column(
                        children: [
                          for (var i = 0; i < habits.length; i++) ...[
                            if (i != 0) Divider(height: 1, color: gp.border),
                            InkWell(
                              onTap: _saving ? null : () => _pick(habits[i]),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 14),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(habits[i].name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.w600,
                                              color: gp.textPrimary)),
                                    ),
                                    Icon(Icons.chevron_right_rounded,
                                        size: 18, color: gp.textTert),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

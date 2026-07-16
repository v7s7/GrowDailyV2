import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../../shared/widgets/habit_limit_gate.dart';
import '../../habits/catalog/islamic_habit_catalog.dart';
import '../../habits/notifiers/custom_habits_notifier.dart';
import '../models/room_model.dart';
import '../notifiers/rooms_notifier.dart';

/// Opens the Join Room sheet and resolves to the room's code once actually
/// joined, or null if dismissed/cancelled - same "let the caller navigate"
/// contract as [showCreateRoomSheet]. [initialCode] pre-fills the code
/// field and searches immediately - used when a `growdaily://join/CODE`
/// deep link (see main.dart) opens this sheet, so tapping a friend's
/// invite lands here with everything already filled in instead of asking
/// the joiner to type the code they just tapped.
Future<String?> showJoinRoomSheet(
  BuildContext context,
  WidgetRef ref, {
  String? initialCode,
}) {
  HapticFeedback.selectionClick();
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    useSafeArea: true,
    builder: (_) => JoinRoomSheet(initialCode: initialCode),
  );
}

class JoinRoomSheet extends ConsumerStatefulWidget {
  final String? initialCode;
  const JoinRoomSheet({super.key, this.initialCode});

  @override
  ConsumerState<JoinRoomSheet> createState() => _JoinRoomSheetState();
}

class _JoinRoomSheetState extends ConsumerState<JoinRoomSheet> {
  final _codeCtrl = TextEditingController();
  bool _isSearching = false;
  bool _notFound = false;
  RoomModel? _foundRoom;
  List<String> _ownHabitIds = [];

  /// One entry per [RoomModel.sharedHabits], in the same order - null means
  /// "add as a new habit", a habit id means "link this existing one
  /// instead". Pre-filled with [suggestExistingMatch]'s best guess the
  /// moment a 'shared'-mode room is found (see [_search]), but always
  /// editable per row (see [_PlanReviewList]) before actually joining.
  List<String?> _planResolutions = [];
  bool _isJoining = false;

  @override
  void initState() {
    super.initState();
    final code = widget.initialCode?.trim();
    if (code != null && code.isNotEmpty) {
      _codeCtrl.text = code.toUpperCase();
      // Deferred a frame - _search's setState (and its FocusScope.unfocus
      // call, which needs an attached tree) shouldn't run before this
      // sheet has finished its first build. This is what turns a
      // growdaily://join/CODE deep link (see main.dart) into "already
      // searched, just tap Join" instead of a blank field the joiner still
      // has to type into.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _search();
      });
    }
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  /// One best-guess habit id per [templates] entry, in order - like calling
  /// [suggestExistingMatch] separately for each one, except a habit already
  /// suggested for an earlier row is taken off the table for every later
  /// row. Without this, a plan with two similarly-named habits (say, two
  /// prayer-related entries) could suggest the *same* one of the joiner's
  /// habits for both rows, and someone who didn't notice and fix it before
  /// tapping Join would end up with one entry silently uncovered - exactly
  /// the kind of auto-link glitch the "auto only when confident, otherwise
  /// ask" design (see suggestExistingMatch's doc comment) is meant to rule
  /// out.
  List<String?> _resolvePlanSuggestions(
    List<RoomHabitTemplate> templates,
    List<IslamicHabitTemplate> myHabits,
  ) {
    final usedIds = <String>{};
    final result = <String?>[];
    for (final t in templates) {
      final available =
          myHabits.where((h) => !usedIds.contains(h.id)).toList();
      final match = suggestExistingMatch(t.name, available)?.id;
      if (match != null) usedIds.add(match);
      result.add(match);
    }
    return result;
  }

  Future<void> _search() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty || _isSearching) return;
    HapticFeedback.selectionClick();
    FocusScope.of(context).unfocus();
    setState(() {
      _isSearching = true;
      _notFound = false;
      _foundRoom = null;
      _ownHabitIds = [];
      _planResolutions = [];
    });
    final room = await ref.read(roomsControllerProvider).previewRoom(code);
    if (!mounted) return;
    final myHabits = ref.read(habitListProvider);
    setState(() {
      _isSearching = false;
      _foundRoom = room;
      _notFound = room == null;
      _planResolutions = room == null || room.habitMode != RoomHabitMode.shared
          ? []
          : _resolvePlanSuggestions(room.sharedHabits, myHabits);
    });
  }

  bool get _canJoin {
    final room = _foundRoom;
    if (room == null || _isJoining || room.isEnded) return false;
    if (room.habitMode == RoomHabitMode.own) return _ownHabitIds.isNotEmpty;
    return true;
  }

  /// How many *new* habits joining right now would create - every plan
  /// entry resolved to null (see [_planResolutions]) becomes a fresh habit
  /// via CustomHabitsNotifier.add. Used to gate against the account's habit
  /// cap before actually joining, same premium gate every other bulk-add
  /// entry point (Plans tab) already uses.
  int get _newHabitCount => _planResolutions.where((r) => r == null).length;

  Future<void> _join() async {
    final room = _foundRoom;
    if (room == null || !_canJoin) return;
    if (room.habitMode == RoomHabitMode.shared &&
        _newHabitCount > 0 &&
        !canAddHabits(ref, additionalCount: _newHabitCount)) {
      showHabitLimitGate(context, ref);
      return;
    }
    setState(() => _isJoining = true);
    HapticFeedback.mediumImpact();
    final habits = ref.read(habitListProvider);
    // Filters and maps from the same resolved list (rather than mapping
    // ids and names separately) so the two lists handed to joinRoom can
    // never end up different lengths - mirrors CreateRoomSheet._submit's
    // same resolution step.
    final resolvedOwnHabits = [
      for (final id in _ownHabitIds)
        if (habits.where((h) => h.id == id).isNotEmpty)
          habits.firstWhere((h) => h.id == id),
    ];
    final ok = await ref.read(roomsControllerProvider).joinRoom(
          room,
          linkedHabitIds: resolvedOwnHabits.map((h) => h.id).toList(),
          linkedHabitNames: resolvedOwnHabits.map((h) => h.name).toList(),
          planResolutions: _planResolutions,
        );
    if (!mounted) return;
    if (!ok) {
      setState(() => _isJoining = false);
      return;
    }
    Navigator.of(context).pop(room.code);
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    const keyboardAnim = Duration(milliseconds: 220);
    const keyboardCurve = Curves.easeOutCubic;

    return AnimatedPadding(
      duration: keyboardAnim,
      curve: keyboardCurve,
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
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
                    color: gp.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
              child: Text(
                s.roomJoinTitle,
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800, color: gp.textPrimary),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _codeCtrl,
                            autofocus: widget.initialCode == null,
                            textCapitalization: TextCapitalization.characters,
                            onSubmitted: (_) => _search(),
                            decoration: InputDecoration(
                              labelText: s.roomCodeLabel,
                              hintText: s.roomCodeHint,
                              prefixIcon: const Icon(Icons.tag_rounded, size: 20),
                              errorText: _notFound ? s.roomNotFound : null,
                              errorMaxLines: 2,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        FilledButton(
                          onPressed: _isSearching ? null : _search,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 56),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          child: _isSearching
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2.2),
                                )
                              : Text(s.roomFindAction),
                        ),
                      ],
                    ),
                    if (_foundRoom != null) ...[
                      const SizedBox(height: 16),
                      _RoomPreviewCard(room: _foundRoom!),
                      if (_foundRoom!.isEnded) ...[
                        const SizedBox(height: 10),
                        _InlineNotice(text: s.roomAlreadyEndedJoin),
                      ] else if (_foundRoom!.habitMode ==
                          RoomHabitMode.own) ...[
                        const SizedBox(height: 14),
                        _OwnHabitMultiField(
                          selectedIds: _ownHabitIds,
                          onChanged: (ids) => setState(() => _ownHabitIds = ids),
                        ),
                        if (_ownHabitIds.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(s.roomPlanSelectedCount(_ownHabitIds.length),
                              style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: GameColors.gold)),
                        ],
                      ] else if (_foundRoom!.sharedHabits.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        _PlanReviewList(
                          room: _foundRoom!,
                          resolutions: _planResolutions,
                          onChanged: (resolutions) =>
                              setState(() => _planResolutions = resolutions),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
            if (_foundRoom != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                child: FilledButton(
                  onPressed: _canJoin ? _join : null,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _isJoining
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        )
                      : Text(s.roomJoinSubmit),
                ),
              )
            else
              const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class _RoomPreviewCard extends StatelessWidget {
  final RoomModel room;
  const _RoomPreviewCard({required this.room});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: GameColors.gold.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: GameColors.gold.withOpacity(0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.emoji_events_rounded, size: 18, color: GameColors.gold),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  room.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 14.5, fontWeight: FontWeight.w800, color: gp.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            s.roomMemberCount(room.memberCount),
            style: TextStyle(fontSize: 12, color: gp.textSec),
          ),
          const SizedBox(height: 4),
          Text(
            room.habitMode == RoomHabitMode.shared
                ? s.roomPreviewSharedHabit(
                    room.sharedHabits.map((h) => h.name).join(', '))
                : s.roomPreviewOwnMode,
            style: TextStyle(fontSize: 12, color: gp.textSec),
          ),
        ],
      ),
    );
  }
}

/// Small inline warning row - currently only used for "this room already
/// ended" once a search finds a room past its [RoomModel.isEnded] date, so
/// the disabled Join button reads as a clear, explained dead end rather
/// than a mysteriously greyed-out control.
class _InlineNotice extends StatelessWidget {
  final String text;
  const _InlineNotice({required this.text});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: GameColors.error.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: GameColors.error.withOpacity(0.24)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 16, color: GameColors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 12, color: gp.textSec, height: 1.3)),
          ),
        ],
      ),
    );
  }
}

/// One row per [RoomModel.sharedHabits] entry, each independently resolved
/// to either "add as a new habit" or "link this existing one instead" - see
/// [_JoinRoomSheetState._planResolutions]. Pre-filled with a smart guess
/// (suggestExistingMatch), but every row's dropdown always includes both
/// "Add as new" and every one of the joiner's own habits, so a wrong or
/// missing guess is always a single tap to fix before actually joining.
class _PlanReviewList extends ConsumerWidget {
  final RoomModel room;
  final List<String?> resolutions;
  final ValueChanged<List<String?>> onChanged;
  const _PlanReviewList({
    required this.room,
    required this.resolutions,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final myHabits = ref.watch(habitListProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(s.roomPlanReviewLabel,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: gp.textTert)),
        const SizedBox(height: 8),
        for (var i = 0; i < room.sharedHabits.length; i++) ...[
          if (i != 0) const SizedBox(height: 10),
          _PlanReviewRow(
            templateName: room.sharedHabits[i].name,
            myHabits: myHabits,
            value: i < resolutions.length ? resolutions[i] : null,
            onChanged: (id) {
              final next = [...resolutions];
              while (next.length <= i) {
                next.add(null);
              }
              next[i] = id;
              onChanged(next);
            },
          ),
        ],
      ],
    );
  }
}

class _PlanReviewRow extends StatelessWidget {
  final String templateName;
  final List<IslamicHabitTemplate> myHabits;
  final String? value;
  final ValueChanged<String?> onChanged;
  const _PlanReviewRow({
    required this.templateName,
    required this.myHabits,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final resolvedValue = value != null && myHabits.any((h) => h.id == value)
        ? value
        : null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: gp.border, width: 0.5),
      ),
      child: Row(
        children: [
          Icon(Icons.flag_rounded, size: 15, color: gp.textTert),
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
                    style: TextStyle(fontSize: 12, color: GameColors.gold)),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(s.roomPlanAddAsNew,
                        style: TextStyle(fontSize: 12, color: GameColors.gold)),
                  ),
                  ...myHabits.map((h) => DropdownMenuItem<String?>(
                        value: h.id,
                        child: Text(s.roomPlanLinkExisting(h.name),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      )),
                ],
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Multi-select checklist of the joiner's own habits, used only in 'own'
/// mode - one or more become this participant's own [RoomParticipant.
/// linkedHabitIds] for the room directly (see _JoinRoomSheetState._join),
/// no leader plan or cloning involved. Structurally mirrors
/// CreateRoomSheet's own _PlanHabitPicker (same checklist-row pattern,
/// same combined catalog-+-custom habit list) - kept as its own copy here
/// rather than shared, since both are private to their own file, matching
/// how every other small widget in this feature is scoped.
class _OwnHabitMultiField extends ConsumerWidget {
  final List<String> selectedIds;
  final ValueChanged<List<String>> onChanged;
  const _OwnHabitMultiField({required this.selectedIds, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final gp = context.gp;
    final habits = ref.watch(habitListProvider);
    if (habits.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: gp.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: gp.border, width: 0.5),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline_rounded, size: 16, color: gp.textTert),
            const SizedBox(width: 8),
            Expanded(
              child: Text(s.roomNoHabitsYet,
                  style: TextStyle(fontSize: 12.5, color: gp.textSec)),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(s.roomPickHabitsLabel,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: gp.textTert)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: gp.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: gp.border, width: 0.5),
          ),
          child: Column(
            children: [
              for (var i = 0; i < habits.length; i++) ...[
                if (i != 0) Divider(height: 1, color: gp.border),
                _OwnHabitMultiFieldRow(
                  name: habits[i].name,
                  selected: selectedIds.contains(habits[i].id),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    final next = [...selectedIds];
                    if (!next.remove(habits[i].id)) next.add(habits[i].id);
                    onChanged(next);
                  },
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _OwnHabitMultiFieldRow extends StatelessWidget {
  final String name;
  final bool selected;
  final VoidCallback onTap;
  const _OwnHabitMultiFieldRow(
      {required this.name, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? GameColors.gold : Colors.transparent,
                border: Border.all(
                  color: selected ? GameColors.gold : gp.border,
                  width: 1.5,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check_rounded, size: 13, color: Colors.black)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(name,
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: gp.textPrimary)),
            ),
          ],
        ),
      ),
    );
  }
}

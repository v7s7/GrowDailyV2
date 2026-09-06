import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/text_moderation.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/services/share_service.dart';
import '../../../core/theme/game_theme.dart';
import '../../habits/catalog/islamic_habit_catalog.dart';
import '../../habits/notifiers/custom_habits_notifier.dart';
import '../../habits/widgets/add_habit_sheet.dart';
import '../models/room_model.dart';
import '../notifiers/rooms_notifier.dart';
import '../../../shared/widgets/app_snackbar.dart';

/// The quick-pick room lengths, in days - the common cases every leader
/// reaches for at a glance, matching every other quick-pick control in the
/// app (see AddHabitSheet's frequency chips). [null] means no end date.
/// Anything outside this list (a Ramadan-specific 29 days, a full-year 365)
/// still reaches RoomModel via the "Custom" chip below (see
/// _CreateRoomSheetState's _customDurationSelected/_customDurationCtrl and
/// RoomModel.parseCustomRoomDurationDays) - these five options deliberately
/// don't try to enumerate every case, Custom is what covers the rest.
const List<int?> _lengthOptions = [7, 14, 30, 90, null];

/// Opens the Create Room sheet and resolves to the new room's code once
/// it's actually created, or null if the sheet was dismissed/cancelled -
/// the caller (RoomsHubScreen) awaits this and pushes RoomDetailScreen
/// itself once the sheet is out of the way, rather than this widget
/// reaching for navigation past its own lifetime.
Future<String?> showCreateRoomSheet(BuildContext context, WidgetRef ref) {
  HapticFeedback.selectionClick();
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    useSafeArea: true,
    builder: (_) => const CreateRoomSheet(),
  );
}

class CreateRoomSheet extends ConsumerStatefulWidget {
  const CreateRoomSheet({super.key});

  @override
  ConsumerState<CreateRoomSheet> createState() => _CreateRoomSheetState();
}

class _CreateRoomSheetState extends ConsumerState<CreateRoomSheet> {
  final _nameCtrl = TextEditingController();
  RoomHabitMode _habitMode = RoomHabitMode.shared;
  RoomCompeteMode _competeMode = RoomCompeteMode.competitive;
  int? _lengthDays = 14;
  // Whether the "Custom" duration chip (rather than one of _lengthOptions)
  // is the active choice - kept apart from _lengthDays itself so an empty
  // or invalid custom field can never be mistaken for "open-ended picked"
  // (both would otherwise read as null - see _effectiveLengthDays).
  bool _customDurationSelected = false;
  final _customDurationCtrl = TextEditingController();
  List<String> _ownHabitIds = [];
  List<String> _planHabitIds = [];
  bool _isSubmitting = false;

  // Step 1 is the "share the code" moment shown right after a successful
  // create - kept inside this same sheet (like AddHabitSheet's own 2-step
  // flow) instead of a second route, so there's only ever one sheet to
  // dismiss.
  String? _createdCode;

  /// Which half of the form is showing: 0 is the ROOM (name, spirit,
  /// length), 1 is the HABITS. Deliberately a plain int rather than a
  /// PageView: the two steps have very different heights, and a PageView
  /// would force both to the taller one's size and leave the shorter one
  /// with a lot of empty sheet under it.
  int _step = 0;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _customDurationCtrl.dispose();
    super.dispose();
  }

  /// The custom field's current value, or null while it's empty/invalid -
  /// see RoomModel.parseCustomRoomDurationDays for exactly what counts as
  /// either. Only meaningful while [_customDurationSelected] is true.
  int? get _customDurationDays =>
      parseCustomRoomDurationDays(_customDurationCtrl.text);

  /// What actually gets submitted: the typed-and-valid custom value while
  /// Custom is selected, otherwise whichever [_lengthOptions] chip is
  /// picked (including null for open-ended) - the one place that
  /// reconciles the two mutually-exclusive duration inputs into a single
  /// value, so [_submit] never has to know Custom exists at all.
  int? get _effectiveLengthDays =>
      _customDurationSelected ? _customDurationDays : _lengthDays;

  /// Why step one cannot be left yet, or null when it can.
  ///
  /// Returned as the REASON rather than a bool because that is what the
  /// button now says. A disabled button with no explanation was the old
  /// behaviour, and the explanation was usually scrolled out of sight.
  String? _stepOneBlocker(S s) {
    if (_nameCtrl.text.trim().isEmpty) return s.roomCreateNeedsName;
    if (_customDurationSelected && _customDurationDays == null) {
      return s.roomCreateNeedsDuration;
    }
    return null;
  }

  /// Why the room cannot be created yet, or null when it can.
  String? _stepTwoBlocker(S s) {
    final picked = _habitMode == RoomHabitMode.shared ? _planHabitIds : _ownHabitIds;
    if (picked.isEmpty) return s.roomCreateNeedsHabit;
    return null;
  }

  bool get _canSubmit {
    if (_nameCtrl.text.trim().isEmpty) return false;
    if (_customDurationSelected && _customDurationDays == null) return false;
    if (_habitMode == RoomHabitMode.shared) {
      return _planHabitIds.isNotEmpty;
    }
    return _ownHabitIds.isNotEmpty;
  }

  /// The length as step two's header shows it.
  String _lengthLabel(S s) => _effectiveLengthDays == null
      ? s.roomDurationOpenEnded
      : s.daysCount(_effectiveLengthDays!);

  /// Leaves step one for step two.
  ///
  /// The objectionable-name check moved here from [_submit] on purpose. It
  /// used to fire after every other decision had been made, which is the
  /// worst possible moment to be told the first field is unusable; now it
  /// fires while the name is still the thing being worked on.
  void _goToHabits() {
    if (_stepOneBlocker(S.of(context)) != null) return;
    if (isObjectionable(_nameCtrl.text)) {
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showOne(
        SnackBar(content: Text(S.of(context).roomNameNotAllowed)),
      );
      return;
    }
    HapticFeedback.selectionClick();
    FocusScope.of(context).unfocus();
    setState(() => _step = 1);
  }

  void _backToRoom() {
    HapticFeedback.selectionClick();
    FocusScope.of(context).unfocus();
    setState(() => _step = 0);
  }

  /// One of the quick-pick lengths, or null for no end date. Leaves Custom.
  void _pickLength(int? days) {
    HapticFeedback.selectionClick();
    setState(() {
      _customDurationSelected = false;
      _lengthDays = days;
    });
  }

  Future<void> _submit() async {
    if (!_canSubmit || _isSubmitting) return;
    // A room name reaches everyone who joins by code, which makes it
    // user-generated content under App Review guideline 1.2. Refused here
    // rather than silently sanitised: quietly renaming someone's room
    // would be more confusing than telling them it can't be used.
    if (isObjectionable(_nameCtrl.text)) {
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showOne(
        SnackBar(content: Text(S.of(context).roomNameNotAllowed)),
      );
      return;
    }
    setState(() => _isSubmitting = true);
    HapticFeedback.mediumImpact();
    // Read before the await below, so this never touches context across an
    // async gap.
    final isAr = S.of(context).isAr;
    final habits = ref.read(habitListProvider);
    // Filters and maps from the same resolved list (rather than mapping
    // ids and names separately) so the two lists handed to createRoom can
    // never end up different lengths, even if a selected habit somehow
    // vanished between picking it and tapping Create.
    final resolvedOwnHabits = [
      for (final id in _ownHabitIds)
        if (habits.where((h) => h.id == id).isNotEmpty)
          habits.firstWhere((h) => h.id == id),
    ];
    final code = await ref.read(roomsControllerProvider).createRoom(
          name: _nameCtrl.text.trim(),
          habitMode: _habitMode,
          planHabitIds: _planHabitIds,
          duration: _effectiveLengthDays == null
              ? RoomDuration.open
              : RoomDuration.fixed,
          lengthDays: _effectiveLengthDays,
          leaderLinkedHabitIds: resolvedOwnHabits.map((h) => h.id).toList(),
          // These strings are persisted on the room document and rendered
          // verbatim to every member (there is no re-localisation on read),
          // so the raw English `name` of a preset would have been burned into
          // an otherwise-Arabic room permanently. Writing the creator's
          // display name is what every other surface shows; a room whose
          // members genuinely differ in language would need the catalog id
          // stored instead, which is a larger change than this bug warrants.
          leaderLinkedHabitNames:
              resolvedOwnHabits.map((h) => h.localName(isAr)).toList(),
          competeMode: _competeMode,
        );
    if (!mounted) return;
    if (code == null) {
      setState(() => _isSubmitting = false);
      return;
    }
    setState(() {
      _isSubmitting = false;
      _createdCode = code;
    });
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;
    final rawMaxHeight =
        bottom > 0 ? screenHeight - bottom - 24 : screenHeight * 0.9;
    final maxHeight = rawMaxHeight < 200.0 ? 200.0 : rawMaxHeight;
    const keyboardAnim = Duration(milliseconds: 220);
    const keyboardCurve = Curves.easeOutCubic;

    return AnimatedPadding(
      duration: keyboardAnim,
      curve: keyboardCurve,
      padding: EdgeInsets.only(bottom: bottom),
      child: AnimatedContainer(
        duration: keyboardAnim,
        curve: keyboardCurve,
        constraints: BoxConstraints(maxHeight: maxHeight),
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
              _createdCode == null ? _formContent() : _shareContent(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _formContent() {
    final s = S.of(context);
    return Flexible(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _stepHeader(s),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: _step == 0 ? _roomStep(s) : _habitStep(s),
            ),
          ),
          _stepFooter(s),
        ],
      ),
    );
  }

  /// Title, step counter, and on step two a back arrow plus what step one
  /// decided. Carrying the room's name and length forward is what keeps the
  /// second screen from feeling like it forgot the first.
  Widget _stepHeader(S s) {
    final gp = context.gp;
    final onHabits = _step == 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (onHabits) ...[
                Semantics(
                  button: true,
                  label: s.roomCreateBack,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _backToRoom,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(end: 10),
                      child: Icon(Icons.arrow_back_ios_new_rounded,
                          size: 17, color: gp.textSec),
                    ),
                  ),
                ),
              ],
              Expanded(
                child: Text(
                  onHabits ? s.roomCreateStepHabitsTitle : s.roomCreateTitle,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: gp.textPrimary),
                ),
              ),
              _StepDots(step: _step),
            ],
          ),
          // Only step two carries a subtitle, and it is context rather than
          // chrome: which room, how long. Step one had "Step 1 of 2" under
          // its title, which is exactly what the two dots beside it already
          // say, in more words.
          if (onHabits) ...[
            const SizedBox(height: 3),
            Text(
              s.roomCreateRoomSummary(
                _nameCtrl.text.trim(),
                _lengthLabel(s),
                _competeMode == RoomCompeteMode.competitive
                    ? s.roomCompeteModeCompetitive
                    : s.roomCompeteModeTeam,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: gp.textTert),
            ),
          ],
        ],
      ),
    );
  }

  /// Step one: what the room IS.
  Widget _roomStep(S s) {
    final gp = context.gp;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _nameCtrl,
          // No autofocus. It used to open the keyboard before the sheet had
          // finished appearing, which covered two thirds of the form with
          // the user's first look at it.
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _goToHabits(),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: s.roomNameLabel,
            hintText: s.roomNameHint,
            prefixIcon: const Icon(Icons.flag_rounded, size: 20),
          ),
        ),
        // Tappable ideas instead of one baked-in example: the old
        // placeholder named a habit, which is the one thing a room is not.
        // Hidden once there is a name, so it never sits under a field the
        // user has already filled.
        if (_nameCtrl.text.trim().isEmpty) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                s.roomNameIdeas,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: gp.textSec),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final idea in s.roomNameSuggestions)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(end: 8),
                          child: ActionChip(
                            label: Text(idea),
                            labelStyle: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: gp.textPrimary),
                            backgroundColor: gp.surface,
                            side: BorderSide(color: gp.border),
                            visualDensity: VisualDensity.compact,
                            onPressed: () {
                              HapticFeedback.selectionClick();
                              setState(() {
                                _nameCtrl.text = idea;
                                _nameCtrl.selection = TextSelection.collapsed(
                                    offset: idea.length);
                              });
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 20),
        _SectionLabel(s.roomCompeteModeLabel),
        const SizedBox(height: 8),
        // Two cards side by side, each saying in one line what it means,
        // rather than a split button with the meaning in grey under it.
        // This is the decision that shapes the whole room (see
        // RoomCompeteMode), and the split button under-explained it: the
        // hint only ever described the picked side, so the other side was
        // a word. Side by side, not stacked, so it costs a card's height
        // and not two.
        _ChoiceCards(
          choices: [
            _Choice(
              icon: Icons.leaderboard_rounded,
              title: s.roomCompeteModeCompetitive,
              hint: s.roomCompeteModeCompetitiveHint,
            ),
            _Choice(
              icon: Icons.groups_rounded,
              title: s.roomCompeteModeTeam,
              hint: s.roomCompeteModeTeamHint,
            ),
          ],
          selected: _competeMode == RoomCompeteMode.competitive ? 0 : 1,
          onChanged: (i) => setState(() => _competeMode =
              i == 0 ? RoomCompeteMode.competitive : RoomCompeteMode.team),
        ),
        const SizedBox(height: 20),
        _SectionLabel(s.roomDurationLabel),
        const SizedBox(height: 8),
        // Two rows that fill the width: the four lengths as equal quarters,
        // then the two open choices as equal halves. A Wrap used to lay
        // these out, and it left a ragged second line (two pills hugging one
        // edge under four of different widths), which Aziz asked to fix.
        Row(
          children: [
            for (final (i, days) in _lengthOptions.whereType<int>().indexed) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: _DurationChip(
                  label: s.daysCount(days),
                  selected: !_customDurationSelected && _lengthDays == days,
                  onTap: () => _pickLength(days),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _DurationChip(
                label: s.roomDurationOpenEnded,
                selected: !_customDurationSelected && _lengthDays == null,
                onTap: () => _pickLength(null),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _DurationChip(
                label: s.roomDurationCustomOption,
                selected: _customDurationSelected,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _customDurationSelected = true);
                },
              ),
            ),
          ],
        ),
        // Only shown once Custom is picked - a plain number field rather
        // than a dialog, same "chip reveals a field inline" pattern as
        // AddHabitSheet's LimitUnit.custom/reminder-lead Custom option.
        if (_customDurationSelected) ...[
          const SizedBox(height: 10),
          TextField(
            controller: _customDurationCtrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: s.roomDurationCustomHint,
              helperText: s.roomDurationCustomRange,
              errorText: _customDurationCtrl.text.trim().isEmpty ||
                      _customDurationDays != null
                  ? null
                  : s.roomDurationCustomInvalid,
            ),
          ),
        ],
        const SizedBox(height: 10),
        // The length reads as a commitment the first time; it is not, and
        // saying so here is what stops people picking 7 days to be safe.
        Row(
          children: [
            Icon(Icons.schedule_rounded, size: 13, color: gp.textTert),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                s.roomDurationExtendHint,
                style: TextStyle(fontSize: 11.5, color: gp.textTert),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Step two: what everybody DOES. The mode and the picker belong together
  /// because the mode is what decides what the picker means.
  Widget _habitStep(S s) {
    final shared = _habitMode == RoomHabitMode.shared;
    final picked = shared ? _planHabitIds : _ownHabitIds;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionLabel(s.roomHabitModeLabel),
        const SizedBox(height: 8),
        // Same paired cards as the spirit on step one, for the same reason:
        // "leader's plan" and "everyone's own" are not self-explaining
        // words, and the one line each card carries is what tells them
        // apart.
        _ChoiceCards(
          choices: [
            _Choice(
              icon: Icons.checklist_rounded,
              title: s.roomHabitModeShared,
              hint: s.roomHabitModeSharedHint,
            ),
            _Choice(
              icon: Icons.person_rounded,
              title: s.roomHabitModeOwnShort,
              hint: s.roomHabitModeOwnHint,
            ),
          ],
          selected: shared ? 0 : 1,
          onChanged: (i) => setState(() => _habitMode =
              i == 0 ? RoomHabitMode.shared : RoomHabitMode.own),
        ),
        const SizedBox(height: 18),
        // One row above the picker: which habits this means, and, once
        // something is picked, how many. The count is the one thing here
        // the user cannot see at a glance once the list is long.
        Row(
          children: [
            Expanded(
              child: Text(
                shared ? s.roomPlanHabitsLabel : s.roomOwnHabitsLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: context.gp.textTert),
              ),
            ),
            if (picked.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: GameColors.gold.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
                ),
                child: Text(
                  s.roomPlanSelectedCount(picked.length),
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: GameColors.gold),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        _PlanHabitPicker(
          selectedIds: picked,
          onChanged: (ids) => setState(() {
            if (shared) {
              _planHabitIds = ids;
            } else {
              _ownHabitIds = ids;
            }
          }),
          isSharedTemplate: shared,
        ),
      ],
    );
  }

  /// The one button, saying what it is waiting for while it waits.
  Widget _stepFooter(S s) {
    final blocker = _step == 0 ? _stepOneBlocker(s) : _stepTwoBlocker(s);
    final enabled = blocker == null && !_isSubmitting;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      child: FilledButton(
        onPressed:
            enabled ? (_step == 0 ? _goToHabits : _submit) : null,
        style: FilledButton.styleFrom(
          minimumSize: const Size(double.infinity, 50),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: _isSubmitting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              )
            : Text(blocker ??
                (_step == 0 ? s.roomCreateNext : s.roomCreateSubmit)),
      ),
    );
  }

  Widget _shareContent() {
    final gp = context.gp;
    final s = S.of(context);
    final code = _createdCode!;
    return Flexible(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: GameColors.gold.withOpacity(0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.emoji_events_rounded,
                    size: 28, color: GameColors.gold),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              s.roomCreatedTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800, color: gp.textPrimary),
            ),
            const SizedBox(height: 6),
            Text(
              s.roomShareCode,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: gp.textSec),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: gp.surface,
                borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
                border: Border.all(color: GameColors.gold.withOpacity(0.4)),
              ),
              child: Column(
                children: [
                  Text(
                    code,
                    textAlign: TextAlign.center,
                    // Latin letters either way; pinned so Arabic shaping
                    // never reorders them.
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 6,
                      color: GameColors.gold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // What was just made, under the code that names it, so
                  // the sheet does not have to be remembered from a screen
                  // ago.
                  Text(
                    s.roomCreateRoomSummary(
                      _nameCtrl.text.trim(),
                      _lengthLabel(s),
                      _competeMode == RoomCompeteMode.competitive
                          ? s.roomCompeteModeCompetitive
                          : s.roomCompeteModeTeam,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: gp.textTert),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // The one privacy fact a leader asks about before sharing.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline_rounded, size: 13, color: gp.textTert),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    s.roomCreatedPrivateNote,
                    style: TextStyle(fontSize: 11.5, color: gp.textTert),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      Clipboard.setData(ClipboardData(text: code));
                      ScaffoldMessenger.of(context).showOne(
                        SnackBar(content: Text(s.roomCodeCopied)),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: Text(s.roomCopyAction),
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(46)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      ShareService.shareText(
                        context,
                        s.roomShareMessage(_nameCtrl.text.trim(), code),
                      );
                    },
                    icon: const Icon(Icons.ios_share_rounded, size: 16),
                    label: Text(s.roomShareAction),
                    style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(46)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // The room does not start by itself, and "created" reads as
            // "started" to a first-time leader. One card says what the next
            // move is and where it lives.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: gp.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: gp.border, width: 0.5),
              ),
              child: Row(
                children: [
                  Icon(Icons.play_circle_outline_rounded,
                      size: 18, color: gp.textSec),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.roomCreatedNextTitle,
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: gp.textPrimary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          s.roomCreatedNextBody,
                          style: TextStyle(
                              fontSize: 11.5, color: gp.textSec, height: 1.35),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // "Open the room" rather than "Done": done says the job is
            // finished, and the next thing to do is inside the room.
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pop(code),
              // A forward chevron: Flutter mirrors it in RTL, so it points
              // the way the room is (left, in Arabic).
              icon: const Icon(Icons.arrow_forward_ios_rounded, size: 15),
              label: Text(s.roomOpenAction),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                foregroundColor: gp.textPrimary,
                side: BorderSide(color: gp.border),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Two dashes: where you are, and how much is left. Chosen over "1/2" text
/// because the counter under the title already says that in words, and over
/// a progress bar because two steps is not a journey worth a bar.
class _StepDots extends StatelessWidget {
  final int step;
  const _StepDots({required this.step});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 2; i++) ...[
          if (i > 0) const SizedBox(width: 5),
          AnimatedContainer(
            duration: GameMotion.relaxed,
            curve: Curves.easeOutCubic,
            width: i == step ? 22 : 10,
            height: 4,
            decoration: BoxDecoration(
              color: i == step ? GameColors.gold : gp.border,
              borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
            ),
          ),
        ],
      ],
    );
  }
}

/// One of the sheet's two either/or decisions, as a pair of cards.
///
/// Each card is an icon, the option's name, and one line of what picking it
/// means, with a check on the picked one. The pair replaced a split button
/// with a single grey sentence under it: that sentence only ever explained
/// the picked side, so the other option was a bare word until you tried it.
/// Side by side rather than stacked, so the pair costs one card's height.
class _ChoiceCards extends StatelessWidget {
  final List<_Choice> choices;
  final int selected;
  final ValueChanged<int> onChanged;

  const _ChoiceCards({
    required this.choices,
    required this.selected,
    required this.onChanged,
  });

  @override
  // IntrinsicHeight so the pair shares the taller card's height (the hints
  // differ in length) without asking the scroll view for a height it does
  // not have: a stretched Row inside SingleChildScrollView gets infinite
  // constraints and throws.
  Widget build(BuildContext context) => IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < choices.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(
                child: _ChoiceCard(
                  choice: choices[i],
                  selected: i == selected,
                  onTap: i == selected ? null : () => onChanged(i),
                ),
              ),
            ],
          ],
        ),
      );
}

class _Choice {
  final IconData icon;
  final String title;
  final String hint;
  const _Choice({required this.icon, required this.title, required this.hint});
}

class _ChoiceCard extends StatelessWidget {
  final _Choice choice;
  final bool selected;
  final VoidCallback? onTap;

  const _ChoiceCard({
    required this.choice,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Semantics(
      button: true,
      selected: selected,
      label: '${choice.title}. ${choice.hint}',
      child: InkWell(
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        child: AnimatedContainer(
          duration: GameMotion.quick,
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
          decoration: BoxDecoration(
            color: selected ? GameColors.gold.withOpacity(0.10) : gp.surface,
            borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
            border: Border.all(
              color: selected ? GameColors.gold : gp.border,
              width: selected ? 1.1 : 0.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: selected
                          ? GameColors.gold.withOpacity(0.16)
                          : gp.surfaceHL,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(choice.icon,
                        size: 20, color: selected ? GameColors.gold : gp.textSec),
                  ),
                  const Spacer(),
                  AnimatedOpacity(
                    duration: GameMotion.quick,
                    opacity: selected ? 1 : 0,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: GameColors.gold,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.check_rounded,
                          size: 12, color: GameColors.onGold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                choice.title,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: gp.textPrimary),
              ),
              const SizedBox(height: 4),
              Text(
                choice.hint,
                style: TextStyle(fontSize: 11.5, color: gp.textSec, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: TextStyle(
          fontSize: 12, fontWeight: FontWeight.w700, color: context.gp.textTert));
}

/// One quick-pick or Custom duration pill. Sized to a minimum 44pt tap
/// target (Apple HIG's floor for a comfortably-tappable control) via
/// [BoxConstraints] rather than by inflating the font, so "7 Days" and a
/// longer localized label like "No end date" - or a custom value the field
/// below produces - all stay the same comfortable height instead of
/// drifting with whatever text happens to be inside. Laid out in rows of
/// equal [Expanded] cells, so the pill fills whatever width its row gives
/// it and the label scales down (never wraps or clips) if a cell is narrow
/// for it at a large text size.
class _DurationChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _DurationChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return InkWell(
      borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
      onTap: onTap,
      child: AnimatedContainer(
        duration: GameMotion.quick,
        constraints: const BoxConstraints(minHeight: 44),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? GameColors.gold.withOpacity(0.14) : gp.surface,
          borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
          border: Border.all(
            color: selected ? GameColors.gold : gp.border,
            width: selected ? 1.1 : 0.8,
          ),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(label,
              maxLines: 1,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected ? GameColors.gold : gp.textSec)),
        ),
      ),
    );
  }
}

/// Multi-select list of the leader's own habits - used for both modes now.
/// In 'shared' mode each one checked here becomes a plan entry every joiner
/// gets matched against (or a fresh clone of, if they don't have anything
/// close - see RoomsController.joinRoom and suggestExistingMatch). In 'own'
/// mode there's no plan/cloning involved - this just becomes the leader's
/// own [RoomParticipant.linkedHabitIds] directly, same as any other
/// participant picking their own habits to track (see JoinRoomSheet's own
/// mirror of this same widget). Reuses the exact same combined
/// catalog-+-custom list Grid/AddHabitSheet already show, so this is
/// exactly the habit list this person already recognizes from
/// everywhere else in the app.
class _PlanHabitPicker extends ConsumerStatefulWidget {
  final List<String> selectedIds;
  final ValueChanged<List<String>> onChanged;
  final bool isSharedTemplate;
  const _PlanHabitPicker({
    required this.selectedIds,
    required this.onChanged,
    this.isSharedTemplate = false,
  });

  @override
  ConsumerState<_PlanHabitPicker> createState() => _PlanHabitPickerState();
}

class _PlanHabitPickerState extends ConsumerState<_PlanHabitPicker> {
  // Most-recently-created id first - purely a display-order nicety local to
  // this one picker instance (switching between shared/own mode swaps in a
  // whole new _PlanHabitPicker anyway, so this never needs to survive that).
  // Selection state itself still lives in widget.selectedIds/onChanged, same
  // as ever - this only decides where a freshly created habit renders in
  // the list so it's obviously right there instead of wherever
  // habitListProvider's own order happens to put it.
  final List<String> _justCreatedIds = [];

  Future<void> _createNew() async {
    HapticFeedback.selectionClick();
    final created = await showModalBottomSheet<IslamicHabitTemplate>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (_) => const AddHabitSheet(),
    );
    if (created == null || !mounted) return;
    final others =
        ref.read(habitListProvider).where((h) => h.id != created.id).toList();
    final match = suggestExistingMatch(created.name, others);
    if (match != null && mounted) {
      final s = S.of(context);
      ScaffoldMessenger.of(context).showOne(
        SnackBar(
          content:
              Text(s.roomPossibleDuplicateWarning(match.localName(s.isAr))),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        ),
      );
    }
    setState(() => _justCreatedIds.insert(0, created.id));
    widget.onChanged([...widget.selectedIds, created.id]);
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final allHabits = ref.watch(habitListProvider);
    final habitById = {for (final h in allHabits) h.id: h};
    // Anything in _justCreatedIds (newest first) leads, then everything
    // else in habitListProvider's own order - a plain reorder, nothing
    // dropped or duplicated, so a stale id (habit deleted right after being
    // created here, unlikely but not impossible) just quietly falls out via
    // the null-filter below instead of crashing.
    final ordered = [
      for (final id in _justCreatedIds)
        if (habitById[id] != null) habitById[id]!,
      for (final h in allHabits)
        if (!_justCreatedIds.contains(h.id)) h,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _createNew,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: GameColors.gold.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: GameColors.gold.withOpacity(0.4)),
            ),
            child: Row(
              children: [
                Icon(Icons.add_circle_rounded, size: 18, color: GameColors.gold),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.roomCreateNewHabitAction,
                          style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: GameColors.gold)),
                      // Inside the row it describes, not floating under it.
                      if (widget.isSharedTemplate) ...[
                        const SizedBox(height: 2),
                        Text(s.roomCreateNewHabitSharedNote,
                            style: TextStyle(
                                fontSize: 11, color: gp.textSec, height: 1.3)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (ordered.isEmpty)
          Container(
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
          )
        else
          Container(
            decoration: BoxDecoration(
              color: gp.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: gp.border, width: 0.5),
            ),
            child: Column(
              children: [
                for (var i = 0; i < ordered.length; i++) ...[
                  if (i != 0) Divider(height: 1, color: gp.border),
                  _PlanHabitRow(
                    // localName, not the raw `name` field: for a preset that
                    // field holds the English catalog name, so an Arabic user
                    // picking habits for a room saw "Fajr Prayer" in a screen
                    // that is otherwise entirely Arabic.
                    name: ordered[i].localName(s.isAr),
                    selected: widget.selectedIds.contains(ordered[i].id),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      final next = [...widget.selectedIds];
                      if (!next.remove(ordered[i].id)) next.add(ordered[i].id);
                      widget.onChanged(next);
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

class _PlanHabitRow extends StatelessWidget {
  final String name;
  final bool selected;
  final VoidCallback onTap;
  const _PlanHabitRow(
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
              duration: GameMotion.quick,
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

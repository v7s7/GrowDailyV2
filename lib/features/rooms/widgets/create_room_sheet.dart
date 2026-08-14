import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/services/share_service.dart';
import '../../../core/theme/game_theme.dart';
import '../../habits/catalog/islamic_habit_catalog.dart';
import '../../habits/notifiers/custom_habits_notifier.dart';
import '../../habits/widgets/add_habit_sheet.dart';
import '../models/room_model.dart';
import '../notifiers/rooms_notifier.dart';

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

  bool get _canSubmit {
    if (_nameCtrl.text.trim().isEmpty) return false;
    if (_customDurationSelected && _customDurationDays == null) return false;
    if (_habitMode == RoomHabitMode.shared) {
      return _planHabitIds.isNotEmpty;
    }
    return _ownHabitIds.isNotEmpty;
  }

  Future<void> _submit() async {
    if (!_canSubmit || _isSubmitting) return;
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
    final gp = context.gp;
    final s = S.of(context);
    return Flexible(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
            child: Text(
              s.roomCreateTitle,
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
                  TextField(
                    controller: _nameCtrl,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: s.roomNameLabel,
                      hintText: s.roomNameHint,
                      prefixIcon: const Icon(Icons.flag_rounded, size: 20),
                    ),
                  ),
                  // Tappable ideas instead of one baked-in example: the old
                  // placeholder named a habit, which is the one thing a room
                  // is not. Hidden once there is a name, so it never sits
                  // under a field the user has already filled.
                  if (_nameCtrl.text.trim().isEmpty) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Text(
                          s.roomNameIdeas,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: gp.textSec,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                for (final idea in s.roomNameSuggestions)
                                  Padding(
                                    padding:
                                        const EdgeInsetsDirectional.only(end: 8),
                                    child: ActionChip(
                                      label: Text(idea),
                                      labelStyle: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                        color: gp.textPrimary,
                                      ),
                                      backgroundColor: gp.surface,
                                      side: BorderSide(color: gp.border),
                                      visualDensity: VisualDensity.compact,
                                      onPressed: () {
                                        HapticFeedback.selectionClick();
                                        setState(() {
                                          _nameCtrl.text = idea;
                                          _nameCtrl.selection =
                                              TextSelection.collapsed(
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
                  const SizedBox(height: 18),
                  _SectionLabel(s.roomCompeteModeLabel),
                  const SizedBox(height: 8),
                  _ModeCard(
                    icon: Icons.leaderboard_rounded,
                    title: s.roomCompeteModeCompetitive,
                    subtitle: s.roomCompeteModeCompetitiveHint,
                    selected: _competeMode == RoomCompeteMode.competitive,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _competeMode = RoomCompeteMode.competitive);
                    },
                  ),
                  const SizedBox(height: 8),
                  _ModeCard(
                    icon: Icons.diversity_3_rounded,
                    title: s.roomCompeteModeTeam,
                    subtitle: s.roomCompeteModeTeamHint,
                    selected: _competeMode == RoomCompeteMode.team,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _competeMode = RoomCompeteMode.team);
                    },
                  ),
                  const SizedBox(height: 18),
                  _SectionLabel(s.roomHabitModeLabel),
                  const SizedBox(height: 8),
                  _ModeCard(
                    icon: Icons.groups_rounded,
                    title: s.roomHabitModeShared,
                    subtitle: s.roomHabitModeSharedHint,
                    selected: _habitMode == RoomHabitMode.shared,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _habitMode = RoomHabitMode.shared);
                    },
                  ),
                  const SizedBox(height: 8),
                  _ModeCard(
                    icon: Icons.person_rounded,
                    title: s.roomHabitModeOwn,
                    subtitle: s.roomHabitModeOwnHint,
                    selected: _habitMode == RoomHabitMode.own,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _habitMode = RoomHabitMode.own);
                    },
                  ),
                  const SizedBox(height: 14),
                  if (_habitMode == RoomHabitMode.shared) ...[
                    _SectionLabel(s.roomPlanHabitsLabel),
                    const SizedBox(height: 4),
                    Text(s.roomPlanHabitsHint,
                        style: TextStyle(fontSize: 11.5, color: gp.textSec, height: 1.3)),
                    const SizedBox(height: 8),
                    _PlanHabitPicker(
                      selectedIds: _planHabitIds,
                      onChanged: (ids) => setState(() => _planHabitIds = ids),
                      isSharedTemplate: true,
                    ),
                    if (_planHabitIds.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(s.roomPlanSelectedCount(_planHabitIds.length),
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: GameColors.gold)),
                    ],
                  ] else ...[
                    _SectionLabel(s.roomOwnHabitsLabel),
                    const SizedBox(height: 4),
                    Text(s.roomOwnHabitsHint,
                        style: TextStyle(fontSize: 11.5, color: gp.textSec, height: 1.3)),
                    const SizedBox(height: 8),
                    _PlanHabitPicker(
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
                  ],
                  const SizedBox(height: 18),
                  _SectionLabel(s.roomDurationLabel),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final days in _lengthOptions)
                        _DurationChip(
                          label: days == null
                              ? s.roomDurationOpenEnded
                              : s.daysCount(days),
                          selected:
                              !_customDurationSelected && _lengthDays == days,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() {
                              _customDurationSelected = false;
                              _lengthDays = days;
                            });
                          },
                        ),
                      _DurationChip(
                        label: s.roomDurationCustomOption,
                        selected: _customDurationSelected,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _customDurationSelected = true);
                        },
                      ),
                    ],
                  ),
                  // Only shown once Custom is picked - a plain number field
                  // rather than a dialog, same "chip reveals a field inline"
                  // pattern as AddHabitSheet's LimitUnit.custom/reminder-lead
                  // Custom option, so this doesn't introduce a new mechanic
                  // for a user who's already met the pattern elsewhere.
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
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: FilledButton(
              onPressed: _canSubmit && !_isSubmitting ? _submit : null,
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    )
                  : Text(s.roomCreateSubmit),
            ),
          ),
        ],
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
              child: Text(
                code,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 6,
                  color: GameColors.gold,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      Clipboard.setData(ClipboardData(text: code));
                      ScaffoldMessenger.of(context).showSnackBar(
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
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(code),
              child: Text(s.roomDoneAction),
            ),
          ],
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

class _ModeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: AnimatedContainer(
        duration: GameMotion.quick,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? GameColors.gold.withOpacity(0.1) : gp.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? GameColors.gold : gp.border,
            width: selected ? 1.1 : 0.8,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: (selected ? GameColors.gold : gp.textSec).withOpacity(0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon,
                  size: 17, color: selected ? GameColors.gold : gp.textSec),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: gp.textPrimary)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(fontSize: 11.5, color: gp.textSec, height: 1.3)),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle_rounded, size: 20, color: GameColors.gold),
          ],
        ),
      ),
    );
  }
}

/// One quick-pick or Custom duration pill. Sized to a minimum 44x44 tap
/// target (Apple HIG's floor for a comfortably-tappable control) via
/// [BoxConstraints] rather than by inflating the font, so "7 Days" and a
/// longer localized label like "No end date" - or a custom value the field
/// below produces - all stay the same comfortable height instead of
/// drifting with whatever text happens to be inside. Wrap (the only place
/// this is ever laid out) already sizes each pill to its own intrinsic
/// width, so nothing here needs to truncate or wrap text.
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
        constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? GameColors.gold.withOpacity(0.14) : gp.surface,
          borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
          border: Border.all(
            color: selected ? GameColors.gold : gp.border,
            width: selected ? 1.1 : 0.8,
          ),
        ),
        child: Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected ? GameColors.gold : gp.textSec)),
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
      ScaffoldMessenger.of(context).showSnackBar(
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
                  child: Text(s.roomCreateNewHabitAction,
                      style: TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w700, color: GameColors.gold)),
                ),
              ],
            ),
          ),
        ),
        if (widget.isSharedTemplate) ...[
          const SizedBox(height: 6),
          Text(s.roomCreateNewHabitSharedNote,
              style: TextStyle(fontSize: 11, color: gp.textSec, height: 1.3)),
        ],
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

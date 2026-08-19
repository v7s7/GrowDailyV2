import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/voice_note_service.dart';
import '../../../core/theme/game_theme.dart';
import '../../../shared/widgets/reminder_limit_gate.dart';
import '../../../shared/widgets/voice_note_gate.dart';
import '../../auth/notifiers/auth_notifier.dart';
import '../models/matrix_task.dart';
import '../notifiers/matrix_notifier.dart';
import '../../../shared/widgets/overlay_notice.dart';
import 'reminder_picker.dart'
    show ReminderPicker, pickReminderMoment, remindersFor;
import 'voice_note_player.dart' show VoiceNoteRow, showRenameVoiceNoteSheet;

/// Stays open after each add so a quick brain-dump ("buy milk" ⏎ "wash car"
/// ⏎ "call mom" ⏎ …) doesn't mean reopening this sheet for every single
/// item. The field clears and keeps focus after each add; the primary
/// button reads "Add" while there's text to submit and "Done" once the
/// field is empty, so the same button (or the keyboard's enter key) both
/// adds and — once you're finished — closes the sheet.
///
/// Title-only by default, on purpose — that's the fast path and it stays
/// exactly as fast as it's always been. The reminder picker sits right
/// under the title field, always visible - setting a reminder is common
/// enough (and easy to miss entirely once hidden) that it doesn't get an
/// extra tap gating it the way heavier, rarer additions do. "Add details"
/// is a separate, collapsed-by-default opt-in just for a description and a
/// voice-note recorder (Premium only; see voice_note_gate.dart), for
/// whoever wants to attach more to *this* item before submitting it.
/// Collapses back to the fast default after every submit, so choosing to
/// add details once doesn't slow down the rest of a rapid multi-add — and
/// the reminder resets right along with it: it's a per-item choice, not a
/// sticky one, so the next quick-added task starts with no reminder again.
/// Editing details on a task already in the matrix happens from its pencil
/// icon (see TaskDetailSheet) instead — this sheet is only ever about
/// what's being added right now.
class AddTaskSheet extends ConsumerStatefulWidget {
  final MatrixQuadrant quadrant;
  final void Function(
    String title, {
    String? description,
    List<VoiceNote>? voiceNotes,
    List<DateTime>? reminderAts,

    /// Which entry of [reminderAts] the user actually picked, as opposed to
    /// the ones derived from it — see MatrixTask.reminderAnchorAt. Without
    /// it the task can't reproduce the ladder it was built with when it's
    /// reopened.
    DateTime? reminderAnchorAt,
  }) onAdd;

  const AddTaskSheet({
    super.key,
    required this.quadrant,
    required this.onAdd,
  });

  @override
  ConsumerState<AddTaskSheet> createState() => _AddTaskSheetState();
}

class _AddTaskSheetState extends ConsumerState<AddTaskSheet> {
  final _ctrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _focus = FocusNode();
  final List<String> _addedTitles = [];

  /// Whether any task added in this session anchors its reminder on a
  /// LATER calendar day. Under the default Today lens such a task is
  /// legitimately invisible the moment the sheet closes — which, with no
  /// explanation, read as the add having silently failed. One quiet line
  /// under the confirmation list closes that dead end without touching
  /// the lens semantics.
  bool _addedFutureAnchored = false;
  bool _hasText = false;
  bool _detailsExpanded = false;

  bool _recording = false;
  // Every note recorded on this sheet before the task exists yet — each
  // already a full, named-or-not VoiceNote (same client-generates-the-id
  // pattern TaskDetailSheet uses for a note added after the fact), so
  // _submit() can just hand the whole list to widget.onAdd instead of
  // juggling a single path/duration pair.
  List<VoiceNote> _pendingNotes = [];
  Duration _elapsed = Duration.zero;
  Timer? _timer;

  // Reminder picked for the *next* item to be submitted — same per-item,
  // resets-after-submit treatment as _pendingNotes/_descCtrl, not a sticky
  // setting across the whole rapid multi-add session. See ReminderRow /
  // pickReminderMoment in reminder_picker.dart for the shared picking UI.
  // Anchor + signed offsets rather than a flat list of moments: that's the
  // shape the picker edits in, and deriving the moments from it (see
  // remindersFor) means the chips and the scheduled reminders can never
  // disagree. Only _submit flattens them, on the way to MatrixNotifier.
  DateTime? _anchorAt;
  Set<int> _offsets = {};

  List<DateTime> get _reminderAts =>
      remindersFor(anchor: _anchorAt, offsets: _offsets);

  // ref.watch here (inside a getter, not directly in build()) is safe
  // specifically because every call site below is itself inside build() —
  // same synchronous frame, so the dependency still registers correctly.
  // Resolves to the user's own custom color for this quadrant if they've
  // set one (see MatrixState.colorFor), else the same built-in default
  // this switch used to hardcode.
  Color get _color => ref.watch(matrixProvider).colorFor(widget.quadrant);

  String _title(bool isAr) =>
      ref.watch(matrixProvider).titleFor(widget.quadrant, isAr);

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() {
      final has = _ctrl.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _descCtrl.dispose();
    _focus.dispose();
    _timer?.cancel();
    if (_recording) {
      // Sheet dismissed mid-recording — stop and discard rather than
      // leaving the recorder running against a screen that's gone.
      VoiceNoteService.instance.cancelRecording().ignore();
    } else {
      // Recorded but never attached to a submitted task (the sheet closed
      // before the current item was added) — delete them so they don't sit
      // orphaned in the voice_notes folder forever. Guards against leaving
      // the floating global player pointed at a file that's about to
      // vanish, same as TaskDetailSheet's _removeNote does.
      for (final note in _pendingNotes) {
        if (VoiceNoteService.instance.nowPlaying.value?.noteId == note.id) {
          VoiceNoteService.instance.stopPlayback().ignore();
        }
        File(note.path).delete().ignore();
      }
    }
    super.dispose();
  }

  /// Adds the current text and keeps the sheet open for the next one, or —
  /// if the field is already empty — closes it. Shared by the primary
  /// button and the keyboard's submit action so both always agree on what
  /// pressing "go" does at any given moment. A no-op while actively
  /// recording — stop the recording first, so a stray Enter can't submit a
  /// text-only task and orphan the in-progress note.
  Future<void> _submit() async {
    if (_recording) return;
    final text = _ctrl.text.trim();
    if (text.isEmpty) {
      Navigator.pop(context);
      return;
    }
    final description = _descCtrl.text.trim();
    final reminderAts = _reminderAts;
    HapticFeedback.mediumImpact();
    // Requested *before* widget.onAdd — which schedules the actual OS
    // notification synchronously inside MatrixNotifier.add — rather than
    // after, as this previously did. Requesting only after scheduling had
    // already happened meant a task's very first-ever reminder was
    // scheduled while permission was still undetermined; flutter_local_
    // notifications doesn't retroactively activate a notification that was
    // submitted before permission existed, even once the user grants it a
    // moment later. This was a real bug, not just a cosmetic ordering
    // detail: it silently broke the first reminder anyone ever set from
    // this sheet. Only awaited when this task actually carries a reminder,
    // so a plain add (the common case) is untouched, and once permission
    // has been decided once, every later call resolves near-instantly (the
    // OS doesn't re-prompt), so this doesn't meaningfully slow down rapid
    // multi-add either — same request-then-warn-on-false contract as
    // _DailyReminderRow in notification_settings_screen.dart, just with the
    // request landing before scheduling instead of after.
    var granted = true;
    if (reminderAts.isNotEmpty) {
      granted = await NotificationService.instance.requestPermissions();
    }
    widget.onAdd(
      text,
      description: description.isEmpty ? null : description,
      voiceNotes: _pendingNotes,
      reminderAts: reminderAts,
      reminderAnchorAt: _anchorAt,
    );
    if (!mounted) return;
    final now = DateTime.now();
    final anchor = _anchorAt;
    final anchorsLater = anchor != null &&
        DateTime(anchor.year, anchor.month, anchor.day)
            .isAfter(DateTime(now.year, now.month, now.day));
    setState(() {
      _addedFutureAnchored = _addedFutureAnchored || anchorsLater;
      _addedTitles.add(text);
      _ctrl.clear();
      _descCtrl.clear();
      // These notes now belong to the task just handed to widget.onAdd —
      // only the *reference* to them resets here, same as _voiceNotePath
      // used to just go back to null without deleting anything.
      _pendingNotes = [];
      _anchorAt = null;
      _offsets = {};
      // Back to the fast title-only default for the next item — adding
      // details is a deliberate, per-item choice, not a sticky mode.
      _detailsExpanded = false;
    });
    _focus.requestFocus();
    if (reminderAts.isNotEmpty && !granted && mounted) {
      // Overlay, not SnackBar: this sheet is a modal, and a SnackBar
      // renders on the Scaffold BEHIND it — the user who denied
      // notifications never saw this warning and believed the reminder
      // was armed. See showOverlayNotice.
      showOverlayNotice(
        context,
        S.of(context).reminderPermissionDenied,
        icon: Icons.notifications_off_outlined,
      );
    }
  }

  Future<void> _toggleRecording() async {
    if (!hasVoiceNoteAccess(ref)) {
      showVoiceNoteGate(context, ref);
      return;
    }
    if (_recording) {
      final result = await VoiceNoteService.instance.stopRecording();
      _timer?.cancel();
      if (!mounted) return;
      setState(() => _recording = false);
      if (result != null) {
        // Signed-in users get this note's audio embedded as base64 too, so
        // it can sync to a second device (see VoiceNote.audioBase64) —
        // guests have no second device to sync to, so skip the extra
        // encode/storage work entirely for them.
        final uid = ref.read(authStateProvider).asData?.value?.uid;
        String? audioBase64;
        if (uid != null) {
          final existingSyncedBytes = _pendingNotes.fold<int>(
            0,
            (sum, n) => sum + (n.audioBase64?.length ?? 0),
          );
          audioBase64 = await VoiceNoteService.instance.encodeForSync(
            result.path,
            existingSyncedBytes: existingSyncedBytes,
          );
          if (!mounted) return;
        }
        final note = VoiceNote(
          id: const Uuid().v4(),
          path: result.path,
          name: '',
          durationSeconds: result.durationSeconds,
          createdAt: DateTime.now(),
          audioBase64: audioBase64,
        );
        setState(() => _pendingNotes = [..._pendingNotes, note]);
        // Prompts a name right away, same as TaskDetailSheet — "step1" is
        // far more likely to actually get typed the moment the recording
        // is fresh than if naming means hunting down the pencil icon
        // later. Dismissing this without saving just leaves it as the
        // "Recording N" placeholder, still fully usable.
        _renameNote(note);
      }
      return;
    }
    final granted = await VoiceNoteService.instance.hasPermission();
    if (!granted) {
      if (mounted) {
        // Overlay, not SnackBar — invisible behind this modal otherwise.
        showOverlayNotice(
          context,
          S.of(context).voiceNoteMicPermissionDenied,
          icon: Icons.mic_off_rounded,
        );
      }
      return;
    }
    // Unlike before, a fresh recording no longer replaces an earlier one —
    // a task can carry several notes now, so this just adds another.
    HapticFeedback.mediumImpact();
    await VoiceNoteService.instance.startRecording();
    if (!mounted) return;
    setState(() {
      _recording = true;
      _elapsed = Duration.zero;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final next = _elapsed + const Duration(seconds: 1);
      setState(() => _elapsed = next);
      // Auto-stop at the cap instead of letting a note grow past what
      // encodeForSync budgets a synced recording for — same effect as
      // tapping the mic button again, just triggered by the clock instead
      // of a tap.
      if (next.inSeconds >= VoiceNoteService.maxRecordingSeconds) {
        _toggleRecording();
      }
    });
  }

  /// The note's own name if it has one, otherwise "Recording N" — N is
  /// this note's 1-based position among the notes pending on this sheet,
  /// computed at display time same as TaskDetailSheet's _displayName.
  String _displayName(VoiceNote note) {
    if (note.name.isNotEmpty) return note.name;
    final index = _pendingNotes.indexWhere((n) => n.id == note.id);
    return S
        .of(context)
        .voiceNoteDefaultName(index < 0 ? _pendingNotes.length : index + 1);
  }

  void _renameNote(VoiceNote note) {
    showRenameVoiceNoteSheet(
      context,
      currentName: _displayName(note),
      onSave: (name) {
        setState(() {
          _pendingNotes = _pendingNotes
              .map((n) => n.id == note.id ? n.copyWith(name: name) : n)
              .toList();
        });
      },
    );
  }

  void _removeNote(VoiceNote note) {
    HapticFeedback.lightImpact();
    // Otherwise the floating player could keep "playing" a file that's
    // about to be deleted out from under it.
    if (VoiceNoteService.instance.nowPlaying.value?.noteId == note.id) {
      VoiceNoteService.instance.stopPlayback().ignore();
    }
    setState(() {
      _pendingNotes = _pendingNotes.where((n) => n.id != note.id).toList();
    });
    File(note.path).delete().ignore();
  }

  void _toggleDetails() {
    HapticFeedback.selectionClick();
    setState(() => _detailsExpanded = !_detailsExpanded);
  }

  /// The anchor: the moment the task is actually about. Straight to the
  /// full picker, because this is the one value the app can't guess.
  Future<void> _pickAnchor() async {
    final picked = await pickReminderMoment(context, initial: _anchorAt);
    if (picked == null || !mounted) return;
    setState(() => _anchorAt = picked);
  }

  void _clearReminders() {
    HapticFeedback.lightImpact();
    setState(() {
      _anchorAt = null;
      _offsets = {};
    });
  }

  /// Offsets are a set, so tapping a selected chip removes it — that's what
  /// makes the grid multi-select rather than a radio group.
  void _toggleOffset(int signedMinutes) {
    final next = Set<int>.from(_offsets);
    if (!next.remove(signedMinutes)) {
      if (_reminderAts.length >= NotificationService.kMaxTaskReminderSlots) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).matrixReminderMaxReached)),
        );
        return;
      }
      next.add(signedMinutes);
    }
    setState(() => _offsets = next);
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final isAr = s.isAr;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;
    // Resting size (no keyboard) stays ~85% of the screen; once the keyboard
    // opens, cap to whatever is left above it instead. The old cap was
    // `screenHeight * 0.85` unconditionally, computed from the FULL screen
    // while the keyboard was subtracted only in the sibling AnimatedPadding
    // — so ConstrainedBox clamped the card to the post-keyboard height while
    // the Column below still demanded the pre-keyboard one. Because
    // Flex.clipBehavior defaults to Clip.none, the overflow was *painted*
    // outside the card rather than clipped: the ADD TASK button and the
    // multi-add hint rendered underneath the iOS keyboard, present but
    // unreachable, with nothing scrollable to bring them back. Same fix and
    // same reasoning as AddHabitSheet, which hit this first.
    //
    // The floor matters on a landscape phone, where a keyboard can leave
    // less than 200pt: without it the card collapses to nothing at all.
    final rawMaxHeight =
        bottom > 0 ? screenHeight - bottom - 24 : screenHeight * 0.85;
    final maxHeight = rawMaxHeight < 200.0 ? 200.0 : rawMaxHeight;
    final canSubmit = (_hasText || _addedTitles.isNotEmpty) && !_recording;
    return AnimatedPadding(
      duration: GameMotion.standard,
      curve: Curves.easeOut,
      padding: EdgeInsets.fromLTRB(12, 0, 12, 12 + bottom),
      // AnimatedContainer, not Container, and on the same duration/curve as
      // the padding above: the keyboard moves both the sheet's offset and
      // its height, and animating only one of them makes the card snap while
      // it slides.
      child: AnimatedContainer(
        duration: GameMotion.standard,
        curve: Curves.easeOut,
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: BoxDecoration(
          color: gp.surfaceHigh,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: gp.border, width: 0.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 6),
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: gp.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // The one Flexible in this Column, and the only thing that can
            // absorb the shrink when the keyboard takes half the screen.
            // Everything that grows — the reminder section most of all,
            // which gains a chip per custom offset and a row per reminder —
            // lives inside it, so a tall stack scrolls instead of being
            // painted off the bottom of the card. The grabber above and the
            // ADD TASK footer below stay fixed and always reachable.
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: _color.withOpacity(0.12),
                              borderRadius:
                                  BorderRadius.circular(GameSpacing.pillRadius),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    color: _color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _title(isAr),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: _color,
                                    // Letter-spacing disconnects Arabic glyphs
                                    // (the script is cursive/joined) — only the
                                    // Latin small-caps label wants that look.
                                    letterSpacing: isAr ? 0 : 1.0,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              widget.quadrant.localSubtitle(isAr),
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: gp.textSec),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: gp.surfaceHL,
                          borderRadius:
                              BorderRadius.circular(GameSpacing.cardRadius),
                          border: Border.all(color: gp.border, width: 0.5),
                        ),
                        child: TextField(
                          controller: _ctrl,
                          focusNode: _focus,
                          onSubmitted: (_) => _submit(),
                          textCapitalization: TextCapitalization.sentences,
                          textInputAction: TextInputAction.done,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w500,
                            color: gp.textPrimary,
                            height: 1.4,
                          ),
                          maxLines: 3,
                          minLines: 1,
                          decoration: InputDecoration(
                            hintText: s.matrixWhatToDo,
                            hintStyle: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w400,
                              color: gp.textTert.withOpacity(0.7),
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Always visible, unlike description/voice notes below - see
                    // this class's own doc comment for why the reminder specifically
                    // doesn't wait for "Add details".
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: ReminderPicker(
                        anchorAt: _anchorAt,
                        offsets: _offsets,
                        color: _color,
                        isAr: isAr,
                        canStack:
                            canAddAnotherReminder(ref, _reminderAts.length),
                        onPickAnchor: _pickAnchor,
                        onClear: _clearReminders,
                        onToggleOffset: _toggleOffset,
                        onLocked: () => showReminderLimitGate(context, ref),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: GestureDetector(
                          onTap: _toggleDetails,
                          behavior: HitTestBehavior.opaque,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _detailsExpanded
                                      ? Icons.remove_circle_outline_rounded
                                      : Icons.add_circle_outline_rounded,
                                  size: 14,
                                  color: _color,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _detailsExpanded
                                      ? s.matrixHideDetails
                                      : s.matrixAddDetails,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: _color,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_detailsExpanded) ...[
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: gp.surfaceHL,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: gp.border, width: 0.5),
                          ),
                          child: TextField(
                            controller: _descCtrl,
                            textCapitalization: TextCapitalization.sentences,
                            style: TextStyle(
                              fontSize: 13.5,
                              color: gp.textPrimary,
                              height: 1.4,
                            ),
                            maxLines: 3,
                            minLines: 1,
                            decoration: InputDecoration(
                              hintText: s.matrixDescriptionHint,
                              hintStyle: TextStyle(
                                fontSize: 13.5,
                                color: gp.textTert.withOpacity(0.7),
                              ),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              filled: false,
                              contentPadding:
                                  const EdgeInsets.symmetric(vertical: 10),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    s.voiceNotesTitle,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: gp.textTert,
                                      letterSpacing: isAr ? 0 : 1.0,
                                    ),
                                  ),
                                ),
                                MicRecordButton(
                                  recording: _recording,
                                  elapsed: _elapsed,
                                  color: _color,
                                  onTap: _toggleRecording,
                                  locked: !hasVoiceNoteAccess(ref),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (_recording)
                              Text(
                                s.voiceNoteRecording,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: GameColors.error,
                                ),
                              )
                            else if (_pendingNotes.isEmpty)
                              Text(
                                s.voiceNoteTapToRecord,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: gp.textTert,
                                ),
                              )
                            else
                              for (var i = 0; i < _pendingNotes.length; i++)
                                Padding(
                                  padding: EdgeInsets.only(
                                    bottom:
                                        i == _pendingNotes.length - 1 ? 0 : 8,
                                  ),
                                  child: VoiceNoteRow(
                                    note: _pendingNotes[i],
                                    displayName: _displayName(_pendingNotes[i]),
                                    color: _color,
                                    onRename: () =>
                                        _renameNote(_pendingNotes[i]),
                                    onDelete: () =>
                                        _removeNote(_pendingNotes[i]),
                                  ),
                                ),
                          ],
                        ),
                      ),
                    ] else if (_addedTitles.isEmpty) ...[
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          s.matrixAddMultipleHint,
                          style: TextStyle(fontSize: 11.5, color: gp.textTert),
                        ),
                      ),
                    ],
                    // Moved above the button and out of its own ListView. It used to
                    // sit below the footer inside a Flexible, which by then had no
                    // free space left to hand it — so the confirmation list rendered
                    // at zero height and was invisible exactly when it mattered.
                    // Above the input is also where its own comment always said it
                    // wanted to be: "right under the input every time".
                    if (_addedTitles.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Divider(height: 1, color: gp.divider),
                      ),
                      const SizedBox(height: 12),
                      // A plain Column, not a ListView: this is already inside a
                      // SingleChildScrollView, and nesting a second scrollable would
                      // need a height nobody here can supply.
                      for (var i = 0; i < _addedTitles.length; i++)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: _color.withOpacity(0.06),
                              borderRadius: BorderRadius.circular(
                                GameSpacing.buttonRadius,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.check_circle_rounded,
                                  size: 15,
                                  color: _color,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    // Reversed so the just-added item appears
                                    // closest to the input, not at the far end of
                                    // the list.
                                    _addedTitles[_addedTitles.length - 1 - i],
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: gp.textPrimary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ).animate().fadeIn(duration: 200.ms),
                      if (_addedFutureAnchored)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
                          child: Row(
                            children: [
                              Icon(Icons.schedule_rounded,
                                  size: 13, color: gp.textTert),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Text(
                                  S.of(context).matrixAddedForLater,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: gp.textSec,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              // Fresh open with nothing typed and nothing added yet still
              // shows a disabled "ADD TASK" (same as before this sheet
              // could stay open) — a "Done" button is only the right
              // primary action once there's actually something to be done
              // with.
              child: Builder(
                builder: (_) {
                  final showDone = !_hasText && _addedTitles.isNotEmpty;
                  return FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 52),
                      backgroundColor: canSubmit ? _color : gp.surfaceHL,
                      foregroundColor: canSubmit ? Colors.black : gp.textTert,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(GameSpacing.cardRadius),
                      ),
                    ),
                    onPressed: canSubmit ? _submit : null,
                    child: Text(
                      showDone ? s.matrixDone : s.matrixAddTask,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: isAr ? 0 : 1.4,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      )
          .animate()
          .slideY(begin: 0.08, duration: 280.ms, curve: Curves.easeOutCubic)
          .fadeIn(duration: 200.ms),
    );
  }
}

/// Mic / stop toggle for recording a voice note. Swaps icon, color, and
/// (while recording) shows a live mm:ss so there's no ambiguity about
/// whether it's actually capturing. Used both in AddTaskSheet's "Add
/// details" section and in TaskDetailSheet — public (no leading
/// underscore) for exactly that reason.
class MicRecordButton extends StatelessWidget {
  final bool recording;
  final Duration elapsed;
  final Color color;
  final VoidCallback onTap;

  /// Draws the small gold lock on the mic for free accounts. The gate
  /// itself still lives at the tap (showVoiceNoteGate) — this is only the
  /// missing WARNING: an unlocked-looking mic that upsells after the tap
  /// reads as a trap, and voice_note_gate.dart's own doc comment has asked
  /// for a locked affordance all along. The button stays tappable — the
  /// tap IS the pitch.
  final bool locked;

  const MicRecordButton({
    super.key,
    required this.recording,
    required this.elapsed,
    required this.color,
    required this.onTap,
    this.locked = false,
  });

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final mm = elapsed.inMinutes.toString().padLeft(2, '0');
    final ss = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return Semantics(
      button: true,
      label: recording ? s.voiceNoteTapToStop : s.voiceNoteTapToRecord,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: GameMotion.quick,
          padding:
              EdgeInsets.symmetric(horizontal: recording ? 10 : 8, vertical: 8),
          decoration: BoxDecoration(
            color: recording
                ? GameColors.error.withOpacity(0.14)
                : color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (locked && !recording)
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(Icons.mic_rounded, size: 18, color: color),
                    PositionedDirectional(
                      end: -5,
                      bottom: -3,
                      child: Container(
                        padding: const EdgeInsets.all(1.5),
                        decoration: BoxDecoration(
                          color: GameColors.gold,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFF14100A),
                            width: 1,
                          ),
                        ),
                        child: const Icon(
                          Icons.lock_rounded,
                          size: 8,
                          color: Color(0xFF14100A),
                        ),
                      ),
                    ),
                  ],
                )
              else
                Icon(
                  recording ? Icons.stop_rounded : Icons.mic_rounded,
                  size: 18,
                  color: recording ? GameColors.error : color,
                ),
              if (recording) ...[
                const SizedBox(width: 6),
                Text(
                  '$mm:$ss',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: GameColors.error,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

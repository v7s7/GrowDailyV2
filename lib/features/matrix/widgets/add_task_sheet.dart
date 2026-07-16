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
import '../../../shared/widgets/voice_note_gate.dart';
import '../../auth/notifiers/auth_notifier.dart';
import '../models/matrix_task.dart';
import '../notifiers/matrix_notifier.dart';
import 'reminder_picker.dart' show ReminderRow, pickReminderMoment;
import 'voice_note_player.dart' show VoiceNoteRow, showRenameVoiceNoteSheet;

/// Stays open after each add so a quick brain-dump ("buy milk" ⏎ "wash car"
/// ⏎ "call mom" ⏎ …) doesn't mean reopening this sheet for every single
/// item. The field clears and keeps focus after each add; the primary
/// button reads "Add" while there's text to submit and "Done" once the
/// field is empty, so the same button (or the keyboard's enter key) both
/// adds and — once you're finished — closes the sheet.
///
/// Title-only by default, on purpose — that's the fast path and it stays
/// exactly as fast as it's always been. "Add details" is an explicit,
/// collapsed-by-default opt-in that reveals a description field, a
/// reminder-time picker, and a voice-note recorder (Premium only; see
/// voice_note_gate.dart) for whoever wants to attach more to *this* item
/// before submitting it. Collapses back to the fast default after every
/// submit, so choosing to add details once doesn't slow down the rest of a
/// rapid multi-add — including the reminder: it's a per-item choice, not a
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
    DateTime? reminderAt,
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
  DateTime? _reminderAt;

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
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _focus.requestFocus());
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
    final reminderAt = _reminderAt;
    HapticFeedback.mediumImpact();
    widget.onAdd(
      text,
      description: description.isEmpty ? null : description,
      voiceNotes: _pendingNotes,
      reminderAt: reminderAt,
    );
    if (!mounted) return;
    setState(() {
      _addedTitles.add(text);
      _ctrl.clear();
      _descCtrl.clear();
      // These notes now belong to the task just handed to widget.onAdd —
      // only the *reference* to them resets here, same as _voiceNotePath
      // used to just go back to null without deleting anything.
      _pendingNotes = [];
      _reminderAt = null;
      // Back to the fast title-only default for the next item — adding
      // details is a deliberate, per-item choice, not a sticky mode.
      _detailsExpanded = false;
    });
    _focus.requestFocus();
    // Checked after the task is already handed off and the UI's reset back
    // to the fast-add state — actual scheduling happens unconditionally
    // inside MatrixNotifier.add regardless of permission (flutter_local_
    // notifications just silently won't display it if denied), so this is
    // purely a courtesy warning, not a gate, and shouldn't hold up the next
    // item in a rapid multi-add. Same request-then-warn-on-false contract
    // as _DailyReminderRow in notification_settings_screen.dart.
    if (reminderAt != null) {
      final granted = await NotificationService.instance.requestPermissions();
      if (!granted && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).reminderPermissionDenied)),
        );
      }
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
              0, (sum, n) => sum + (n.audioBase64?.length ?? 0));
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).voiceNoteMicPermissionDenied)),
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

  Future<void> _pickReminder() async {
    final picked = await pickReminderMoment(context, initial: _reminderAt);
    if (picked == null || !mounted) return;
    setState(() => _reminderAt = picked);
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final isAr = s.isAr;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final canSubmit = (_hasText || _addedTitles.isNotEmpty) && !_recording;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      padding: EdgeInsets.fromLTRB(12, 0, 12, 12 + bottom),
      child: Container(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85),
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
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              child: Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                                color: _color, shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        Text(_title(isAr),
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: _color,
                                // Letter-spacing disconnects Arabic glyphs
                                // (the script is cursive/joined) — only the
                                // Latin small-caps label wants that look.
                                letterSpacing: isAr ? 0 : 1.0)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(widget.quadrant.localSubtitle(isAr),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: gp.textSec)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: gp.surfaceHL,
                  borderRadius: BorderRadius.circular(16),
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
                      height: 1.4),
                  maxLines: 3,
                  minLines: 1,
                  decoration: InputDecoration(
                    hintText: s.matrixWhatToDo,
                    hintStyle: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w400,
                        color: gp.textTert.withOpacity(0.7)),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
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
                              color: _color),
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
                      horizontal: 16, vertical: 4),
                  decoration: BoxDecoration(
                    color: gp.surfaceHL,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: gp.border, width: 0.5),
                  ),
                  child: TextField(
                    controller: _descCtrl,
                    textCapitalization: TextCapitalization.sentences,
                    style: TextStyle(
                        fontSize: 13.5, color: gp.textPrimary, height: 1.4),
                    maxLines: 3,
                    minLines: 1,
                    decoration: InputDecoration(
                      hintText: s.matrixDescriptionHint,
                      hintStyle: TextStyle(
                          fontSize: 13.5,
                          color: gp.textTert.withOpacity(0.7)),
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
                child: ReminderRow(
                  value: _reminderAt,
                  color: _color,
                  isAr: isAr,
                  onTap: _pickReminder,
                  onClear: () => setState(() => _reminderAt = null),
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
                                letterSpacing: isAr ? 0 : 1.0),
                          ),
                        ),
                        MicRecordButton(
                          recording: _recording,
                          elapsed: _elapsed,
                          color: _color,
                          onTap: _toggleRecording,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_recording)
                      Text(s.voiceNoteRecording,
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: GameColors.error))
                    else if (_pendingNotes.isEmpty)
                      Text(s.voiceNoteTapToRecord,
                          style:
                              TextStyle(fontSize: 11.5, color: gp.textTert))
                    else
                      for (var i = 0; i < _pendingNotes.length; i++)
                        Padding(
                          padding: EdgeInsets.only(
                              bottom:
                                  i == _pendingNotes.length - 1 ? 0 : 8),
                          child: VoiceNoteRow(
                            note: _pendingNotes[i],
                            displayName: _displayName(_pendingNotes[i]),
                            color: _color,
                            onRename: () => _renameNote(_pendingNotes[i]),
                            onDelete: () => _removeNote(_pendingNotes[i]),
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
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              // Fresh open with nothing typed and nothing added yet still
              // shows a disabled "ADD TASK" (same as before this sheet
              // could stay open) — a "Done" button is only the right
              // primary action once there's actually something to be done
              // with.
              child: Builder(builder: (_) {
                final showDone = !_hasText && _addedTitles.isNotEmpty;
                return FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52),
                    backgroundColor: canSubmit ? _color : gp.surfaceHL,
                    foregroundColor: canSubmit ? Colors.black : gp.textTert,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: canSubmit ? _submit : null,
                  child: Text(showDone ? s.matrixDone : s.matrixAddTask,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: isAr ? 0 : 1.4)),
                );
              }),
            ),
            SizedBox(height: _addedTitles.isEmpty ? 20 : 4),
            if (_addedTitles.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Divider(height: 1, color: gp.divider),
              ),
              Flexible(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  shrinkWrap: true,
                  itemCount: _addedTitles.length,
                  itemBuilder: (context, i) {
                    // Reversed so the just-added item appears right under
                    // the input every time, not at the bottom of a list
                    // that's scrolled out of view.
                    final title = _addedTitles[_addedTitles.length - 1 - i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: _color.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle_rounded,
                                size: 15, color: _color),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: gp.textPrimary),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ).animate().fadeIn(duration: 200.ms);
                  },
                ),
              ),
            ],
          ],
        ),
      ).animate().slideY(
          begin: 0.08,
          duration: 280.ms,
          curve: Curves.easeOutCubic).fadeIn(duration: 200.ms),
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

  const MicRecordButton({
    super.key,
    required this.recording,
    required this.elapsed,
    required this.color,
    required this.onTap,
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
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.symmetric(
              horizontal: recording ? 10 : 8, vertical: 8),
          decoration: BoxDecoration(
            color: recording
                ? GameColors.error.withOpacity(0.14)
                : color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(100),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
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

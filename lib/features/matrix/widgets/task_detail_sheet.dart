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
import 'add_task_sheet.dart' show MicRecordButton;
import 'quadrant_card.dart' show ActionRow;
import 'reminder_picker.dart' show ReminderRow, pickReminderMoment;
import 'voice_note_player.dart' show VoiceNoteRow, showRenameVoiceNoteSheet;

/// Opened from a task's pencil icon (see quadrant_card.dart's _TaskTile) —
/// the richer counterpart to AddTaskSheet's title-only quick add: this is
/// where an already-added task's title, description, reminder, and voice
/// notes get edited after the fact, plus Delete/Move-to-quadrant (migrated
/// here from the old "..." menu, so the row still only carries one icon
/// for this).
///
/// Only talks to the outside world through callbacks — never touches
/// matrixProvider directly — so MatrixScreen stays the single place that
/// owns provider access for this whole feature, same as every
/// QuadrantCard/_TaskTile callback already does.
///
/// Title/description save once, when the sheet closes (swipe, back
/// gesture, or Delete/Move popping it) rather than per-keystroke, so
/// editing doesn't spam Firestore writes. Voice note changes save
/// immediately on record/rename/remove instead — losing a just-recorded
/// note to an accidental swipe-dismiss is a much worse trade than a couple
/// of extra writes.
class TaskDetailSheet extends ConsumerStatefulWidget {
  final MatrixTask task;
  final void Function(String id, String title) onRename;
  final void Function(
    String id, {
    String? description,
    bool? clearDescription,
  }) onUpdateDetails;
  final void Function(String id, VoiceNote note) onAddVoiceNote;
  final void Function(String id, String noteId, String name) onRenameVoiceNote;
  final void Function(String id, String noteId) onRemoveVoiceNote;
  final void Function(String id, DateTime? reminderAt) onSetReminder;
  final VoidCallback onDelete;
  final void Function(MatrixQuadrant quadrant) onMove;

  const TaskDetailSheet({
    super.key,
    required this.task,
    required this.onRename,
    required this.onUpdateDetails,
    required this.onAddVoiceNote,
    required this.onRenameVoiceNote,
    required this.onRemoveVoiceNote,
    required this.onSetReminder,
    required this.onDelete,
    required this.onMove,
  });

  @override
  ConsumerState<TaskDetailSheet> createState() => _TaskDetailSheetState();
}

class _TaskDetailSheetState extends ConsumerState<TaskDetailSheet> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  // Local mirror of widget.task.voiceNotes, same reasoning as the title/
  // description controllers above: this sheet never re-reads
  // matrixProvider, so every add/rename/remove updates this list directly
  // (for instant UI feedback) *and* fires the matching callback (to
  // actually persist it) rather than waiting on a round-trip that would
  // never arrive.
  late List<VoiceNote> _voiceNotes;
  // Same local-mirror-plus-immediate-persist treatment as _voiceNotes
  // above — see setReminder's doc comment (matrix_notifier.dart) for why
  // this saves right on pick instead of waiting for dispose() the way
  // title/description do.
  late DateTime? _reminderAt;

  bool _recording = false;
  Duration _elapsed = Duration.zero;
  Timer? _timer;

  // See AddTaskSheet's identical _color getter for why ref.watch inside a
  // build()-only getter is safe here.
  Color get _color => ref.watch(matrixProvider).colorFor(widget.task.quadrant);

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.task.title);
    _descCtrl = TextEditingController(text: widget.task.description ?? '');
    _voiceNotes = List.of(widget.task.voiceNotes);
    _reminderAt = widget.task.reminderAt;
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_recording) {
      // Sheet dismissed mid-recording — stop and discard, same as
      // AddTaskSheet does, rather than leaving the recorder running.
      VoiceNoteService.instance.cancelRecording().ignore();
    }
    // Playback is deliberately left running here — closing this sheet is
    // not supposed to stop it. See VoiceNoteService.stopPlayback's doc
    // comment: the floating global player docked above GameNavBar exists
    // precisely so a note keeps playing after you leave the sheet (or the
    // whole screen) it was started from.
    final title = _titleCtrl.text.trim();
    if (title.isNotEmpty && title != widget.task.title) {
      widget.onRename(widget.task.id, title);
    }
    final description = _descCtrl.text.trim();
    if (description != (widget.task.description ?? '')) {
      widget.onUpdateDetails(
        widget.task.id,
        description: description.isEmpty ? null : description,
        clearDescription: description.isEmpty,
      );
    }
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
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
          final existingSyncedBytes = _voiceNotes.fold<int>(
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
        setState(() => _voiceNotes = [..._voiceNotes, note]);
        widget.onAddVoiceNote(widget.task.id, note);
        // Prompts a name right away, same idea as Voice Memos — "step1"
        // etc. is far more likely to actually get typed the moment the
        // recording is fresh than if naming means hunting down the pencil
        // icon later. Dismissing this without saving just leaves it as the
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
  /// this note's 1-based position among *this task's* notes, computed at
  /// display time rather than stored, so deleting an earlier note doesn't
  /// leave a later one stuck showing a stale number.
  String _displayName(VoiceNote note) {
    if (note.name.isNotEmpty) return note.name;
    final index = _voiceNotes.indexWhere((n) => n.id == note.id);
    return S.of(context).voiceNoteDefaultName(index < 0 ? _voiceNotes.length : index + 1);
  }

  void _renameNote(VoiceNote note) {
    showRenameVoiceNoteSheet(
      context,
      currentName: _displayName(note),
      onSave: (name) {
        setState(() {
          _voiceNotes = _voiceNotes
              .map((n) => n.id == note.id ? n.copyWith(name: name) : n)
              .toList();
        });
        widget.onRenameVoiceNote(widget.task.id, note.id, name);
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
      _voiceNotes = _voiceNotes.where((n) => n.id != note.id).toList();
    });
    widget.onRemoveVoiceNote(widget.task.id, note.id);
    File(note.path).delete().ignore();
  }

  Future<void> _pickReminder() async {
    final picked = await pickReminderMoment(context, initial: _reminderAt);
    if (picked == null || !mounted) return;
    setState(() => _reminderAt = picked);
    widget.onSetReminder(widget.task.id, picked);
    // Scheduling itself always happens regardless (see
    // NotificationService.scheduleTaskReminder's doc comment on why it
    // doesn't gate on permission) — this request is purely so a denied
    // permission can be surfaced right away instead of the reminder
    // silently never firing.
    final granted = await NotificationService.instance.requestPermissions();
    if (!granted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.of(context).reminderPermissionDenied)),
      );
    }
  }

  void _clearReminder() {
    HapticFeedback.lightImpact();
    setState(() => _reminderAt = null);
    widget.onSetReminder(widget.task.id, null);
  }

  void _delete() {
    HapticFeedback.mediumImpact();
    Navigator.pop(context);
    widget.onDelete();
  }

  void _move(MatrixQuadrant q) {
    HapticFeedback.selectionClick();
    Navigator.pop(context);
    widget.onMove(q);
  }

  Color _colorFor(MatrixQuadrant q) => ref.watch(matrixProvider).colorFor(q);

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final isAr = s.isAr;
    final matrixState = ref.watch(matrixProvider);
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final others = MatrixQuadrant.values
        .where((q) => q != widget.task.quadrant)
        .toList();
    return AnimatedPadding(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      padding: EdgeInsets.fromLTRB(12, 0, 12, 12 + bottom),
      child: Container(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.88),
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
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
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
                            Text(matrixState.titleFor(widget.task.quadrant, isAr),
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: _color,
                                    letterSpacing: isAr ? 0 : 1.0)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      decoration: BoxDecoration(
                        color: gp.surfaceHL,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: gp.border, width: 0.5),
                      ),
                      child: TextField(
                        controller: _titleCtrl,
                        textCapitalization: TextCapitalization.sentences,
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: gp.textPrimary,
                            height: 1.4),
                        maxLines: 3,
                        minLines: 1,
                        decoration: InputDecoration(
                          hintText: s.matrixWhatToDo,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        s.matrixTaskDetails,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: gp.textTert,
                            letterSpacing: isAr ? 0 : 1.0),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
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
                            fontSize: 13.5,
                            color: gp.textPrimary,
                            height: 1.4),
                        maxLines: 5,
                        minLines: 2,
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
                    const SizedBox(height: 10),
                    ReminderRow(
                      value: _reminderAt,
                      color: _color,
                      isAr: isAr,
                      onTap: _pickReminder,
                      onClear: _clearReminder,
                    ),
                    const SizedBox(height: 14),
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
                    else if (_voiceNotes.isEmpty)
                      Text(s.voiceNoteTapToRecord,
                          style: TextStyle(
                              fontSize: 11.5, color: gp.textTert))
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < _voiceNotes.length; i++)
                            Padding(
                              padding: EdgeInsets.only(
                                  bottom:
                                      i == _voiceNotes.length - 1 ? 0 : 8),
                              child: VoiceNoteRow(
                                note: _voiceNotes[i],
                                displayName: _displayName(_voiceNotes[i]),
                                color: _color,
                                onRename: () => _renameNote(_voiceNotes[i]),
                                onDelete: () => _removeNote(_voiceNotes[i]),
                              ),
                            ),
                        ],
                      ),
                    const SizedBox(height: 24),
                    ActionRow(
                      icon: Icons.delete_outline_rounded,
                      iconColor: GameColors.error,
                      label: s.matrixDeleteTask,
                      labelColor: GameColors.error,
                      onTap: _delete,
                    ),
                    const SizedBox(height: 18),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        s.matrixMoveToQuadrant,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: gp.textTert,
                            letterSpacing: isAr ? 0 : 1.2),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...others.map((q) => Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: ActionRow(
                            dotColor: _colorFor(q),
                            label: matrixState.titleFor(q, isAr),
                            subtitle: q.localSubtitle(isAr),
                            onTap: () => _move(q),
                          ),
                        )),
                  ],
                ),
              ),
            ),
          ],
        ),
      )
          .animate()
          .slideY(begin: 0.08, duration: 280.ms, curve: Curves.easeOutCubic)
          .fadeIn(duration: 200.ms),
    );
  }
}


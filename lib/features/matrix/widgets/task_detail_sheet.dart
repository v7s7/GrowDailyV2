import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/services/voice_note_service.dart';
import '../../../core/theme/game_theme.dart';
import '../../../shared/widgets/voice_note_gate.dart';
import '../models/matrix_task.dart';
import 'add_task_sheet.dart' show MicRecordButton, VoiceNoteChip;
import 'quadrant_card.dart' show ActionRow, VoiceNotePlayButton;

/// Opened from a task's pencil icon (see quadrant_card.dart's _TaskTile) —
/// the richer counterpart to AddTaskSheet's title-only quick add: this is
/// where an already-added task's title, description, and voice note get
/// edited after the fact, plus Delete/Move-to-quadrant (migrated here from
/// the old "..." menu, so the row still only carries one icon for this).
///
/// Only talks to the outside world through callbacks — never touches
/// matrixProvider directly — so MatrixScreen stays the single place that
/// owns provider access for this whole feature, same as every
/// QuadrantCard/_TaskTile callback already does.
///
/// Title/description save once, when the sheet closes (swipe, back
/// gesture, or Delete/Move popping it) rather than per-keystroke, so
/// editing doesn't spam Firestore writes. Voice note changes save
/// immediately on record/remove instead — losing a just-recorded note to
/// an accidental swipe-dismiss is a much worse trade than a couple of
/// extra writes.
class TaskDetailSheet extends ConsumerStatefulWidget {
  final MatrixTask task;
  final void Function(String id, String title) onRename;
  final void Function(
    String id, {
    String? description,
    bool? clearDescription,
    String? voiceNotePath,
    int? voiceNoteDurationSeconds,
    bool? clearVoiceNote,
  }) onUpdateDetails;
  final VoidCallback onDelete;
  final void Function(MatrixQuadrant quadrant) onMove;

  const TaskDetailSheet({
    super.key,
    required this.task,
    required this.onRename,
    required this.onUpdateDetails,
    required this.onDelete,
    required this.onMove,
  });

  @override
  ConsumerState<TaskDetailSheet> createState() => _TaskDetailSheetState();
}

class _TaskDetailSheetState extends ConsumerState<TaskDetailSheet> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  String? _voiceNotePath;
  int? _voiceNoteDurationSeconds;

  bool _recording = false;
  Duration _elapsed = Duration.zero;
  Timer? _timer;

  Color get _color => switch (widget.task.quadrant) {
        MatrixQuadrant.doFirst => GameColors.error,
        MatrixQuadrant.schedule => GameColors.xpBlue,
        MatrixQuadrant.delegate => GameColors.streakOrange,
        MatrixQuadrant.eliminate => GameColors.textTertiary,
      };

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.task.title);
    _descCtrl = TextEditingController(text: widget.task.description ?? '');
    _voiceNotePath = widget.task.voiceNotePath;
    _voiceNoteDurationSeconds = widget.task.voiceNoteDurationSeconds;
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_recording) {
      // Sheet dismissed mid-recording — stop and discard, same as
      // AddTaskSheet does, rather than leaving the recorder running.
      VoiceNoteService.instance.cancelRecording().ignore();
    }
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
        final oldPath = _voiceNotePath;
        setState(() {
          _voiceNotePath = result.path;
          _voiceNoteDurationSeconds = result.durationSeconds;
        });
        widget.onUpdateDetails(
          widget.task.id,
          voiceNotePath: result.path,
          voiceNoteDurationSeconds: result.durationSeconds,
        );
        // The old recording is now orphaned on disk — this task's pointer
        // just moved on to the new one.
        if (oldPath != null && oldPath != result.path) {
          File(oldPath).delete().ignore();
        }
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
    // Recording over an existing note that's currently playing back would
    // otherwise leave playback running against a file that's about to be
    // replaced.
    if (VoiceNoteService.instance.currentlyPlayingTaskId.value ==
        widget.task.id) {
      VoiceNoteService.instance.stopPlayback().ignore();
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
      setState(() => _elapsed += const Duration(seconds: 1));
    });
  }

  void _removeVoiceNote() {
    HapticFeedback.lightImpact();
    final path = _voiceNotePath;
    setState(() {
      _voiceNotePath = null;
      _voiceNoteDurationSeconds = null;
    });
    widget.onUpdateDetails(widget.task.id, clearVoiceNote: true);
    if (path != null) File(path).delete().ignore();
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

  Color _colorFor(MatrixQuadrant q) => switch (q) {
        MatrixQuadrant.doFirst => GameColors.error,
        MatrixQuadrant.schedule => GameColors.xpBlue,
        MatrixQuadrant.delegate => GameColors.streakOrange,
        MatrixQuadrant.eliminate => GameColors.textTertiary,
      };

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final isAr = s.isAr;
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
                            Text(widget.task.quadrant.localLabel(isAr),
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
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        MicRecordButton(
                          recording: _recording,
                          elapsed: _elapsed,
                          color: _color,
                          onTap: _toggleRecording,
                        ),
                        const SizedBox(width: 10),
                        if (_recording)
                          Text(s.voiceNoteRecording,
                              style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: GameColors.error))
                        else if (_voiceNotePath != null) ...[
                          VoiceNotePlayButton(
                            taskId: widget.task.id,
                            path: _voiceNotePath!,
                            color: _color,
                          ),
                          const SizedBox(width: 2),
                          Expanded(
                            child: VoiceNoteChip(
                              color: _color,
                              durationSeconds: _voiceNoteDurationSeconds ?? 0,
                              onRemove: _removeVoiceNote,
                            ),
                          ),
                        ] else
                          Text(s.voiceNoteTapToRecord,
                              style: TextStyle(
                                  fontSize: 11.5, color: gp.textTert)),
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
                            label: q.localLabel(isAr),
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

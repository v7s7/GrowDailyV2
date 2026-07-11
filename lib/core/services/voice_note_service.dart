import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

/// Records and plays back short voice notes attached to Tasks (see
/// MatrixTask.voiceNotePath).
///
/// Local-only by design — recordings live in the app's own documents folder
/// and are referenced by a plain file path, the same for guests and
/// signed-in users. That means a voice note won't follow a signed-in user
/// to a second device (nothing here uploads anything anywhere), but it also
/// means: no Firebase Storage bucket to configure, no upload step to fail,
/// and the recording never leaves the device at all. Cross-device sync
/// would need Storage + security rules layered on top of this later — a
/// separate, bigger piece of work, not a prerequisite for a working
/// voice-note feature today.
class VoiceNoteService {
  VoiceNoteService._();
  static final instance = VoiceNoteService._();

  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  DateTime? _recordingStartedAt;

  /// Which task's voice note (if any) is playing right now — a plain
  /// ValueNotifier rather than a Riverpod provider, since this is a bare
  /// singleton the widget tree listens to directly (same style as
  /// NotificationService/HomeWidgetService), not something that goes
  /// through `ref`. Null means nothing is playing.
  final ValueNotifier<String?> currentlyPlayingTaskId = ValueNotifier(null);

  bool get isRecording => _recordingStartedAt != null;

  /// Checks (and, the first time, requests) microphone permission. Call
  /// this before showing a "recording…" UI state, not after — starting a
  /// record() call that silently fails permission is a worse experience
  /// than asking up front.
  Future<bool> hasPermission() => _recorder.hasPermission();

  /// Starts recording to a fresh file under the app's documents folder
  /// (voice_notes/), named by a random id rather than a task id — at
  /// record-start time, from the Add Task sheet, the task doesn't exist
  /// yet. Safe to call even if hasPermission() hasn't been checked; it
  /// simply won't start if permission isn't granted.
  Future<void> startRecording() async {
    if (isRecording) return;
    if (!await _recorder.hasPermission()) return;
    final docsDir = await getApplicationDocumentsDirectory();
    final notesDir = Directory('${docsDir.path}/voice_notes');
    if (!await notesDir.exists()) {
      await notesDir.create(recursive: true);
    }
    final path = '${notesDir.path}/${const Uuid().v4()}.m4a';
    await _recorder.start(const RecordConfig(), path: path);
    _recordingStartedAt = DateTime.now();
  }

  /// Stops the current recording. Returns its path and length, or null if
  /// nothing was recording — or if what was captured is under a second,
  /// which is almost always an accidental tap rather than an intentional
  /// note, in which case the near-empty file is deleted rather than kept.
  Future<({String path, int durationSeconds})?> stopRecording() async {
    final startedAt = _recordingStartedAt;
    final path = await _recorder.stop();
    final durationSeconds =
        startedAt == null ? 0 : DateTime.now().difference(startedAt).inSeconds;
    _recordingStartedAt = null;
    if (path == null) return null;
    if (durationSeconds < 1) {
      File(path).delete().ignore();
      return null;
    }
    return (path: path, durationSeconds: durationSeconds);
  }

  /// Discards the current recording entirely — e.g. the Add Task sheet was
  /// dismissed mid-recording. Deletes the partial file via record's own
  /// cancel() rather than leaving it orphaned in the documents folder.
  Future<void> cancelRecording() async {
    _recordingStartedAt = null;
    await _recorder.cancel();
  }

  /// Toggles playback of [taskId]'s voice note at [path]: starts it if
  /// nothing (or a different task's note) is playing, stops it if this
  /// exact one already is. Only one voice note plays at a time — starting
  /// this one always stops whatever else was playing first.
  Future<void> togglePlayback(String taskId, String path) async {
    if (currentlyPlayingTaskId.value == taskId) {
      await _player.stop();
      currentlyPlayingTaskId.value = null;
      return;
    }
    await _player.stop();
    currentlyPlayingTaskId.value = taskId;
    unawaited(_player.play(DeviceFileSource(path)));
    // Clears the "playing" indicator once the clip finishes on its own —
    // guarded so a completion event from an *earlier* clip (already
    // superseded by a newer togglePlayback call) can't clear the new one.
    unawaited(_player.onPlayerComplete.first.then((_) {
      if (currentlyPlayingTaskId.value == taskId) {
        currentlyPlayingTaskId.value = null;
      }
    }));
  }

  /// Stops whatever's playing without starting anything else — used when
  /// leaving a screen that shows voice-note rows, so audio doesn't keep
  /// playing after its play button has scrolled off/been disposed.
  Future<void> stopPlayback() async {
    await _player.stop();
    currentlyPlayingTaskId.value = null;
  }
}

import 'dart:async';
import 'dart:convert' show base64Encode, base64Decode;
import 'dart:io';

import 'dart:ui' show Color;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

/// Everything the floating global player (docked above GameNavBar) and
/// every list row need to know about the note currently loaded — set as
/// one atomic unit by [VoiceNoteService.play] so the title/color shown next
/// to the controls can never end up describing a different note than the
/// one actually playing.
class NowPlayingVoiceNote {
  final String noteId;
  final String path;
  final String title;
  final Color color;
  final int durationSeconds;
  // Carried along so VoiceNotePlayer can pass it back into svc.play() if it
  // ever needs to reload this same note (see its _skip/_seekToFraction) —
  // without this, that reload would only know [path], which is useless for
  // a note that synced down to this device without ever being recorded on
  // it.
  final String? audioBase64;

  const NowPlayingVoiceNote({
    required this.noteId,
    required this.path,
    required this.title,
    required this.color,
    required this.durationSeconds,
    this.audioBase64,
  });
}

/// Records and plays back short voice notes attached to Tasks (see
/// MatrixTask.voiceNotes).
///
/// Recordings always live locally first — the app's own documents folder,
/// referenced by a plain file path, same for guests and signed-in users.
/// For a signed-in user, a short (≤[maxRecordingSeconds]) note also gets
/// base64-encoded (see [encodeForSync]) and stored inline on the
/// VoiceNote itself, riding along with the task's normal Firestore sync —
/// no Firebase Storage bucket, no separate upload step, entirely free of
/// the Blaze plan a Storage bucket would require. That's what lets a note
/// follow a signed-in user to a second device: [play]/[togglePlayback]
/// fall back to decoding those synced bytes (via [_resolveSource]) when
/// [path] doesn't exist on the device doing the playing. A note over
/// budget, or recorded as a guest, stays device-local only — it still
/// plays fine here, it just won't show up anywhere else.
///
/// Exactly one note plays at a time, app-wide, by design — same as any
/// music/podcast player. That single shared slot is what makes a *global*
/// floating player possible: whichever note is loaded here is the one
/// GameNavBar shows above the nav bar, on every tab, until it's paused-out/
/// finishes/gets closed, regardless of which screen (or which task's
/// recordings list) it was started from.
class VoiceNoteService {
  VoiceNoteService._() {
    // Wired once, persistently — every play/pause/seek call below drives
    // the same AudioPlayer instance, so this one set of listeners covers
    // every row's play button, the recordings list, and the floating
    // global player, all reacting to the same source of truth.
    _posSub = _player.onPositionChanged.listen((p) {
      // Guards against a stray event from a clip that already finished/
      // got superseded landing after nowPlaying moved on.
      if (nowPlaying.value != null) position.value = p;
    });
    _durSub = _player.onDurationChanged.listen((d) {
      if (nowPlaying.value != null) duration.value = d;
    });
    _completeSub = _player.onPlayerComplete.listen((_) {
      isPlaying.value = false;
      position.value = Duration.zero;
      nowPlaying.value = null;
    });
  }
  static final instance = VoiceNoteService._();

  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  late final StreamSubscription<Duration> _posSub;
  late final StreamSubscription<Duration> _durSub;
  late final StreamSubscription<void> _completeSub;

  DateTime? _recordingStartedAt;

  /// Which voice note (if any) is loaded in the player right now, plus the
  /// title/color to show alongside it — a plain ValueNotifier rather than
  /// a Riverpod provider, since this is a bare singleton the widget tree
  /// listens to directly (same style as NotificationService/
  /// HomeWidgetService), not something that goes through `ref`. Null means
  /// nothing is loaded. Non-null covers both "playing" and "paused" — check
  /// [isPlaying] to tell those apart.
  final ValueNotifier<NowPlayingVoiceNote?> nowPlaying = ValueNotifier(null);

  /// Whether the loaded note is actively playing (as opposed to paused).
  /// Only meaningful while [nowPlaying] is non-null.
  final ValueNotifier<bool> isPlaying = ValueNotifier(false);

  /// Live playback position of the loaded note, driven by audioplayers'
  /// own position stream — what VoiceNotePlayer's scrubber tracks.
  final ValueNotifier<Duration> position = ValueNotifier(Duration.zero);

  /// Duration of the loaded note. Seeded from the estimate taken at
  /// record time (see [stopRecording]) until the player reports the real
  /// decoded duration, so the scrubber never has to show 0:00 while the
  /// file is still opening.
  final ValueNotifier<Duration> duration = ValueNotifier(Duration.zero);

  /// Playback speed applied to the loaded note — one of 1.0 / 1.5 / 2.0,
  /// cycled by the speed pill in VoiceNotePlayer. Resets to 1x whenever a
  /// *different* note loads (see [play]): speed is a per-listen choice
  /// here, not a saved preference, same as most voice-memo players.
  final ValueNotifier<double> speed = ValueNotifier(1.0);

  bool get isRecording => _recordingStartedAt != null;

  /// Checks (and, the first time, requests) microphone permission. Call
  /// this before showing a "recording…" UI state, not after — starting a
  /// record() call that silently fails permission is a worse experience
  /// than asking up front.
  Future<bool> hasPermission() => _recorder.hasPermission();

  /// Hard cap on a single recording's length in seconds. Enforced by the
  /// Add Task / Task Detail sheets' own elapsed-time timers (see their
  /// recording Timer.periodic), not by the recorder itself — this is just
  /// the one shared number both read, so they can't quietly drift out of
  /// sync with each other. Exists to keep a single note's base64 payload
  /// (see [encodeForSync]) a known, small, worst case size, which is what
  /// [maxSyncedBytesPerTask] below is sized around.
  static const int maxRecordingSeconds = 30;

  /// AAC-LC at a much lower bitrate and channel count than record's plain
  /// defaults (128kbps stereo — tuned for music, not talking into a
  /// phone). Voice stays perfectly intelligible well below that, and every
  /// bit saved here directly shrinks the base64 payload [encodeForSync]
  /// has to fit under a task's sync budget: mono halves it outright, and
  /// dropping to 48kbps shrinks it again to roughly a third — together
  /// leaving room for several synced notes per task instead of barely one.
  static const _recordConfig = RecordConfig(
    encoder: AudioEncoder.aacLc,
    bitRate: 48000,
    numChannels: 1,
  );

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
    await _recorder.start(_recordConfig, path: path);
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

  /// Highest total base64 bytes across one task's voiceNotes this service
  /// will try to stay under — well clear of Firestore's hard 1MiB
  /// (1,048,576-byte) per-document limit. A task document carries more
  /// than just voiceNotes (title, description, timestamps, ...), and a
  /// batch write alongside dashboard/grid updates has its own overall
  /// request-size ceiling too, so this leaves generous headroom rather
  /// than racing right up to either one.
  static const int maxSyncedBytesPerTask = 700 * 1024;

  /// Reads the just-recorded file at [path] and returns its base64
  /// encoding, ready to store on a VoiceNote's audioBase64 field — or null
  /// if embedding it would push this task's total synced audio over
  /// [maxSyncedBytesPerTask], or if the file can't be read at all.
  ///
  /// Deliberately degrades by skipping sync rather than failing the save:
  /// a note that comes back null here still has its local [path] and
  /// plays back fine on the device that recorded it — it just won't be
  /// there yet on a second device. Callers pass [existingSyncedBytes] (the
  /// sum of this task's *other* notes' `audioBase64?.length`) so the
  /// budget is enforced per task, not per note — several small notes can
  /// still add up to too much even if each one individually would fit.
  Future<String?> encodeForSync(
    String path, {
    required int existingSyncedBytes,
  }) async {
    try {
      final bytes = await File(path).readAsBytes();
      // Base64 inflates by ~4/3 — checked against the raw byte count here,
      // before doing the actual encoding work, so an over-budget file is
      // rejected cheaply instead of encoding it first and throwing the
      // result away.
      final estimatedEncodedBytes = (bytes.length * 4 / 3).ceil();
      if (existingSyncedBytes + estimatedEncodedBytes >
          maxSyncedBytesPerTask) {
        return null;
      }
      return base64Encode(bytes);
    } catch (_) {
      return null;
    }
  }

  /// Picks what to actually hand audioplayers for [path]/[audioBase64]:
  /// the local file if it's actually there (the recording device, or a
  /// second device that already downloaded this note once), else the
  /// synced bytes decoded straight into memory. Returns null only when
  /// neither is available — a note recorded on another device that never
  /// synced audio down (over budget, or recorded before this feature
  /// existed) — which [play] treats as "nothing to play" rather than
  /// crashing into a player with no source.
  Future<Source?> _resolveSource(String path, String? audioBase64) async {
    if (await File(path).exists()) return DeviceFileSource(path);
    if (audioBase64 != null) {
      return BytesSource(base64Decode(audioBase64), mimeType: 'audio/mp4');
    }
    return null;
  }

  /// Loads and plays the voice note [noteId] at [path], showing [title] in
  /// [color] wherever it's now the loaded note (the recordings-list row,
  /// and the floating global player docked above GameNavBar). Switching to
  /// a *different* note always restarts at 0:00 and resets speed to 1x;
  /// calling this again for the same note while it's paused resumes
  /// instead of restarting — same as tapping play in any music app, you
  /// don't expect it to jump back to the start.
  ///
  /// [durationSeconds] seeds [duration] immediately (from the estimate
  /// taken at record time) so the total-time label doesn't show 0:00 for
  /// the instant before the real decoded duration streams in.
  ///
  /// [audioBase64] is the note's synced audio, if any (see
  /// VoiceNote.audioBase64) — only actually used as a fallback source when
  /// [path] doesn't exist on this device (see [_resolveSource]); the local
  /// file is always preferred when it's there.
  Future<void> play(
    String noteId,
    String path, {
    required String title,
    required Color color,
    required int durationSeconds,
    String? audioBase64,
  }) async {
    if (nowPlaying.value?.noteId == noteId) {
      await _player.resume();
      // Must follow play()/resume(), not precede it (audioplayers docs).
      await _player.setPlaybackRate(speed.value);
      isPlaying.value = true;
      return;
    }
    final source = await _resolveSource(path, audioBase64);
    // Neither a local file nor synced bytes — a note recorded on another
    // device that hasn't synced audio down to this one. Nothing to play,
    // so leave nowPlaying/isPlaying untouched rather than loading a player
    // with no source.
    if (source == null) return;
    await _player.stop();
    nowPlaying.value = NowPlayingVoiceNote(
      noteId: noteId,
      path: path,
      title: title,
      color: color,
      durationSeconds: durationSeconds,
      audioBase64: audioBase64,
    );
    position.value = Duration.zero;
    duration.value = Duration(seconds: durationSeconds);
    speed.value = 1.0;
    isPlaying.value = true;
    await _player.play(source);
    await _player.setPlaybackRate(speed.value);
  }

  /// Pauses the loaded note in place — unlike [stopPlayback], the position
  /// is retained so play() resumes exactly where it left off.
  Future<void> pause() async {
    await _player.pause();
    isPlaying.value = false;
  }

  /// Seeks the loaded note to an absolute position, clamped to
  /// `[0, duration]`. Updates [position] immediately (rather than only
  /// once the platform call resolves) so the scrubber snaps to the new
  /// spot without waiting on a round trip.
  Future<void> seek(Duration to) async {
    final max = duration.value;
    final clamped = to < Duration.zero
        ? Duration.zero
        : (max > Duration.zero && to > max ? max : to);
    position.value = clamped;
    await _player.seek(clamped);
  }

  /// Seeks relative to the current position — powers the ±5s skip buttons.
  Future<void> seekBy(Duration delta) => seek(position.value + delta);

  /// Cycles the loaded note's speed 1x -> 1.5x -> 2x -> 1x.
  Future<void> cycleSpeed() async {
    final next = switch (speed.value) {
      1.0 => 1.5,
      1.5 => 2.0,
      _ => 1.0,
    };
    speed.value = next;
    await _player.setPlaybackRate(next);
  }

  /// Toggles playback of note [noteId] at [path]: starts it if nothing (or
  /// a different note) is playing, stops it (not just pauses — resets to
  /// 0:00) if this exact one already is. Used by each recordings-list
  /// row's compact play/pause button (TaskDetailSheet); the floating
  /// global player calls [play]/[pause] directly instead since it has
  /// separate buttons for each.
  Future<void> togglePlayback(
    String noteId,
    String path, {
    required String title,
    required Color color,
    required int durationSeconds,
    String? audioBase64,
  }) async {
    if (nowPlaying.value?.noteId == noteId) {
      await stopPlayback();
      return;
    }
    await play(noteId, path,
        title: title,
        color: color,
        durationSeconds: durationSeconds,
        audioBase64: audioBase64);
  }

  /// Stops whatever's loaded entirely (position resets to 0) and closes
  /// the floating global player — the explicit "X" there, and by
  /// [togglePlayback]'s "tap the same one again" case. Deliberately *not*
  /// called just because the screen/row that started playback was left —
  /// the whole point of the floating player is that it survives that.
  Future<void> stopPlayback() async {
    await _player.stop();
    nowPlaying.value = null;
    isPlaying.value = false;
    position.value = Duration.zero;
  }

  /// Cancels the player's stream listeners and releases it. The service
  /// itself is a singleton that normally lives for the whole app session
  /// (nothing calls this today) — it exists so the class doesn't leak
  /// subscriptions by construction, and for tests that spin up/tear down
  /// their own instance.
  Future<void> dispose() async {
    await _posSub.cancel();
    await _durSub.cancel();
    await _completeSub.cancel();
    await _player.dispose();
  }
}

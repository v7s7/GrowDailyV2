// Deterministic tests for the three pure, static helpers pulled out of
// VoiceNoteService (see each one's doc comment): the sync-budget check
// behind encodeForSync, the seek-position clamp behind seek, and the
// speed-cycle mapping behind cycleSpeed.
//
// Deliberately not tested here: encodeForSync/seek/cycleSpeed themselves,
// startRecording/stopRecording, play/pause/togglePlayback, or anything else
// touching VoiceNoteService.instance. That singleton's constructor wires up
// real AudioPlayer/AudioRecorder listeners at construction time (see the
// class's own constructor), and record/audioplayers are real platform
// plugins with no fake/mock implementation set up in this project - so
// exercising them meaningfully needs a real device or a mocking layer this
// codebase doesn't have yet, not a plain unit test. The three functions
// below are exactly the logic that's left once the plugin/file-I/O parts
// are set aside.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/services/voice_note_service.dart';

void main() {
  group('VoiceNoteService.wouldExceedSyncBudget', () {
    test('a small file with no existing synced bytes is well under budget',
        () {
      expect(
        VoiceNoteService.wouldExceedSyncBudget(
          rawByteLength: 1000,
          existingSyncedBytes: 0,
        ),
        isFalse,
      );
    });

    test('existing bytes already at the cap rejects even a tiny new file',
        () {
      expect(
        VoiceNoteService.wouldExceedSyncBudget(
          rawByteLength: 1,
          existingSyncedBytes: VoiceNoteService.maxSyncedBytesPerTask,
        ),
        isTrue,
      );
    });

    test(
        'landing exactly on maxSyncedBytesPerTask is allowed - the boundary '
        'is inclusive (encodeForSync uses >, not >=)', () {
      // 537,600 raw bytes inflate via the ~4/3 base64 estimate to exactly
      // 716,800 (= maxSyncedBytesPerTask = 700 * 1024), with no remainder -
      // chosen so this test isolates the boundary check itself from any
      // floating-point rounding in the ceil().
      expect(VoiceNoteService.maxSyncedBytesPerTask, 716800);
      expect(
        VoiceNoteService.wouldExceedSyncBudget(
          rawByteLength: 537600,
          existingSyncedBytes: 0,
        ),
        isFalse,
      );
    });

    test('one raw byte past that exact boundary now exceeds the budget', () {
      expect(
        VoiceNoteService.wouldExceedSyncBudget(
          rawByteLength: 537601,
          existingSyncedBytes: 0,
        ),
        isTrue,
      );
    });

    test('budget is enforced across the whole task, not per note', () {
      // Two individually-small notes that together push the task over.
      const perNote = 400 * 1024; // ~533KB encoded each, ~1.04MB together
      final firstOk = VoiceNoteService.wouldExceedSyncBudget(
        rawByteLength: perNote,
        existingSyncedBytes: 0,
      );
      final secondExceeds = VoiceNoteService.wouldExceedSyncBudget(
        rawByteLength: perNote,
        existingSyncedBytes: (perNote * 4 / 3).ceil(),
      );
      expect(firstOk, isFalse);
      expect(secondExceeds, isTrue);
    });
  });

  group('VoiceNoteService.clampSeekPosition', () {
    const max = Duration(seconds: 30);

    test('a negative target clamps to zero', () {
      expect(
        VoiceNoteService.clampSeekPosition(
          const Duration(seconds: -5),
          max: max,
        ),
        Duration.zero,
      );
    });

    test('a target within range is returned unchanged', () {
      const target = Duration(seconds: 10);
      expect(
        VoiceNoteService.clampSeekPosition(target, max: max),
        target,
      );
    });

    test('a target past the end clamps down to max', () {
      expect(
        VoiceNoteService.clampSeekPosition(
          const Duration(seconds: 45),
          max: max,
        ),
        max,
      );
    });

    test('a target exactly at max is returned as-is', () {
      expect(
        VoiceNoteService.clampSeekPosition(max, max: max),
        max,
      );
    });

    test('a target of exactly zero is not treated as negative', () {
      expect(
        VoiceNoteService.clampSeekPosition(Duration.zero, max: max),
        Duration.zero,
      );
    });

    test(
        'when max is Duration.zero (real duration not streamed in yet), '
        'no upper clamp is applied', () {
      const target = Duration(seconds: 5);
      expect(
        VoiceNoteService.clampSeekPosition(target, max: Duration.zero),
        target,
      );
    });
  });

  group('VoiceNoteService.nextPlaybackSpeed', () {
    test('1x cycles to 1.5x', () {
      expect(VoiceNoteService.nextPlaybackSpeed(1.0), 1.5);
    });

    test('1.5x cycles to 2x', () {
      expect(VoiceNoteService.nextPlaybackSpeed(1.5), 2.0);
    });

    test('2x cycles back to 1x', () {
      expect(VoiceNoteService.nextPlaybackSpeed(2.0), 1.0);
    });

    test('an unrecognized speed defensively resets to 1x', () {
      expect(VoiceNoteService.nextPlaybackSpeed(0.75), 1.0);
    });
  });
}

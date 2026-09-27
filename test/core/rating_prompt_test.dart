// The rating question (rating_prompt.dart): asked only after a streak steps
// onto 7, 30 or 100 days, never in a phone's first week, never twice in 120
// days. Aziz, 2026-09-26: "add the rating prompt".
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/core/services/local_store_service.dart';
import 'package:grow_daily_v2/core/services/rating_prompt.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('when a streak earns the question', () {
    test('one step onto a milestone', () {
      expect(streakEarnsRatingAsk(from: 6, to: 7), isTrue);
      expect(streakEarnsRatingAsk(from: 29, to: 30), isTrue);
      expect(streakEarnsRatingAsk(from: 99, to: 100), isTrue);
    });

    test('not a streak read back at launch, and not past a milestone', () {
      expect(streakEarnsRatingAsk(from: 0, to: 7), isFalse,
          reason: 'a load jumps the number, nobody reached anything');
      expect(streakEarnsRatingAsk(from: 7, to: 8), isFalse);
      expect(streakEarnsRatingAsk(from: 3, to: 4), isFalse);
      expect(streakEarnsRatingAsk(from: 8, to: 7), isFalse);
    });

    test('never in the first week, never twice in 120 days', () {
      final start = DateTime(2026, 9, 1, 9);
      expect(
        mayAskForRating(now: start.add(const Duration(days: 6)), firstSeen: start),
        isFalse,
      );
      expect(
        mayAskForRating(now: start.add(const Duration(days: 7)), firstSeen: start),
        isTrue,
      );
      final asked = DateTime(2026, 10, 1);
      expect(
        mayAskForRating(
          now: asked.add(const Duration(days: 119)),
          firstSeen: start,
          lastAsked: asked,
        ),
        isFalse,
      );
      expect(
        mayAskForRating(
          now: asked.add(const Duration(days: 120)),
          firstSeen: start,
          lastAsked: asked,
        ),
        isTrue,
      );
    });
  });

  group('on a phone', () {
    late Directory tmp;
    late int requests;
    late DateTime now;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('rating_prompt_');
      Hive.init(tmp.path);
      await Hive.openBox<dynamic>('box_settings');
      requests = 0;
      now = DateTime(2026, 9, 1, 9);
      RatingPrompt.clock = () => now;
      RatingPrompt.requestOverride = () async => requests++;
    });

    tearDown(() async {
      RatingPrompt.clock = DateTime.now;
      RatingPrompt.requestOverride = null;
      await Hive.deleteFromDisk();
      if (tmp.existsSync()) await tmp.delete(recursive: true);
    });

    Future<Map<String, dynamic>> stored() =>
        LocalStoreService.getSettingsMap(kRatingPromptKey);

    test('a phone with no first day yet is stamped, and not asked', () async {
      expect(await RatingPrompt.maybeAskAfterStreak(from: 6, to: 7), isFalse);
      expect(requests, 0);
      expect((await stored())['firstSeen'], now.toIso8601String());
    });

    test('asks once the week is up, then waits 120 days', () async {
      await RatingPrompt.noteFirstSeen();
      now = now.add(const Duration(days: 8));
      expect(await RatingPrompt.maybeAskAfterStreak(from: 6, to: 7), isTrue);
      expect(requests, 1);
      expect((await stored())['asks'], 1);

      now = now.add(const Duration(days: 23));
      expect(await RatingPrompt.maybeAskAfterStreak(from: 29, to: 30), isFalse,
          reason: 'inside the 120-day gap');
      expect(requests, 1);

      now = now.add(const Duration(days: 100));
      expect(await RatingPrompt.maybeAskAfterStreak(from: 99, to: 100), isTrue);
      expect(requests, 2);
      expect((await stored())['asks'], 2);
    });

    test('a step that is not a milestone never asks', () async {
      await RatingPrompt.noteFirstSeen();
      now = now.add(const Duration(days: 30));
      expect(await RatingPrompt.maybeAskAfterStreak(from: 0, to: 7), isFalse);
      expect(await RatingPrompt.maybeAskAfterStreak(from: 10, to: 11), isFalse);
      expect(requests, 0);
      expect((await stored())['lastAsked'], isNull);
    });

    test('the first day is kept, not moved by later launches', () async {
      await RatingPrompt.noteFirstSeen();
      final first = (await stored())['firstSeen'];
      now = now.add(const Duration(days: 3));
      await RatingPrompt.noteFirstSeen();
      expect((await stored())['firstSeen'], first);
    });
  });
}

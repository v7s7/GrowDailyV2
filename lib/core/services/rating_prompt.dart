import 'package:flutter/foundation.dart';
import 'package:in_app_review/in_app_review.dart';

import 'analytics_service.dart';
import 'local_store_service.dart';

/// The system's own "rate this app" question, asked at a good moment.
///
/// Aziz, 2026-09-26: "add the rating prompt". The app never asked, and
/// stars decide a good share of downloads. It asks only after something
/// good: the day a streak reaches one of [kRatingStreakMilestones], a few
/// seconds after the tap that earned it. Never in a phone's first
/// [kRatingFirstAskAfter], never twice inside [kRatingAskGap], never on the
/// web. The OS has the last word on top of that (StoreKit shows it at most
/// three times a year, and not to someone who already rated this version),
/// so what is kept here is only when this phone last ASKED.

/// The streaks that earn the question: a full week, a month, a hundred
/// days. Days GameConstants.streakBonuses already celebrates.
const Set<int> kRatingStreakMilestones = {7, 30, 100};

/// How long this phone has to have had the app before the first question.
const Duration kRatingFirstAskAfter = Duration(days: 7);

/// The least time between two questions from this app.
const Duration kRatingAskGap = Duration(days: 120);

/// The wait after the milestone, so the tap's own feedback lands first.
const Duration kRatingAskDelay = Duration(seconds: 3);

/// Settings map: `{firstSeen, lastAsked, asks}`, on this phone.
const String kRatingPromptKey = 'rating_prompt_v1';

/// Whether a streak that went from [from] to [to] is the moment to ask:
/// one step up, onto a milestone. A step, not a value: a streak read back
/// at launch or after a refresh jumps from 0 to where it was, and that is
/// nobody reaching anything.
bool streakEarnsRatingAsk({required int from, required int to}) =>
    to == from + 1 && kRatingStreakMilestones.contains(to);

/// Whether this phone may ask at [now].
bool mayAskForRating({
  required DateTime now,
  required DateTime firstSeen,
  DateTime? lastAsked,
}) {
  if (now.difference(firstSeen) < kRatingFirstAskAfter) return false;
  if (lastAsked != null && now.difference(lastAsked) < kRatingAskGap) {
    return false;
  }
  return true;
}

class RatingPrompt {
  RatingPrompt._();

  /// Stands in for the store's own request in tests.
  @visibleForTesting
  static Future<void> Function()? requestOverride;

  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  /// Stamps the first day this phone ran a build that asks, which is what
  /// [kRatingFirstAskAfter] counts from. Called at launch; a no-op after
  /// the first time.
  static Future<void> noteFirstSeen() async {
    if (kIsWeb) return;
    try {
      final data = await LocalStoreService.getSettingsMap(kRatingPromptKey);
      if (data['firstSeen'] is String) return;
      await LocalStoreService.putSettingsMap(kRatingPromptKey, {
        ...data,
        'firstSeen': clock().toIso8601String(),
      });
    } catch (_) {}
  }

  /// Asks, after a streak went from [from] to [to], when every rule above
  /// allows it. Returns whether it asked the OS (which may still not show
  /// anything).
  static Future<bool> maybeAskAfterStreak({
    required int from,
    required int to,
  }) async {
    if (kIsWeb || !streakEarnsRatingAsk(from: from, to: to)) return false;
    try {
      final data = await LocalStoreService.getSettingsMap(kRatingPromptKey);
      final now = clock();
      final firstSeen = DateTime.tryParse('${data['firstSeen']}');
      if (firstSeen == null) {
        // A phone with no stamp yet has had the app for no time at all.
        await noteFirstSeen();
        return false;
      }
      final lastAsked = DateTime.tryParse('${data['lastAsked']}');
      if (!mayAskForRating(
        now: now,
        firstSeen: firstSeen,
        lastAsked: lastAsked,
      )) {
        return false;
      }
      final request = requestOverride;
      if (request == null && !await InAppReview.instance.isAvailable()) {
        return false;
      }
      // Stamped before asking: a question the OS chose not to show still
      // counts, or a phone past Apple's yearly cap would be asked again at
      // every milestone.
      await LocalStoreService.putSettingsMap(kRatingPromptKey, {
        ...data,
        'lastAsked': now.toIso8601String(),
        'asks': ((data['asks'] as num?)?.toInt() ?? 0) + 1,
      });
      AnalyticsService.instance
          .track('rating_prompt_requested', props: {'streak': to});
      await (request?.call() ?? InAppReview.instance.requestReview());
      return true;
    } catch (_) {
      return false;
    }
  }
}

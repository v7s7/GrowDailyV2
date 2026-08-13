import 'dart:async' show unawaited;

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Thin wrapper around [FirebaseAnalytics] — every call site elsewhere in
/// this app (auth, premium, habit completion, streak freeze, comeback
/// bonus, ...) already calls [track] at exactly the right moments; this
/// class used to just `debugPrint` the event and throw it away, which meant
/// none of that ever reached anywhere a real retention/funnel/feature-usage
/// question could be answered from it. Kept as one wrapper (rather than
/// every call site touching `FirebaseAnalytics.instance` directly) for two
/// reasons: one place to coerce values into whatever types Firebase
/// Analytics parameters actually accept (see [_sanitizeValue] — several
/// existing call sites pass bools, which `logEvent` itself would reject),
/// and one place to swap providers later without touching a dozen call
/// sites across five features.
class AnalyticsService {
  AnalyticsService._();
  static final instance = AnalyticsService._();

  FirebaseAnalytics get _analytics => FirebaseAnalytics.instance;

  /// Logs [event] with [props], best-effort. Deliberately still a plain
  /// `void` method, not `Future<void>` — every one of the dozen existing
  /// call sites invokes this as a bare, un-awaited statement (an
  /// intentional fire-and-forget: a tracking call must never be what a
  /// real user-facing action — completing a habit, buying Premium — waits
  /// on or fails because of), and this project's analysis_options.yaml
  /// enables `unawaited_futures`, so changing this to return a `Future`
  /// would put a new lint warning on every single call site instead of
  /// just here. The real `logEvent` call happens beneath that synchronous
  /// signature and is awaited internally so its errors land in the
  /// `catchError` below rather than as an unhandled Future rejection.
  void track(String event, {Map<String, Object?> props = const {}}) {
    final sanitized = <String, Object>{};
    props.forEach((key, value) {
      final v = _sanitizeValue(value);
      if (v != null) sanitized[key] = v;
    });
    try {
      final future = _analytics.logEvent(
        name: event,
        parameters: sanitized.isEmpty ? null : sanitized,
      );
      unawaited(future.catchError((Object e, StackTrace st) {
        _recordFailure(
            e, st, 'AnalyticsService.track failed for event "$event"');
      }));
    } catch (e, st) {
      _recordFailure(e, st, 'AnalyticsService.track failed for event "$event"');
    }
  }

  void _recordFailure(Object error, StackTrace stackTrace, String reason) {
    // Firebase plugins are deliberately unavailable in unit tests and can
    // also be unavailable during an early-startup failure. Analytics must
    // remain strictly best-effort in both cases.
    try {
      FirebaseCrashlytics.instance.recordError(
        error,
        stackTrace,
        reason: reason,
      );
    } catch (_) {
      // There is no initialized Firebase app to report to.
    }
    if (kDebugMode) {
      debugPrint('[Analytics] $reason: $error');
    }
  }

  /// Firebase Analytics event parameters only accept String/int/double —
  /// not bool, not null, not arbitrary objects (an assertion `logEvent`
  /// itself enforces). Real call sites pass bools directly today (e.g.
  /// DashboardNotifier's `habit_completed` event carries
  /// `allHabitsDoneAfter`/`streakJustEarned`), which would otherwise throw
  /// on every single completion. Bools become 1/0 (not the strings
  /// "true"/"false") so they stay usable as a numeric filter/breakdown in
  /// the Firebase console; an [Enum] logs its [Enum.name]; anything else
  /// unrecognized falls back to [Object.toString] rather than dropping the
  /// whole event over one bad field.
  Object? _sanitizeValue(Object? value) {
    if (value == null) return null;
    if (value is String || value is int || value is double) return value;
    if (value is bool) return value ? 1 : 0;
    if (value is Enum) return value.name;
    return value.toString();
  }

  /// Ties this device's analytics history to the signed-in account instead
  /// of leaving every session anonymous — same idea as
  /// `PurchaseService.logIn` linking RevenueCat's identity, called from the
  /// same authStateProvider listener in main.dart right alongside it. Only
  /// ever meaningfully changes retention/funnel analysis (which sessions
  /// belong to the same real person across devices/reinstalls); it doesn't
  /// gate or affect anything the app does.
  void setUserId(String? uid) {
    final future = _analytics.setUserId(id: uid);
    unawaited(future.catchError((Object e, StackTrace st) {
      FirebaseCrashlytics.instance.recordError(
        e,
        st,
        reason: 'AnalyticsService.setUserId failed',
      );
    }));
  }
}

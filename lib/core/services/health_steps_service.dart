import 'dart:io';

import 'package:health/health.dart';

/// Why [HealthStepsService] could not produce a step count — every case the
/// caller shows some explanation for, mirroring [DeviceLocationFailure].
enum HealthStepsFailure {
  /// Android without the Health Connect app installed (or an SDK too old to
  /// carry it). iOS never returns this: HealthKit ships with the OS.
  notSupported,

  /// The platform will not hand over steps: the person declined the
  /// permission sheet, revoked it later, or Health Connect auto-revoked it
  /// after a month of the app going unused.
  ///
  /// Android reaches this from a read as well as from [requestPermission],
  /// because Health Connect fails the query outright when the permission is
  /// gone. iOS reaches it only from [requestPermission] and even then only
  /// rarely: a *read* denial there is indistinguishable from "no data" by
  /// design, since HealthKit hides read grants from apps.
  permissionDenied,

  /// Platform-channel failure, or the platform returned nothing.
  unavailable,
}

/// Outcome of a steps read — the app's established "never throw, return a
/// typed result" shape (see DeviceLocationOutcome, PurchaseOutcome).
class HealthStepsOutcome {
  final int? steps;
  final HealthStepsFailure? failure;

  const HealthStepsOutcome._({this.steps, this.failure});

  factory HealthStepsOutcome.success(int steps) =>
      HealthStepsOutcome._(steps: steps);

  factory HealthStepsOutcome.failed(HealthStepsFailure reason) =>
      HealthStepsOutcome._(failure: reason);

  bool get isSuccess => steps != null;
}

/// Read-only bridge to the platform step counter: Apple Health on iOS
/// (which already aggregates iPhone and Apple Watch, deduplicated by the
/// OS), Health Connect on Android. One data type (STEPS), one permission
/// (READ), no writes — the narrowest possible surface, matching what the
/// Info.plist / Play Data safety declarations promise.
///
/// Used by the walking-habit link (see step_habit_detector.dart for how a
/// habit becomes linkable, and stepsTodayProvider for the polling side).
class HealthStepsService {
  HealthStepsService._();
  static final instance = HealthStepsService._();

  final Health _health = Health();
  bool _configured = false;

  static const _types = [HealthDataType.STEPS];
  static const _permissions = [HealthDataAccess.READ];

  /// Which store is behind the link, for the copy that has to name it.
  ///
  /// The two platforms fail in different ways and the person has to be sent
  /// to different places, so the strings cannot be one wording. Exposed here
  /// rather than letting each surface reach for dart:io, so there is one
  /// answer to "is this the Health Connect side" in the whole app.
  static bool get usesHealthConnect => Platform.isAndroid;

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  /// Whether this device can supply steps at all. iOS: always. Android:
  /// only with the Health Connect app present (preinstalled on 14+, a Play
  /// download on older versions).
  Future<bool> isSupported() async {
    try {
      await _ensureConfigured();
      if (!Platform.isAndroid) return true;
      return await _health.isHealthConnectAvailable();
    } catch (_) {
      return false;
    }
  }

  /// Whether the platform will actually hand over steps right now.
  ///
  /// Android answers truthfully: Health Connect exposes the granted set, and
  /// the plugin checks membership against it, so this catches a permission
  /// the person revoked later or that Health Connect auto-revoked after a
  /// month of the app going unused.
  ///
  /// iOS returns null, meaning "unknowable", and callers must treat it that
  /// way rather than as a no. HealthKit hides read grants from apps by
  /// design — `authorizationStatus` reports the *write* side only, and the
  /// plugin's iOS branch returns nil for every READ permission it is asked
  /// about. There is no workaround; see [stepsForDay] for what the app does
  /// with that instead.
  Future<bool?> hasReadPermission() async {
    try {
      await _ensureConfigured();
      if (Platform.isAndroid && !await _health.isHealthConnectAvailable()) {
        return false;
      }
      return await _health.hasPermissions(_types, permissions: _permissions);
    } catch (_) {
      return null;
    }
  }

  /// Shows the platform permission sheet for read-only steps. Returns true
  /// when the user granted it. Safe to call again after a denial: iOS shows
  /// its sheet only once (later calls are a silent no), Android may ask
  /// again. Callers treat false as "link stays off", never as an error.
  ///
  /// Truthful on Android, where the plugin reports the permission sheet's
  /// actual answer. NOT truthful on iOS: HKHealthStore's success flag means
  /// "the sheet was presented and dismissed", not "granted", so this returns
  /// true even for a person who tapped Don't Allow. Nothing can be done
  /// about that here, which is why [stepsForDay]'s zero has to be explained
  /// to the person rather than treated as a fact about their day.
  Future<bool> requestPermission() async {
    try {
      await _ensureConfigured();
      return await _health.requestAuthorization(
        _types,
        permissions: _permissions,
      );
    } catch (_) {
      return false;
    }
  }

  /// The step total for the calendar day containing [day] (midnight to
  /// midnight). Callers pass the app's *effective* day, not the clock day:
  /// in the after-midnight window (see DateTimeGameExt.effectiveDay) the
  /// habit-day still in progress is yesterday's, and yesterday's habit
  /// must be judged against yesterday's steps — the platform's counter
  /// resets at calendar midnight, so reading "midnight to now" there
  /// would grade Tuesday's walk against Wednesday's near-zero (verified
  /// live at 12:23 AM before this took the day parameter).
  ///
  /// Manual entries count, same as sensor-recorded ones. Excluding them
  /// was considered as anti-cheat and rejected: tapping the habit square
  /// is already a one-tap way to "cheat" a habit app, so filtering the
  /// Health side protects nothing, while honestly-logged walks (phone
  /// left at home) and the number the person sees in the Health app both
  /// stop matching what this returns.
  ///
  /// On iOS a zero can mean "read permission denied" just as well as "no
  /// steps yet" (Apple hides which), so it resolves to a zero-step success
  /// here and the surfaces that show it say so in words rather than
  /// asserting a cause they cannot know. Android has no such excuse and
  /// reports the refusal properly — see the branch below.
  Future<HealthStepsOutcome> stepsForDay(DateTime day) async {
    try {
      await _ensureConfigured();
      if (Platform.isAndroid && !await _health.isHealthConnectAvailable()) {
        return HealthStepsOutcome.failed(HealthStepsFailure.notSupported);
      }
      // Both ends built from the calendar, not by adding 24 hours to the
      // first. On the two days a year a DST zone shifts, a day is 23 or 25
      // hours long, so `start + 1 day` lands an hour inside the next day or
      // an hour short of the end of this one: an hour of somebody else's
      // steps counted, or an hour of their own thrown away, on the one day
      // they would have no way to explain it. DateTime(y, m, d + 1) is the
      // next local midnight whatever the offset does, and it rolls months
      // and years over by itself.
      final start = DateTime(day.year, day.month, day.day);
      final end = DateTime(day.year, day.month, day.day + 1);
      final steps = await _health.getTotalStepsInInterval(start, end);
      // A null means two different things on the two platforms, and
      // flattening both to zero was hiding a real failure on one of them.
      //
      // Android: the plugin's aggregate call returns null ONLY from its own
      // catch block — a genuine empty day comes back as 0, not null. So a
      // null here is Health Connect refusing (the commonest cause being a
      // permission the person revoked, or the automatic revoke after a month
      // of not opening the app), and reporting it as "you walked 0 steps" put
      // a false statement about someone's day on their board.
      //
      // iOS: never null. HealthKit's statistics query returns a sum, and a
      // denied read returns an empty set summing to zero — indistinguishable
      // from a day that has not started yet, by Apple's design. So zero
      // stands as a success there and the UI explains itself instead.
      if (steps == null && Platform.isAndroid) {
        return HealthStepsOutcome.failed(HealthStepsFailure.permissionDenied);
      }
      return HealthStepsOutcome.success(steps ?? 0);
    } catch (_) {
      return HealthStepsOutcome.failed(HealthStepsFailure.unavailable);
    }
  }
}

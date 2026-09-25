import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart' show Geolocator, LocationPermission;

import '../../../core/l10n/app_strings.dart';
import '../../../core/l10n/wording_edits.dart' show WordingEditsStore;
import '../../../core/services/device_location_service.dart';
import '../../../core/services/home_widget_service.dart';
import '../../../core/services/local_store_service.dart';
import '../../habits/models/habit_cue.dart';
import '../../habits/notifiers/custom_habits_notifier.dart'
    show habitListProvider;
import '../models/notification_settings.dart';
import 'notification_settings_notifier.dart';

/// How far the phone must be from the saved place before the place moves.
/// A prayer time shifts about a minute for every 25 km east or west, so
/// under 10 km nothing anyone could see changes, and a fix that wobbles
/// inside one city never rewrites the place.
const kPrayerPlaceMoveMeters = 10000.0;

/// How long after one look at the phone's location the next may be taken,
/// when a place is already saved. Coming back to the app every few minutes
/// is normal; checking where the phone is each time is not needed.
const _recheckEvery = Duration(minutes: 30);

/// Set once the system prompt has been shown from here. iOS only ever
/// shows it once anyway; Android would show it again after one "deny", and
/// nobody should be asked on every app open.
const _kAskedKey = 'prayer_place_auto_asked_v1';

/// What one run of [autoLocatePrayerPlace] does.
enum AutoLocateStep {
  /// Nothing. No prayer feature needs a place, the place was picked by
  /// hand, or the location cannot be read without asking and asking is not
  /// warranted.
  stay,

  /// Read the phone's location, which is already allowed.
  locate,

  /// Ask for location access first, then read it.
  askThenLocate,
}

/// The decision, from what is known before touching the location at all.
/// Pure, so every branch is a unit test.
@visibleForTesting
AutoLocateStep autoLocateStep({
  required NotificationLocation? saved,
  required LocationPermission permission,
  required bool needed,
  required bool askedBefore,
}) {
  if (!needed) return AutoLocateStep.stay;
  if (saved?.auto == false) return AutoLocateStep.stay;
  if (permission == LocationPermission.whileInUse ||
      permission == LocationPermission.always) {
    // A place saved before `auto` existed (null) moves too: granting
    // access was the only way one got saved without a search.
    return AutoLocateStep.locate;
  }
  // `denied` is also how iOS reports "never asked", and it is the only
  // state the system prompt can still be shown from. Only for a feature
  // with no place at all: a saved one keeps working as it is.
  if (saved == null &&
      !askedBefore &&
      permission == LocationPermission.denied) {
    return AutoLocateStep.askThenLocate;
  }
  return AutoLocateStep.stay;
}

/// Whether a fix at [lat],[lng] should replace [saved].
@visibleForTesting
bool prayerPlaceMoved(NotificationLocation? saved, double lat, double lng) =>
    saved == null ||
    Geolocator.distanceBetween(saved.lat, saved.lng, lat, lng) >=
        kPrayerPlaceMoveMeters;

/// Stands in for [HomeWidgetService.hasPrayerWidget] in tests, which have
/// no WidgetKit. Null in the app.
@visibleForTesting
Future<bool> Function()? debugPrayerWidgetPlaced;

bool _running = false;
DateTime? _lastLookAt;

/// Forgets the last look and any run in flight. Tests only.
@visibleForTesting
void resetAutoLocatePrayerPlace() {
  _running = false;
  _lastLookAt = null;
}

/// The prayer place, found by the phone whenever something needs it.
///
/// Until 2026-09-25 a location was only ever set by a person: a tap on the
/// row in Settings, or the prompt Add Habit shows when a prayer cue is
/// picked with none saved. Two things went wrong because of that. A
/// prayer widget added to the Home Screen said «حدّد موقعك» and waited,
/// since placing a widget never asked for anything; and a saved place
/// never moved, so someone who travelled kept the old city's prayers on
/// the widget and in every reminder. Aziz: "make the location detect fast
/// in any needs".
///
/// So this runs when the app comes up and each time it comes back from the
/// background (main.dart), and on each run:
///  1. Stops unless a prayer feature needs a place: a prayer widget is
///     placed, or a habit is tied to a prayer.
///  2. Stops if the saved place was picked by hand ([NotificationLocation.
///     auto] false). That was a choice, and a tap on the row is the way
///     back to automatic.
///  3. With location access already granted, reads the phone's location
///     ([DeviceLocationService.detect], usually instant) and saves it when
///     nothing is saved or the saved place is [kPrayerPlaceMoveMeters] or
///     more away.
///  4. With nothing saved and access never asked for, asks once per
///     install. That is the moment a widget or a prayer habit is waiting
///     on it, so the system prompt arrives with its reason in view.
///
/// Everything a new place changes follows from the one settings write:
/// main.dart's settings listener re-arms the reminders and pushes the
/// widget a fresh week (PrayerWidgetFeed), so a widget placed a minute ago
/// counts to the right prayer as soon as the app has been opened once.
///
/// What it cannot do: move the place while the app stays closed. A widget
/// cannot read the location itself without computing prayer times itself,
/// which it deliberately never does (see PrayerWidgetFeed), and watching
/// the location in the background would need "Always" access.
///
/// Never throws, and a second call while one is running is dropped.
///
/// [now] is for tests, which need the [_recheckEvery] spacing without
/// waiting half an hour.
Future<void> autoLocatePrayerPlace(ProviderRead read, {DateTime? now}) async {
  if (kIsWeb || _running) return;
  _running = true;
  try {
    // Never inside the frame that called it: main.dart calls this from
    // listeners, and a first read below can be what creates a provider.
    await Future<void>.delayed(Duration.zero);
    await read(notificationSettingsProvider.notifier).settled;

    final at = now ?? DateTime.now();
    final saved = read(notificationSettingsProvider).location;
    final lastLook = _lastLookAt;
    if (saved != null &&
        lastLook != null &&
        at.difference(lastLook) < _recheckEvery) {
      return;
    }

    final step = autoLocateStep(
      saved: saved,
      permission: await DeviceLocationService.permission(),
      needed: await _prayerPlaceNeeded(read),
      askedBefore: await _askedBefore(),
    );
    if (step == AutoLocateStep.stay) return;
    if (step == AutoLocateStep.askThenLocate) await _markAsked();

    _lastLookAt = at;
    final outcome = await DeviceLocationService.detect(
      mayAsk: step == AutoLocateStep.askThenLocate,
    );
    if (!outcome.isSuccess) return;
    final fix = outcome.fix!;

    // Read again: a city may have been picked by hand while the fix came.
    final current = read(notificationSettingsProvider).location;
    if (current?.auto == false) return;
    if (!prayerPlaceMoved(current, fix.latitude, fix.longitude)) return;

    final s = S.edited(read(localeProvider), WordingEditsStore.current);
    await savePhoneLocation(
      read,
      fix,
      isAr: s.isAr,
      resolvingLabel: s.notifLocationResolving,
      genericLabel: s.notifLocationSetGeneric,
    );
  } catch (e) {
    // The place stays as it was, and the next resume tries again.
    debugPrint('[autoLocatePrayerPlace] skipped: $e');
  } finally {
    _running = false;
  }
}

/// A prayer widget placed, or any habit tied to one of the five prayers.
Future<bool> _prayerPlaceNeeded(ProviderRead read) async {
  final habits = read(habitListProvider);
  if (habits.any((h) => HabitCue.fromStoredValue(h.cueAfter).isPrayer)) {
    return true;
  }
  final placed = debugPrayerWidgetPlaced;
  if (placed != null) return placed();
  return HomeWidgetService.instance.hasPrayerWidget();
}

Future<bool> _askedBefore() async {
  try {
    final box = await LocalStoreService.settingsBox();
    return box.get(_kAskedKey) == true;
  } catch (_) {
    // Unreadable reads as asked: better to miss one prompt than to repeat
    // it on every open.
    return true;
  }
}

Future<void> _markAsked() async {
  try {
    final box = await LocalStoreService.settingsBox();
    await box.put(_kAskedKey, true);
  } catch (_) {}
}

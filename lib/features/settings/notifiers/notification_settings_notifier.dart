import 'dart:async' show unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/country_lookup_service.dart';
import '../../../core/services/device_location_service.dart';
import '../../../core/services/local_store_service.dart';
import '../models/notification_settings.dart';

const _kSettingsKey = 'notification_settings_v1';

/// Owns [NotificationSettings] — every toggle/time/location the
/// Notifications settings screen edits, persisted device-locally (Hive,
/// works for guests too) and mirrored to Firestore for signed-in accounts.
/// Structured identically to ReminderTimeNotifier (habit_plans.dart):
/// synchronous-looking construction backed by an async `_load()`,
/// `pullFromAccount`/`detachAccount` for the sign-in/sign-out lifecycle,
/// device-local value always wins over the account's on first load.
///
/// Kept as a single blob (one Hive key, one Firestore field) rather than
/// one provider per toggle: every mutation here goes through [_persist],
/// which is also the one place that re-triggers NotificationService's
/// scheduling — so every setting change (including ones made while
/// offline) reliably reaches the actual scheduled notifications through
/// the same path main.dart's reactive listener already uses, with nothing
/// bypassing it.
class NotificationSettingsNotifier extends StateNotifier<NotificationSettings> {
  NotificationSettingsNotifier() : super(const NotificationSettings()) {
    _loadFuture = _load();
  }

  String? _uid;
  late final Future<void> _loadFuture;

  // Whether this device had its own saved settings already, the moment
  // _load() ran — distinct from `state` itself (which is never null, it's
  // always at least the all-defaults instance) so pullFromAccount has an
  // honest way to ask "should an account value overwrite this?" the same
  // way ReminderTimeNotifier asks `state != null`.
  bool _hasLocalValue = false;

  Future<void> _load() async {
    final map = await LocalStoreService.getSettingsMap(_kSettingsKey);
    if (map.isNotEmpty) {
      _hasLocalValue = true;
      if (mounted) state = NotificationSettings.fromMap(map);
    }
  }

  Future<void> _persist(NotificationSettings next) async {
    state = next;
    _hasLocalValue = true;
    await LocalStoreService.putSettingsMap(_kSettingsKey, next.toMap());
    if (_uid != null) {
      FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .set({'notificationSettings': next.toMap()}, SetOptions(merge: true))
          .catchError((_) {});
    }
  }

  /// General-purpose mutator — every Settings screen row calls this with a
  /// small closure, e.g. `update((s) => s.copyWith(masterEnabled: v))`.
  /// Awaiting the returned future is only needed where the caller shows a
  /// result (e.g. a permission-denied snackbar); most rows fire-and-forget
  /// since `state` (and the Switch/row bound to it) already updates
  /// synchronously via the `state = next` inside [_persist].
  Future<void> update(
    NotificationSettings Function(NotificationSettings current) mutator,
  ) =>
      _persist(mutator(state));

  /// Called once a signed-in uid is known (mirrors ReminderTimeNotifier.
  /// pullFromAccount exactly) — only pulls the account's saved settings
  /// when this device doesn't already have its own, and never on its own
  /// triggers a permission prompt or reschedule; the reactive listener that
  /// watches this provider picks up the new state and reschedules through
  /// the normal path.
  Future<void> pullFromAccount(String uid) async {
    _uid = uid;
    await _loadFuture;
    if (_hasLocalValue) return;
    try {
      final snap =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final saved = snap.data()?['notificationSettings'];
      if (saved is! Map) return;
      final map = LocalStoreService.asStringMap(saved);
      if (map.isEmpty || !mounted) return;
      state = NotificationSettings.fromMap(map);
      _hasLocalValue = true;
      await LocalStoreService.putSettingsMap(_kSettingsKey, map);
    } catch (_) {
      // No saved settings for this account yet, or offline — device-local
      // defaults keep applying, same as a guest.
    }
  }

  /// Signed out — future updates go back to being device-local only, same
  /// as ReminderTimeNotifier.detachAccount.
  void detachAccount() => _uid = null;
}

final notificationSettingsProvider = StateNotifierProvider<
    NotificationSettingsNotifier, NotificationSettings>(
  (_) => NotificationSettingsNotifier(),
);

/// One-shot "ask, don't send them digging through Settings" location setup —
/// the exact GPS-detect-then-resolve-in-the-background flow
/// NotificationSettingsScreen's own location row already used, factored out
/// here so any other screen can trigger the same real permission prompt +
/// save inline instead of just telling someone to go set it manually
/// elsewhere. First real use: AddHabitSheet, the moment someone picks a
/// prayer-linked cue with no location saved yet — previously that just
/// showed a small "go set your location in Settings" line and left the
/// habit's reminder silently unscheduled if they didn't act on it.
///
/// Never throws — mirrors [DeviceLocationService.detect]'s own "always a
/// typed result" contract, so the caller decides what (if anything) to show
/// on a denied/unavailable outcome. [isMounted] is checked before every
/// post-`await` use of [ref] (same guard NotificationSettingsScreen's own
/// State.mounted provided) since this can be called from any widget whose
/// lifetime doesn't match this function's — a modal sheet the user closes
/// mid-detect being the obvious case.
Future<DeviceLocationOutcome> detectAndSaveLocation(
  WidgetRef ref, {
  required bool isAr,
  required String resolvingLabel,
  required String genericLabel,
  required bool Function() isMounted,
}) async {
  final outcome = await DeviceLocationService.detect();
  if (!outcome.isSuccess || !isMounted()) return outcome;

  final fix = outcome.fix!;
  await ref.read(notificationSettingsProvider.notifier).update((c) => c.copyWith(
        location: NotificationLocation(
          lat: fix.latitude,
          lng: fix.longitude,
          label: resolvingLabel,
        ),
      ));

  // Fire-and-forget: the location itself is already set and usable (every
  // caller needs is the lat/lng, available the instant the block above
  // returns) — the nicer place-name label and country code are a
  // background upgrade, not something worth making anyone wait on a second
  // network round trip for.
  unawaited(() async {
    final place = await CountryLookupService.lookupPlace(
      fix.latitude,
      fix.longitude,
      languageCode: isAr ? 'ar' : 'en',
    );
    if (!isMounted()) return;
    final current = ref.read(notificationSettingsProvider).location;
    // Guards the exact same race NotificationSettingsScreen's own
    // background resolution does: don't let a slow lookup from this fix
    // clobber a newer location someone's since set another way.
    if (current == null ||
        current.lat != fix.latitude ||
        current.lng != fix.longitude) {
      return;
    }
    await ref.read(notificationSettingsProvider.notifier).update((c) => c.copyWith(
          resolvedCountryCode: place.code ?? c.resolvedCountryCode,
          location: NotificationLocation(
            lat: fix.latitude,
            lng: fix.longitude,
            label: place.label ?? genericLabel,
          ),
        ));
  }());

  return outcome;
}

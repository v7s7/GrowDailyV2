import 'dart:async' show unawaited;
import 'dart:convert' show jsonEncode;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/country_lookup_service.dart';
import '../../../core/services/device_location_service.dart';
import '../../../core/services/local_store_service.dart';
import '../models/notification_settings.dart';

const _kSettingsKey = 'notification_settings_v1';

/// What [NotificationSettingsNotifier._mirrorUp] last put on an account from
/// this device: `uid|settings as JSON`. See that method.
const _kMirroredKey = 'notification_settings_mirrored_v1';

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
  NotificationSettingsNotifier({FirebaseFirestore? firestore})
      : _firestore = firestore,
        super(const NotificationSettings()) {
    _loadFuture = _load();
  }

  /// A test's stand-in; the real project otherwise.
  final FirebaseFirestore? _firestore;
  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

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
      _db
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

  /// Completes once this device's own saved settings are in [state]. Until
  /// then [state] is the all-defaults placeholder, whose null location
  /// means "not read yet", not "this person has none": anything that acts
  /// on a missing location (the prayer widget's feed) waits for this.
  Future<void> get loaded => _loadFuture;

  /// The latest [pullFromAccount], so [settled] can wait for it.
  Future<void>? _pullFuture;

  /// Completes once this device's saved settings are loaded and any
  /// account pull already started has landed.
  ///
  /// autoLocatePrayerPlace waits on this before it writes a place. A save
  /// that lands while a pull is still reading would go up to the account
  /// as this device's defaults plus the place, over the account's own
  /// settings, and the pull would then put the old ones back on this
  /// device only.
  Future<void> get settled async {
    await loaded;
    final pull = _pullFuture;
    if (pull != null) await pull;
  }

  /// Called once a signed-in uid is known (mirrors ReminderTimeNotifier.
  /// pullFromAccount exactly) — only pulls the account's saved settings
  /// when this device doesn't already have its own, and never on its own
  /// triggers a permission prompt or reschedule; the reactive listener that
  /// watches this provider picks up the new state and reschedules through
  /// the normal path.
  Future<void> pullFromAccount(String uid) =>
      _pullFuture = _pullFromAccount(uid);

  Future<void> _pullFromAccount(String uid) async {
    _uid = uid;
    await _loadFuture;
    if (_hasLocalValue) {
      await _mirrorUp(uid);
      return;
    }
    try {
      final snap = await _db.collection('users').doc(uid).get();
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

  /// Puts this device's own settings on the account when the account may
  /// not have them.
  ///
  /// The account's copy is what the server reads to decide whether a push
  /// may reach this person at all: the room pushes (functions/push_policy.js)
  /// and the admin's message to everyone (scripts/admin_lookup's Messages
  /// page) both skip someone whose all-notifications switch is off, and
  /// hold back in their quiet hours. [_persist] writes it only for a change
  /// made while signed in, so settings saved as a guest, while signed out,
  /// or on a build before this existed never reached it, and a person who
  /// had switched notifications off could still be sent one.
  ///
  /// Written once per account per device, then again only after a change,
  /// never on every launch: a marker in the settings box remembers what went
  /// up. A failed write leaves the marker alone, so the next sign-in tries
  /// again.
  Future<void> _mirrorUp(String uid) async {
    final settings = state.toMap();
    final marker = '$uid|${jsonEncode(settings)}';
    try {
      final box = await LocalStoreService.settingsBox();
      if (box.get(_kMirroredKey) == marker) return;
      await _db
          .collection('users')
          .doc(uid)
          .set({'notificationSettings': settings}, SetOptions(merge: true));
      await box.put(_kMirroredKey, marker);
    } catch (_) {
      // Offline, or no Firebase at all (unit tests): the account keeps what
      // it had until the next sign-in or change.
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

  await savePhoneLocation(
    ref.read,
    outcome.fix!,
    isAr: isAr,
    resolvingLabel: resolvingLabel,
    genericLabel: genericLabel,
    isMounted: isMounted,
  );
  return outcome;
}

/// A provider read, from a widget's ref or the app's own container alike,
/// so the same save can run from a sheet and from app start.
typedef ProviderRead = T Function<T>(ProviderListenable<T> provider);

/// Saves [fix] as the phone's own location (`auto: true`, so the app keeps
/// it current), then upgrades its label to the real place name and fills
/// in the country code in the background.
///
/// The place is usable the instant the first write lands: every caller
/// needs only the lat/lng, and the nicer «المنامة، البحرين» label and the
/// country code are a background upgrade, not something worth making
/// anyone wait on a second network round trip for.
///
/// A place that MOVES (one was saved before) drops the old country code in
/// that same first write. Outside the Gulf the method comes from the code,
/// so Riyadh's code on a Cairo fix would compute Cairo with Saudi rules
/// for as long as the lookup takes, and for good if it fails offline;
/// with no code the coordinates' own region applies until the new one
/// lands.
///
/// [isMounted], when given, is checked after every await: a sheet the user
/// closes mid-lookup has taken its ref with it.
Future<void> savePhoneLocation(
  ProviderRead read,
  DeviceLocationFix fix, {
  required bool isAr,
  required String resolvingLabel,
  required String genericLabel,
  bool Function()? isMounted,
}) async {
  bool alive() => isMounted?.call() ?? true;
  final notifier = read(notificationSettingsProvider.notifier);
  await notifier.update((c) {
    final base = c.location == null ? c : c.copyWith(clearLocation: true);
    return base.copyWith(
      location: NotificationLocation(
        lat: fix.latitude,
        lng: fix.longitude,
        label: resolvingLabel,
        auto: true,
      ),
    );
  });

  unawaited(() async {
    final place = await CountryLookupService.lookupPlace(
      fix.latitude,
      fix.longitude,
      languageCode: isAr ? 'ar' : 'en',
    );
    if (!alive() || !notifier.mounted) return;
    final current = read(notificationSettingsProvider).location;
    // Don't let a slow lookup from this fix clobber a newer location
    // someone's since set another way.
    if (current == null ||
        current.lat != fix.latitude ||
        current.lng != fix.longitude) {
      return;
    }
    await notifier.update((c) => c.copyWith(
          resolvedCountryCode: place.code ?? c.resolvedCountryCode,
          location: NotificationLocation(
            lat: fix.latitude,
            lng: fix.longitude,
            label: place.label ?? genericLabel,
            auto: true,
          ),
        ));
  }());
}

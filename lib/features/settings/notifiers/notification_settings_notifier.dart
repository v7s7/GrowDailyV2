import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

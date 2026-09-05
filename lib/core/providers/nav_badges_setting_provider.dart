import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/local_store_service.dart';

const _kNavBadgesKey = 'nav_badges_enabled_v1';
const _kNavBadgesField = 'navBadges';

/// Whether the bottom bar draws its badges (see navBadgesProvider).
///
/// On by default, because a badge that only ever means "this needs you"
/// is worth having. Off is for the person who finds any mark on the bar
/// a nag, and it is FREE: turning a thing off is never the paid part.
/// Lives in the customiser under the preview, where the switch and the
/// thing it changes sit together.
///
/// Same persistence shape as NavLayoutNotifier: instant on this device
/// (Hive, seeded at boot), mirrored to the account (`navBadges` on the user
/// document) so a second device catches up on sign-in. Only "off" is ever
/// worth a field; on is the default and Reset-like, so switching back on
/// deletes it rather than writing `true`.
class NavBadgesSettingNotifier extends StateNotifier<bool> {
  NavBadgesSettingNotifier([bool initial = true]) : super(initial);

  String? _uid;

  Future<void> set(bool enabled) async {
    state = enabled;
    try {
      final box = await LocalStoreService.settingsBox();
      if (enabled) {
        await box.delete(_kNavBadgesKey);
      } else {
        await box.put(_kNavBadgesKey, false);
      }
    } catch (_) {}
    if (_uid != null) {
      FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .set({
            _kNavBadgesField: enabled ? FieldValue.delete() : false,
          }, SetOptions(merge: true))
          .catchError((_) {});
    }
  }

  /// The account's saved choice wins over this device's, same as the
  /// layout: this device is the one catching up. Nothing saved means on.
  Future<void> pullFromAccount(String uid) async {
    _uid = uid;
    try {
      final snap =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final saved = snap.data()?[_kNavBadgesField];
      final enabled = saved is bool ? saved : true;
      if (!mounted || enabled == state) return;
      state = enabled;
      final box = await LocalStoreService.settingsBox();
      if (enabled) {
        await box.delete(_kNavBadgesKey);
      } else {
        await box.put(_kNavBadgesKey, false);
      }
    } catch (_) {}
  }

  /// Sign-out: back to the default for whoever signs in next, without
  /// touching the account.
  Future<void> detachAccount() async {
    _uid = null;
    if (state) return;
    state = true;
    try {
      final box = await LocalStoreService.settingsBox();
      await box.delete(_kNavBadgesKey);
    } catch (_) {}
  }
}

final navBadgesEnabledProvider =
    StateNotifierProvider<NavBadgesSettingNotifier, bool>(
        (ref) => NavBadgesSettingNotifier());

/// For main.dart's boot overrides: the first frame draws the bar without
/// badges for someone who switched them off, instead of flashing them.
Future<bool> loadPersistedNavBadgesEnabled() async {
  try {
    final box = await LocalStoreService.settingsBox();
    return box.get(_kNavBadgesKey) as bool? ?? true;
  } catch (_) {
    return true;
  }
}

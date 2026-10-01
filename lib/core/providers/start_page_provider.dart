import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/local_store_service.dart';
import 'nav_layout_provider.dart' show NavTab;

const _kStartPageKey = 'start_page_v1';
const _kStartPageField = 'startPage';

/// The page the app opens on: Habits (the default, as it always was) or
/// Tasks. Aziz, 2026-09-30: someone who lives in their task list should not
/// have to swipe past the habit board every time they open the app.
///
/// Only the PREFERENCE lives here. What the app actually opens on is
/// resolveStartTab(bar, preference), because the bar can lose the page
/// picked here (Tasks removed from it), and then the app opens on the other
/// of the two instead of pushing a page that is not in the bar.
///
/// FREE, unlike the bar it sits beside: picking which of two pages comes
/// first takes nothing Premium sells. Settings › Look › Pages holds the row.
///
/// Same persistence shape as NavBadgesSettingNotifier: instant on this
/// device (Hive, seeded at boot so the first frame is already the right
/// page), mirrored to the account (`startPage` on the user document, the
/// tab's storage id) so a second device catches up on sign-in. Only a
/// non-default choice is worth a field; picking Habits again deletes it.
class StartPageNotifier extends StateNotifier<NavTab> {
  StartPageNotifier([NavTab initial = NavTab.grid])
      : super(startPageOrDefault(initial.id));

  String? _uid;

  Future<void> set(NavTab tab) async {
    final next = startPageOrDefault(tab.id);
    state = next;
    await _store(next);
    if (_uid != null) {
      FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .set({
            _kStartPageField:
                next == NavTab.grid ? FieldValue.delete() : next.id,
          }, SetOptions(merge: true))
          .catchError((_) {});
    }
  }

  /// The account's saved choice wins over this device's, same as the bar:
  /// this device is the one catching up. Nothing saved means Habits.
  Future<void> pullFromAccount(String uid) async {
    _uid = uid;
    try {
      final snap =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final saved = snap.data()?[_kStartPageField];
      final tab = startPageOrDefault(saved is String ? saved : null);
      if (!mounted || tab == state) return;
      state = tab;
      await _store(tab);
    } catch (_) {}
  }

  /// Sign-out: back to Habits for whoever signs in next, without touching
  /// the account (NavBadgesSettingNotifier.detachAccount's rule).
  Future<void> detachAccount() async {
    _uid = null;
    if (state == NavTab.grid) return;
    state = NavTab.grid;
    await _store(NavTab.grid);
  }

  Future<void> _store(NavTab tab) async {
    try {
      final box = await LocalStoreService.settingsBox();
      if (tab == NavTab.grid) {
        await box.delete(_kStartPageKey);
      } else {
        await box.put(_kStartPageKey, tab.id);
      }
    } catch (_) {}
  }
}

/// Habits or Tasks, from a stored id. Anything else (nothing stored, an id
/// a newer build wrote for a page this one cannot open on) is Habits.
NavTab startPageOrDefault(String? id) {
  final tab = NavTab.byId(id);
  return tab != null && tab.isHomePage ? tab : NavTab.grid;
}

final startPageProvider = StateNotifierProvider<StartPageNotifier, NavTab>(
    (ref) => StartPageNotifier());

/// For main.dart's boot overrides: the shell reads this in its initState to
/// pick its first page, so it has to be right before the first frame.
Future<NavTab> loadPersistedStartPage() async {
  try {
    final box = await LocalStoreService.settingsBox();
    final raw = box.get(_kStartPageKey);
    return startPageOrDefault(raw is String ? raw : null);
  } catch (_) {
    return NavTab.grid;
  }
}

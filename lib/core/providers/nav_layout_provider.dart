import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/local_store_service.dart';

/// Every destination the bottom bar can hold.
///
/// The enum is the IDENTITY of a tab, nothing more: which screen, whether
/// it can be removed, how it is spelled in storage. What it looks like (icon,
/// label) and what it builds live in `shared/widgets/nav_tabs.dart`, so this
/// file stays free of Flutter widgets and the layout rules below can be unit
/// tested without a widget tree.
///
/// [id] is the storage spelling, on disk (Hive) and on the account
/// (Firestore `navTabs`). It is deliberately not `name`: renaming an enum
/// value must never silently change what a saved layout means, and an id
/// written by a newer build that this build does not know is simply dropped
/// by [sanitizeNavTabs] rather than crashing the shell.
enum NavTab {
  grid('grid'),
  profile('profile'),
  matrix('matrix'),
  rooms('rooms'),
  progress('progress'),
  settings('settings'),
  tasbih('tasbih'),
  rewards('rewards'),
  closet('closet'),
  nightReview('night_review'),
  yearRecord('year_record');

  final String id;
  const NavTab(this.id);

  /// Habits is the app's home (the Android back button walks up to tab 0,
  /// and every "add your first habit" flow lands there) and Profile is the
  /// one place Settings, and therefore this very customiser, can be reached
  /// from. A bar without either would strand someone; a bar without Tasks
  /// is simply a choice.
  bool get isPinned => this == NavTab.grid || this == NavTab.profile;

  static NavTab? byId(String? id) {
    for (final t in NavTab.values) {
      if (t.id == id) return t;
    }
    return null;
  }
}

/// Five is the most a phone-width bar holds before the labels stop being
/// words: at 402pt, five items leave about 65pt each, which is the widest
/// Arabic label here ("سجل السنة") at the 1.4x label cap. Six would not be.
const int kNavTabsMax = 5;

/// What everyone starts with, and what Reset returns to. Order matters: it
/// is the bar's order, and Grid at 0 is what the shell's back handling
/// assumes is home.
const List<NavTab> kDefaultNavTabs = [
  NavTab.grid,
  NavTab.profile,
  NavTab.matrix,
];

/// Turns whatever was stored into a layout the shell can trust.
///
/// Storage is never assumed clean: Hive can hold a list an older build
/// wrote, Firestore can hold one a NEWER build wrote (an id this build has
/// never heard of), and either can hold duplicates or be missing a pinned
/// tab after a hand edit. The rules, in order:
///
///  1. Unknown ids are dropped, duplicates keep their first position.
///  2. Pinned tabs that are missing are put back: Grid first, Profile right
///     after it, which is also their default position.
///  3. Over [kNavTabsMax], unpinned tabs are dropped from the END, so the
///     tabs the person placed first survive and pinned ones always do.
///  4. Nothing usable at all falls back to [kDefaultNavTabs].
///
/// Pure, so a corrupt document costs a unit test rather than a device.
List<NavTab> sanitizeNavTabs(Iterable<Object?> ids) {
  final seen = <NavTab>{};
  final out = <NavTab>[];
  for (final raw in ids) {
    final tab = NavTab.byId(raw is String ? raw : null);
    if (tab == null || !seen.add(tab)) continue;
    out.add(tab);
  }
  if (out.isEmpty) return List.of(kDefaultNavTabs);
  if (!out.contains(NavTab.grid)) out.insert(0, NavTab.grid);
  if (!out.contains(NavTab.profile)) {
    out.insert(out.indexOf(NavTab.grid) + 1, NavTab.profile);
  }
  while (out.length > kNavTabsMax) {
    final i = out.lastIndexWhere((t) => !t.isPinned);
    // Unreachable in practice (two pinned tabs, cap of five), kept so a
    // future cap change cannot loop forever.
    if (i < 0) break;
    out.removeAt(i);
  }
  return out;
}

bool isDefaultNavTabs(List<NavTab> tabs) {
  if (tabs.length != kDefaultNavTabs.length) return false;
  for (var i = 0; i < tabs.length; i++) {
    if (tabs[i] != kDefaultNavTabs[i]) return false;
  }
  return true;
}

const _kNavTabsKey = 'nav_tabs_v1';
const _kNavTabsField = 'navTabs';

/// The bottom bar's tabs, in order.
///
/// Same persistence shape as ThemePresetNotifier, because it is the same
/// kind of thing: instant on this device (Hive, seeded at boot so the first
/// frame already shows the right bar), mirrored to the account (Firestore
/// `navTabs`) so a second device catches up on sign-in.
///
/// Customising is Premium-only, but that gate lives in the UI
/// (NavBarSettingsScreen), not here, for the reason every other gate in the
/// app gives: access ending never takes anything away. A layout someone
/// built during the trial keeps working after it; only EDITING re-gates.
/// The notifier therefore never asks about entitlement, same as
/// ThemePresetNotifier applying a saved paid preset.
class NavLayoutNotifier extends StateNotifier<List<NavTab>> {
  NavLayoutNotifier([List<NavTab>? initial])
      : super(initial == null ? List.of(kDefaultNavTabs) : List.of(initial));

  // Set after construction, same as the theme notifiers: the provider is
  // created before auth resolves.
  String? _uid;

  /// Replaces the whole layout. Sanitised on the way in, so callers can
  /// hand over exactly what the person arranged and trust the result.
  Future<void> set(List<NavTab> tabs) =>
      _apply(sanitizeNavTabs([for (final t in tabs) t.id]));

  Future<void> add(NavTab tab) async {
    if (state.contains(tab) || state.length >= kNavTabsMax) return;
    await _apply([...state, tab]);
  }

  Future<void> remove(NavTab tab) async {
    if (tab.isPinned || !state.contains(tab)) return;
    await _apply([for (final t in state) if (t != tab) t]);
  }

  /// [ReorderableListView] semantics: [newIndex] is given against the list
  /// WITH the moved row still in place, so a downward move is off by one.
  Future<void> move(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex -= 1;
    if (oldIndex == newIndex ||
        oldIndex < 0 ||
        oldIndex >= state.length ||
        newIndex < 0 ||
        newIndex >= state.length) {
      return;
    }
    final next = List.of(state);
    final moved = next.removeAt(oldIndex);
    next.insert(newIndex, moved);
    await _apply(next);
  }

  /// Back to [kDefaultNavTabs], and the stored override is REMOVED rather
  /// than rewritten as the default list. "No custom layout" and "a custom
  /// layout that happens to equal the default" are different facts, and a
  /// clean account document is the one that lets a future default change
  /// reach people who never customised.
  Future<void> reset() async {
    state = List.of(kDefaultNavTabs);
    try {
      final box = await LocalStoreService.settingsBox();
      await box.delete(_kNavTabsKey);
    } catch (_) {}
    if (_uid != null) {
      FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .set({_kNavTabsField: FieldValue.delete()}, SetOptions(merge: true))
          .catchError((_) {});
    }
  }

  Future<void> _apply(List<NavTab> tabs, {bool persistToAccount = true}) async {
    state = tabs;
    final ids = [for (final t in tabs) t.id];
    try {
      final box = await LocalStoreService.settingsBox();
      await box.put(_kNavTabsKey, ids);
    } catch (_) {}
    if (persistToAccount && _uid != null) {
      FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .set({_kNavTabsField: ids}, SetOptions(merge: true))
          .catchError((_) {});
    }
  }

  /// Called once a signed-in uid is known. The account's saved layout wins
  /// over this device's, same as ThemePresetNotifier.pullFromAccount: this
  /// device is the one catching up. An account with nothing saved leaves
  /// the local layout alone (a guest who customised during the trial and
  /// then registered keeps what they built; it reaches the account on their
  /// next edit).
  Future<void> pullFromAccount(String uid) async {
    _uid = uid;
    try {
      final snap =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final saved = snap.data()?[_kNavTabsField];
      if (saved is! List) return;
      final tabs = sanitizeNavTabs(saved);
      if (!mounted) return;
      await _apply(tabs, persistToAccount: false);
    } catch (_) {}
  }

  /// Sign-out. Drops back to the default bar without touching the account:
  /// any non-default layout was made under Premium, and the next person to
  /// sign in on this device should not inherit someone else's paid setup,
  /// which is the exact rule ThemePresetNotifier.detachAccount applies to a
  /// paid preset. The account keeps its layout for its own next sign-in.
  Future<void> detachAccount() async {
    _uid = null;
    if (isDefaultNavTabs(state)) return;
    state = List.of(kDefaultNavTabs);
    try {
      final box = await LocalStoreService.settingsBox();
      await box.delete(_kNavTabsKey);
    } catch (_) {}
  }
}

final navLayoutProvider =
    StateNotifierProvider<NavLayoutNotifier, List<NavTab>>(
        (ref) => NavLayoutNotifier());

/// Reads the persisted layout, if any, for main.dart's boot overrides, so
/// the very first frame already draws the right bar instead of three tabs
/// that then jump to five. Null means "nothing stored", never a crash.
Future<List<NavTab>?> loadPersistedNavTabs() async {
  try {
    final box = await LocalStoreService.settingsBox();
    final raw = box.get(_kNavTabsKey);
    if (raw is! List) return null;
    return sanitizeNavTabs(raw);
  } catch (_) {
    return null;
  }
}

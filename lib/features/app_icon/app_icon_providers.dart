import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/local_store_service.dart';
import '../auth/notifiers/auth_notifier.dart';
import '../dashboard/notifiers/dashboard_notifier.dart';
import 'app_icon_catalog.dart';
import 'app_icon_service.dart';

final appIconServiceProvider =
    Provider<AppIconService>((ref) => const AppIconService());

/// Whether this phone can change its Home Screen icon at all. False on
/// Android and the web without asking anything.
final appIconsAvailableProvider = FutureProvider<bool>(
  (ref) => ref.watch(appIconServiceProvider).supported(),
);

/// The icon on the Home Screen right now, as iOS reports it; null until the
/// first answer. Never stored by the app: iOS keeps it, across launches and
/// accounts, so there is nothing to sync and nothing to drift.
class AppIconNotifier extends StateNotifier<AppIconChoice?> {
  AppIconNotifier(this._service) : super(null) {
    refresh();
  }

  final AppIconService _service;

  Future<AppIconChoice> refresh() async {
    final choice = await _service.current();
    if (mounted) state = choice;
    return choice;
  }

  /// Puts [choice] on the Home Screen; true when it is there. Only from a
  /// person's own tap (iOS answers every change with an alert).
  Future<bool> apply(AppIconChoice choice) async {
    final ok = await _service.set(choice);
    if (!mounted) return ok;
    if (ok) {
      state = choice;
    } else {
      await refresh();
    }
    return ok;
  }
}

final appIconProvider = StateNotifierProvider<AppIconNotifier, AppIconChoice?>(
  (ref) => AppIconNotifier(ref.watch(appIconServiceProvider)),
);

// ─── This phone's two icon preferences ──────────────────────────────────────

const _kFollowThemeKey = 'app_icon_follow_theme_v1';
const _kOfferDeclinesKey = 'app_icon_offer_declines_v1';
const _kRamadanCardKey = 'app_icon_ramadan_card_v1';

/// How many «مو الحين» end the offer after a theme change for good.
///
/// Two, so a person who changes themes often and does not care about the
/// icon is asked twice and then left alone; the Settings row is always
/// there when they do care.
const int kAppIconOfferDeclineLimit = 2;

@immutable
class AppIconPrefs {
  const AppIconPrefs({
    this.loaded = false,
    this.followTheme = false,
    this.offerDeclines = 0,
    this.ramadanCardYear = 0,
  });

  final bool loaded;

  /// «مع المظهر»: the icon takes each theme's colour as it is picked.
  final bool followTheme;

  /// «مو الحين» answers to the offer, see [kAppIconOfferDeclineLimit].
  final int offerDeclines;

  /// The Hijri year whose «رمضان مبارك» card this phone has shown, 0 before
  /// the first (see app_icon_prompts.dart).
  final int ramadanCardYear;

  AppIconPrefs copyWith({
    bool? followTheme,
    int? offerDeclines,
    int? ramadanCardYear,
  }) =>
      AppIconPrefs(
        loaded: true,
        followTheme: followTheme ?? this.followTheme,
        offerDeclines: offerDeclines ?? this.offerDeclines,
        ramadanCardYear: ramadanCardYear ?? this.ramadanCardYear,
      );
}

/// Device-local on purpose, not mirrored to the account: the icon these
/// describe is this phone's, and a second device has its own Home Screen.
class AppIconPrefsNotifier extends StateNotifier<AppIconPrefs> {
  AppIconPrefsNotifier({AppIconPrefs? initial})
      : super(initial ?? const AppIconPrefs()) {
    ready = initial != null ? Future.value() : _load();
  }

  /// Completes once the stored values are in [state].
  late final Future<void> ready;

  Future<void> _load() async {
    try {
      final box = await LocalStoreService.settingsBox();
      if (!mounted) return;
      state = AppIconPrefs(
        loaded: true,
        followTheme: box.get(_kFollowThemeKey) == true,
        offerDeclines: (box.get(_kOfferDeclinesKey) as int?) ?? 0,
        ramadanCardYear: (box.get(_kRamadanCardKey) as int?) ?? 0,
      );
    } catch (_) {
      if (mounted) state = state.copyWith();
    }
  }

  Future<void> setFollowTheme(bool on) async {
    state = state.copyWith(followTheme: on);
    try {
      final box = await LocalStoreService.settingsBox();
      if (on) {
        await box.put(_kFollowThemeKey, true);
      } else {
        await box.delete(_kFollowThemeKey);
      }
    } catch (_) {}
  }

  Future<void> noteOfferDeclined() async {
    final n = state.offerDeclines + 1;
    state = state.copyWith(offerDeclines: n);
    try {
      final box = await LocalStoreService.settingsBox();
      await box.put(_kOfferDeclinesKey, n);
    } catch (_) {}
  }

  /// The «رمضان مبارك» card for Ramadan [year] has been on screen.
  Future<void> noteRamadanCardShown(int year) async {
    if (!mounted || year <= state.ramadanCardYear) return;
    state = state.copyWith(ramadanCardYear: year);
    try {
      final box = await LocalStoreService.settingsBox();
      await box.put(_kRamadanCardKey, year);
    } catch (_) {}
  }
}

final appIconPrefsProvider =
    StateNotifierProvider<AppIconPrefsNotifier, AppIconPrefs>(
  (ref) => AppIconPrefsNotifier(),
);

// ─── The growing plant ──────────────────────────────────────────────────────

/// Counts full days: days that reached the streak's bar, 80% of that day's
/// habits (kStreakDayCompletionThreshold), in all of an account's history.
///
/// Every such day already carries the mark that says so, 'streakEarnedToday'
/// on its daily record, written by the tap that reached the bar and never
/// taken back (an undo leaves a finished day finished, see
/// DashboardState.streakEarnedToday). So this asks nothing new of the data
/// and cannot disagree with the streak about which days were full.
///
/// An account asks Firestore for the count alone, an aggregation that costs
/// one read per thousand days, rather than reading the days themselves. A
/// guest's days are on the phone already.
class FullDayCounter {
  const FullDayCounter([this._db]);

  /// Firestore, or the app's own instance when null (a test hands in a fake).
  final FirebaseFirestore? _db;

  /// Full days for [uid] (null: this phone's guest); null when the count
  /// cannot be had right now (offline, say), which reads as "not known",
  /// never as zero.
  Future<int?> count(String? uid) async {
    try {
      if (uid == null) {
        final box = await LocalStoreService.dailyBox();
        return box.values
            .where((d) => d is Map && d['streakEarnedToday'] == true)
            .length;
      }
      final snap = await (_db ?? FirebaseFirestore.instance)
          .collection('users')
          .doc(uid)
          .collection('daily')
          .where('streakEarnedToday', isEqualTo: true)
          .count()
          .get();
      return snap.count;
    } catch (e) {
      debugPrint('[AppIcon] full days: $e');
      return null;
    }
  }
}

final fullDayCounterProvider =
    Provider<FullDayCounter>((ref) => const FullDayCounter());

/// The two marks a newly full day moves: today reaching the bar, and the
/// last day that did. Null while the dashboard still holds placeholder
/// numbers. What [plantFullDaysProvider] counts again on, and nothing else.
final fullDayMarksProvider = Provider<({DateTime? last, bool today})?>(
  (ref) => ref.watch(
    dashboardProvider.select(
      (d) => d.statsAreReal
          ? (last: d.lastStreakDay, today: d.streakEarnedToday)
          : null,
    ),
  ),
);

/// This account's full days (see [FullDayCounter]); null while the dashboard
/// still holds placeholder numbers or the count is not to be had.
///
/// Counted again only when a day could have just become full: when the
/// account changes, when the dashboard's placeholder gives way to the real
/// thing, and when [fullDayMarksProvider] moves. Not on every tap, and not
/// on resume: a count that cannot have changed is not worth a read. A day
/// finished late, in yesterday's grace window after today was already
/// full, moves neither mark and waits for the next launch; it is never
/// lost, only a launch late.
///
/// iPhone only, like everything the count feeds; anywhere else it is null
/// without asking anything.
final plantFullDaysProvider = FutureProvider<int?>((ref) async {
  if (!AppIconService.onThisPlatform) return null;
  // Not before sign-in has been read back: until then every account looks
  // like the guest, and the guest's count would stand in for it.
  final auth = ref.watch(authStateProvider);
  if (!auth.hasValue) return null;
  final uid = auth.value?.uid;
  if (ref.watch(fullDayMarksProvider) == null) return null;
  return ref.watch(fullDayCounterProvider).count(uid);
});

// v3 since the plant began growing with full days (2026-09-25): a shape the
// v2 rule (any day with a completion) had opened is not carried over.
const _kGrowthKeyPrefix = 'app_icon_growth_v3_';

@immutable
class PlantGrowth {
  const PlantGrowth({
    this.loaded = false,
    this.earned = PlantShape.sprout,
    this.celebrated = PlantShape.sprout,
  });

  final bool loaded;

  /// The furthest shape ever opened. A ratchet: an earned shape does not
  /// close again, whatever the count behind it later says.
  final PlantShape earned;

  /// The furthest shape the «نبتتك كبرت» card has been shown for.
  final PlantShape celebrated;
}

/// Per account on this device (the key carries the uid, "guest" when signed
/// out), so a shape one person grew is not handed to whoever signs in next.
class PlantGrowthNotifier extends StateNotifier<PlantGrowth> {
  PlantGrowthNotifier(this._account, {PlantGrowth? initial})
      : super(initial ?? const PlantGrowth()) {
    ready = initial != null ? Future.value() : _load();
  }

  final String _account;
  late final Future<void> ready;

  String get _key => '$_kGrowthKeyPrefix$_account';

  Future<void> _load() async {
    try {
      final box = await LocalStoreService.settingsBox();
      if (!mounted) return;
      final raw = box.get(_key);
      final earned = raw is Map ? raw['earned'] : null;
      final celebrated = raw is Map ? raw['celebrated'] : null;
      state = PlantGrowth(
        loaded: true,
        earned: _shapeAt(earned) ?? PlantShape.sprout,
        celebrated: _shapeAt(celebrated) ?? PlantShape.sprout,
      );
    } catch (_) {
      if (mounted) {
        state = PlantGrowth(
          loaded: true,
          earned: state.earned,
          celebrated: state.celebrated,
        );
      }
    }
  }

  static PlantShape? _shapeAt(Object? i) =>
      i is int && i >= 0 && i < PlantShape.values.length
          ? PlantShape.values[i]
          : null;

  /// Moves the ratchet up to what [fullDays] has opened. Never down.
  Future<void> observe(int fullDays) async {
    if (!mounted) return;
    final reached = grownShapeFor(fullDays);
    if (reached.index <= state.earned.index) return;
    state = PlantGrowth(
      loaded: true,
      earned: reached,
      celebrated: state.celebrated,
    );
    await _persist();
  }

  Future<void> markCelebrated(PlantShape shape) async {
    // The card that calls this can outlive the account it was grown for
    // (a sign-out while it is open); that account's record is then left as
    // it was rather than written by a notifier that no longer exists.
    if (!mounted || shape.index <= state.celebrated.index) return;
    state = PlantGrowth(loaded: true, earned: state.earned, celebrated: shape);
    await _persist();
  }

  Future<void> _persist() async {
    try {
      final box = await LocalStoreService.settingsBox();
      await box.put(_key, {
        'earned': state.earned.index,
        'celebrated': state.celebrated.index,
      });
    } catch (_) {}
  }
}

final plantGrowthProvider =
    StateNotifierProvider<PlantGrowthNotifier, PlantGrowth>((ref) {
  final uid = ref.watch(authStateProvider).asData?.value?.uid;
  return PlantGrowthNotifier(uid ?? 'guest');
});

/// The shapes this person can pick: everything the ratchet or today's count
/// has opened, whichever is further.
PlantShape earnedShape(PlantGrowth growth, int? fullDays) {
  final now = fullDays == null ? PlantShape.sprout : grownShapeFor(fullDays);
  return now.index > growth.earned.index ? now : growth.earned;
}

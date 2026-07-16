import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/local_store_service.dart';
import '../../../core/services/notification_service.dart';
import '../../auth/notifiers/auth_notifier.dart';
import 'islamic_habit_catalog.dart';

// ─── Plan definitions ─────────────────────────────────────────────────────────

class HabitPlan {
  final String id;
  final String nameEn;
  final String nameAr;
  final String descEn;
  final String descAr;
  final Color color;
  final IconData icon;
  final List<String> catalogIds;

  const HabitPlan({
    required this.id,
    required this.nameEn,
    required this.nameAr,
    required this.descEn,
    required this.descAr,
    required this.color,
    required this.icon,
    required this.catalogIds,
  });

  String localName(bool isAr) => isAr ? nameAr : nameEn;
  String localDesc(bool isAr) => isAr ? descAr : descEn;

  List<IslamicHabitTemplate> get habits =>
      IslamicHabitCatalog.templates.where((t) => catalogIds.contains(t.id)).toList();

  int get totalDailyXp =>
      habits.fold(0, (sum, t) => sum + t.xpReward);
}

// Curated down from 8 heavily-overlapping plans to 6 distinct ones (July
// 2026) — each maps to a routine type people demonstrably stick with
// (morning routines form fastest thanks to consistent cues; curated
// programs and timed challenges are the patterns habit apps converge on).
// Every habit inside carries a real, accurate timing anchor now — see the
// per-habit cue/weekday fixes in islamic_habit_catalog.dart made alongside
// this. quran_memorization is deliberately in no plan (too advanced for a
// starter bundle); it keeps working for anyone who already has it active.
const habitPlans = <HabitPlan>[
  HabitPlan(
    id: 'morning_warrior',
    nameEn: 'Morning Warrior',
    nameAr: 'محارب الفجر',
    descEn: 'Fajr, athkar, a page of Quran, no phone. The hour that decides your day.',
    descAr: 'فجر، أذكار، صفحة قرآن، وبدون تلفون. أول ساعة تحدد يومك.',
    color: Color(0xFF4A9EFF),
    icon: Icons.wb_twilight,
    catalogIds: [
      'wake_early', 'morning_athkar', 'quran_daily_page', 'no_phone_morning',
    ],
  ),
  HabitPlan(
    id: 'deen_essentials',
    nameEn: 'Deen Essentials',
    nameAr: 'أساس الدين',
    descEn: 'Athkar morning and evening, daily Quran, Monday & Thursday fasting, and sadaqah.',
    descAr: 'أذكار الصباح والمساء، ورد يومي، صيام الاثنين والخميس، وصدقة.',
    color: Color(0xFF34C759),
    icon: Icons.mosque,
    catalogIds: [
      'morning_athkar', 'evening_athkar', 'quran_daily_page',
      'sunnah_fasting', 'daily_sadaqah',
    ],
  ),
  HabitPlan(
    id: 'night_routine',
    nameEn: 'Night Routine',
    nameAr: 'روتين الليل',
    descEn: 'Sleep before midnight, plan tomorrow tonight, and rise for tahajjud.',
    descAr: 'نم قبل منتصف الليل، خطط لبكرة من الليلة، وقم للتهجد.',
    color: Color(0xFFBF5AF2),
    icon: Icons.bedtime_rounded,
    catalogIds: ['sleep_schedule', 'daily_planning', 'tahajjud'],
  ),
  HabitPlan(
    id: 'discipline_30',
    nameEn: '30-Day Discipline',
    nameAr: 'تحدي الانضباط ٣٠ يوم',
    descEn: 'Cold showers, early mornings, no sugar, and the gym. One month to reset.',
    descAr: 'دش بارد، صحيان مبكر، بدون سكر، ورياضة. شهر واحد يعدّل كل شي.',
    color: Color(0xFFFF6B35),
    icon: Icons.local_fire_department_rounded,
    catalogIds: ['cold_shower', 'wake_early', 'no_sugar', 'gym_consistency'],
  ),
  HabitPlan(
    id: 'deep_focus',
    nameEn: 'Deep Focus',
    nameAr: 'تركيز عميق',
    descEn: 'One real deep work block, a clear inbox, and tomorrow planned before you sleep.',
    descAr: 'فترة تركيز بدون مقاطعات، بريد مرتب، وبكرة مخطط له من الليل.',
    color: Color(0xFF2ECF8F),
    icon: Icons.rocket_launch_rounded,
    catalogIds: ['deep_work_block', 'inbox_zero', 'daily_planning'],
  ),
  // Pre-marriage, not married life — built directly on the Prophet's ﷺ own
  // prescription for those not yet able to marry (fasting + guarding
  // chastity, صحيح البخاري ٥٠٦٥) plus the classical readiness checklist:
  // dua, learning the rights of marriage, and saving for the mahr.
  // marriage_gratitude/marriage_checkin (married-couple habits) left out on
  // purpose — they keep working for anyone who already has them active,
  // and belong to a future "Married Life" plan, not preparation.
  HabitPlan(
    id: 'marriage_prep',
    nameEn: 'Marriage Preparation',
    nameAr: 'التحضير للزواج',
    descEn: 'The sunnah path to marriage: dua, knowledge, saving, fasting, and guarding your chastity.',
    descAr: 'طريق السنة للزواج: دعاء، علم، توفير، صيام، وغض البصر.',
    color: Color(0xFFFF6FA5),
    icon: Icons.favorite_rounded,
    catalogIds: [
      'marriage_dua', 'marriage_read', 'marriage_savings',
      'lower_gaze', 'sunnah_fasting',
    ],
  ),
];

// ─── Active catalog provider ──────────────────────────────────────────────────

const _kActiveKey = 'active_catalog_ids_v1';
const _kReminderKey = 'daily_reminder_time_v1';

/// Which Islamic Habit Catalog templates the user has turned on — the
/// actual on/off switch [habitListProvider] (custom_habits_notifier.dart)
/// reads before merging in [customHabitsProvider]'s user-authored habits.
///
/// This used to be Hive-only with no `_uid` branch at all — the one piece
/// of "which habits/goals am I running" that didn't follow every other
/// notifier's signed-in-Firestore/guest-local-Hive pattern (matrix tasks,
/// custom habits, dashboard, grid, etc. all already do), so a catalog habit
/// switched on here quietly never showed up on a second device even though
/// its completions (keyed by the same catalog id, in DashboardNotifier)
/// synced just fine. Now mirrors [HabitOrderNotifier] exactly: a flat field
/// on the user doc, since a handful of catalog ids doesn't need its own
/// subcollection.
class ActiveCatalogNotifier extends StateNotifier<Set<String>> {
  final String? _uid;

  /// True until the very first Firestore/Hive read resolves - see
  /// CustomHabitsNotifier.isLoading's doc comment (custom_habits_notifier.
  /// dart) for why this lives as a plain field rather than being folded
  /// into [state] itself, and habitsStillLoadingProvider (same file) for
  /// where the two combine into the one signal a screen actually watches.
  bool isLoading = true;

  ActiveCatalogNotifier(this._uid) : super(const {}) {
    if (_uid != null) {
      _load();
    } else {
      _loadGuest();
    }
  }

  DocumentReference<Map<String, dynamic>> get _userRef =>
      FirebaseFirestore.instance.collection('users').doc(_uid);

  Future<void> _loadGuest() async {
    final box = await LocalStoreService.settingsBox();
    final raw = box.get(_kActiveKey);
    if (!mounted) return;
    if (raw is List) {
      state = Set<String>.from(raw.whereType<String>());
    } else {
      // Nothing to load, but still force a fresh state reference so
      // habitsStillLoadingProvider's watchers notice this pass finished -
      // see isLoading's own doc comment.
      state = Set.of(state);
    }
    isLoading = false;
  }

  Future<void> _load() async {
    if (_uid == null) return;
    try {
      final snap = await _userRef.get();
      if (!mounted) return;
      final raw = snap.data()?['activeCatalogIds'];
      if (raw is List) {
        state = Set<String>.from(raw.whereType<String>());
        isLoading = false;
        return;
      }
      // No Firestore field yet — either a brand-new account, or one that
      // signed in before this synced at all. In the second case there may
      // already be real picks sitting in this device's own local Hive box
      // (from back when this was Hive-only) — seed from that instead of
      // silently showing an empty list and making it look like every
      // catalog habit this person turned on just vanished, then persist it
      // so it's captured in Firestore from here on.
      final box = await LocalStoreService.settingsBox();
      final localRaw = box.get(_kActiveKey);
      if (localRaw is List) {
        state = Set<String>.from(localRaw.whereType<String>());
        if (state.isNotEmpty) _save();
      }
    } catch (_) {
    } finally {
      // Covers every path that didn't already return above: the local-
      // Hive-seed fallback (found or not), and the catch-all error - none
      // of those necessarily reassign `state` on their own (a fresh
      // account with no Firestore field and no local seed never does), so
      // this forces one last fresh reference through regardless, exactly
      // mirroring CustomHabitsNotifier._load's identical guard.
      if (mounted && isLoading) {
        isLoading = false;
        state = Set.of(state);
      }
    }
  }

  Future<void> _save() async {
    if (_uid != null) {
      _userRef
          .set({'activeCatalogIds': state.toList()}, SetOptions(merge: true))
          .ignore();
      return;
    }
    final box = await LocalStoreService.settingsBox();
    await box.put(_kActiveKey, state.toList());
  }

  void toggle(String catalogId) {
    if (state.contains(catalogId)) {
      state = Set.of(state)..remove(catalogId);
    } else {
      state = {...state, catalogId};
    }
    _save();
  }

  void activatePlan(HabitPlan plan) {
    state = {...state, ...plan.catalogIds};
    _save();
  }

  void deactivatePlan(HabitPlan plan) {
    state = state.difference(plan.catalogIds.toSet());
    _save();
  }

  bool planIsActive(HabitPlan plan) =>
      plan.catalogIds.every(state.contains);
}

final activeCatalogProvider =
    StateNotifierProvider<ActiveCatalogNotifier, Set<String>>((ref) {
  final uid = ref.watch(authStateProvider).asData?.value?.uid;
  return ActiveCatalogNotifier(uid);
});

// ─── Daily reminder time provider ─────────────────────────────────────────────

class ReminderTimeNotifier extends StateNotifier<TimeOfDay?> {
  ReminderTimeNotifier() : super(null) {
    _loadFuture = _load();
  }

  // See ThemeModeNotifier's identical field (theme_provider.dart) for why
  // this is set after construction rather than threaded through the
  // provider.
  String? _uid;

  // _load() is the one thing here that's async from the very start (every
  // other synced notifier in the app seeds its initial value synchronously
  // via a boot-time provider override instead) — pullFromAccount below
  // awaits this first so it can't race _load() and stomp a value that was
  // already sitting in this device's own Hive storage.
  late final Future<void> _loadFuture;

  Future<void> _load() async {
    final box = await LocalStoreService.settingsBox();
    final raw = box.get(_kReminderKey) as String?;
    if (raw != null && mounted) {
      state = _parse(raw);
    }
  }

  TimeOfDay? _parse(String raw) {
    final parts = raw.split(':');
    if (parts.length != 2) return null;
    return TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 20,
      minute: int.tryParse(parts[1]) ?? 0,
    );
  }

  /// Saves the reminder time and (re)schedules the local notification.
  /// Returns whether notification permission was actually granted — the
  /// time is saved either way (so it's ready to fire the moment the user
  /// grants permission from system settings), but previously this discarded
  /// [NotificationService.requestPermissions]'s result entirely, so a user
  /// who denied the OS permission prompt saw the reminder time saved with
  /// no indication their reminder would never actually fire.
  Future<bool> set(TimeOfDay time) async {
    state = time;
    final raw = '${time.hour}:${time.minute}';
    final box = await LocalStoreService.settingsBox();
    await box.put(_kReminderKey, raw);
    if (_uid != null) {
      FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .set({'reminderTime': raw}, SetOptions(merge: true))
          .catchError((_) {});
    }
    final granted = await NotificationService.instance.requestPermissions();
    await NotificationService.instance
        .scheduleDailyReminder(hour: time.hour, minute: time.minute);
    return granted;
  }

  Future<void> clear() async {
    state = null;
    final box = await LocalStoreService.settingsBox();
    await box.delete(_kReminderKey);
    if (_uid != null) {
      FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .set({'reminderTime': FieldValue.delete()}, SetOptions(merge: true))
          .catchError((_) {});
    }
    await NotificationService.instance.cancelDailyReminder();
  }

  /// Called once a signed-in uid is known — pulls this account's saved
  /// reminder time, if any, but ONLY fills it in when this device doesn't
  /// already have a time of its own (an existing device-local time always
  /// wins, since it's the one actually scheduled here). Deliberately does
  /// NOT request notification permission or call scheduleDailyReminder by
  /// itself: doing that automatically right after sign-in, rather than from
  /// an explicit tap on the Daily Reminder row, is exactly the kind of
  /// out-of-context permission prompt that's poor practice (and against
  /// iOS's own guidance) to spring on someone. The time still shows up
  /// pre-filled instead of "Tap to set reminder" though, so actually
  /// turning it on for real on this device is then just one confirming tap
  /// instead of having to remember what time was used elsewhere.
  Future<void> pullFromAccount(String uid) async {
    _uid = uid;
    await _loadFuture;
    if (state != null) return;
    try {
      final snap =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final saved = snap.data()?['reminderTime'] as String?;
      if (saved == null) return;
      final parsed = _parse(saved);
      if (parsed == null || !mounted) return;
      state = parsed;
      final box = await LocalStoreService.settingsBox();
      await box.put(_kReminderKey, saved);
    } catch (_) {}
  }

  /// Signed out - future set()/clear() calls go back to being device-local
  /// only, same as a guest.
  void detachAccount() => _uid = null;
}

final reminderTimeProvider =
    StateNotifierProvider<ReminderTimeNotifier, TimeOfDay?>(
  (_) => ReminderTimeNotifier(),
);

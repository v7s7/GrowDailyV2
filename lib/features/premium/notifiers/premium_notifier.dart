import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart' show CustomerInfo;

import '../../../core/services/analytics_service.dart';
import '../../../core/services/local_store_service.dart';
import '../../../core/services/purchase_service.dart';

/// How long the old app-side Premium trial lasts, counted from the moment
/// an install first booted a build that had it.
///
/// ── No new trials ─────────────────────────────────────────────────────────
/// Aziz, 2026-09-17: new installs no longer get one. An install that already
/// holds [_kTrialStartKey] keeps exactly the days it had left, nothing is cut
/// short and nothing is deleted; an install without that key never gains
/// it, because nothing writes it any more (see [loadLegacyTrial]). The
/// reasons, so it does not come back in the same shape:
///
///  1. It unlocked paid features outside In-App Purchase, which guideline
///     3.1.1 does not allow. Apple sanctions two timed trials: an
///     introductory offer set up in App Store Connect on an auto-renewing
///     subscription (3.1.2(a)), and a free Tier 0 "XX-day Trial"
///     non-consumable, which 3.1.1 describes for apps that sell WITHOUT
///     subscriptions. This app sells growdaily_monthly, so its route is the
///     first one: a free week on the monthly plan (see below). This comment
///     used to say Apple only attaches trials to subscriptions, which is why
///     the trial had been built app-side.
///  2. It started silently, with nothing telling anyone a clock was
///     running, and while it ran every contextual upsell stayed hidden. That
///     is part of why build 70 was rejected under 2.1(b): the reviewer could
///     not find the purchases.
///  3. It lived on the device, so a reinstall or each new web browser
///     started it over, and a clock set back reopened it.
///
/// A store trial (a free week on the monthly subscription) was deferred, not
/// ruled out; that waits for data.
///
/// What still holds for the trials left running: access ending never deletes
/// anything (reminders keep firing, voice notes stay playable, over-cap
/// habits are kept, only ADDING re-gates), so a legacy trial lapsing is
/// exactly as safe as a subscription lapsing.
const int kTrialDays = 7;

/// Hive key for a legacy trial's start moment. Read, never written: the
/// builds that had the trial stamped DateTime.now() here on their first
/// boot, and since 2026-09-17 nothing stamps it at all (see [kTrialDays]).
/// The name is unchanged so installs that already hold it keep their days.
///
/// The value is a LOCAL wall-clock ISO string with no offset, which matters
/// for [kTrialFutureTolerance]: after a trip west, a recent stamp reads as
/// later than the local clock.
const _kTrialStartKey = 'premium_trial_start_v1';

/// Hive key for the one-way "this install's legacy trial is over" latch.
///
/// Written the first time the app sees the window closed (see
/// [LegacyTrial.observe]) and read at boot. Once written, the trial never
/// reopens whatever the clock says afterwards. Without it the window was
/// only date math against a clock the user controls, so setting the date
/// back a week reopened every Premium gate. Never cleared.
///
/// It can only latch what the app has seen, and only [kTrialLatchGrace]
/// after the end; the accepted gaps are listed there.
const _kTrialEndedKey = 'premium_trial_ended_v1';

/// How long after a legacy trial's window closes before [_kTrialEndedKey]
/// is written.
///
/// Access closes at the end itself; only the LATCH waits. The stored start
/// is a local wall-clock time with no offset (see [_kTrialStartKey]), so a
/// trip east, or a clock nudged forward and back, makes the window look
/// closed hours before it really is. Latching at that moment would take
/// those hours away for good. A day covers any time zone move (at most 26
/// hours apart), and rollback protection still holds for anyone the app sees
/// a day past the end.
///
/// The accepted gaps, for a trial nobody new can get: the latch only records
/// an end the app has seen a day after it, and setting the clock back while
/// the window is still open extends it, as it always did.
const Duration kTrialLatchGrace = Duration(days: 1);

/// How far ahead of the clock a stored trial start may sit and still count.
///
/// A start later than now can only come from a clock that was wrong when it
/// was stamped, or is wrong now. Taken at face value, a stamp from a device
/// whose date was set years ahead on first boot would read as a trial with
/// years left once the date was put right, and the days-left line would say
/// so. Ten minutes absorbs an ordinary correction, such as a network time
/// sync landing just after boot.
///
/// A stamp past this is IGNORED, not ended: it opens nothing while it is
/// ahead of the clock, and it does not write [_kTrialEndedKey], because no
/// window was ever seen to close. The honest case this protects is a trip
/// west. The stamp carries no offset (see [_kTrialStartKey]), so a trial
/// started in Bahrain in the last few hours reads as hours ahead of a New
/// York clock, and it has to come back once the clock catches up, not be
/// lost. The rule is re-applied on every evaluation rather than once at
/// boot for the same reason.
const Duration kTrialFutureTolerance = Duration(minutes: 10);

/// The longest [premiumAccessProvider] waits before looking at a legacy
/// trial again.
///
/// Its timer used to be armed for the exact end of the window. With
/// [kTrialFutureTolerance] no plausible window ends more than about seven
/// days out, but the timer should not depend on that: browsers fire a
/// setTimeout longer than about 24.8 days at once, and a timer that fires at
/// once and re-arms itself is a loop. Capped, the worst case is one cheap
/// re-read every few hours, and a re-read that finds the same answer
/// notifies nobody (a Provider only notifies when its value changes).
const Duration kTrialRecheckCap = Duration(hours: 3);

/// Whether the free-features trial window is still open. Pure so the
/// window math is unit-testable without Riverpod or clocks, same shape as
/// [canBrowseHistoryMonth]. Only the window: whether a stored start should
/// be believed at all is [legacyTrialIsOpen]'s question.
bool trialIsActive({required DateTime start, required DateTime now}) =>
    now.isBefore(start.add(const Duration(days: kTrialDays)));

/// Whole days of trial remaining, for the paywall's status line. Counts a
/// partial day as a day (someone 6.5 days in has "1 day left", not zero).
///
/// Never more than [kTrialDays]: a start inside [kTrialFutureTolerance] of
/// the clock would otherwise round up to an eighth day on a seven-day trial.
int trialDaysLeft({required DateTime start, required DateTime now}) {
  final end = start.add(const Duration(days: kTrialDays));
  if (!now.isBefore(end)) return 0;
  final days = (end.difference(now).inSeconds / Duration.secondsPerDay).ceil();
  return days > kTrialDays ? kTrialDays : days;
}

/// Whether a stored trial start is believable at [now]: not later than the
/// clock by more than [kTrialFutureTolerance]. Pure, see that constant for
/// why a later stamp is ignored rather than ended.
bool trialStartIsPlausible({required DateTime start, required DateTime now}) =>
    !start.isAfter(now.add(kTrialFutureTolerance));

/// Whether a legacy trial grants Premium features at [now]: a stored
/// [start], the ended latch not written, a plausible stamp, and an open
/// window. Pure; [LegacyTrial.isOpenAt] is this with the stored values.
bool legacyTrialIsOpen({
  required DateTime? start,
  required bool ended,
  required DateTime now,
}) {
  if (start == null || ended) return false;
  if (!trialStartIsPlausible(start: start, now: now)) return false;
  return trialIsActive(start: start, now: now);
}

/// Whether [now] is the moment to write the ended latch: a plausible stored
/// start whose window closed at least [kTrialLatchGrace] ago, with the latch
/// not yet written.
///
/// A missing start never latches (there was no trial), and neither does an
/// implausible one (no window was seen to close; see
/// [kTrialFutureTolerance]). Pure, so "latches once, and only on a real
/// close" is a unit test.
bool legacyTrialShouldLatchEnded({
  required DateTime? start,
  required bool ended,
  required DateTime now,
}) {
  if (start == null || ended) return false;
  if (!trialStartIsPlausible(start: start, now: now)) return false;
  final latchAt =
      start.add(const Duration(days: kTrialDays)).add(kTrialLatchGrace);
  return !now.isBefore(latchAt);
}

/// How long [premiumAccessProvider] waits before re-evaluating a legacy
/// trial that started at [start]: one second past the end of the window
/// while it is open, or one second past the latch moment
/// ([kTrialLatchGrace]) once it has closed, but never longer than
/// [kTrialRecheckCap] and never shorter than a second. Aiming at the latch
/// once closed is what keeps the grace day from re-arming every second.
///
/// The one-second floor is the other half of the loop guard: a zero or
/// negative wait (a window already closed, a clock that jumped) would
/// re-arm on the next tick forever. Pure so both bounds are unit tests.
Duration trialRecheckDelay({required DateTime start, required DateTime now}) {
  const floor = Duration(seconds: 1);
  final end = start.add(const Duration(days: kTrialDays));
  final target = now.isBefore(end) ? end : end.add(kTrialLatchGrace);
  final wait = target.difference(now) + floor;
  if (wait > kTrialRecheckCap) return kTrialRecheckCap;
  if (wait < floor) return floor;
  return wait;
}

/// A legacy trial as this install holds it: the stored start, if any, and
/// whether the one-way ended latch ([_kTrialEndedKey]) has been written.
///
/// A plain object rather than provider state on purpose. The latch is set
/// from INSIDE [premiumAccessProvider]'s build, the one place that sees the
/// window close, and Riverpod forbids a provider changing another
/// provider's state while it builds. Nothing needs to rebuild when the
/// latch is set anyway: the evaluation that sets it already answers
/// "closed".
class LegacyTrial {
  LegacyTrial({this.start, bool ended = false}) : _ended = ended;

  /// The stored start, or null for an install that never had a trial,
  /// which is every install since 2026-09-17.
  final DateTime? start;

  bool _ended;

  /// Whether the ended latch is set, in memory or on disk.
  bool get ended => _ended;

  /// Whether the passage of time can still change this trial's answer.
  /// False for nearly every install (no start, or already latched), which is
  /// what keeps main.dart's resume hook and the access provider's timer free
  /// for them.
  bool get needsRecheck => start != null && !_ended;

  /// See [legacyTrialIsOpen].
  bool isOpenAt(DateTime now) =>
      legacyTrialIsOpen(start: start, ended: _ended, now: now);

  /// Days left for the paywall's status line, zero whenever the trial is
  /// not open at [now] (no start, latched, implausible, or over).
  int daysLeftAt(DateTime now) =>
      isOpenAt(now) ? trialDaysLeft(start: start!, now: now) : 0;

  /// Sets the ended latch if [now] shows the window closed and it is not set
  /// yet (see [legacyTrialShouldLatchEnded]). Returns whether it latched on
  /// this call.
  ///
  /// Latching records `legacy_trial_ended` once, with whether the install
  /// held a real entitlement at that moment ([entitled]), which is the only
  /// conversion signal the old trial can still give. Once per install: the
  /// in-memory flag guards this process and the Hive flag guards every later
  /// launch. A failed write can let it record again on a later launch, which
  /// costs one duplicate event and never access.
  bool observe(DateTime now, {required bool entitled}) {
    if (!legacyTrialShouldLatchEnded(start: start, ended: _ended, now: now)) {
      return false;
    }
    _ended = true;
    AnalyticsService.instance
        .track('legacy_trial_ended', props: {'entitled': entitled});
    unawaited(_persistEnded());
    return true;
  }

  /// Fire and forget, `await`ed inside the try for the same reason as
  /// [PremiumNotifier]'s own cache write: opening a Hive box can fail
  /// synchronously or through its future, and this runs inside a provider
  /// build, where an escaping throw would take the gate down with it. The
  /// in-memory latch above already answers "closed" either way.
  Future<void> _persistEnded() async {
    try {
      final box = await LocalStoreService.settingsBox();
      await box.put(_kTrialEndedKey, true);
    } catch (_) {
      // Nothing to do: this process stays latched, and the next launch
      // sees the same closed window and latches again.
    }
  }
}

/// Reads a legacy trial from disk: the stored start and the ended latch.
/// Read-only, and that is the whole change: it used to be loadOrStartTrial,
/// which stamped "now" whenever nothing was stored, so every install's
/// clock started on its first boot. It never writes a start now, so an
/// install without one stays without one (see [kTrialDays]).
///
/// Returns the start whenever it parses, even one ahead of the clock:
/// plausibility is judged at each evaluation instead (see
/// [kTrialFutureTolerance] for the trip that makes a boot-time verdict
/// wrong). Called once from main.dart's boot sequence beside
/// [loadPersistedPremium]; a broken box answers "no trial", never a crash.
Future<LegacyTrial> loadLegacyTrial() async {
  try {
    final box = await LocalStoreService.settingsBox();
    final raw = box.get(_kTrialStartKey);
    return LegacyTrial(
      start: raw is String ? DateTime.tryParse(raw) : null,
      ended: box.get(_kTrialEndedKey) == true,
    );
  } catch (_) {
    return LegacyTrial();
  }
}

/// This install's legacy trial, seeded at boot (see main.dart's overrides).
/// The default is no trial, which is also what every new install reads and
/// what a test that never seeds it gets.
final legacyTrialProvider = Provider<LegacyTrial>((_) => LegacyTrial());

/// Where [premiumAccessProvider] reads the time: DateTime.now, and only a
/// test overrides it, so a clock set back after the window closed can be
/// driven without a real week passing.
final trialClockProvider = Provider<DateTime Function()>((_) => DateTime.now);

/// Whether Premium FEATURES are open right now: a real entitlement, or a
/// legacy trial still inside its window (installs from before 2026-09-17
/// only; see [kTrialDays]).
///
/// Every feature gate reads THIS, not [premiumProvider]. The distinction
/// matters in exactly one place: the paywall, which must keep reading the
/// real entitlement so a legacy trial holder still sees plans and prices
/// (and a trial-days-left line) instead of "Premium is active".
///
/// Re-evaluates itself on a timer while a legacy trial can still change
/// (see [trialRecheckDelay]), so gates re-lock mid-session without waiting
/// for a restart; main.dart also invalidates it on resume, because that
/// timer does not run while the app is suspended. Every evaluation also
/// offers the trial the chance to latch ended ([LegacyTrial.observe]),
/// including for an entitled install, so a buyer's old window still closes
/// for good and still records whether it converted.
final premiumAccessProvider = Provider<bool>((ref) {
  final entitled = ref.watch(premiumProvider);
  final trial = ref.watch(legacyTrialProvider);
  if (!trial.needsRecheck) return entitled;
  final now = ref.watch(trialClockProvider)();
  trial.observe(now, entitled: entitled);
  final open = trial.isOpenAt(now);
  if (trial.needsRecheck) {
    final timer = Timer(
      trialRecheckDelay(start: trial.start!, now: now),
      ref.invalidateSelf,
    );
    ref.onDispose(timer.cancel);
  }
  return entitled || open;
});

/// Free-tier limits. Guests have a smaller cap of their own
/// (kGuestHabitLimit, custom_habits_notifier.dart); signed-in
/// free accounts get a generous cap that most users won't hit for weeks —
/// the paywall should feel like an invitation, not a wall.
const int kFreeHabitLimit = 10;

/// How many reminders the free tier can attach to a single Matrix task.
/// One is the whole free offering here, and deliberately so: a single
/// reminder is what a task app is expected to do at all, while *stacking*
/// them — nudged at 3:00, 3:30 and 4:00 for a 5pm meeting — is the alarm-
/// clock behaviour worth paying for. Premium is uncapped rather than
/// merely a bigger number, so the upgrade reads as "this limit goes away"
/// instead of trading one ceiling for another.
///
/// Note this gates *adding*, not keeping: [canAddReminder] is only ever
/// asked before a new reminder is created, so a task that already carries
/// several keeps firing all of them if an entitlement lapses. Silently
/// dropping reminders someone had set would be the worst possible way to
/// find out a subscription expired.
///
/// Separately from this product cap, NotificationService.
/// kMaxTaskReminderSlots bounds how many of a task's reminders can be
/// armed with the OS at once — that one is an iOS platform limit, not a
/// tier limit, and applies to Premium too.
const int kFreeTaskReminders = 1;

/// Whether another reminder may be added to a task that currently has
/// [current] of them. Pure so it's unit-testable without Riverpod or
/// RevenueCat, same shape and reasoning as [canBrowseHistoryMonth].
bool canAddReminder({required int current, required bool isPremium}) =>
    isPremium || current < kFreeTaskReminders;

/// How many reminders one HABIT may carry on the free tier.
///
/// Deliberately the same number, and the same argument, as
/// [kFreeTaskReminders]: one nudge at the time you chose is what a habit
/// tracker is expected to do, and a stack around that one moment — ten
/// minutes before Maghrib, again on the dot, again half an hour after — is
/// the part worth paying for. Two features asking the identical question
/// should not answer it differently, or the app has two reminder rules to
/// learn instead of one.
///
/// "Reminders", not "extras": a habit's primary shift
/// (IslamicHabitTemplate.reminderOffsetMinutes) counts toward this, exactly
/// as a task's anchor counts toward its own limit. So free means the one
/// reminder every habit has always had, and nothing is taken away from
/// anybody by this gate existing.
///
/// Gates *adding* only, for the same reason [kFreeTaskReminders] does: a
/// habit that already carries a stack keeps firing all of it if an
/// entitlement lapses, and can still have entries removed.
///
/// Separately from this product cap, [kMaxHabitReminders] bounds how many
/// the OS will hold for one habit — that one applies to Premium too.
const int kFreeHabitReminders = 1;

/// The ceiling on one habit's reminder stack, Premium included.
///
/// Lower than a task's eight because a habit's reminders are STANDING: each
/// one occupies a pending OS notification every day for as long as the
/// habit lives, where a task's are spent once and gone. iOS keeps only 64
/// pending notifications per app, and NotificationService already sizes its
/// own budget note against "8 habits at 4 times a day" — four is that same
/// number, so a habit with a stack costs no more than a habit counted four
/// times a day already did.
const int kMaxHabitReminders = 4;

/// Whether another reminder may be added to a habit that currently has
/// [current] of them (its primary shift included). Pure, same shape as
/// [canAddReminder], and it answers false at [kMaxHabitReminders] for
/// everyone: [locked] separates "you could buy this" from "this is full".
({bool allowed, bool locked}) canAddHabitReminder({
  required int current,
  required bool isPremium,
}) {
  if (current >= kMaxHabitReminders) return (allowed: false, locked: false);
  if (isPremium || current < kFreeHabitReminders) {
    return (allowed: true, locked: false);
  }
  return (allowed: false, locked: true);
}

/// How many months of any history surface the free tier can browse — the
/// current month plus two before it, matching the Monthly Heatmap's free
/// window exactly so the whole app tells one consistent story: free sees
/// the recent past, Premium owns its whole history.
const int kFreeHistoryMonths = 3;

/// Whether a history screen (Night Review calendar, Habit Notes journal)
/// may browse to the month starting at [monthStart]. Pure so it's
/// unit-testable — see test/features/premium/history_gate_test.dart.
/// [now] is any date inside the current month (callers pass
/// `DateTime.now().effectiveDay`).
bool canBrowseHistoryMonth({
  required DateTime monthStart,
  required DateTime now,
  required bool isPremium,
}) {
  if (isPremium) return true;
  final monthsBack =
      (now.year - monthStart.year) * 12 + (now.month - monthStart.month);
  return monthsBack < kFreeHistoryMonths;
}

/// Whether the account has GrowDaily Premium.
///
/// This is the single entitlement seam for the whole app: every UI gate
/// (habit cap, voice notes, heatmap history, ...) reads this provider, and
/// it's driven entirely by [PurchaseService] — RevenueCat's verified
/// CustomerInfo, never a value this client could set on its own. There's
/// deliberately no Firestore field behind this anymore (see
/// firestore.rules' premiumFieldOk() comment, now historical): RevenueCat
/// tracks entitlement per App User ID and [PurchaseService.logIn]/[logOut]
/// (wired to authStateProvider — see main.dart) ties that id to this
/// account, so the same purchase already follows the account across
/// devices/reinstalls without this notifier needing to sync anything
/// itself.
/// Hive key for the last known entitlement, with the account it belonged to.
/// See [loadPersistedPremium] for why this exists at all.
const _kPremiumCacheKey = 'premium_entitlement_v1';

/// The entitlement this device last saw, for seeding [premiumProvider]
/// before the first frame.
///
/// ── Why a cache, when RevenueCat is the source of truth ────────────────
/// It used to start at `false` every single launch and only become true
/// after [PurchaseService.logIn] finished a NETWORK ROUND TRIP. Three things
/// followed from that, all of them reported as "the app does not know I am
/// Premium until I open the Premium page":
///
///  1. Every cold start flashed the free UI at a paying customer: locked
///     history, muted year strips, a blurred recap card, an upgrade banner.
///  2. Offline, it never recovered. A paying customer on a plane was simply
///     a free customer, because the only thing that could correct the guess
///     was a request that could not complete.
///  3. If that one request failed, nothing retried until the app was
///     resumed or the paywall screen was opened by hand, which is exactly
///     the "open the page and then it notices" behaviour.
///
/// So the entitlement is now persisted like every other boot-time setting
/// this app already restores before its first frame (theme mode, preset,
/// font, locale, guest mode). RevenueCat stays the ONLY authority: this is
/// a warm start, not a second source of truth, and the first authoritative
/// answer that arrives overwrites it in both directions, including a lapse
/// or a refund flipping it back off.
///
/// It is deliberately NOT a Firestore field. One used to exist and was
/// removed on purpose (see firestore.rules' premiumFieldOk() comment):
/// anything the client can write, the client can grant itself. A local
/// cache carries no such risk, because it can only ever make THIS device
/// briefly optimistic about an account that already had the entitlement,
/// and the SDK corrects it within seconds. Cross-device is already solved
/// by RevenueCat itself, which keys entitlement to the App User ID that
/// [PurchaseService.logIn] binds to the account.
Future<bool> loadPersistedPremium() async {
  // A read that throws would take main.dart's boot sequence with it, so a
  // broken box answers "free" and lets RevenueCat correct it, exactly as it
  // would for a device that had never cached anything.
  try {
    final box = await LocalStoreService.settingsBox();
    final raw = box.get(_kPremiumCacheKey);
    if (raw is! Map) return false;
    return raw['entitled'] == true;
  } catch (_) {
    return false;
  }
}

/// The account the cached entitlement belonged to, so a DIFFERENT account
/// signing in on this device can never inherit it.
Future<String?> loadPersistedPremiumUid() async {
  try {
    final box = await LocalStoreService.settingsBox();
    final raw = box.get(_kPremiumCacheKey);
    if (raw is! Map) return null;
    final uid = raw['uid'];
    return uid is String && uid.isNotEmpty ? uid : null;
  } catch (_) {
    return null;
  }
}

class PremiumNotifier extends StateNotifier<bool> {
  StreamSubscription<CustomerInfo>? _sub;

  /// WEB ONLY: the server-written entitlement mirror on `users/{uid}`.
  ///
  /// RevenueCat has no Flutter web SDK, so PurchaseService.configure()
  /// returns null on kIsWeb and [customerInfoUpdates] never emits there.
  /// Someone who bought Premium on their iPhone therefore read as FREE on
  /// the web app, with no way to prove otherwise. The revenueCatWebhook
  /// Cloud Function mirrors the entitlement onto the user doc and this
  /// listens to it.
  ///
  /// Deliberately NOT used on iOS or Android. The SDK is the authority
  /// there: it is fresher than any webhook (a purchase is live before the
  /// event lands), it works offline from its own cache, and it keeps
  /// working through a webhook outage. Reading the mirror on mobile would
  /// trade all three for nothing.
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _mirrorSub;

  /// The account this device's cached entitlement was written for, read from
  /// disk at boot. Compared against the account that actually signs in, in
  /// [bindAccount].
  String? _cachedUid;

  /// The signed-in account, once known. Null for a guest.
  String? _uid;

  PremiumNotifier({bool initial = false, String? cachedUid})
      : _cachedUid = cachedUid,
        _uid = cachedUid,
        super(initial) {
    // Live updates for anything that happens *after* construction — a
    // purchase completing, a renewal or refund picked up on next launch,
    // a restore. See PurchaseService.customerInfoUpdates' doc comment.
    _sub = PurchaseService.instance.customerInfoUpdates.listen(applyCustomerInfo);
    // Plus an immediate one-time look so state isn't just the cached guess
    // until the first update happens to arrive — mirrors every other
    // notifier here that seeds itself at construction.
    refresh();
  }

  /// Ties the cached entitlement to the account that actually signed in.
  ///
  /// Called from main.dart's auth listener, alongside [PurchaseService.logIn].
  /// If this device's cache belonged to a DIFFERENT account, the seeded guess
  /// is wrong and is dropped immediately rather than left standing until
  /// RevenueCat answers: a shared or resold device must never show one
  /// person's subscription to the next person who signs in.
  void bindAccount(String uid) {
    _uid = uid;
    _listenToMirror(uid);
    final stale = _cachedUid != null && _cachedUid != uid;
    _cachedUid = uid;
    if (stale && state) {
      // Deferred by a microtask, and that is not a detail.
      //
      // main.dart's auth listener is registered with fireImmediately, so on
      // a cold start this runs SYNCHRONOUSLY inside initState, while the
      // widget tree is still building. Dropping `state` right here would
      // notify every widget watching premiumProvider mid-build, which
      // Flutter asserts on ('!_dirty': markNeedsBuild during build) and
      // which takes the whole app to a red screen rather than to the free
      // tier. A microtask runs the moment that synchronous work finishes,
      // so the wrong entitlement is never painted, and never mutated from
      // inside a build either.
      Future.microtask(() => _set(false));
      return;
    }
    // Re-stamp the cache under this uid so a guest who signs up keeps the
    // entitlement they just bought.
    if (state) _persist();
  }

  /// Signed out. Drops the entitlement and the cache together, so the next
  /// account on this device starts from nothing rather than from whatever
  /// the last one had.
  void detachAccount() {
    _uid = null;
    _cachedUid = null;
    _mirrorSub?.cancel();
    _mirrorSub = null;
    _set(false);
  }

  /// Subscribes to this account's server-written mirror, on web only.
  ///
  /// The callback is async by construction (a Firestore snapshot never
  /// arrives inside a build), so unlike [bindAccount]'s own stale-cache
  /// path this needs no microtask guard.
  void _listenToMirror(String uid) {
    if (!kIsWeb) return;
    _mirrorSub?.cancel();
    _mirrorSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen(
      (snap) {
        // A doc that has never been written by the webhook says nothing
        // about entitlement, so it reads as free rather than as an error.
        if (_uid != uid) return; // Account changed while in flight.
        _set(_mirrorSaysPremium(snap.data()));
      },
      // Offline, signed out mid-stream, or rules denied: fail to FREE and
      // let a later snapshot correct it. Never throw into the zone.
      onError: (_) {},
    );
  }

  /// Whether the mirror on the user doc grants Premium right now.
  ///
  /// `premiumActive` is the webhook's verdict at the moment it wrote. The
  /// expiry is re-checked here as well, so a subscription that lapsed
  /// while no webhook landed (an outage, a dropped delivery) stops reading
  /// as Premium rather than hanging on until the next event.
  static bool _mirrorSaysPremium(Map<String, dynamic>? data) {
    if (data == null) return false;
    if (data['premiumActive'] != true) return false;
    final expires = data['premiumExpiresAtMs'];
    if (expires is! int) return true; // Lifetime, or no expiry recorded.
    return expires > DateTime.now().millisecondsSinceEpoch;
  }

  void _set(bool entitled) {
    if (!mounted) return;
    if (entitled && !state) {
      AnalyticsService.instance.track('premium_activated');
    }
    final changed = entitled != state;
    state = entitled;
    if (changed || entitled) _persist();
  }

  void _persist() {
    // Fire and forget: a failed write costs one cold start's worth of
    // optimism, never correctness, since RevenueCat still answers.
    //
    // try/catch AND catchError, which is not belt and braces. Opening the
    // box can fail SYNCHRONOUSLY (LocalStoreService.settingsBox throws a
    // HiveError outright when Hive has not been initialised), and a
    // synchronous throw walks straight past .catchError, which only ever
    // sees a failed Future. This is called from bindAccount during app
    // start, so an escaping throw there would land mid-mount and take the
    // first frame with it. Caching the entitlement must never be able to
    // stop the app opening.
    unawaited(_write());
  }

  /// The actual write, `await`ed inside a try so BOTH failure shapes land in
  /// the same catch.
  ///
  /// Opening a Hive box can fail synchronously (no path configured) and can
  /// also complete its future with an error, and a `.then(...).catchError(...)`
  /// chain does not reliably contain both: the synchronous throw escapes to
  /// the caller, which here is bindAccount, which main.dart calls during app
  /// start. An escaping throw there lands mid-mount and takes the first frame
  /// with it, turning a best-effort cache write into a launch failure.
  ///
  /// Not unit-testable, and worth saying why so nobody tries again: Hive
  /// completes its own internal opening-box completer with the same error, so
  /// in a test zone the failure is reported as unhandled no matter how
  /// completely the CALLER handles it. A test asserting "this does not throw"
  /// fails even when the code under test is perfect, which is how the first
  /// attempt at one fooled itself. In the app there is no such zone, and this
  /// catch is what keeps the throw off bindAccount's caller.
  Future<void> _write() async {
    try {
      final box = await LocalStoreService.settingsBox();
      await box.put(_kPremiumCacheKey, {'uid': _uid, 'entitled': state});
    } catch (_) {
      // Nothing to do: the next authoritative answer rewrites this anyway.
    }
  }

  /// Applies [info] to [state] right now, synchronously - no waiting on
  /// the async stream above. PremiumScreen calls this immediately after a
  /// successful purchase/restore with the CustomerInfo RevenueCat already
  /// handed back in that same call, rather than trusting that
  /// [PurchaseService.customerInfoUpdates] has delivered the same update
  /// yet. Both paths carry the same already-verified CustomerInfo -
  /// calling this early is just removing a race between "the purchase
  /// call resolved" and "the separate listener happened to fire", not a
  /// second source of truth. Safe to call redundantly (idempotent): if
  /// the stream listener above also reports the same info moments later,
  /// `entitled == state` and nothing changes.
  void applyCustomerInfo(CustomerInfo info) {
    if (!mounted) return;
    _set(PurchaseService.instance.isEntitled(info));
  }

  /// Forces a fresh look at RevenueCat's cached entitlement. Cheap and
  /// safe to call often (see PurchaseService.getCustomerInfo's doc
  /// comment) — kept for main.dart's app-resume hook, same as every other
  /// notifier's refresh() here.
  Future<void> refresh() async {
    final info = await PurchaseService.instance.getCustomerInfo();
    if (info != null && mounted) {
      // Through _set, not a bare assignment: a refresh that finds a lapsed
      // subscription has to clear the cache too, or the next cold start
      // would seed the entitlement straight back.
      _set(PurchaseService.instance.isEntitled(info));
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _mirrorSub?.cancel();
    super.dispose();
  }
}

final premiumProvider =
    StateNotifierProvider<PremiumNotifier, bool>((ref) => PremiumNotifier());

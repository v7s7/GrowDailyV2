import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color, TimeOfDay;
import 'package:flutter/services.dart' show MethodChannel, PlatformException;
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../features/grid/models/square_state.dart';
import '../../features/habits/models/habit_schedule.dart';
import '../../features/settings/models/notification_settings.dart';
import '../extensions/datetime_ext.dart';
import '../l10n/reminder_copy.dart';
import 'local_store_service.dart';
import 'evening_note_record.dart';
import 'alarm_service.dart';
import 'armed_reminder_record.dart';
import 'armed_task_record.dart';
import 'home_widget_service.dart';
import 'notification_action_background.dart';
import 'prayer_times_service.dart';

/// One habit's reminder inputs, as read straight off its [HabitCue] by
/// main.dart — a *raw*, unresolved cue (at most one of [clockTimes]/
/// [prayerKey] is set, never both) plus the dashboard context needed to
/// decide whether to fire at all. Turning this into an actual fire time —
/// including the prayer-time calculation itself — happens inside
/// [NotificationService.scheduleSmartReminders], alongside the settings
/// that affect it (location, calculation method, offset, quiet hours), so
/// main.dart's job stays "read the providers and hand over what they say"
/// rather than duplicating scheduling policy.
typedef HabitReminderInput = ({
  String id,
  String name,
  /// Every clock time this habit is due at, ascending and deduped — the
  /// canonical list [HabitCue.clockTimes] hands back. Empty for a
  /// prayer-linked or freeform cue.
  ///
  /// One reminder is scheduled per entry, and an entry's INDEX here is the
  /// notification slot it owns for the life of that habit. Still mutually
  /// exclusive with [prayerKey]: a habit is anchored to clock times or to a
  /// prayer, never both.
  List<TimeOfDay> clockTimes,
  /// The signed shift for each entry of [clockTimes], index-aligned.
  ///
  /// A multi-time habit carries its own per-time shifts (they live in the cue
  /// beside the times, so the two cannot desync); a single-time one gets a
  /// one-entry list holding the habit's reminderOffsetMinutes, which is
  /// exactly what it has always used. Either way this is the only number the
  /// scheduler reads, so there is never a question of the two stacking.
  List<int> clockOffsets,

  /// How many consecutive slots belong to a SINGLE occurrence of this habit.
  ///
  /// 1 for every habit whose reminders are one-per-occurrence, which is every
  /// habit that predates stacked reminders and every multi-time habit. Higher
  /// only when one anchor is fired at several shifts (see
  /// IslamicHabitTemplate.extraReminderOffsets), where the slots come in
  /// runs of this size.
  ///
  /// It exists for the done-suppression below, which stands down the earliest
  /// still-today reminders one per completion. That arithmetic is only right
  /// while a slot IS an occurrence: with a stack, logging the habit once
  /// silenced its ten-minutes-early nudge and then still pinged on the dot
  /// and again half an hour later, for a square already filled.
  int remindersPerOccurrence,

  /// The extra shifts a PRAYER-anchored habit fires at, on top of
  /// [reminderOffsetMinutes]. Empty for everything else.
  ///
  /// Clock-anchored stacks arrive here already expanded into [clockTimes] /
  /// [clockOffsets], because a clock time is a moment this file can compute
  /// on its own. A prayer is not: its moment comes from PrayerTimesService a
  /// day at a time, inside the resolution loop below, so the stack has to be
  /// applied there rather than by the caller.
  List<int> extraReminderOffsets,
  String? prayerKey,
  int streak,
  /// How many of today's [dailyTarget] have already been logged.
  ///
  /// Replaces a plain `isDoneToday` bool, which could not express the state a
  /// habit counted several times a day spends most of its day in. One of two
  /// done at 2pm used to read as "not done" and re-arm BOTH reminders, or —
  /// had it read as done — cancel the evening one the person still needed.
  int completedCount,
  int dailyTarget,
  /// Effective days since this habit was last completed, or null if it never
  /// has been. Feeds the reminder's own wording, not its schedule, and now
  /// only tells a habit never done from one done before: a habit never once
  /// done is asked for its first square («بسم الله، أول مربع لها.»), and no
  /// line names how long it has been since. See habitOnTimeLine.
  int? lastDoneDaysAgo,
  /// How long this habit's timer runs, when it has one, so the reminder can
  /// state the real length instead of gesturing at «بضع دقائق». Null for a
  /// habit with no timer.
  int? timerSeconds,
  // Signed minutes from the resolved clock/prayer moment to the fire time:
  // negative = before, 0 = exactly on time, positive = after. Ignored when
  // both clockTimes and prayerKey are empty/null, since there's no moment to
  // offset from. Mirrors IslamicHabitTemplate.reminderOffsetMinutes — see
  // that field's doc comment for the migration off the old always-before
  // `reminderLeadMinutes`.
  int reminderOffsetMinutes,
  // Lets this habit's reminder through quiet hours (the per-habit "Allow
  // anyway" escape hatch). Mirrors IslamicHabitTemplate.ignoreQuietHours.
  bool ignoreQuietHours,
  // Ring as a real alarm rather than a notification. Mirrors
  // IslamicHabitTemplate.alarm; what that means per platform is
  // AlarmService's business, and a slot that cannot be an alarm falls
  // back to a Time Sensitive notification (see _scheduleOne).
  bool alarm,
  /// A quit habit («ترك أو تقليل»). Its timed reminder is a check-in with
  /// التزام / ما التزمت under it, never Mark Done / Snooze, never an alarm, and
  /// never bundled with build habits (see _scheduleOne).
  bool isQuit,
  /// The set-a-limit shape of a quit habit; picks the check-in's question.
  bool isLimit,
  /// The weekdays this habit is actually due on (DateTime.weekday values,
  /// 1 = Monday … 7 = Sunday). Empty means every day.
  ///
  /// The scheduler needs this because a fire time ROLLS: a reminder whose
  /// clock time has already passed moves to the next day, and without
  /// knowing the habit's real schedule that next day can be one the habit
  /// was never due on. A habit set to Sun/Tue/Thu at 20:00, recomputed at
  /// 21:00 on Thursday, was scheduled for Friday 20:00 and pinged about a
  /// day it does not run. See [resolveClockSlots].
  Set<int> scheduledWeekdays,
  /// What the offset is measured FROM, already localized, when that has a
  /// name worth saying out loud: "المغرب" / "Maghrib" for a prayer-linked
  /// habit, null for a clock time.
  ///
  /// Only ever a prayer. A clock cue's anchor is a clock time, and the
  /// notification's own timestamp already shows the reader a clock, so
  /// naming it back at them ("باقي ١٥ دقيقة على ٩:٠٠") adds nothing — see
  /// habitReminderBody in core/l10n/reminder_copy.dart. Passed in by
  /// main.dart rather than derived from [prayerKey] here, because the cue
  /// that knows the label is already open on that side and this file has no
  /// business owning a second copy of the prayer names.
  String? anchorLabel,
  /// For a flexible weekly quota ("N times a week, any days"), N. Null for
  /// a daily habit and for one pinned to specific weekdays, which are judged
  /// by their days; a quota habit has none and is judged by its week. See
  /// quotaFactsOn (habit_schedule.dart) and habitOnTimeLine.
  int? weekTarget,
  /// For a quota habit, the indices (0 = the Saturday that starts the
  /// current display week) of this week's days already logged, or null
  /// while the week's squares are not loaded, in which case the wording
  /// makes no claim about the week. Ignored when [weekTarget] is null.
  Set<int>? weekDoneDays,
});

typedef _ResolvedReminder = ({
  String id,
  String name,
  tz.TZDateTime fireTime,
  int streak,
  /// Which of this habit's reminder slots this is — the index of its time in
  /// [HabitReminderInput.clockTimes]. See [NotificationService._habitReminderId].
  int slot,
  /// How many occurrences ahead of the next one this is: 0 is the very next
  /// time this slot comes round, 1 the one after that, and so on up to
  /// [NotificationService.kOccurrencesPerSlot] - 1.
  ///
  /// A slot used to hold exactly one pending notification, which meant a
  /// phone that was not opened for a day had nothing left armed for the day
  /// after. Keeping the next few occurrences of every slot in the scheduler
  /// at once is what closes that, and depth is the extra dimension the id
  /// needs so the copies can be scheduled and cancelled independently — see
  /// [NotificationService._habitReminderId].
  int depth,
  /// Signed minutes from the moment this reminder is ABOUT to the moment it
  /// actually fires: negative = early, 0 = on the dot, positive = late.
  ///
  /// [fireTime] alone cannot answer this — it is already post-offset, so
  /// there is nothing left to difference it against. Carried through here
  /// so the body can say which of the three it is; without it every
  /// reminder claimed to be the third.
  int offsetMinutes,
  /// The prayer this habit's offset is measured from, localized, or null
  /// for a clock time. Mirrors [HabitReminderInput.anchorLabel].
  String? anchorLabel,
  /// Today's progress and the target it counts against, for the "2 of 3
  /// today" line. Mirrors [HabitReminderInput]'s pair; only read when this
  /// reminder actually fires on the effective day it was armed on, since
  /// the text is baked in at schedule time and today's count says nothing
  /// about a slot that rolled to tomorrow. See
  /// [NotificationService._scheduleOne].
  int completedCount,
  int dailyTarget,
  /// Mirrors [HabitReminderInput.lastDoneDaysAgo], measured from today; the
  /// distance to [fireTime] is added back on when the body is built.
  int? lastDoneDaysAgo,
  /// Mirrors [HabitReminderInput.timerSeconds].
  int? timerSeconds,
  /// The habit's schedule, carried through so the wording can be re-based
  /// onto the fire day on the habit's OWN days rather than the calendar.
  /// Mirrors [HabitReminderInput.scheduledWeekdays], [weekTarget] and
  /// [weekDoneDays]; see [NotificationService.reminderFactsAtFireDay].
  Set<int> scheduledWeekdays,
  int? weekTarget,
  Set<int>? weekDoneDays,
  /// Whether this reminder is anchored to a prayer, which makes it Time
  /// Sensitive on iOS: delivered through Focus and Do Not Disturb, the way
  /// the app's own quiet hours already step aside for a prayer cue (see
  /// NotificationSettings.quietHoursAppliesToPrayer). A clock reminder is
  /// not: a Focus the person set is theirs to keep, and a 9pm habit nudge
  /// is not the kind of moment that justifies breaking it.
  bool timeSensitive,
  /// Mirrors [HabitReminderInput.alarm]: this slot is scheduled through
  /// AlarmService when it can be, and never bundled with other habits,
  /// since an alarm has one thing to say and one button to say it with.
  bool alarm,
  /// Mirrors [HabitReminderInput.isQuit] and [HabitReminderInput.isLimit].
  bool isQuit,
  bool isLimit,
});

/// The habit with the most green days in the Grid's current week, which
/// names Friday's numbered note (see NotificationService.weeklyNotePlan).
/// [isQuit] counts its green days as «التزام» rather than «خضرا».
typedef WeekTopHabit = ({String name, int greenDays, bool isQuit});

/// One habit's week as the Friday note reads it: its name in the app's
/// language, whether it is a quit habit, and the seven squares of the week
/// the Grid is showing. See [NotificationService.weekTopHabit].
typedef WeekHabitRow = ({String name, bool isQuit, List<SquareState> squares});

/// One habit of today's board as the evening streak note counts it: done for
/// the day or not, and whether it is a quit habit. See
/// [NotificationService.todayBoardCounts].
typedef TodayBoardHabit = ({bool isDone, bool isQuit});

/// Today's board in the three numbers the evening streak note is worded
/// from. [pendingBuild] is the build habits among [pending].
typedef TodayBoardCounts = ({int done, int pending, int pendingBuild});

/// What a recompute may say about the week, which depends on what the Grid
/// is showing. See [NotificationService.weeklyNoteBasis].
enum WeeklyNoteBasis {
  /// The Grid is mid-load. Whatever the last recompute armed is left alone,
  /// and the recompute the moment the real data lands decides.
  skip,

  /// The Grid has loaded THIS week, so its squares can be counted: the
  /// numbered copy, if the week is worth numbering.
  numbered,

  /// The Grid has loaded another week, so this week's squares are not in
  /// hand. Only the claim-free copy, and a numbered copy an earlier
  /// recompute armed is cleared rather than left to fire a stale count.
  claimFree,
}

/// One notification the Friday note arms: its id, its words, when, and
/// whether it repeats every Friday or fires once.
typedef WeeklyNoteSlot = ({
  int id,
  ReminderLine copy,
  DateTime fireAt,
  bool repeatsWeekly,
});

/// Real local-notification service backing daily/habit reminders,
/// prayer-linked reminders, streak-risk nudges, and in-the-moment
/// celebration pings (habit completed, level up, achievement unlocked).
///
/// A habit or task reminder can also ring as a real ALARM instead of a
/// notification (IslamicHabitTemplate.alarm, MatrixTask.alarm, chosen per
/// item in the sheets). Those slots go through AlarmService, which is
/// AlarmKit on iOS 26 and newer; on Android the same choice lands on the
/// alarm-audio channel below, and anywhere a real alarm cannot be made the
/// slot falls back to a Time Sensitive notification. The alarm and the
/// notification for one slot share an id, and every schedule clears the
/// other system's copy, so a reminder never rings twice.
/// Uses `flutter_local_notifications` — no remote push server is involved,
/// everything is scheduled/fired on-device, which is what keeps this
/// entirely free to run. Prayer-linked reminders resolve their fire time
/// through [PrayerTimesService], which reaches out to a live prayer-times
/// API for an exact result and falls back to an offline calculation when
/// there's no connection — see that class's doc comment.
///
/// ── Why "smart" scheduling means one-off, not recurring ─────────────
/// flutter_local_notifications can schedule a notification that recurs
/// forever at a fixed clock time (`matchDateTimeComponents:
/// DateTimeComponents.time`), which used to be how per-habit reminders
/// worked here — but a recurring schedule fires unconditionally, with no
/// way to skip just *today's* occurrence. That's a real problem for
/// "smart, not spammy": it means still nagging about a habit that's
/// already been marked done for the day. A fixed clock time is also simply
/// the WRONG time for a prayer-anchored habit, which is the other half of
/// the argument: "fifteen minutes before Fajr" is a different moment every
/// morning, and a recurring schedule would freeze it at whatever it was
/// the day it was armed — about twenty minutes out by the end of a month.
/// So each occurrence is scheduled individually, computed for the day it
/// lands on, and re-decided every time something relevant changes: a habit
/// gets completed, the habit list changes, settings change, or the app
/// comes back to the foreground (see main.dart's
/// `_recomputeNotifications`, which is wired to all of those).
///
/// ── How far ahead ────────────────────────────────────────────────────
/// One occurrence per slot was the original answer, and it left a hole: a
/// phone that was not opened for a day had nothing armed for the day after,
/// so the reminders went quiet until it was. Each slot now keeps its next
/// [kOccurrencesPerSlot] occurrences armed at once, each one resolved
/// against its OWN day — a prayer-anchored habit reads that day's prayer
/// times (PrayerTimesService.calculateDays, one request per month for any
/// country, and Bahrain's bundled official table with no request at all),
/// and a clock habit is rebuilt from that day's wall clock so a daylight
/// saving change does not shift it by an hour. Same-day completion still
/// stands down only the copies that belong to today, so finishing a habit
/// silences today and leaves tomorrow morning armed.
///
/// A reminder that rings as a real alarm keeps a month instead
/// ([kAlarmWindowDays]): alarms sit outside the notification budget, and a
/// wake-up alarm is the one reminder that must not go quiet because the app
/// was left closed for a few days.
///
/// The window is bounded by iOS's hard 64-pending limit rather than by
/// appetite — see [kMaxPendingHabitSlots] and _scheduleResolved's trim,
/// which drops the latest-firing entries first, so a heavy user loses the
/// far end of the window and never the next reminder.
///
/// One-time native setup still required after `flutter create .` generates
/// the ios/ and android/ folders on your Mac:
///   iOS    — none beyond what this service already requests at runtime.
///   Android — a small notification icon at
///             android/app/src/main/res/drawable/ic_notification.png
///             (falls back to @mipmap/ic_launcher if you skip this).
class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();

  /// The daily reminder's fallback: seven weekly repeats, ids 1001 to 1007,
  /// one per DateTime weekday (Monday is 1). See [scheduleDailyReminder].
  static const _dailyFallbackBase = 1000;
  /// Tonight's one-shot, worded from where the day stands; see
  /// [scheduleDailyReminder].
  static const _dailyTonightId = 1010;
  /// Today's board as last reported by main.dart's recompute, kept so a
  /// caller with no state of its own cannot reword tonight's line.
  ({
    int done,
    int total,
    int streak,
    bool streakEarnedToday,
    int pendingBuild,
  })? _dailyState;
  /// The notification settings as last reported by main.dart's recompute,
  /// kept for the same reason [_dailyState] is: see [scheduleEveningNote].
  NotificationSettings? _eveningSettings;
  /// The channel every ordinary reminder and celebration posts to.
  ///
  /// ── Why the id has a v2 on it ────────────────────────────────────────
  /// Android FREEZES a channel's importance the moment it is first created.
  /// createNotificationChannel on an existing id updates its name and
  /// description and nothing else, deliberately, so that a person's own
  /// choice about how loud an app is allowed to be cannot be overwritten by
  /// an update. The only way to change the importance the app SHIPS with is
  /// a new id.
  ///
  /// It had to change because the old channel was IMPORTANCE_DEFAULT, and on
  /// Android that means the reminder makes a sound and slides into the shade
  /// without ever appearing on screen. No heads-up banner, at all. The same
  /// reminder on iOS arrives as a banner, and the alarm channel below was
  /// already IMPORTANCE_MAX, so a habit reminder was the one thing in this
  /// app that quietly did not show up — for a reminder the person explicitly
  /// asked for, at a time they chose.
  ///
  /// IMPORTANCE_HIGH, not MAX: high is a banner, max additionally overrides
  /// Do Not Disturb and is what an alarm the person set to wake them uses
  /// (see [_alarmChannelId]). A reminder should be seen, not force its way
  /// past a Focus.
  static const _channelId = 'growdaily_reminders_v2';
  static const _channelName = 'Grow Daily';
  static const _channelDesc = 'Habit reminders and progress celebrations';

  /// The pre-v2 id, kept only so [init] can clean it out of the person's
  /// notification settings, where it would otherwise sit forever as a second
  /// empty entry for the same app.
  static const _legacyChannelId = 'growdaily_general';

  // Android's answer to "ring as an alarm": a second channel on the ALARM
  // audio stream at maximum importance, so a reminder the person switched
  // to alarm plays at alarm volume and through Do Not Disturb wherever the
  // person allows alarms, the way a clock app's would. iOS needs no channel:
  // its alarms are real AlarmKit alarms, see AlarmService.
  /// The accent Android tints a notification's small icon and app name
  /// with, on the notifications this app posts ITSELF.
  ///
  /// The same value as `@color/notification_color` in
  /// android/app/src/main/res/values/colors.xml, which the manifest already
  /// points FCM at. That meta-data only covers notifications the Firebase
  /// SDK builds from a tray push; anything posted through
  /// flutter_local_notifications carries no colour unless it is set here, so
  /// a room push arrived brand green and the habit reminder beside it
  /// arrived grey — one app looking like two in the same shade.
  ///
  /// Deliberately a constant and not the live theme preset, for the same
  /// reason colors.xml gives: a person who switches to Ocean or Nour Violet
  /// changes GameColors at runtime, and a notification already handed to the
  /// system cannot follow. The default brand green is the honest constant.
  static const _notificationAccent = Color(0xFF2ECF8F);

  static const _alarmChannelId = 'growdaily_alarm';
  static const _alarmChannelName = 'Grow Daily alarms';
  static const _alarmChannelDesc = 'Reminders you chose to ring as alarms';

  // ── Actionable notifications ─────────────────────────────────
  //
  // The iOS actions are BACKGROUND actions (no DarwinNotificationActionOption
  // .foreground); Android's still open the app (showsUserInterface: true).
  //
  // iOS used to match Android, and the reason it no longer does is a wrist:
  // a paired Apple Watch hides foreground actions when the app has no watch
  // app, because there is nothing on the watch to bring forward. So «تمت»
  // and «تأجيل ساعة» existed on the phone and were simply absent from the
  // very same reminder on the watch, which showed only Dismiss. (The watch
  // simulator still draws them, which is how this went unnoticed.) A
  // background action is shown on both devices and delivered to the phone
  // either way, and it also means marking a habit done from the lock screen
  // no longer has to open the app.
  //
  // The cost is that the tap arrives in a second, headless Flutter engine
  // with none of the app's state, so it is not completed there. It is
  // queued and paid at the next app open, through the exact
  // _handleNotificationAction path a foreground tap always used; see
  // notification_action_background.dart for the split and main.dart's
  // _processPendingNotificationActions for the drain. Snooze is the one
  // action that acts in the background engine itself. None of it runs
  // without two lines in ios/Runner/AppDelegate.swift (the notification
  // centre delegate, and a background task around each response); that
  // file says why.
  static const _habitCategoryId = 'habitReminderCategory';
  static const actionMarkDone = 'mark_done';
  static const actionSnooze = 'snooze_1h';

  // Quit-habit evening check-in — its own category because its two actions
  // mean something different from Mark Done/Snooze: "On Track" affirms the
  // day (same reward path as Mark Done), "Slipped" logs today as a
  // slip/over-limit day (red square, any same-day reward reversed) — see
  // main.dart's _handleNotificationAction. Same background routing as the
  // habit category above.
  static const _quitCategoryId = 'quitCheckInCategory';
  static const actionStayedClean = 'quit_on_track';
  static const actionSlipped = 'quit_slipped';

  /// Body-tap payload for notifications whose natural landing place is the
  /// Today screen (daily reminder, streak-risk nudge) — deliberately a
  /// value that can never collide with a habit/task id, which are UUIDs or
  /// snake_case catalog ids, never colon-prefixed.
  static const openTodayPayload = 'open:today';

  /// Body-tap payload for the week's numbered note (the one-shot armed at
  /// [_weeklyNumberedId]): it is about the week that has just sealed, and
  /// Profile shows that week's recap card from the instant it goes out, so
  /// the tap lands there (see weeklyNoteTapRoute). Same colon-prefixed shape
  /// as [openTodayPayload], for the same reason.
  static const openWeeklyRecapPayload = 'open:weekly-recap';

  bool _initialized = false;

  // A response that arrived before `onAction` was wired up — either a cold
  // app-launch resolved during init(), or (in principle) a very early tap
  // that raced main.dart's initState(). Flushed the moment onAction is set.
  NotificationResponse? _pendingResponse;
  void Function(String actionId, String? payload)? _onAction;

  /// Set once, from main.dart's app-level State, after the provider tree
  /// exists — so Mark Done/Snooze taps can call straight into the same
  /// completeHabit/snooze logic the UI itself uses. Assigning this replays
  /// any response that arrived first (e.g. the app was cold-launched by a
  /// notification action before this was set).
  set onAction(void Function(String actionId, String? payload)? callback) {
    _onAction = callback;
    final pending = _pendingResponse;
    if (callback != null && pending != null) {
      _pendingResponse = null;
      callback(pending.actionId ?? '', pending.payload);
    }
  }

  /// Inert since 2026-09-24. It gated the celebration pings, then only a
  /// room's local new-habit banner, and both are gone, so main.dart no
  /// longer mirrors it. The widget tests still set it false (from when it
  /// kept their suites headless), so it stays a no-op until they are
  /// cleaned up together.
  set celebrationsEnabled(bool value) {}

  /// Whether the app is currently running in Arabic — kept in sync by
  /// main.dart's reactive settings listener (this is a plain singleton with
  /// no ProviderRef and no BuildContext, so it can't read the locale
  /// itself).
  ///
  /// The celebration notifications below used to be hardcoded English —
  /// "Level up!", "Achievement unlocked", "+120 XP · +30 Gold" — which
  /// meant an Arabic user earned "شهر من الإتقان" in the app and then got
  /// a push notification about "Month of Mastery". Every *scheduled*
  /// notification in this file was already localized (they take an `isAr`
  /// argument from a widget that has a BuildContext); these three fire
  /// from DashboardNotifier, which has neither, hence the flag.
  ///
  /// Callers that need to localize their *own* argument — picking
  /// `AchievementModel.localName` for [showAchievementUnlocked], say —
  /// read this too, rather than each carrying a separate copy of the
  /// locale down to the call site.
  bool isArabic = false;

  void _dispatch(NotificationResponse response) {
    final callback = _onAction;
    if (callback == null) {
      _pendingResponse = response;
      return;
    }
    callback(response.actionId ?? '', response.payload);
  }

  /// Re-resolves the device's IANA timezone into tz.local.
  ///
  /// init() does this exactly once per process, which was correct until you
  /// consider travel: a device that changes timezone while the app stays
  /// alive kept scheduling every reminder on the OLD zone's wall clock (a
  /// 21:00 habit fired at 21:00 Bahrain time in London), and quiet hours
  /// were judged against the wrong local minutes. main.dart calls this on
  /// every app resume, before the recompute, so the first reschedule after
  /// landing is already in the new zone. Same silent-fallback contract as
  /// init(): an unresolvable name keeps the previous location.
  Future<void> refreshTimezone() async {
    if (kIsWeb) return;
    try {
      final currentTimeZone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(currentTimeZone));
    } catch (_) {}
  }

  /// Which language the iOS action buttons are currently registered in.
  ///
  /// English until [applyLocale] says otherwise, which is safe as a default
  /// for the window it covers: main.dart calls that as soon as it has read
  /// the persisted locale, before any reminder is scheduled.
  bool _actionsAreAr = false;

  /// iOS initialization settings, whose only language-dependent part is the
  /// two notification categories.
  ///
  /// An iOS action button belongs to a CATEGORY, registered once for the
  /// process, not to the individual notification the way Android's is. So
  /// this is the only place the buttons' language can be set, and changing
  /// it means registering the categories again.
  ///
  /// Not const: DarwinNotificationAction.plain() isn't a const constructor
  /// (confirmed by `flutter analyze`, not assumed), so nothing that
  /// contains it can be const either.
  DarwinInitializationSettings _iosInit(bool isAr) =>
      DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
        notificationCategories: [
          DarwinNotificationCategory(
            _habitCategoryId,
            actions: [
              DarwinNotificationAction.plain(
                actionMarkDone,
                markDoneAction(isAr),
              ),
              DarwinNotificationAction.plain(
                actionSnooze,
                snoozeAction(isAr),
              ),
            ],
          ),
          // Shared wording that works for both quit shapes: «التزام» / "On
          // Track" covers avoid-completely and set-a-limit alike, where
          // "Stayed Clean" would read oddly against a coffee limit.
          DarwinNotificationCategory(
            _quitCategoryId,
            actions: [
              DarwinNotificationAction.plain(
                actionStayedClean,
                onTrackAction(isAr),
              ),
              DarwinNotificationAction.plain(
                actionSlipped,
                slippedAction(isAr),
              ),
            ],
          ),
        ],
      );

  /// Points the iOS action buttons at [isAr]'s language, re-registering the
  /// categories if that is a change.
  ///
  /// Called at boot once the persisted locale has been read, and again from
  /// main.dart's locale listener, because someone switching the app to
  /// Arabic should not keep getting a «تمت» button that says "Mark Done".
  /// Re-registering is the documented way to replace a category set (iOS
  /// keeps whatever was registered last), and it only touches the buttons:
  /// ids, channels, pending schedules and the tap handler are all unchanged
  /// by it. No-ops on Android, where the labels are built per notification
  /// and already follow the language, and no-ops when nothing changed.
  Future<void> applyLocale(bool isAr) async {
    if (kIsWeb) return;
    if (!_initialized) {
      // A process whose first registration this is registers straight in
      // the right language, rather than English first and a second
      // registration to correct it. Both engines take this branch: main()
      // reads the persisted locale and calls this instead of init(), and the
      // background action engine (notification_action_background.dart) does
      // the same before a snooze. The gap between an English registration
      // and its correction is not academic: a background launch can be
      // suspended inside it, and the next reminder then shows English
      // buttons on an Arabic account (seen live on 2026-09-06).
      _actionsAreAr = isAr;
      await init();
      return;
    }
    await init();
    if (_actionsAreAr == isAr) return;
    _actionsAreAr = isAr;
    await _plugin.initialize(
      InitializationSettings(
        android:
            const AndroidInitializationSettings('@drawable/ic_notification'),
        iOS: _iosInit(isAr),
      ),
      onDidReceiveNotificationResponse: _dispatch,
      onDidReceiveBackgroundNotificationResponse: notificationActionBackground,
    );
    debugPrint(
        '[NotificationService] Action buttons now ${isAr ? 'ar' : 'en'}');
  }

  Future<void> init() async {
    if (kIsWeb || _initialized) return;

    tz_data.initializeTimeZones();
    try {
      final currentTimeZone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(currentTimeZone));
    } catch (_) {
      // Fall back to UTC if the plugin can't resolve the device's IANA
      // timezone name; schedules still fire, just anchored to UTC until
      // that's resolved.
    }

    // '@drawable/ic_notification', not '@mipmap/ic_launcher': Android draws a
    // notification's small icon as a pure alpha mask, discarding colour, so
    // the full-colour launcher icon arrives in the status bar as a
    // featureless white square. ic_notification is the seedling mark redrawn
    // as a white-on-transparent vector. Must stay in sync with the
    // com.google.firebase.messaging.default_notification_icon meta-data in
    // AndroidManifest.xml, so a local reminder and an FCM room push look the
    // same in the shade.
    const androidInit =
        AndroidInitializationSettings('@drawable/ic_notification');
    await _plugin.initialize(
      InitializationSettings(
          android: androidInit, iOS: _iosInit(_actionsAreAr)),
      onDidReceiveNotificationResponse: _dispatch,
      onDidReceiveBackgroundNotificationResponse: notificationActionBackground,
    );

    // Create the Android channel up front rather than letting the first
    // AndroidNotificationDetails create it lazily.
    //
    // On Android 8+ a notification posted to a channel that does not exist
    // yet is dropped by the system. The lazy path is fine for local
    // reminders, which are always posted by this process, but an FCM room
    // push (see functions/index.js notifyRoomFinish) can be handled by the
    // Firebase SDK while the app has never run a scheduling call - a fresh
    // install that joins a room and gets a push before setting its first
    // reminder. The manifest points FCM's default_notification_channel_id at
    // this same id, so creating it here is what makes that push land.
    //
    // No-op on iOS: resolvePlatformSpecificImplementation returns null.
    final androidChannels = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidChannels?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDesc,
        // See _channelId: high is a heads-up banner, which is what a
        // reminder the person asked for should be, and what the same
        // reminder already is on iOS.
        importance: Importance.high,
      ),
    );
    // The pre-v2 channel, removed rather than left behind. Android keeps a
    // channel until the app deletes it or is uninstalled, so without this
    // every upgrading device would show two Grow Daily entries in its
    // notification settings, one of them permanently empty.
    //
    // Best-effort and repeated on every launch on purpose: a reminder that
    // was already sitting in the OS scheduler names the old channel in its
    // own stored payload, and the plugin recreates a named channel lazily
    // when it posts, so one can come back. The next recompute replaces
    // those with v2 reminders and the next launch clears it again.
    await androidChannels?.deleteNotificationChannel(_legacyChannelId);
    await androidChannels?.createNotificationChannel(
      const AndroidNotificationChannel(
        _alarmChannelId,
        _alarmChannelName,
        description: _alarmChannelDesc,
        importance: Importance.max,
        audioAttributesUsage: AudioAttributesUsage.alarm,
      ),
    );

    // If a notification action cold-launched the app (it was fully
    // terminated when tapped), the tap never reaches
    // onDidReceiveNotificationResponse above — this recovers that case,
    // queuing it the same as any other response until onAction is wired up.
    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    final launchResponse = launchDetails?.notificationResponse;
    if (launchDetails?.didNotificationLaunchApp == true &&
        launchResponse != null) {
      _pendingResponse = launchResponse;
    }

    // An alarm that rings while the app is in front, see
    // AlarmService.onForegroundAlarm. The same reminder, as the banner the
    // notification path would have shown, with the same buttons.
    AlarmService.instance.onForegroundAlarm = showForegroundAlarm;

    _initialized = true;
    // Says, in one line on any real phone, whether this device will honour
    // the exact alarms every reminder now asks for (see [_androidMode]).
    // Worth a line at startup rather than only the per-slot refusal in
    // [_zonedSchedule]: "no refusal logged" is not the same evidence as
    // "exact alarms are on", and the whole reason the hour of slack went
    // unnoticed for so long is that nothing ever said which mode was in
    // force. Null on iOS and below Android 12, where the question does not
    // arise and exactness is simply available.
    final exact = await androidChannels?.canScheduleExactNotifications();
    debugPrint('[NotificationService] Ready'
        '${exact == null ? '' : ', exact alarms: ${exact ? 'yes' : 'NO, '
            'reminders may arrive up to an hour late'}'}');
  }

  /// Shows the reminder behind alarm slot [slotId] as an immediate
  /// notification. iOS presents no alarm over its own app, so this is what
  /// a person who happens to have the app open gets instead: the banner,
  /// the sound, and Mark Done / Snooze for a habit. Time Sensitive, since it
  /// stands in for an alarm the person asked for.
  Future<void> showForegroundAlarm(int slotId) async {
    if (kIsWeb) return;
    final known = AlarmService.instance.scheduledFor(slotId);
    if (known == null) {
      // Scheduled by an earlier launch; the words are gone with it. Better
      // a nameless nudge than silence for an alarm the person set.
      await _plugin.show(
        slotId,
        _actionsAreAr ? 'حان وقت التذكير' : 'Reminder time',
        null,
        _taskReminderDetails(alarmStyle: true),
      );
      return;
    }
    final isAr = _actionsAreAr;
    await _plugin.show(
      slotId,
      known.title,
      known.subtitle,
      known.kind == 'habit'
          ? _habitReminderDetails(isAr, timeSensitive: true, alarmStyle: true)
          : _taskReminderDetails(alarmStyle: true),
      payload: known.targetId,
    );
  }

  /// Hive key for "has this device already told us the OS-level
  /// notification permission is granted" - see [requestPermissions]'s doc
  /// comment for why this exists.
  static const _kPermissionGrantedKey = 'notification_permission_granted_v1';

  /// Prompts the user for permission. Call this once, from a moment that
  /// makes sense in the flow (e.g. right after onboarding, or when the user
  /// first sets a reminder time) rather than at cold start.
  ///
  /// In practice this is called from four different places (AddHabitSheet,
  /// AddTaskSheet, TaskDetailSheet, habit_plans.dart's daily-reminder setup)
  /// - every one of them a genuinely reasonable moment to ask, and every one
  /// of them independent of the others, so nothing before this fix stopped
  /// the *second* one of these that ran from re-invoking the native
  /// permission call all over again. iOS/Android themselves never show a
  /// second system dialog once someone's actually answered the first one -
  /// a repeat request when the OS already has a real answer just returns
  /// that answer straight back with no UI - so this was never a case of
  /// anyone actually being asked to decide twice. It was still a real,
  /// pointless platform-channel round trip on every single save though, and
  /// worth actually shortcutting rather than leaving as "harmless but
  /// wasteful". Once a call here has genuinely confirmed "granted", every
  /// later call - this session or a future one - skips the native call
  /// entirely and returns true immediately.
  ///
  /// Deliberately NOT cached on a denial: unlike a granted answer (which
  /// essentially never reverts on its own), someone can always flip
  /// notifications back on for this app from their device Settings after
  /// having said no here - caching "denied" forever would keep silently
  /// re-declining on their behalf even after they've since turned it on
  /// themselves. Re-asking after a denial is exactly as safe as before this
  /// change (still just an instant no-UI echo of their last real answer,
  /// unless Settings changed it), so there's nothing to lose by leaving
  /// that path exactly as it was.
  Future<bool> requestPermissions() async {
    if (kIsWeb) return false;
    // The cached 'granted' flag is a fast path, NOT the truth.
    //
    // It used to short-circuit and return true forever, so a permission the
    // person revoked in iOS Settings stayed masked: every later call claimed
    // success, nothing was ever actually scheduled, and the "notifications
    // are off" warning this method exists to trigger never appeared. Asking
    // the OS is cheap and, once answered, never re-prompts — so the cache
    // buys nothing worth a permanently wrong answer. Kept only as the
    // fallback for platforms that return null below.
    final cached =
        await LocalStoreService.getSettingsMap(_kPermissionGrantedKey);
    final ios = await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    final android = await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    // Null means "this platform doesn't answer" (e.g. Android below 13),
    // not "denied" — so a null side is simply not evidence either way and
    // the other platform's answer decides. If neither answers, fall back to
    // the last real answer we recorded rather than assuming success.
    final answered = ios ?? android;
    final granted = answered ?? (cached['granted'] == true);
    // Written on every call, not only on success — that one-sided write is
    // what let a revoked permission stay cached as granted forever.
    await LocalStoreService.putSettingsMap(
        _kPermissionGrantedKey, {'granted': granted});
    return granted;
  }

  /// Whether the OS will actually DISPLAY this app's notifications right
  /// now — the system-Settings-level answer, not the app's own toggles.
  ///
  /// This is the question the app could not answer during a real incident:
  /// with iOS notifications switched off in system Settings, every toggle in
  /// Notification Settings read "on", every schedule call "succeeded", the
  /// test button "sent" — and iOS silently dropped all of it. Nothing
  /// anywhere told the person their reminders were going nowhere.
  /// NotificationSettingsScreen's permission banner renders off this.
  ///
  /// Returns null when the platform can't say (web, or an OS without the
  /// query) — callers should treat null as "assume fine, say nothing".
  Future<bool?> checkSystemPermission() async {
    if (kIsWeb) return null;
    await init();
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      final options = await ios.checkPermissions();
      return options?.isEnabled;
    }
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      final appLevel = await android.areNotificationsEnabled();
      if (appLevel != true) return appLevel;
      // The app-level switch is not how notifications actually get turned
      // off on Android. Long-press a reminder, "turn off notifications", and
      // the shade silences THAT CHANNEL while the app-level flag stays true
      // — so this returned "enabled", the banner that exists to explain
      // missing reminders never appeared, and the one thing the person had
      // done to cause it was invisible to the app. That banner is the whole
      // reason this method exists.
      //
      // IMPORTANCE_NONE on the channel is the off state. A channel that is
      // not in the list yet has simply never been created (init makes it, so
      // in practice only before the first init) and is not "off".
      final channels = await android.getNotificationChannels();
      final reminders = channels?.where((c) => c.id == _channelId);
      if (reminders == null || reminders.isEmpty) return true;
      return reminders.first.importance != Importance.none;
    }
    return null;
  }

  /// Sends the person to this app's own notification settings in the OS.
  ///
  /// Android goes through a MethodChannel into MainActivity.kt rather than
  /// url_launcher. The banner used to call `launchUrl('app-settings:')` for
  /// both platforms, but that scheme is iOS-only: url_launcher_android
  /// builds a plain ACTION_VIEW around `Uri.parse("app-settings:")`, nothing
  /// resolves it, and the button did nothing at all. Verified on an Android
  /// 13 emulator - the intent was dispatched and the foreground activity
  /// never changed, so the one escape hatch offered to someone whose
  /// reminders were silently dropped was itself dead.
  ///
  /// Returns whether a settings screen was actually opened.
  Future<bool> openSystemNotificationSettings() async {
    if (kIsWeb) return false;
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        const channel = MethodChannel('com.growdaily.v2/system_settings');
        final ok = await channel.invokeMethod<bool>(
          'openNotificationSettings',
        );
        return ok ?? false;
      } catch (e) {
        if (kDebugMode) {
          debugPrint('openSystemNotificationSettings failed: $e');
        }
        return false;
      }
    }
    // iOS: the documented deep link into this app's own Settings page.
    try {
      return await launchUrl(Uri.parse('app-settings:'));
    } catch (_) {
      return false;
    }
  }

  /// Best effort at getting notifications actually switched on, for the
  /// banner's single call to action.
  ///
  /// Tries the OS permission prompt FIRST. That matters on Android 13+,
  /// where POST_NOTIFICATIONS starts ungranted on every fresh install: the
  /// banner's "notifications are off" state is the DEFAULT there, not
  /// evidence that anyone switched anything off, and the fix is one system
  /// dialog rather than a trip through Settings. If the prompt cannot help
  /// (already answered, or an OS that does not ask), fall back to opening
  /// the settings screen.
  ///
  /// Returns true if notifications are enabled by the time this resolves.
  Future<bool> ensureSystemPermission() async {
    if (kIsWeb) return false;
    if (await requestPermissions()) return true;
    if (await checkSystemPermission() == true) return true;
    await openSystemNotificationSettings();
    return false;
  }

  /// How every reminder in this file is armed on Android.
  ///
  /// This was [AndroidScheduleMode.inexactAllowWhileIdle], which reads like a
  /// considerate choice and is not one. Measured on an API 33 device with the
  /// release APK, every armed reminder came back out of `dumpsys alarm` like
  /// this:
  ///
  ///   type=RTC_WAKEUP origWhen=2026-09-21 20:30:00.000 window=+1h0m0s0ms
  ///   whenElapsed=+1d7h20m51s477ms  maxWhenElapsed=+1d8h20m51s477ms
  ///
  /// `maxWhenElapsed` exactly an hour past `whenElapsed` — the system was free
  /// to deliver a 20:30 reminder any time before 21:30. Android's own
  /// documentation says the same in words: from Android 12 a
  /// setAndAllowWhileIdle alarm is "invoked within one hour of the trigger
  /// time". An hour of slack on a reminder someone set for a specific minute
  /// is not a late reminder, it is a reminder they stop believing in, and it
  /// is what the first Android testers reported as turning notifications on
  /// and getting nothing.
  ///
  /// Exactness costs a manifest permission, which is why it was avoided:
  /// SCHEDULE_EXACT_ALARM drags in Play's restricted-permission form.
  /// USE_EXACT_ALARM does not — it is granted at install on API 33+, cannot
  /// be revoked, and Play allows it for the reminder apps whose core promise
  /// is a thing happening at a time the person chose. Below 33 the manifest
  /// falls back to SCHEDULE_EXACT_ALARM (maxSdkVersion 32), which IS
  /// revocable, which is what [_zonedSchedule] catches.
  static const _androidMode = AndroidScheduleMode.exactAllowWhileIdle;

  /// The mode for a slot the person chose to ring as an alarm (منبّه).
  ///
  /// Android has no AlarmKit — [AlarmService] is iOS only, so its schedule()
  /// simply returns false here and the slot lands back on a notification.
  /// [AndroidScheduleMode.alarmClock] is the nearest true equivalent: the
  /// system treats a setAlarmClock entry as a user-visible alarm, shows the
  /// alarm icon in the status bar, and exempts it from Doze and battery
  /// saver both. A habit someone wakes up for is exactly the case the mode
  /// exists for.
  static AndroidScheduleMode _modeFor({required bool alarm}) =>
      alarm ? AndroidScheduleMode.alarmClock : _androidMode;

  /// [_plugin.zonedSchedule] with this file's one Android mode and the one
  /// fallback that matters.
  ///
  /// Every caller passed the same `uiLocalNotificationDateInterpretation`, so
  /// it lives here rather than seven times over.
  ///
  /// The catch is only reachable on Android 12 (API 31-32), where the
  /// manifest asks for SCHEDULE_EXACT_ALARM: it is pre-granted there, but the
  /// person can switch "Alarms & reminders" back off. The plugin's
  /// checkCanScheduleExactAlarms then throws
  /// PlatformException('exact_alarms_not_permitted') and the reminder is
  /// never armed at all — silently, which is the exact failure shape this
  /// file keeps having to design against (see the receivers in
  /// AndroidManifest.xml, and [checkSystemPermission]'s incident). A
  /// reminder that can be an hour late still beats one that never comes, so
  /// that case retries inexact.
  Future<void> _zonedSchedule(
    int id,
    String? title,
    String? body,
    tz.TZDateTime when,
    NotificationDetails details, {
    bool alarm = false,
    DateTimeComponents? matchDateTimeComponents,
    String? payload,
  }) async {
    Future<void> arm(AndroidScheduleMode mode) => _plugin.zonedSchedule(
          id,
          title,
          body,
          when,
          details,
          androidScheduleMode: mode,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: matchDateTimeComponents,
          payload: payload,
        );
    try {
      await arm(_modeFor(alarm: alarm));
    } on PlatformException catch (e) {
      if (e.code != 'exact_alarms_not_permitted') rethrow;
      debugPrint('[NotificationService] #$id: exact alarms refused, '
          'falling back to inexact (up to an hour late)');
      await arm(AndroidScheduleMode.inexactAllowWhileIdle);
    }
  }

  NotificationDetails get _details => const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          color: _notificationAccent,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      );

  /// Same as [_details] but tagged with the habit-reminder category/actions
  /// so Mark Done + Snooze show up on the notification itself.
  ///
  /// [timeSensitive] marks the iOS notification Time Sensitive: delivered
  /// immediately, through Focus and Do Not Disturb, on the phone and on a
  /// paired watch. Set for prayer-anchored reminders only (see
  /// _ResolvedReminder.timeSensitive). It needs the matching entitlement in
  /// Runner.entitlements, and the person keeps the last word: iOS lets them
  /// turn Time Sensitive off per app in Settings.
  //
  // Takes the language rather than being a const: Android builds its action
  // labels per notification, so these follow the app's current language for
  // free. (iOS cannot: its buttons belong to a CATEGORY registered once at
  // init, which is what [applyLocale] exists to re-register.)
  NotificationDetails _habitReminderDetails(
    bool isAr, {
    bool timeSensitive = false,
    bool alarmStyle = false,
  }) =>
      NotificationDetails(
        android: AndroidNotificationDetails(
          alarmStyle ? _alarmChannelId : _channelId,
          alarmStyle ? _alarmChannelName : _channelName,
          channelDescription: alarmStyle ? _alarmChannelDesc : _channelDesc,
          color: _notificationAccent,
          importance: alarmStyle ? Importance.max : Importance.high,
          priority: alarmStyle ? Priority.max : Priority.high,
          category: alarmStyle ? AndroidNotificationCategory.alarm : null,
          audioAttributesUsage: alarmStyle
              ? AudioAttributesUsage.alarm
              : AudioAttributesUsage.notification,
          actions: [
            AndroidNotificationAction(actionMarkDone, markDoneAction(isAr),
                showsUserInterface: true),
            AndroidNotificationAction(actionSnooze, snoozeAction(isAr),
                showsUserInterface: true),
          ],
        ),
        iOS: DarwinNotificationDetails(
          categoryIdentifier: _habitCategoryId,
          interruptionLevel:
              timeSensitive ? InterruptionLevel.timeSensitive : null,
        ),
      );

  /// [_details] for one task's reminder. [alarmStyle] is the task's alarm
  /// choice on a platform where an alarm is a notification (Android's alarm
  /// channel) or where the real alarm could not be made (an iOS refusal):
  /// then the reminder at least reaches through Focus as Time Sensitive.
  NotificationDetails _taskReminderDetails({required bool alarmStyle}) =>
      NotificationDetails(
        android: AndroidNotificationDetails(
          alarmStyle ? _alarmChannelId : _channelId,
          alarmStyle ? _alarmChannelName : _channelName,
          channelDescription: alarmStyle ? _alarmChannelDesc : _channelDesc,
          color: _notificationAccent,
          importance: alarmStyle ? Importance.max : Importance.high,
          priority: alarmStyle ? Priority.max : Priority.high,
          category: alarmStyle ? AndroidNotificationCategory.alarm : null,
          audioAttributesUsage: alarmStyle
              ? AudioAttributesUsage.alarm
              : AudioAttributesUsage.notification,
        ),
        iOS: DarwinNotificationDetails(
          interruptionLevel:
              alarmStyle ? InterruptionLevel.timeSensitive : null,
        ),
      );

  /// [_details] for a combined 2+ habit ping, Time Sensitive when any member
  /// is (see [_habitReminderDetails]): a bundle holding a Fajr habit must
  /// reach through Sleep Focus the way that habit's own reminder would have.
  NotificationDetails _bundleDetails({required bool timeSensitive}) =>
      NotificationDetails(
        android: const AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          color: _notificationAccent,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          interruptionLevel:
              timeSensitive ? InterruptionLevel.timeSensitive : null,
        ),
      );

  /// Same shape as [_habitReminderDetails], tagged with the quit check-in
  /// category instead so its On Track / Slipped actions show up — see
  /// [scheduleEveningNote].
  NotificationDetails _quitCheckInDetails(bool isAr) => NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          color: _notificationAccent,
          importance: Importance.high,
          priority: Priority.high,
          actions: [
            AndroidNotificationAction(actionStayedClean, onTrackAction(isAr),
                showsUserInterface: true),
            AndroidNotificationAction(actionSlipped, slippedAction(isAr),
                showsUserInterface: true),
          ],
        ),
        iOS: const DarwinNotificationDetails(
            categoryIdentifier: _quitCategoryId),
      );

  // ── Daily reminder copy ──────────────────────────────────────
  //
  // Lives in core/l10n/reminder_copy.dart (dailyReminderLine and
  // dailyFallbackLine), pure and tested, next to the per-habit ladder that
  // replaced the old per-habit pool for the same reason: a fixed pool says
  // the same thing to every state. The day seed below still picks the
  // fallback line and the variant of tonight's, so a reschedule that runs
  // twice on one day does not visibly reword a pending notification.

  /// Today's number, for copy that varies by day. Fixed rather than random
  /// so a reschedule that happens to run twice in one day doesn't visibly
  /// reword a pending notification, and mixable with a habit id so two
  /// habits firing in the same minute don't pick the same sentence.
  ///
  /// Taken off the pass's own clock ([_clockAt]) rather than DateTime.now()
  /// wherever a test supplies one, so the variant a test asserts on is the
  /// variant of the day it set, not of the day the suite happens to run.
  static int _seedOfDay(DateTime day) =>
      day.year * 400 + day.month * 31 + day.day;

  /// The rotation seed for one habit's reminder copy: the day that copy
  /// FIRES, mixed with the habit id.
  ///
  /// It used to be the day the reminders were scheduled. With several days
  /// armed ahead ([kOccurrencesPerSlot]) every copy then drew the same seed,
  /// so a phone left closed read the same ask on every one of those
  /// mornings. Seeded by its own day, a copy keeps one voice for that day (a
  /// mid-day reschedule does not reword it) and the next morning's reads
  /// differently.
  @visibleForTesting
  static int reminderVariantSeed(DateTime fireTime, String habitId) =>
      _seedOfDay(fireTime) + habitId.hashCode;


  /// THE evening notification, scheduled (or rescheduled) at [hour]:[minute]
  /// local time. Safe to call every time the user changes the time or the
  /// day moves: it replaces the previous schedules under the same ids.
  ///
  /// ── One banner an evening, and why ──────────────────────────────────
  /// This one method replaces three that each armed their own notification
  /// and none of which could see the others: the daily reminder, the
  /// streak-risk note (its own clock, [NotificationSettings.streakRiskTime])
  /// and one quit check-in PER quit habit, on that same clock. On
  /// 2026-09-13 a tester's lock screen carried «٤ من ١١ خلّصت، والباقي ٧
  /// عادات بس» at 20:00 and «٤ من ١١ خلّصت 👏🏼 سوي ٥ عادات بس» at 20:33,
  /// the same board counted twice inside half an hour, and Aziz's own
  /// carried the streak note and a check-in stamped the same minute.
  ///
  /// The cap is structural rather than counted: there is one id, armed in
  /// one place, so nothing else CAN arm an evening banner. A daily budget
  /// that counts would not work here anyway — these are scheduled ahead and
  /// fire with the app closed, so there is nothing running to count them.
  /// [eveningNoteLine] decides what the single banner says.
  ///
  /// Quiet hours cover it, as they covered two of the three notifications
  /// it replaces: a window reaching over [hour]:[minute] silences the
  /// evening rather than letting a picked time overrule a picked window.
  ///
  /// ── What is still two notifications ─────────────────────────────────
  /// Tonight ([_dailyTonightId]) is a one-shot worded from where the day
  /// stands ([eveningNoteLine]): how many of today's build habits are done,
  /// what is left, and the streak pointed at tomorrow. Quit habits are not
  /// in it (Aziz, 2026-09-24): one notifies only through a reminder the
  /// person set for it. It is skipped outright when
  /// nothing is owed, because "your habits are waiting" after a finished day
  /// is the exact complaint that led here (Aziz, 2026-09-07). The fallback is seven WEEKLY repeats, one per
  /// weekday ([_dailyFallbackBase] + weekday), each with a line that claims
  /// nothing about the day ([dailyFallbackLine]), so a phone that stays
  /// closed for days still hears something. Tonight's weekday is skipped
  /// whenever today's state is known, so the two never fire on the same
  /// night; every recompute (habit list, dashboard, settings, app resume)
  /// re-arms tonight's line and the other six weekdays.
  ///
  /// Weekly rather than one daily repeat because a daily repeat cannot be
  /// told to start tomorrow: iOS keeps only the time from the date it is
  /// given (DateTimeComponents.time), and on 2026-09-07 the "from tomorrow"
  /// fallback fired tonight a minute after the state-aware line, two
  /// reminders for one evening. A weekday repeat carries the weekday, so
  /// today's can be left out.
  ///
  /// [done], [total], [streak], [streakEarnedToday] and
  /// [pendingBuildHabitCount] describe today. When omitted (the
  /// reminder-time picker's post-permission call has none of them) the last
  /// reported state is reused, so that call cannot overwrite tonight's line
  /// with a generic one; with no state ever reported, the fallback simply
  /// starts tonight.
  Future<void> scheduleEveningNote({
    /// The current notification settings. Optional for the one caller that
    /// has none — the reminder-time picker's post-permission reschedule
    /// (ReminderTimeNotifier.setTime), which knows only the new time. It
    /// reuses the last settings main.dart reported, exactly as it already
    /// reuses the last board state, so that call cannot quietly re-arm the
    /// evening under defaults the person has changed. Before any recompute
    /// has run there is nothing to reuse, and the defaults are the honest
    /// answer.
    NotificationSettings? settings,
    int hour = 20,
    int minute = 0,
    bool isAr = false,
    int? done,
    int? total,
    int? streak,
    bool? streakEarnedToday,
    int? pendingBuildHabitCount,
    int urgentTasks = 0,
    DateTime? now,
  }) async {
    if (kIsWeb) return;
    await init();
    final config = settings ?? _eveningSettings ?? const NotificationSettings();
    if (settings != null) _eveningSettings = settings;
    if (done != null && total != null) {
      _dailyState = (
        done: done,
        total: total,
        streak: streak ?? 0,
        streakEarnedToday: streakEarnedToday ?? false,
        pendingBuild: pendingBuildHabitCount ?? (total - done),
      );
    }
    final state = _dailyState;
    // Every quit id this instance has ever armed, cleared unconditionally:
    // the per-habit check-ins are gone, folded into this one note, and a
    // build that armed them before the merge must not leave them ringing.
    await _cancelRetiredEveningIds();

    final at = _clockAt(now);
    final next = _nextInstanceOf(hour, minute, now: at);
    final firesTonight = next.year == at.year &&
        next.month == at.month &&
        next.day == at.day;

    // Quiet hours cover the whole evening note, as they covered two of the
    // three notifications it replaces. A window that reaches over the
    // note's time silences it; the window is the person's own setting and
    // moving it is one tap.
    final muted = config.quietHoursEnabled &&
        isMinuteWithinQuietHours(
          next.hour * 60 + next.minute,
          config.quietHoursStart,
          config.quietHoursEnd,
        );

    // One note an evening, whatever the clock says now. A note that has
    // already gone out today (at the time set then, or as today's weekday
    // fallback) closes today: a time moved later after it came used to
    // bring a second one the same night (page item 7, 2026-09-24). See
    // EveningNoteRecord.
    final record = await _readEveningRecord();
    final wentOutToday = eveningNoteWentOut(record, at);

    final tonight = state == null || !firesTonight || muted || wentOutToday
        ? null
        : eveningNoteLine(
            done: state.done,
            total: state.total,
            streak: state.streak,
            streakEarnedToday: state.streakEarnedToday,
            pendingBuildHabitCount: state.pendingBuild,
            // The streak ask is the strongest sentence the note can carry,
            // and it is also the one with its own switch. Off means the
            // note falls through to the plain board line, not that the
            // note goes quiet.
            streakAskEnabled: config.streakRiskEnabled,
            urgentTasks: config.matrixNudgeEnabled ? urgentTasks : 0,
            variantIndex: _seedOfDay(at),
            isAr: isAr,
          );
    if (tonight == null) {
      // Pending only (see [_cancelIfPending]). Every road to a null
      // [tonight] is a count going stale rather than the reminder being
      // switched off: nothing is owed any more, or the reminder's time has
      // been and gone so [next] is tomorrow, or no state was ever reported.
      // Tonight's line counts today's board («٢ من ٥ خلّصت، والباقي ٣ بس.»)
      // and is a one-shot, so once it is delivered it leaves the pending
      // list, and a plain cancel here took it off the notification list on
      // the next recompute of the same evening. Switching the reminder off
      // is the other thing, and [cancelDailyReminder] still cancels
      // outright.
      await _cancelIfPending({_dailyTonightId});
    } else {
      await _zonedSchedule(
        _dailyTonightId,
        tonight.title,
        tonight.body,
        next,
        _details,
        // Body-tap routing: land on Today, where the habits this reminder
        // is about actually live, see main.dart's _handleNotificationBodyTap.
        payload: openTodayPayload,
      );
    }

    // With today's state in hand, tonight is covered (or deliberately
    // silent), so today's weekday sits out this week; the next recompute,
    // on any later day, arms it again. With no state at all every weekday
    // is armed, tonight included.
    // The fallbacks sit at the SAME hour:minute as the note, so a quiet
    // window reaching over that minute reaches over all seven of them.
    // Silencing tonight's worded note and leaving next Tuesday's generic one
    // to fire inside the window would be the same setting answering two
    // ways. Plain cancels: a window edited to cover the time is that
    // reminder being switched off for as long as the window says so, and a
    // weekly repeat is pending for its whole life anyway.
    // A note already out today takes today's fallback down with tonight's.
    final skipToday =
        muted || (firesTonight && (state != null || wentOutToday));
    final armedWeekdays = <int>{};
    for (var weekday = DateTime.monday; weekday <= DateTime.sunday; weekday++) {
      final id = _dailyFallbackBase + weekday;
      if (muted || (skipToday && weekday == at.weekday)) {
        await _plugin.cancel(id);
        continue;
      }
      final fallback = dailyFallbackLine(weekday, isAr);
      await _zonedSchedule(
        id,
        fallback.title,
        fallback.body,
        _nextInstanceOfWeekday(weekday, hour, minute),
        _details,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        payload: openTodayPayload,
      );
      armedWeekdays.add(weekday);
    }
    await _keepEveningRecord(
      EveningNoteRecord(
        armedAt: at,
        hour: hour,
        minute: minute,
        tonightAt: tonight == null ? null : next,
        tonightDay: tonight == null ? null : eveningDayKey(next),
        fallbackWeekdays: armedWeekdays,
        wentOutOn: wentOutToday ? eveningDayKey(at) : null,
      ),
    );
    debugPrint('[NotificationService] Evening note set, '
        '$hour:${minute.toString().padLeft(2, '0')}, tonight: '
        '${!firesTonight ? 'already passed' : muted ? 'quiet hours' : wentOutToday ? 'one already went out today' : state == null ? 'no state, fallback' : tonight == null ? 'nothing owed, skipped' : 'one note'}');
  }

  /// See [EveningNoteRecord]. In memory once read, and in the Hive settings
  /// box so it survives the app being closed between the note and the next
  /// open, which is exactly when a time gets changed.
  EveningNoteRecord? _eveningRecord;
  bool _eveningRecordRead = false;
  static const _kEveningRecordKey = 'evening_note_record_v1';

  Future<EveningNoteRecord?> _readEveningRecord() async {
    if (_eveningRecordRead) return _eveningRecord;
    _eveningRecordRead = true;
    if (!LocalStoreService.settingsBoxOpen) return null;
    try {
      _eveningRecord = EveningNoteRecord.fromMap(
          await LocalStoreService.getSettingsMap(_kEveningRecordKey));
    } catch (_) {
      // No store (unit tests): this run's memory only.
    }
    return _eveningRecord;
  }

  /// Keeps [next], written only when it says something new. An unchanged
  /// schedule keeps the moment it was first armed: that is what tells a
  /// weekly fallback that fired today from one armed after its minute.
  Future<void> _keepEveningRecord(EveningNoteRecord? record) async {
    final held = _eveningRecord;
    final next = record != null && held != null && record.sameScheduleAs(held)
        ? record.withArmedAt(held.armedAt)
        : record;
    if (next == held) return;
    _eveningRecord = next;
    if (!LocalStoreService.settingsBoxOpen) return;
    try {
      if (next == null) {
        final box = await LocalStoreService.settingsBox();
        await box.delete(_kEveningRecordKey);
      } else {
        await LocalStoreService.putSettingsMap(
            _kEveningRecordKey, next.toMap());
      }
    } catch (_) {
      // No store (unit tests): kept in memory for this run.
    }
  }

  /// Forgets what was armed, so a test starts from a phone that has never
  /// had an evening note. The service is a singleton.
  @visibleForTesting
  void debugResetEveningRecord() {
    _eveningRecord = null;
    _eveningRecordRead = true;
  }

  /// Cancels the ids the evening note RETIRED: the streak-risk note (8000)
  /// and every per-habit quit check-in this instance has armed.
  ///
  /// Both used to be separate notifications at the same minute as each
  /// other; they are sentences inside the evening note now. Unconditional
  /// plain cancels, because there is nothing left that may hold them: an
  /// id nothing can arm again is not a count going stale, so the
  /// pending-only rule ([_cancelIfPending]) does not apply.
  bool _retiredEveningIdsSwept = false;

  /// Re-arms the once-per-run sweep of the retired evening ids, so a test
  /// can watch it happen more than once. The service is a singleton, so
  /// without this the first test to schedule an evening note spends the
  /// sweep for the whole file.
  @visibleForTesting
  void debugResetRetiredEveningSweep() => _retiredEveningIdsSwept = false;

  Future<void> _cancelRetiredEveningIds() async {
    // Once per app run, not once per recompute. Nothing in this build can
    // arm either id, so after one sweep there is never anything to find,
    // and a recompute runs several times on a plain resume (see the serial
    // lane below). The pending read is the expensive part of this method
    // and the sweep is already competing with the reminder pass for it.
    if (_retiredEveningIdsSwept) return;
    _retiredEveningIdsSwept = true;
    await _plugin.cancel(_streakRiskId);
    // The quit band is swept from what the system actually holds rather
    // than from a set this instance kept, because the ids that matter most
    // here were armed by the PREVIOUS build: [_quitCheckInHabitIds] was
    // in-memory only, so on the first cold start after this merge it is
    // empty while up to one check-in per quit habit is still armed for
    // tonight. A pending read names them all; with no read (the plugin can
    // refuse it) nothing is cancelled blind, and the next pass tries again.
    final live = await _liveNotificationIds();
    if (live == null) return;
    for (final id in live) {
      if (id >= _quitCheckInBase && id < _quitCheckInBase + 1000) {
        await _plugin.cancel(id);
      }
    }
  }

  Future<void> cancelDailyReminder({DateTime? now}) async {
    if (kIsWeb) return;
    await _plugin.cancel(_dailyTonightId);
    await _cancelRetiredEveningIds();
    for (var weekday = DateTime.monday; weekday <= DateTime.sunday; weekday++) {
      await _plugin.cancel(_dailyFallbackBase + weekday);
    }
    // Nothing is armed now, but a note that went out today still closes
    // today: switched off and on again the same night, the evening does not
    // start over (see EveningNoteRecord).
    final at = _clockAt(now);
    final wentOutToday = eveningNoteWentOut(await _readEveningRecord(), at);
    await _keepEveningRecord(
        wentOutToday ? EveningNoteRecord.wentOut(eveningDayKey(at)) : null);
    debugPrint('[NotificationService] Daily reminder cancelled');
  }

  // Habit ids this instance currently owns a reminder (or a deliberate
  // no-reminder decision) for, so the next call can clean up exactly the
  // ones that no longer apply (habit deleted, cue changed to something
  // unresolvable) instead of leaving stale schedules behind. In-memory
  // only — re-derived fresh from the current habit list on every cold
  // start, since main.dart calls this with fireImmediately on the habit
  // list provider.
  final Set<String> _habitReminderHabitIds = {};

  // Near-band alarm ids the pass currently running has actually armed. The
  // comment above is the reason this exists: _habitReminderHabitIds is the
  // app's own memory of what it scheduled, and a habit deleted while the
  // app was closed, or by a build that did not cancel on delete, is not in
  // it — so nothing names that habit's alarms and they ring forever. What
  // is really armed is known only to the system, so at the end of a pass
  // this is what it is allowed to still be holding, and everything else in
  // the band goes (see [_reapOrphanHabitAlarms]).
  final Set<int> _armedHabitAlarmIds = {};

  // Every habit reminder the pass currently running has armed, with the
  // moment it fires and whether it went out as a notification or an alarm,
  // and every bundle. Handed to the App Group once the pass has armed them
  // (see [_publishArmedReminders]) for the Done paths outside the app, which
  // cannot work any of these ids out for themselves.
  final List<ArmedHabitCopy> _armedCopies = [];
  final List<ArmedBundle> _armedBundles = [];

  // What the notification system actually holds, read once at the start of
  // the pass now running (see [_liveNotificationIds]). Null means the read
  // failed and the sweep falls back to cancelling blind.
  Set<int>? _sweepLiveNoteIds;

  // Whether the pass now running can arm AlarmKit alarms at all. False makes
  // every alarm reminder a notification, which spends the pending budget.
  bool _alarmsReady = false;

  /// The most reminder slots one habit can hold in a day.
  ///
  /// Mirrors the stepper's own cap (kMaxTimesPerDay in add_habit_sheet), and
  /// is repeated rather than imported because that constant lives inside a
  /// `part of` a widget file. Kept here as the id scheme's own bound: the
  /// 5000..5999 band has to stay a band, so the number of slots must be
  /// something this file can state and loop over.
  static const int _maxHabitReminderSlots = 12;

  /// The notification id for one habit's reminder in one slot of the day.
  ///
  /// A habit counted N times a day wants N reminders, and every one of them
  /// has to be independently schedulable and cancellable — one id per habit
  /// meant the second slot silently replaced the first, so a habit set to
  /// four times a day would ping once and look broken.
  ///
  /// Slot 0 deliberately returns the exact id this method returned before
  /// slots existed. Ids are the only handle the OS has on an already-
  /// scheduled notification: changing slot 0's id would strand every
  /// reminder currently sitting in the system scheduler on every device
  /// that upgrades, uncancellable and unreplaceable, until it fired. The
  /// `'$habitId#$slot'` shape for the rest matches the same trick this file
  /// already plays for repeated task reminders.
  /// The band-relative part of a slot's id. Public so the slot scheme itself
  /// can be tested — the two id methods below are just this plus their band,
  /// and the properties worth locking (slot 0 is unchanged, slots differ,
  /// nothing escapes its band) all live here.
  @visibleForTesting
  static int reminderSlotOffset(String habitId, int slot) =>
      (slot == 0 ? habitId.hashCode : '$habitId#$slot'.hashCode).abs() % 1000;

  /// Which moment each of [times] next falls at, one entry per time, with the
  /// slot index it owns.
  ///
  /// Pure and static so the whole of this feature's 24-hour arithmetic is
  /// testable with no device, no plugin and no network — [times] and a
  /// simulated [now] in, slots and fire times out. That matters more here than
  /// anywhere else in this file: the cases that break a multi-time habit are
  /// all clock arithmetic (a list spanning midnight, an offset pushing a time
  /// across it, a time landing exactly on now), and none of them are reachable
  /// from a widget test.
  ///
  /// The slot is the index in [times], NEVER the position in fire-time order.
  /// Fire order swaps during a single day — at 11:00 a habit set for 00:00 and
  /// 12:00 resolves to [tomorrow 00:00, today 12:00], and at 13:00 to
  /// [tomorrow 00:00, tomorrow 12:00], so 00:00 and 12:00 would trade slots as
  /// the day passed. Ids are `hash('habitId#slot')` and the OS has no other
  /// handle on a scheduled notification, so a trade means the next cancel aims
  /// at the wrong id and strands a live reminder that nothing can call back.
  /// [times] is canonical (ascending, deduped — see HabitCue.times), so its
  /// index is stable across recomputes, across the day and across restarts.
  /// [offsets] is index-aligned with [times]: entry i is the signed minute
  /// shift for time i (negative before, positive after). A short list is read
  /// as 0 past its end, so a caller with one shared offset passes a one-entry
  /// list only when there is one time.
  /// Whether a resolved [fire] moment lands on a day this habit actually
  /// runs. [weekdays] is DateTime.weekday values; empty means every day.
  ///
  /// Tested against the fire time's EFFECTIVE day, not its calendar date,
  /// because that is the day the rest of the app considers the habit due:
  /// `isScheduledFor` is asked about `DateTime.now().effectiveDay`
  /// everywhere else, so a 02:00 reminder belongs to the previous
  /// calendar day's board, exactly like the square it is reminding about.
  static bool _fireDayIsScheduled(DateTime fire, Set<int> weekdays) {
    if (weekdays.isEmpty) return true;
    return weekdays.contains(fire.effectiveDay.weekday);
  }

  /// Expands a habit's ONE clock anchor into the (time, offset) pairs a
  /// stacked reminder means, in slot order.
  ///
  /// [times] / [offsets] are the habit's occurrences as the cue stores them,
  /// index-aligned. [primaryOffset] is the habit's own shift and
  /// [extraOffsets] the stack on top of it (see
  /// IslamicHabitTemplate.extraReminderOffsets).
  ///
  /// Returns the inputs untouched, and a perOccurrence of 1, unless there is
  /// genuinely something to expand — a single occurrence with a non-empty
  /// stack. That guard is the compatibility promise: no existing habit's
  /// slots move, because slot indices are notification ids and a habit whose
  /// slots renumber strands whatever the OS is already holding.
  ///
  /// The primary comes first so it keeps slot 0. Duplicates are dropped
  /// (a stack that repeats the primary would otherwise schedule the same
  /// minute twice) and the rest keep the order they were stored in, which is
  /// sorted, so the same set always produces the same slots.
  ///
  /// Genuinely public, unlike [resolveClockSlots]: main.dart calls it while
  /// building each HabitReminderInput, because that is where a habit's cue
  /// and its stack are both in hand. It lives here rather than there so slot
  /// numbering stays owned by the file that turns a slot into an id.
  static ({List<TimeOfDay> times, List<int> offsets, int perOccurrence})
      expandStackedSlots({
    required List<TimeOfDay> times,
    required List<int> offsets,
    required int primaryOffset,
    required List<int> extraOffsets,
  }) {
    if (times.length != 1 || extraOffsets.isEmpty) {
      return (times: times, offsets: offsets, perOccurrence: 1);
    }
    final stack = <int>{primaryOffset, ...extraOffsets}
        .take(_maxHabitReminderSlots)
        .toList();
    return (
      times: [for (var i = 0; i < stack.length; i++) times.first],
      offsets: stack,
      perOccurrence: stack.length,
    );
  }

  @visibleForTesting
  static List<({int slot, tz.TZDateTime fireTime})> resolveClockSlots(
    List<TimeOfDay> times,
    List<int> offsets,
    tz.TZDateTime now, {
    /// Days this habit runs — see HabitReminderInput.scheduledWeekdays.
    /// Defaults to every day so existing callers and tests are unchanged.
    Set<int> scheduledWeekdays = const {},
  }) =>
      [
        for (final o in resolveClockOccurrences(times, offsets, now,
            scheduledWeekdays: scheduledWeekdays, occurrences: 1))
          (slot: o.slot, fireTime: o.fireTime),
      ];

  /// The next [occurrences] moments each of [times] falls at, one entry per
  /// (slot, depth) pair.
  ///
  /// Depth 0 is the next occurrence — exactly what [resolveClockSlots]
  /// always returned, which is why that method is now a one-occurrence call
  /// into this one rather than a second copy of the same arithmetic.
  /// Depth 1 and up are the ones after it, on the habit's own days, and
  /// they exist so a phone that is not opened tomorrow still has tomorrow's
  /// reminder armed (see [kOccurrencesPerSlot]).
  ///
  /// The slot is the index in [times], NEVER the position in fire-time
  /// order — see [resolveClockSlots]' own doc comment for why that
  /// distinction is load-bearing for ids.
  ///
  /// Each day's moment is BUILT from that day's wall clock rather than by
  /// adding 24 hours to the previous one. The two are the same number
  /// everywhere without daylight saving, and an hour apart across a
  /// transition — "every day at 07:00" means seven in the morning on each
  /// of those days, not a fixed number of hours after the first. This
  /// matters now that a window of days is armed at once in zones the app
  /// has always supported.
  @visibleForTesting
  static List<({int slot, int depth, tz.TZDateTime fireTime})>
      resolveClockOccurrences(
    List<TimeOfDay> times,
    List<int> offsets,
    tz.TZDateTime now, {
    Set<int> scheduledWeekdays = const {},
    Set<String> excusedDayKeys = const {},
    int occurrences = 1,
  }) {
    final out = <({int slot, int depth, tz.TZDateTime fireTime})>[];
    for (var slot = 0;
        slot < times.length && slot < _maxHabitReminderSlots;
        slot++) {
      final offset =
          Duration(minutes: slot < offsets.length ? offsets[slot] : 0);
      final t = times[slot];
      var depth = 0;
      // The first future moment regardless of what weekdays say, kept as
      // the answer for a corrupt weekday set (values outside 1-7, which no
      // UI can produce). Without it such a habit resolves to NOTHING and
      // loses its reminder silently; the single-occurrence version handled
      // the same case by giving up its weekday check after eight rolls and
      // leaving the moment on its natural next occurrence.
      tz.TZDateTime? unrestricted;
      // Whether any moment landed on one of the habit's days at all, excused
      // or not. The fallback below is for a weekday set that matches NOTHING;
      // a window whose only matching days were all covered by a session on
      // another day has nothing owed in it, and must stay silent.
      var weekdaysMatched = false;
      // Bounded so that corrupt set can never spin forever, and generous
      // enough that a once-a-week habit still reaches its full window: a
      // whole week per occurrence, plus the slack the single-occurrence
      // version already allowed for an offset larger than a day.
      final lastDay = 8 + 7 * occurrences;
      for (var dayOffset = 0;
          dayOffset <= lastDay && depth < occurrences;
          dayOffset++) {
        // The offset is applied AFTER the day's wall clock is built, never
        // before a day roll. Rolling the bare clock time first (as this
        // used to) breaks every "after" shift: at 09:10 a habit set for
        // 09:00 with +30 was rolled to tomorrow 09:00 and then shifted,
        // silently skipping today's still-future 09:30 — any recompute
        // inside the anchor→anchor+offset window lost the reminder.
        // Walking days and shifting each also covers the two cases the old
        // pair of rolls handled: a bare time already passed, and an offset
        // dragging an imminent time into the past (8:58, habit at 9:00,
        // -15), as well as custom offsets larger than a day.
        final fire = tz.TZDateTime(tz.local, now.year, now.month,
                now.day + dayOffset, t.hour, t.minute)
            .add(offset);
        if (!fire.isAfter(now)) continue;
        unrestricted ??= fire;
        // The moment also has to land on a day the habit RUNS. Without this
        // a habit set to specific weekdays fired on the wrong ones:
        // Sun/Tue/Thu at 20:00, recomputed at 21:00 on Thursday, rolled one
        // day to Friday 20:00 and pinged about a day it was never due.
        if (!_fireDayIsScheduled(fire, scheduledWeekdays)) continue;
        weekdaysMatched = true;
        // One of its days, already stood in for by a session on another day
        // of the same week (see moved_day_plan.dart): nothing is owed on it,
        // so nothing rings. The shower taken on Wednesday for a Monday,
        // Thursday and Saturday habit silences Thursday's reminder.
        if (excusedDayKeys.contains(fire.effectiveDay.toDateKey())) continue;
        out.add((slot: slot, depth: depth, fireTime: fire));
        depth++;
      }
      if (depth == 0 && !weekdaysMatched && unrestricted != null) {
        out.add((slot: slot, depth: 0, fireTime: unrestricted));
      }
    }
    return out;
  }

  /// The facts a habit reminder's wording is built from, as they will stand
  /// on the day it FIRES, measured on the habit's own schedule.
  ///
  /// Two corrections over reading the inputs as they are:
  ///
  ///  - Re-basing. The inputs are measured today, and a slot whose time has
  ///    passed rolls to the habit's next scheduled day, so today's progress
  ///    is only today's (a rolled slot starts its day at zero, and claiming
  ///    "2 of 3 today" on a day nothing has been logged is exactly the kind
  ///    of visibly-false line reminder_copy exists to stop) and the gap
  ///    since the last completion keeps growing until the reminder lands.
  ///  - The schedule. "Days since last done" is a calendar number, and the
  ///    lapse the wording names must not be: a Wed/Sat habit done Wednesday
  ///    has missed nothing by Saturday, whatever the calendar says. So
  ///    [missedSinceLastDone] counts only the days the habit RUNS ON that
  ///    ended without it, the streak is carried to the fire day only while
  ///    that count is zero (a slot rolled past a day that then goes undone
  ///    used to bake a streak line that was false by the time it fired),
  ///    and a flexible weekly quota, which has no days of its own, is judged
  ///    by its week instead (see quotaFactsOn). A quota habit's streak
  ///    counter is a calendar count and says nothing true about a week, so
  ///    it is dropped from the wording altogether.
  ///
  /// If the habit is completed in the meantime the completion itself
  /// reschedules and all of this is recomputed, so "nothing happens between
  /// now and the fire day" is the honest assumption to bake in.
  ///
  /// A day is only a lapse once it has CLOSED at [fireTime] (see
  /// DateTimeGameExt.isSettledAt): a reminder landing at 07:00 still finds
  /// yesterday open and markable, and must not word it as lost. The streak,
  /// though, is still carried only while no day before the fire day is
  /// unfinished, open or closed; see the body for why.
  @visibleForTesting
  static ({
    int streak,
    int completedCount,
    int? lastDoneDaysAgo,
    int missedSinceLastDone,
    int? weekDone,
    bool owedOnFireDay,
    bool everyDay,
  }) reminderFactsAtFireDay({
    required DateTime today,
    required DateTime fireDay,
    required int streak,
    required int completedCount,
    required int? lastDoneDaysAgo,
    required Set<int> scheduledWeekdays,
    required int? weekTarget,
    required Set<int>? weekDoneDays,
    // The instant the reminder fires. Null judges every day before the fire
    // day as closed, which is how every caller read it before. Required,
    // though nullable, so the scheduler cannot drop it and still compile.
    required DateTime? fireTime,
    // The habit's schedule as it stood on each day
    // (IslamicHabitTemplate.runsOn), for a habit whose schedule changed.
    // Wins over [scheduledWeekdays] for the days since the last completion,
    // which may lie before the change: a Monday-and-Thursday habit made daily
    // on Wednesday still rested on Tuesday, and a daily one moved to Monday
    // and Thursday still missed it. Null for every habit that never changed,
    // whose weekdays are the whole answer.
    bool Function(DateTime day)? runsOn,
  }) {
    final daysAhead = calendarDaysBetween(today, fireDay);
    final lastDone =
        lastDoneDaysAgo == null ? null : dayPlus(today, -lastDoneDaysAgo);
    final basedCompleted = daysAhead == 0 ? completedCount : 0;
    final basedLastDone =
        lastDoneDaysAgo == null ? null : lastDoneDaysAgo + daysAhead;
    final everyDay = scheduledWeekdays.isEmpty;
    if (weekTarget != null) {
      final week = quotaFactsOn(
        fireDay: fireDay,
        weekStart: today.startOfDisplayWeek,
        doneDays: weekDoneDays,
        target: weekTarget,
        lastDone: lastDone,
        fireTime: fireTime,
      );
      return (
        streak: 0,
        completedCount: basedCompleted,
        lastDoneDaysAgo: basedLastDone,
        missedSinceLastDone: week.missedSinceLastDone,
        weekDone: week.done,
        owedOnFireDay: week.owed,
        everyDay: everyDay,
      );
    }
    // The LAPSE is judged up to the fire day, or only up to the day before it
    // while that day is still open when the reminder lands: a 07:00 reminder
    // must not call yesterday lost while yesterday can still be marked.
    final dayBefore = dayPlus(fireDay, -1);
    final judgedUntil = fireTime == null || dayBefore.isSettledAt(fireTime)
        ? fireDay
        : dayBefore;
    final missed = lastDone == null
        ? 0
        : runsOn != null
            ? runDaysStrictlyBetween(lastDone, judgedUntil, runsOn)
            : scheduledDaysStrictlyBetween(
                lastDone,
                judgedUntil,
                scheduledWeekdays,
              );
    // The STREAK is not promised across that open day, though. Ticking the
    // fire day before the open day restarts the streak at 1 (completeHabit
    // measures a scheduledGap of 2, and nextHabitStreak maps it to 1), and
    // this reminder's own Mark Done action ticks the fire day. So at 07:00
    // with yesterday still blank the line names neither a lapse nor a
    // streak; finishing yesterday re-arms the reminder with the streak back.
    // DashboardState.habitStreak holds its open-day reading back for the
    // same reason.
    final unfinishedBefore = lastDone == null
        ? 0
        : runsOn != null
            ? runDaysStrictlyBetween(lastDone, fireDay, runsOn)
            : scheduledDaysStrictlyBetween(lastDone, fireDay, scheduledWeekdays);
    return (
      streak: unfinishedBefore > 0 ? 0 : streak,
      completedCount: basedCompleted,
      lastDoneDaysAgo: basedLastDone,
      missedSinceLastDone: missed,
      weekDone: null,
      owedOnFireDay: false,
      everyDay: everyDay,
    );
  }

  /// How many upcoming occurrences of each slot are kept armed at once.
  ///
  /// One was the old number, and it is the reason a phone left untouched
  /// went quiet: the scheduler held the NEXT Fajr and nothing else, so the
  /// morning after it fired there was nothing left and no recompute due
  /// until the app was opened. Four keeps a long weekend, and for a
  /// prayer-anchored habit each of those four is computed from its OWN
  /// day's prayer times (see PrayerTimesService.calculateDays), so the
  /// reminder tracks the twenty-odd minutes Fajr moves in a month rather
  /// than freezing at whatever it was when it was armed.
  ///
  /// Not larger, because every extra day multiplies how much of iOS's hard
  /// 64-pending budget one habit takes (see [kMaxPendingHabitSlots]), and
  /// the value of a further day falls away fast — a habit app is opened
  /// often, and each open re-arms the whole window anyway. A reminder that
  /// rings as an alarm is the exception, see [kAlarmWindowDays].
  static const int kOccurrencesPerSlot = 4;

  /// Where depth 1 and up live: 400000, 401000, 402000, one 1000-wide band
  /// per depth, matching the existing bands' shape.
  ///
  /// Depth 0 deliberately keeps the exact 5000-band id it has always had.
  /// Ids are the only handle the OS has on an already-scheduled
  /// notification, so moving depth 0 would strand every reminder currently
  /// sitting in the system scheduler on every device that upgrades —
  /// uncancellable and unreplaceable until it fired. The same argument the
  /// slot scheme itself made for slot 0.
  ///
  /// Far above every band this file already uses (5000 habit, 6000 snooze,
  /// 7000 bundle, 8000 streak, 9000 digest, 60000 room (retired), plus the
  /// task bands) and far below the 32-bit ceiling Android notification ids
  /// are bounded by, with 12 slots x 3 extra depths reaching 402999 at most.
  static const int _aheadBandBase = 400000;

  /// How far ahead a reminder that rings as a real ALARM stays armed: every
  /// one of its moments in the next thirty days, each resolved against its
  /// own day, where a notification keeps [kOccurrencesPerSlot].
  ///
  /// iOS gives an app no way to wake itself each night and arm tomorrow, and
  /// a repeating alarm cannot follow a prayer that moves every day, so the
  /// exact alarms are set in advance and topped up on every open. With four
  /// of them, four days without opening the app was all it took to lose a
  /// Fajr alarm someone relies on to wake up. AlarmKit alarms are not part of
  /// iOS's 64-request notification budget (see [kMaxPendingHabitSlots]),
  /// which is what makes a month affordable; a reminder whose alarm cannot be
  /// made keeps the ordinary four, as notifications.
  static const int kAlarmWindowDays = 30;

  /// The deepest occurrence an alarm slot is armed at: one a day for
  /// [kAlarmWindowDays]. Depth [kOccurrencesPerSlot] and deeper is the
  /// EXTENDED window, armed in one reconciling call rather than one schedule
  /// per id (see _syncAlarmWindow).
  static const int _alarmDepthLimit = kAlarmWindowDays;

  /// Where the extended window lives: one 1000-wide band per calendar DAY,
  /// the day's number since 1970 modulo [_alarmWindowBands], plus the same
  /// slot hash as every other habit id, so 500000 to 599999, clear of every
  /// other band. Keyed by the day rather than by depth so the month does not
  /// shift every alarm one id along each morning: the next open finds each
  /// day's alarm already under its id and arms only the day that came into
  /// range. More bands than days in the window, so no two of its days share
  /// one. See [windowAlarmId].
  static const int _alarmWindowBase = 500000;
  static const int _alarmWindowBands = 100;
  static const int _alarmWindowLowId = _alarmWindowBase;
  static const int _alarmWindowHighId =
      _alarmWindowBase + _alarmWindowBands * 1000 - 1;

  /// Most extended-window alarms armed across all habits at once. Shallowest
  /// depths are armed first, so a heavy user gets a shorter month, never a
  /// missing tomorrow, and every open refills it.
  static const int kMaxWindowAlarms = 120;

  /// Where a habit's next-occurrence (depth 0) ids start. Named because
  /// [_reapOrphanHabitAlarms] has to sweep exactly this band and would
  /// silently spare orphans, or eat live alarms, if the two ever drifted.
  static const int _habitBandBase = 5000;

  int _habitReminderId(String habitId, [int slot = 0, int depth = 0]) =>
      depth == 0
          ? _habitBandBase + reminderSlotOffset(habitId, slot)
          : _aheadBandBase +
              (depth - 1) * 1000 +
              reminderSlotOffset(habitId, slot);

  int _snoozeId(String habitId, [int slot = 0]) =>
      6000 + reminderSlotOffset(habitId, slot);

  /// Cancels every slot a habit could be holding, not just its first.
  ///
  /// Every cancel site has to use this: cancelling slot 0 alone is how a
  /// habit that was counted four times a day and then deleted keeps pinging
  /// three times a day forever, with nothing left in the app pointing at it.
  /// Every DEPTH of every slot, for the same reason one level down: a habit
  /// deleted after its window was armed has three more days of copies in
  /// the scheduler behind the one that is about to fire.
  Future<void> _cancelAllHabitReminderSlots(String habitId) async {
    for (var slot = 0; slot < _maxHabitReminderSlots; slot++) {
      await _cancelHabitSlotAllDepths(habitId, slot);
      await _plugin.cancel(_snoozeId(habitId, slot));
    }
  }

  /// Public entry point for a habit that is gone for good: every near-window
  /// slot and depth in both systems (see [_cancelAllHabitReminderSlots]),
  /// serialized against any in-flight recompute the same way
  /// [cancelTaskReminder] is. Deleting or archiving a habit must call this
  /// directly rather than waiting for the next [scheduleSmartReminders]
  /// sweep to notice it is gone — that sweep only catches a habit this
  /// session already remembers scheduling (see [_habitReminderHabitIds]),
  /// which is empty on every cold launch.
  ///
  /// The far, day-keyed extended window (see [kAlarmWindowDays]) is not
  /// touched here: those ids are keyed by calendar day, not by habit, and
  /// are reconciled against the real AlarmKit list on the next
  /// [scheduleSmartReminders] sweep regardless (see [_syncAlarmWindow]).
  Future<void> cancelHabitReminders(String habitId) {
    if (kIsWeb) return Future.value();
    return _serialized(
      () => _cancelAllHabitReminderSlots(habitId),
      ahead: true,
    );
  }

  /// Drops every habit alarm the system is still holding in the near bands
  /// that the pass just finished did not arm.
  ///
  /// The near bands' equivalent of what [_syncAlarmWindow] does for the far
  /// one, and the only thing that can reach an alarm whose habit is already
  /// gone: [cancelHabitReminders] needs a habit id to name, and a habit
  /// deleted by a build that did not cancel on delete left none. Runs at
  /// the end of every full pass, so such an alarm dies the next time the
  /// app works out its reminders rather than ringing for the rest of its
  /// month.
  ///
  /// Safe against eating live alarms because it runs AFTER the pass has
  /// armed everything it wants: the keep set is what was really armed a
  /// moment ago, not a prediction. A slot the pass deliberately left off
  /// (quiet hours, habit done, alarm refused and gone to a notification
  /// instead) is supposed to lose its alarm, and does.
  Future<void> _reapOrphanHabitAlarms() async {
    const bands = [
      (_habitBandBase, _habitBandBase + 999),
      (_aheadBandBase, _aheadBandBase + (kOccurrencesPerSlot - 1) * 1000 - 1),
    ];
    for (final (low, high) in bands) {
      final reaped = await AlarmService.instance.reapOrphans(
        lowId: low,
        highId: high,
        keep: _armedHabitAlarmIds,
      );
      if (reaped != null && reaped > 0) {
        debugPrint('[NotificationService] reaped $reaped orphaned alarm(s) '
            'in $low..$high');
      }
    }
  }

  /// Every armed copy this habit is NOT keeping after a resolution pass,
  /// plus its snooze once the habit is done for today.
  ///
  /// One pass over the whole (slot, depth) grid rather than the old loop
  /// over slots: a habit edited from four times a day to two, or from daily
  /// to once a week, leaves copies behind in both dimensions, and anything
  /// this does not cancel keeps firing forever with nothing in the app
  /// pointing at it.
  ///
  /// The snooze is a one-off the person asked for from a reminder that
  /// already arrived, so it belongs to no depth, and it is cleared only when
  /// today's reason for it is gone: the habit is done ([doneToday]). It used
  /// to be cleared whenever its slot had no reminder left due TODAY, and a
  /// snoozed reminder has always just fired, so the first pass after the
  /// tap cancelled the hour the person asked for: any app open, and on
  /// Android the Snooze button itself, which opens the app (2026-09-24). A
  /// habit deleted, paused or switched off loses its snooze through
  /// [_cancelAllHabitReminderSlots] instead.
  Future<void> _sweepUnkeptSlots(
    String habitId,
    Set<({int slot, int depth})> kept, {
    required bool doneToday,
  }) async {
    for (var slot = 0; slot < _maxHabitReminderSlots; slot++) {
      for (var depth = 0; depth < kOccurrencesPerSlot; depth++) {
        if (kept.contains((slot: slot, depth: depth))) continue;
        // Notification only. This loop is blind — it walks all 12 slots x 4
        // depths for every habit whether or not anything was ever armed
        // there — so pairing it with an alarm cancel cost a second channel
        // round trip per cell: 576 of them per pass on a 12-habit account,
        // measured, to arm 8 things. The alarms are covered instead by
        // [_reapOrphanHabitAlarms], which runs at the end of this same pass
        // and clears, in ONE call per band, every alarm the system really
        // holds that this pass did not arm — the same ids, judged by what
        // is actually armed rather than guessed at. That pass is load-
        // bearing for this: if it ever goes, the alarm cancel has to come
        // back here.
        await _cancelIfHeld(_habitReminderId(habitId, slot, depth));
      }
      if (doneToday) await _cancelIfHeld(_snoozeId(habitId, slot));
    }
  }

  /// Every armed copy of one slot. The snooze id is deliberately NOT
  /// touched — a pending snooze is something the person asked for from a
  /// reminder that already arrived, and it belongs to no depth.
  Future<void> _cancelHabitSlotAllDepths(String habitId, int slot) async {
    for (var depth = 0; depth < kOccurrencesPerSlot; depth++) {
      await _cancelHabitSlot(habitId, slot, depth);
    }
  }

  /// Clears one habit slot in BOTH systems. A slot is scheduled either as a
  /// notification or as an alarm under the same id (see AlarmService), and
  /// a habit switched from one to the other must not keep the old one.
  Future<void> _cancelHabitSlot(String habitId, int slot,
      [int depth = 0]) async {
    final id = _habitReminderId(habitId, slot, depth);
    await _plugin.cancel(id);
    await AlarmService.instance.cancel(id);
  }

  /// The background action handler's stand-down: a habit just recorded as
  /// done for [day] must not be reminded about again that day before the app
  /// opens, by any of its slots, a pending snooze, or a bundle it shares
  /// with habits that are done too.
  ///
  /// [day]'s copies only, read from [armedReminders], the record the last
  /// pass left in the App Group (see ArmedReminderRecord). The headless
  /// engine has no habit list, no cue and no location, so it cannot resolve
  /// fire times; the pass could, and wrote down which id holds which day.
  /// Every later day stays armed, so a habit marked done from the lock
  /// screen and a phone then left alone for three days still reminds on
  /// each of them. [day] is the effective day the tap is queued under, and
  /// [doneOnDay] the habits known done on it, which decides a bundle (see
  /// ArmedReminderRecord.standDownFor).
  ///
  /// This used to cancel depth 0 of every slot, the next occurrence of each,
  /// which is only today's while the last pass ran before today's reminder.
  /// When it ran yesterday, before yesterday's, today's copy sat at depth 1
  /// and rang anyway, and when it ran after today's reminder, depth 0 was
  /// tomorrow's and that went instead. It stays as the fallback for a
  /// missing record: an app updated and not opened since, whose previous
  /// build wrote none.
  ///
  /// Pending notifications only (see [_cancelIfPending]): a reminder already
  /// delivered was right when it came, and stays in the notification list.
  /// Alarms under the same ids go too, when this engine can reach AlarmKit
  /// (AppDelegate registers the channel for it).
  Future<void> standDownHabitReminders(
    String habitId, {
    required String? armedReminders,
    required String day,
    Set<String> doneOnDay = const {},
  }) =>
      _serialized(
        () async {
          final plan = ArmedReminderRecord.standDownFor(
            armedReminders,
            habitId: habitId,
            day: day,
            doneOnDay: doneOnDay,
          );
          final nextOfEachSlot = {
            for (var slot = 0; slot < _maxHabitReminderSlots; slot++)
              _habitReminderId(habitId, slot),
          };
          await _cancelIfPending({
            ...plan?.notifications ?? nextOfEachSlot,
            for (var slot = 0; slot < _maxHabitReminderSlots; slot++)
              _snoozeId(habitId, slot),
          });
          for (final id in plan?.alarms ?? nextOfEachSlot) {
            await AlarmService.instance.cancel(id);
          }
          debugPrint('[NotificationService] $habitId done for $day outside '
              'the app: ${plan == null ? 'no record, next copy of each slot' : '${plan.notifications.length} reminder id(s) and ${plan.alarms.length} alarm(s) for the day'} stood down');
        },
        ahead: true,
      );

  /// Cancels [ids], and only the ones the OS still holds as PENDING.
  ///
  /// The single rule every path that clears a note whose numbers went stale
  /// follows: a note still waiting is cleared rather than left to fire a
  /// false count, and a note already DELIVERED was true when it came, so it
  /// stays in the notification list. A plain cancel cannot make that
  /// distinction on iOS: the plugin's cancel: calls
  /// removeDeliveredNotificationsWithIdentifiers beside
  /// removePendingNotificationRequestsWithIdentifiers (see
  /// FlutterLocalNotificationsPlugin.m), so a Done tapped at 22:30 would
  /// take tonight's 20:30 note off the lock screen. Reading the pending list
  /// first is what keeps that from happening.
  ///
  /// The other two paths that clear these notes follow the same rule in
  /// their own languages: the headless action engine through the two
  /// stand-downs below, and the home screen widget by removing pending
  /// requests only (standDownNotesWithStaleCounts in GrowDailyWidget.swift).
  ///
  /// Switching a note OFF is not this: that is a plain cancel, delivered
  /// copy included, because the person asked for it to go.
  Future<void> _cancelIfPending(Set<int> ids) async {
    if (kIsWeb) return;
    final pending = await _plugin.pendingNotificationRequests();
    for (final request in pending) {
      if (ids.contains(request.id)) await _plugin.cancel(request.id);
    }
  }

  /// Every notification id the system is really holding right now — still to
  /// fire, or already delivered and sitting on the lock screen. Null if it
  /// could not be read.
  ///
  /// Read once per pass so the blind sweep below can skip ids that hold
  /// nothing. Both halves are needed to make that skip EXACT rather than
  /// merely cheap: pending alone would stop the sweep clearing a delivered
  /// copy, which it does today and which some callers rely on. An id in
  /// neither list cannot be cancelled into anything, so not cancelling it
  /// is equivalent to cancelling it, minus a channel round trip — and there
  /// were roughly 60 such round trips per habit per pass, because
  /// [_sweepUnkeptSlots] walks a fixed 12x4 grid for every habit whether or
  /// not that habit ever used those slots. Two calls here replace all of
  /// them.
  /// Cancels [id] unless this pass already knows the system is not holding
  /// it. Same end state either way; see [_liveNotificationIds].
  Future<void> _cancelIfHeld(int id) async {
    if (_sweepLiveNoteIds?.contains(id) ?? true) await _plugin.cancel(id);
  }

  Future<Set<int>?> _liveNotificationIds() async {
    if (kIsWeb) return null;
    try {
      final pending = await _plugin.pendingNotificationRequests();
      final active = await _plugin.getActiveNotifications();
      return {
        for (final request in pending) request.id,
        for (final note in active)
          if (note.id != null) note.id!,
      };
    } catch (_) {
      // Unreadable: fall back to cancelling unconditionally, exactly as
      // this did before the read existed. Slower, never wrong.
      return null;
    }
  }

  /// Clears tonight's evening note (1010) while it is still pending, and
  /// nothing else.
  ///
  /// For the background action engine: a habit finished from the lock
  /// screen or the Watch makes the note's counts false, and that engine has
  /// none of the facts to re-word it (see notification_action_background.
  /// dart). The next recompute arms the note again if anything is still
  /// owed. A note already delivered is left alone, see [_cancelIfPending].
  ///
  /// It used to clear 8000, the streak note, while the board line at 1010
  /// went out with stale numbers beside it; there is one id now, and it is
  /// the one that carries every count a tap here can falsify.
  Future<void> standDownEveningNote() => _cancelIfPending(
        {_dailyTonightId},
      );

  /// Whether the week's numbered note (9001) is still ahead at [now]: any
  /// Friday, since the note it arms does not go out until the Saturday
  /// morning after (see [kWeeklyNoteHour]). The window [weeklyNotePlan] arms
  /// it in, and the one in which a finishing tap outside the app clears it
  /// (see [standDownWeeklyNumberedNote]).
  ///
  /// It used to stop at Friday 19:00, when the note fired. A Friday evening
  /// is inside the window now: the note has not gone out, and a habit
  /// finished at 22:00 still lands on a Friday square the note counts.
  static bool weeklyNumberedNoteAhead(DateTime now) =>
      now.weekday == DateTime.friday;

  /// Clears the week's numbered note (9001) while it is still pending, and
  /// nothing else.
  ///
  /// For the background action engine, on a finishing tap while
  /// [weeklyNumberedNoteAhead]: the note counts the week's green days and
  /// names the habit with the most («٥ أيام خضرا في أسبوعك 👏🏼»), and a
  /// habit finished from the lock screen or the Watch can add a green day
  /// or overtake that habit. The engine has no Grid to count with, so the
  /// note is cleared rather than left wrong, and the next recompute on that
  /// Friday arms it again with the true count.
  ///
  /// Two guards, not one, and they answer different questions. The window
  /// says the note is about TODAY; the pending read says it has not gone out
  /// yet (see [_cancelIfPending]). A week whose note was never armed, or one
  /// already delivered, therefore loses nothing.
  Future<void> standDownWeeklyNumberedNote() => _cancelIfPending(
        {_weeklyNumberedId},
      );

  /// Reminder schedules and cancels run one after another, never two at once.
  ///
  /// main.dart recomputes reminders several times in a row on a resume,
  /// once per provider that settles, and with notifications alone that
  /// was harmless: zonedSchedule under one id simply replaces. An alarm is
  /// not like that. Seen live 2026-09-06 15:26: four passes inside 300 ms
  /// each did cancel-then-schedule on the same AlarmKit id, mobiletimerd
  /// refused one of them as "a duplicate ID", that pass took the fallback
  /// path and cancelled the alarm the winning pass had just made, and the
  /// slot was left with no alarm and, depending on the interleaving, no
  /// notification either. One lane, so no two passes ever interleave.
  ///
  /// In call order, except that [ahead] work (the habit pass, and a habit's
  /// own cancel, stand-down and snooze) goes before every task job still
  /// waiting. The habit pass is what stands a just-ticked habit down, and
  /// at the back of the line it waited for the whole backlog: on 2026-09-22
  /// «صلاة الضحى» was ticked at 09:25, just after the app opened, and its
  /// 10:47 reminder rang anyway. The pass that would have dropped it was
  /// queued behind the opening's own pass and the task sweep every
  /// recompute queues (8 slots in two systems for each task that ever had
  /// a reminder; that account had 39 done ones, over 600 channel calls a
  /// recompute), and iOS froze the app seconds after the phone was locked.
  /// Jumping the queue never interleaves anything: the job already running
  /// always finishes first, and a task's ids share nothing with a habit's
  /// (see [taskReminderId]). A running habit pass also gives way to a
  /// newer one, see [scheduleSmartReminders], and the lane holds background
  /// time while it has work, see [_holdBackgroundTime].
  final List<_LaneJob<Object?>> _laneQueue = [];
  bool _laneBusy = false;

  Future<T> _serialized<T>(Future<T> Function() work, {bool ahead = false}) {
    final job = _LaneJob<T>(work, ahead: ahead);
    if (ahead) {
      // Behind the ahead work already waiting, so those keep call order.
      final firstTaskJob = _laneQueue.indexWhere((j) => !j.ahead);
      _laneQueue.insert(
          firstTaskJob < 0 ? _laneQueue.length : firstTaskJob, job);
    } else {
      _laneQueue.add(job);
    }
    if (!_laneBusy) {
      _laneBusy = true;
      _holdBackgroundTime(true);
      // A microtask, as the chained Future this replaced was: the caller
      // has its Future before any of the work starts.
      scheduleMicrotask(_drainLane);
    }
    return job.done;
  }

  Future<void> _drainLane() async {
    while (_laneQueue.isNotEmpty) {
      await _laneQueue.removeAt(0).run();
    }
    _laneBusy = false;
    _holdBackgroundTime(false);
  }

  static const _backgroundTime =
      MethodChannel('com.growdaily.v2/background_time');

  /// Asks iOS to keep the app running while the lane has work, or gives
  /// that time back once it is empty.
  ///
  /// An app that leaves the screen is suspended about a second later unless
  /// it holds a background task (measured on the simulator, 2026-09-22: Home
  /// at 11:35:23.7, suspended by 11:35:24.9). A tick followed by locking the
  /// phone is exactly that: however soon the pass that stands the habit down
  /// starts, it can still be frozen before it reaches the system, and the
  /// reminder rings. Held from the moment the lane has work until it is
  /// empty, so what was asked for before leaving still lands; iOS bounds it
  /// (about 30 seconds) and AppDelegate gives it back when that runs out.
  /// iOS only, where the channel lives (AppDelegate.swift); the headless
  /// action engine has no such channel and holds its own time around the
  /// tap. Never awaited: a failure costs nothing but the extra time.
  void _holdBackgroundTime(bool hold) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    _backgroundTime.invokeMethod<void>(hold ? 'begin' : 'end').ignore();
  }

  static const _bundleSlotBase = 7000;
  /// Six bundles' worth of distinct fire-time groups PER DAY of the armed
  /// window (see [kOccurrencesPerSlot]) — the same per-day capacity this
  /// had when a slot held one moment, now that a day's groups repeat for
  /// every day in the window. Past the last one, members fall back to
  /// their own individual reminders rather than being dropped (see
  /// _scheduleResolved), so the cap costs tidiness and never a reminder.
  /// The 7000 band is 1000 wide, so this stays inside it many times over.
  static const _maxBundleSlots = 6 * kOccurrencesPerSlot;
  static const _bundleWindow = Duration(minutes: 15);
  static const _streakRiskId = 8000;
  static const _weeklyDigestId = 9000;

  /// Schedules real, individually-cancellable reminders for habits with a
  /// resolvable cue — a fixed clock time, or a prayer cue once a location
  /// is saved in [settings] — replacing the previous
  /// `scheduleHabitReminders`. What "resolvable" excludes on purpose stays
  /// the same as before this rewrite: a routine-anchored preset that isn't
  /// one of the 5 prayers ('before sleep', 'morning', ...), freeform text,
  /// or no cue at all. Those still don't get a reminder — a wrong-time
  /// reminder is worse than none, and this app doesn't have real
  /// schedule/routine data for them yet.
  ///
  /// What's new here beyond prayer resolution:
  ///  - a habit already completed today is skipped entirely, not just
  ///    silently re-notified (see class doc comment on why that requires
  ///    one-off, not recurring, schedules);
  ///  - quiet hours suppress a reminder unless it's prayer-linked and
  ///    [NotificationSettings.quietHoursAppliesToPrayer] is off (the
  ///    default) — see that field's doc comment;
  ///  - 2+ habits landing within [_bundleWindow] of each other combine into
  ///    one notification instead of arriving back-to-back.
  ///
  /// Safe to call any time the habit list, dashboard completion state, or
  /// notification settings change — see main.dart's `_recomputeNotifications`.
  ///
  /// The newest call always wins, and quickly. A pass still waiting when a
  /// newer one arrives is skipped, and a pass already RUNNING gives way at
  /// its next safe point (between habits, and between reminders while it
  /// arms), because a tick has to reach the system before the app can be
  /// suspended: a pass ran its whole length first, so the one carrying a
  /// stand-down waited for it. Stopping there costs nothing, since the newer
  /// pass redoes all of it with fresher inputs, and nothing is left half
  /// done: a bundle's cancels and its schedule are one step, and whatever a
  /// stopped pass had already armed stays reachable by the next one's stale
  /// sweep (see [_habitReminderHabitIds]).
  Future<void> scheduleSmartReminders(
    List<HabitReminderInput> habits,
    NotificationSettings settings, {
    required bool isAr,
    // habitId -> IslamicHabitTemplate.runsOn, for the habits whose schedule
    // has changed (the rest need nothing: their weekdays already answer every
    // day). Read by the wording only, see reminderFactsAtFireDay's runsOn.
    // Beside the records rather than in them because a record field has no
    // default, and every place that builds one would have to spell it out.
    Map<String, bool Function(DateTime day)> runsOnById = const {},
    // habitId -> the day keys a session on another day of the same week
    // already covers (see moved_day_plan.dart). Beside the records for the
    // same reason as [runsOnById]. A habit absent here has nothing excused.
    Map<String, Set<String>> excusedDaysById = const {},
  }) {
    if (kIsWeb) return Future.value();
    final token = ++_sweepToken;
    // Logged once, at the first safe point that finds it overtaken.
    var gaveWayLogged = false;
    bool gaveWay() {
      if (token == _sweepToken) return false;
      if (!gaveWayLogged) {
        gaveWayLogged = true;
        debugPrint('[NotificationService] pass gave way to a newer one');
      }
      return true;
    }

    return _serialized(
      () async {
        // Overtaken while waiting its turn: a later call holds the newer
        // habit list and settings, and its own pass is queued behind this
        // one. Running this one as well would only repeat the work.
        if (token != _sweepToken) return;
        // Set inside the serial lane, so a pass never reads another pass's.
        _runsOnById = runsOnById;
        _excusedDaysById = excusedDaysById;
        await _sweepHabitReminders(
          habits,
          settings,
          isAr: isAr,
          gaveWay: gaveWay,
        );
      },
      ahead: true,
    );
  }

  int _sweepToken = 0;

  /// The current pass's schedules for the habits that changed schedule; see
  /// scheduleSmartReminders.
  Map<String, bool Function(DateTime day)> _runsOnById = const {};

  /// The current pass's covered days per habit; see scheduleSmartReminders.
  Map<String, Set<String>> _excusedDaysById = const {};

  /// [gaveWay] answers whether a newer pass has been asked for, in which
  /// case this one returns at the next safe point; see
  /// [scheduleSmartReminders].
  Future<void> _sweepHabitReminders(
    List<HabitReminderInput> habits,
    NotificationSettings settings, {
    required bool isAr,
    required bool Function() gaveWay,
  }) async {
    await init();

    // Reset before either path below arms anything, so what it collects is
    // this pass's alarms and the reap at the end of both paths judges
    // against those, never against a previous pass's. The record of what
    // was armed likewise holds this pass's reminders and nothing older.
    _armedHabitAlarmIds.clear();
    _armedCopies.clear();
    _armedBundles.clear();
    _sweepLiveNoteIds = await _liveNotificationIds();

    final nextHabitIds = habits.map((h) => h.id).toSet();

    if (!settings.masterEnabled || !settings.habitRemindersEnabled) {
      for (final id in _habitReminderHabitIds) {
        await _cancelAllHabitReminderSlots(id);
      }
      for (var i = 0; i < _maxBundleSlots; i++) {
        await _plugin.cancel(_bundleSlotBase + i);
      }
      _habitReminderHabitIds.clear();
      // The month armed ahead for alarm reminders is not in the per-slot
      // sweep above; an empty window cancels all of it.
      await _syncAlarmWindow(const [], isAr);
      // Nor is anything the per-slot sweep above could not name: it can
      // only reach habits this session remembers scheduling.
      await _reapOrphanHabitAlarms();
      // Nothing is armed, so a Done outside the app has nothing to take down.
      await _publishArmedReminders(const []);
      debugPrint('[NotificationService] Habit reminders off — cleared');
      return;
    }

    final resolved = <_ResolvedReminder>[];
    final now = tz.TZDateTime.now(tz.local);
    // The rest of every alarm reminder's month, past the ordinary window,
    // armed in one call once the ordinary window is (see _syncAlarmWindow).
    final windowed = <_ResolvedReminder>[];
    // Whether an alarm reminder really rings as an alarm here: iOS 26 or
    // newer with the permission granted. Only then does it get the month; a
    // reminder that falls back to a notification is bound by iOS's 64-request
    // budget like any other and keeps the ordinary four.
    final alarmsReady = habits.any((h) => h.alarm && !h.isQuit) &&
        await AlarmService.instance.isAuthorized();
    // Held for _scheduleResolved's budget check: when alarms cannot be armed
    // at all, an alarm reminder is a notification like any other and has to
    // be trimmed like one.
    _alarmsReady = alarmsReady;
    final alarmHorizon = now.add(const Duration(days: kAlarmWindowDays));
    // Prayer times for the whole window, resolved at most ONCE per call
    // (not once per habit, and not once per day): every prayer-linked habit
    // shares the same location, method and madhab, so one run of days
    // answers all of them. Was a per-day map filled lazily, which became
    // the wrong shape the moment a slot wanted several days at once — that
    // would have been one Aladhan round trip per day per recompute, and a
    // recompute runs on every resume. PrayerTimesService.calculateDays
    // takes the whole run in a single request instead.
    //
    // Null until the first prayer-linked habit actually needs it, so a
    // person with no prayer-anchored habit never pays for any of this.
    List<PrayerDayTimes>? prayerDays;
    // How far the window has to reach. A habit that runs every day needs
    // one day per occurrence plus today; one pinned to specific weekdays
    // can need a whole week per occurrence, so it is only paid for when
    // such a habit is actually present.
    final baseWindowDays = habits.any((h) =>
            h.prayerKey != null && h.scheduledWeekdays.isNotEmpty)
        ? 1 + 7 * kOccurrencesPerSlot
        : 1 + kOccurrencesPerSlot;
    // An alarm's month needs a month of prayer times: today plus thirty.
    final prayerWindowDays = alarmsReady &&
            baseWindowDays < kAlarmWindowDays + 1 &&
            habits.any((h) => h.prayerKey != null && h.alarm && !h.isQuit)
        ? kAlarmWindowDays + 1
        : baseWindowDays;

    for (final habit in habits) {
      // Nothing is armed until every habit is resolved, so stopping between
      // two leaves only cancels behind it, each one a copy the newer pass
      // would drop as well or arm again.
      if (gaveWay()) return;
      // The (slot, depth) pairs this habit will hold after this pass.
      // Everything NOT in here is swept below, which is what makes shrinking
      // a habit from four times a day to two actually disarm slots 2 and 3
      // instead of leaving them armed with nothing in the app pointing at
      // them any more — and, now that a slot holds a window of days rather
      // than a single moment, what disarms the days that fell out of it.
      final keptSlots = <({int slot, int depth})>{};

      // Whether this habit's reminders really ring as alarms, which is what
      // earns them a month-long window (see [kAlarmWindowDays]).
      final alarmWindow = alarmsReady && habit.alarm && !habit.isQuit;

      // Every moment a PRAYER-anchored habit fires at: one per shift it
      // carries, times the next few days of each (see
      // [kOccurrencesPerSlot]), in slot then depth order. A habit with no
      // stack resolves slot 0 at depths 0..3 — depth 0 keeping the id this
      // habit has always used.
      final prayerFires =
          <({int slot, int depth, tz.TZDateTime at, int offsetMinutes})>[];
      var isPrayerLinked = false;

      if (habit.clockTimes.isNotEmpty) {
        // ── The multi-time path ──────────────────────────────────────────
        final allTimes = resolveClockOccurrences(
          habit.clockTimes,
          habit.clockOffsets,
          now,
          scheduledWeekdays: habit.scheduledWeekdays,
          excusedDayKeys: _excusedDaysById[habit.id] ?? const {},
          occurrences: alarmWindow ? _alarmDepthLimit : kOccurrencesPerSlot,
        );
        // The ordinary window; an alarm's further days are armed below.
        final candidates = [
          for (final c in allTimes)
            if (c.depth < kOccurrencesPerSlot) c,
        ];
        // An alarm is the person asking to be woken, so quiet hours do not
        // silence it, the same exemption the prayer branch below applies.
        final exempt = habit.ignoreQuietHours || (habit.alarm && !habit.isQuit);
        // Quiet hours are judged PER TIME, not per habit. The old rule
        // cancelled the whole habit the moment its one time landed inside the
        // window, and carried straight over would have been the protein bug:
        // midnight sits inside the default quiet window, so a habit set for
        // 00:00 and 12:00 would lose the perfectly deliverable noon ping
        // along with the midnight one.
        final awake = [
          for (final c in candidates)
            if (exempt ||
                !settings.quietHoursEnabled ||
                !isMinuteWithinQuietHours(
                  c.fireTime.hour * 60 + c.fireTime.minute,
                  settings.quietHoursStart,
                  settings.quietHoursEnd,
                ))
              c,
        ];
        // ── Already done, this many times ────────────────────────────────
        //
        // Suppress the earliest still-TODAY reminders, one per completion, and
        // never one that has already rolled to tomorrow. A 00:00 slot resolved
        // at 2pm is tomorrow's midnight; cancelling it because today's count
        // is met would silently disarm tomorrow morning, and nothing would
        // re-arm it until the app was next opened.
        final today = <({int slot, int depth, tz.TZDateTime fireTime})>[];
        final later = <({int slot, int depth, tz.TZDateTime fireTime})>[];
        // "Today" here must mean the same day the completion count is keyed
        // to — the EFFECTIVE day that rolls at kDayCutoffHour, not the
        // calendar date. Between midnight and the cutoff the two disagree in
        // both directions: a 23:00 habit completed at 23:15 and recomputed
        // at 00:30 resolves to calendar-today 23:00, which is the NEXT
        // effective day's reminder and must not be suppressed by today's
        // count; while a 00:30 slot for an already-finished effective day
        // resolves to calendar-tomorrow and used to stay armed, pinging for
        // a habit the app itself grades as done.
        for (final c in awake) {
          (c.fireTime.effectiveDay.isSameDayAs(now.effectiveDay)
                  ? today
                  : later)
              .add(c);
        }
        today.sort((a, b) => a.fireTime.compareTo(b.fireTime));
        // One completion stands down one OCCURRENCE — which is one slot for
        // an ordinary habit, and a whole run of them for a stacked one. See
        // HabitReminderInput.remindersPerOccurrence: without the multiplier a
        // habit reminding at −10/0/+30 and logged once went quiet for ten
        // minutes and then pinged twice more about a square already filled.
        final perOccurrence =
            habit.remindersPerOccurrence < 1 ? 1 : habit.remindersPerOccurrence;
        final suppress =
            (habit.completedCount * perOccurrence).clamp(0, today.length);
        for (final c in [...today.skip(suppress), ...later]) {
          keptSlots.add((slot: c.slot, depth: c.depth));
          resolved.add((
            id: habit.id,
            name: habit.name,
            fireTime: c.fireTime,
            streak: habit.streak,
            slot: c.slot,
            depth: c.depth,
            // Read back off the same index-aligned list resolveClockSlots
            // consumed, rather than widening that function's return type:
            // it is a @visibleForTesting static with its own pinned
            // expectations (test/multi_time_reminder_slots_test.dart), and
            // clockOffsets is index-aligned with clockTimes by construction,
            // so slot IS the offset's index. Same defensive bound
            // resolveClockSlots itself uses for a short list.
            offsetMinutes: c.slot < habit.clockOffsets.length
                ? habit.clockOffsets[c.slot]
                : 0,
            // A clock time is its own anchor, and the notification already
            // arrives stamped with one.
            anchorLabel: null,
            completedCount: habit.completedCount,
            dailyTarget: habit.dailyTarget,
            lastDoneDaysAgo: habit.lastDoneDaysAgo,
            timerSeconds: habit.timerSeconds,
            scheduledWeekdays: habit.scheduledWeekdays,
            weekTarget: habit.weekTarget,
            weekDoneDays: habit.weekDoneDays,
            timeSensitive: false,
            alarm: habit.alarm,
            isQuit: habit.isQuit,
            isLimit: habit.isLimit,
          ));
        }
        // The rest of an alarm's month. Never today (four occurrences out at
        // the nearest), so the done count above has nothing to stand down.
        for (final c in allTimes) {
          if (c.depth < kOccurrencesPerSlot ||
              !c.fireTime.isBefore(alarmHorizon)) {
            continue;
          }
          windowed.add((
            id: habit.id,
            name: habit.name,
            fireTime: c.fireTime,
            streak: habit.streak,
            slot: c.slot,
            depth: c.depth,
            offsetMinutes: c.slot < habit.clockOffsets.length
                ? habit.clockOffsets[c.slot]
                : 0,
            anchorLabel: null,
            completedCount: habit.completedCount,
            dailyTarget: habit.dailyTarget,
            lastDoneDaysAgo: habit.lastDoneDaysAgo,
            timerSeconds: habit.timerSeconds,
            scheduledWeekdays: habit.scheduledWeekdays,
            weekTarget: habit.weekTarget,
            weekDoneDays: habit.weekDoneDays,
            timeSensitive: false,
            alarm: habit.alarm,
            isQuit: habit.isQuit,
            isLimit: habit.isLimit,
          ));
        }
        // Every armed copy this habit did not keep — dropped for quiet
        // hours, suppressed as done, beyond a count that just shrank, or a
        // depth left over from a window that used to reach further (a habit
        // edited from daily to once a week resolves fewer occurrences, and
        // the copies it no longer wants are still in the scheduler).
        await _sweepUnkeptSlots(
          habit.id,
          keptSlots,
          doneToday: habit.completedCount >= habit.dailyTarget,
        );
        continue;
      } else if (habit.prayerKey != null && settings.location != null) {
        isPrayerLinked = true;
        final loc = settings.location!;
        // The shifts this habit fires at, primary first so it keeps slot 0
        // and the id it has always had. A prayer is still ONE moment — five
        // times a day for a prayer habit means five different prayers, which
        // is a different feature — but that one moment can now be nudged
        // around several times (see extraReminderOffsets).
        //
        // Signed throughout: added, never subtracted. A negative value (the
        // "before" case) shifts backwards on its own.
        final shifts = [
          habit.reminderOffsetMinutes,
          ...habit.extraReminderOffsets,
        ].take(_maxHabitReminderSlots).toList();
        final days = prayerDays ??= await PrayerTimesService.calculateDays(
          latitude: loc.lat,
          longitude: loc.lng,
          from: now,
          days: prayerWindowDays,
          madhab: settings.madhab,
          countryCode: settings.resolvedCountryCode,
        );
        for (var slot = 0; slot < shifts.length; slot++) {
          final offset = Duration(minutes: shifts[slot]);
          // Walk forward collecting the next [kOccurrencesPerSlot]
          // occurrences of this prayer that are both still ahead and on a
          // day the habit actually runs.
          //
          // Each one reads its OWN day's prayer times, which is the whole
          // point of arming a window: Fajr moves by about a minute every
          // other day, so four copies of one frozen moment would be four
          // reminders drifting away from the prayer they name. Day 0 is
          // today (its prayer may already have passed, in which case it is
          // simply skipped) and the days after it are the ones a phone left
          // untouched would otherwise have nothing armed for.
          //
          // A weekday-restricted habit walks the same list and takes only
          // the days it runs on, which is why the window is a week per
          // occurrence for those (see prayerWindowDays).
          //
          // Resolved per shift rather than once and offset afterwards,
          // because two shifts around one prayer can land on different DAYS:
          // recomputed just after Maghrib, a −10 nudge belongs to tomorrow's
          // Maghrib while a +30 one is still ahead today.
          var depth = 0;
          final depthLimit =
              alarmWindow ? _alarmDepthLimit : kOccurrencesPerSlot;
          for (var dayOffset = 0;
              dayOffset < days.length && depth < depthLimit;
              dayOffset++) {
            // Written as an explicit null-check + reassignment rather than a
            // `?.add(...)` chain — Dart's "null-shorting" would make that
            // chain correct too (a `?.` shorts every plain `.` call chained
            // after it, not just the very next one), but that's a
            // sharp-edged-enough corner of the language to avoid leaning on.
            var candidate = days[dayOffset].forKey(habit.prayerKey!);
            if (candidate == null) break;
            candidate = candidate.add(offset);
            if (!candidate.isAfter(now)) continue;
            if (!_fireDayIsScheduled(candidate, habit.scheduledWeekdays)) {
              continue;
            }
            // A day a session elsewhere in the week already covers, as in
            // resolveClockOccurrences.
            if ((_excusedDaysById[habit.id] ?? const <String>{})
                .contains(candidate.effectiveDay.toDateKey())) {
              continue;
            }
            // Past the ordinary four, an alarm's month ends at the horizon.
            if (depth >= kOccurrencesPerSlot &&
                !candidate.isBefore(alarmHorizon)) {
              break;
            }
            prayerFires.add((
              slot: slot,
              depth: depth,
              at: candidate,
              offsetMinutes: shifts[slot],
            ));
            depth++;
          }
        }
      }

      if (prayerFires.isEmpty) {
        await _cancelAllHabitReminderSlots(habit.id);
        continue;
      }

      // The ordinary window, which the quiet-hours and done-today rules
      // below judge; an alarm's further days are armed after them.
      final nearFires = [
        for (final f in prayerFires)
          if (f.depth < kOccurrencesPerSlot) f,
      ];

      // Three ways to be exempt: a prayer-linked reminder (whose whole point
      // is landing near a prayer that's often inside a normal night-time
      // quiet window — see quietHoursAppliesToPrayer), a reminder that rings
      // as an ALARM (the person asked to be woken; with quiet hours set to
      // cover prayers too, a Fajr alarm used to be never armed at all), or
      // this specific habit having been explicitly opted out via Add Habit's
      // "Allow anyway" after being warned about the conflict.
      final exemptFromQuietHours = habit.ignoreQuietHours ||
          (habit.alarm && !habit.isQuit) ||
          (isPrayerLinked && !settings.quietHoursAppliesToPrayer);
      // Judged per shift, matching the clock branch above: a stack whose
      // "an hour before Fajr" entry lands inside the night window loses that
      // one entry, not the on-time reminder beside it that is perfectly
      // deliverable.
      final awakeFires = [
        for (final f in nearFires)
          if (exemptFromQuietHours ||
              !settings.quietHoursEnabled ||
              !isMinuteWithinQuietHours(
                f.at.hour * 60 + f.at.minute,
                settings.quietHoursStart,
                settings.quietHoursEnd,
              ))
            f,
      ];

      // Done for today stands down TODAY's entries only.
      //
      // Every shift in a stack is about the same single prayer moment, so
      // one completion does answer all of them — but only for the day it
      // was logged on. Standing the whole habit down was right when a slot
      // held exactly one moment and that moment was always the next one;
      // with a window armed it silently disarmed tomorrow morning's Fajr
      // too, and nothing re-armed it until the app was next opened. It also
      // fixes the same bug in the old single-occurrence behaviour: complete
      // a Fajr habit after Fajr and the one thing armed was TOMORROW's, and
      // completing today cancelled it.
      //
      // Effective days, not calendar ones, for the same reason the clock
      // branch above uses them: the app's day runs to kDayCutoffHour, so an
      // 04:00 reminder belongs to the night before.
      final doneToday = habit.completedCount >= habit.dailyTarget;
      final keptFires = [
        for (final f in awakeFires)
          if (!(doneToday && f.at.effectiveDay.isSameDayAs(now.effectiveDay)))
            f,
      ];
      final keptPrayerSlots = {
        for (final f in keptFires) (slot: f.slot, depth: f.depth),
      };
      // Every armed copy this habit did not keep — dropped for quiet hours,
      // done for today, beyond a stack that just shrank, or left armed by a
      // multi-time clock cue this habit was edited AWAY from (the clock
      // branch sweeps only its own non-kept slots, and the stale sweep below
      // only covers habits that LEFT the list, so without this those higher
      // slots kept firing daily forever). Runs before _scheduleResolved,
      // preserving the cancel-first ordering the sweep comment below argues
      // for.
      await _sweepUnkeptSlots(
        habit.id,
        keptPrayerSlots,
        doneToday: doneToday,
      );
      for (final f in keptFires) {
        resolved.add((
          id: habit.id,
          name: habit.name,
          fireTime: f.at,
          streak: habit.streak,
          slot: f.slot,
          depth: f.depth,
          // This entry's own shift — the number the notification's wording
          // reads to say «باقي ١٠ دقائق على المغرب» rather than the habit's
          // primary one, which for slots 1 and up is a different reminder.
          offsetMinutes: f.offsetMinutes,
          anchorLabel: habit.anchorLabel,
          completedCount: habit.completedCount,
          dailyTarget: habit.dailyTarget,
          lastDoneDaysAgo: habit.lastDoneDaysAgo,
          timerSeconds: habit.timerSeconds,
          scheduledWeekdays: habit.scheduledWeekdays,
          weekTarget: habit.weekTarget,
          weekDoneDays: habit.weekDoneDays,
          timeSensitive: true,
          alarm: habit.alarm,
          isQuit: habit.isQuit,
          isLimit: habit.isLimit,
        ));
      }
      // The rest of an alarm's month: never today, so the stand-down above
      // has nothing to say about it, and exempt from quiet hours like the
      // alarm it extends.
      for (final f in prayerFires) {
        if (f.depth < kOccurrencesPerSlot) continue;
        windowed.add((
          id: habit.id,
          name: habit.name,
          fireTime: f.at,
          streak: habit.streak,
          slot: f.slot,
          depth: f.depth,
          offsetMinutes: f.offsetMinutes,
          anchorLabel: habit.anchorLabel,
          completedCount: habit.completedCount,
          dailyTarget: habit.dailyTarget,
          lastDoneDaysAgo: habit.lastDoneDaysAgo,
          timerSeconds: habit.timerSeconds,
          scheduledWeekdays: habit.scheduledWeekdays,
          weekTarget: habit.weekTarget,
          weekDoneDays: habit.weekDoneDays,
          timeSensitive: true,
          alarm: habit.alarm,
          isQuit: habit.isQuit,
          isLimit: habit.isLimit,
        ));
      }
    }

    // Swept BEFORE anything is scheduled, never after.
    //
    // Reminder ids are hashes folded into shared 1000-wide bands, so two habits
    // can land on the same id, and cancelling one habit can cancel another's.
    // The done / unresolvable / quiet-hours cancels above all run before
    // _scheduleResolved, so a collision there is immediately overwritten by the
    // real schedule and costs nothing. This sweep used to run after it, which
    // is the one ordering where a collision is permanent: delete a habit as the
    // last thing before backgrounding the app and, on a collision, another
    // habit's just-scheduled reminder was cancelled and simply never fired,
    // with no recompute due until the app was next opened.
    for (final staleId in _habitReminderHabitIds.difference(nextHabitIds)) {
      if (gaveWay()) return;
      await _cancelAllHabitReminderSlots(staleId);
    }
    if (gaveWay()) return;

    // Remembered BEFORE anything is armed, not only once the pass is done:
    // a pass that gives way halfway through arming has put reminders in the
    // system for these habits, and the next pass's stale sweep can only
    // reach a habit this set names. Exact again at the end.
    _habitReminderHabitIds.addAll(nextHabitIds);
    await _scheduleResolved(resolved, settings.bundleEnabled, isAr, gaveWay);
    if (gaveWay()) return;
    // What a Done outside the app reads to know which ids hold which day,
    // written the moment the near window is armed rather than at the very
    // end: until it lands, the record still describes the previous pass,
    // whose ids may name other days now, so the gap is kept as short as the
    // arming allows. The far alarms go in first; their ids are fixed by day
    // (see [windowAlarmId]), so naming them before the sync below says
    // nothing a later day could contradict.
    for (final r in _alarmWindowOrder(windowed).take(kMaxWindowAlarms)) {
      _armedCopies.add((
        habitId: r.id,
        id: windowAlarmId(r.id, r.slot, r.fireTime),
        fireTime: r.fireTime,
        kind: ArmedReminderKind.alarm,
      ));
    }
    await _publishArmedReminders(nextHabitIds);
    await _syncAlarmWindow(windowed, isAr);
    if (gaveWay()) return;
    // Last, because it judges by what this pass actually armed: anything
    // else the near bands still hold belongs to no habit the app has any
    // more (see [_reapOrphanHabitAlarms]). Never after a pass that gave
    // way, whose arming is incomplete; the newer pass reaps instead.
    await _reapOrphanHabitAlarms();

    _habitReminderHabitIds
      ..clear()
      ..addAll(nextHabitIds);
    // Counts SLOTS, not habits — the two stopped being the same number once a
    // habit could hold several times, and the old subtraction went negative.
    // The total is also the observable ceiling check: iOS keeps only 64
    // pending notifications, and 8 habits at 4 times a day is 32 before
    // streak nudges, quit check-ins, the daily reminder and task slots.
    debugPrint('[NotificationService] ${resolved.length} reminder slot(s) '
        'across ${habits.length} habit(s)');
  }

  /// Groups [resolved] by fire time (within [_bundleWindow]) and schedules
  /// either one actionable per-habit notification (groups of 1, or any
  /// group at all when [bundleEnabled] is off) or one combined notification
  /// per group of 2+. Extracted from [scheduleSmartReminders] as its own
  /// step so the grouping logic itself — sort, walk, cut a new group past
  /// the window — reads as one clear pass instead of being interleaved with
  /// the resolution loop above it.
  /// One habit's own reminder, in its own slot, with its Mark Done action.
  ///
  /// [payload] is the BARE habit id, never `id#slot`: main.dart's
  /// _resolveHabit does an exact-id lookup, so a slot-qualified payload would
  /// resolve to null, fall through to the task branch, poll for two seconds
  /// and do nothing at all when the person tapped the notification.
  /// Returns whether this slot spent one of iOS's 64 pending notification
  /// requests — false when it rang through AlarmKit instead, which has no
  /// such budget. The caller needs to know, because an alarm that is REFUSED
  /// falls through to a notification here and spends the budget after all.
  Future<bool> _scheduleOne(_ResolvedReminder r, bool isAr) async {
    // What this reminder says when its timing is "on the dot", which
    // habitReminderBody keeps as-is and an early or late reminder replaces
    // the lead sentence of.
    //
    // Everything state-dependent in it is measured at SCHEDULE time but read
    // at FIRE time, and those can be days apart: a slot whose clock time has
    // already passed rolls to the habit's next scheduled day. So the
    // day-sensitive facts are re-based onto the day this reminder actually
    // lands on, and measured on the habit's own schedule rather than the
    // calendar; see reminderFactsAtFireDay for both rules. The day rolls at
    // midnight, so a 7am reminder belongs to its own calendar day, and the
    // fire INSTANT goes in too: at 7am yesterday is still open until
    // kDayCutoffHour, and cannot be worded as missed yet.
    final facts = _factsAtFireDay(r);
    // Seeded from the day this copy fires, not the day it was armed: see
    // reminderVariantSeed.
    final seed = reminderVariantSeed(r.fireTime, r.id);
    final onTimeLine = habitOnTimeLine(
      streak: facts.streak,
      completedCount: facts.completedCount,
      dailyTarget: r.dailyTarget,
      lastDoneDaysAgo: facts.lastDoneDaysAgo,
      timerSeconds: r.timerSeconds,
      variantIndex: seed,
      isAr: isAr,
      everyDay: facts.everyDay,
      weekTarget: r.weekTarget,
      weekDone: facts.weekDone,
      owedToday: facts.owedOnFireDay,
      // At the adhan itself the prayer is named, «اذن الفجر. سوي عادتك
      // الحين.». It never was: the on-time line was returned before anything
      // read the anchor.
      anchorLabel: r.anchorLabel,
    );
    // A quit habit's reminder is a check-in, not a call to act: its own
    // question, with التزام / ما التزمت under it (quitReminderBody). The build
    // wording ("It's time. Don't let today slip by.") about something the
    // person is trying not to do was the wrong sentence with the wrong
    // buttons.
    final body = r.isQuit
        ? quitReminderBody(isLimit: r.isLimit, isAr: isAr)
        : habitReminderBody(
            offsetMinutes: r.offsetMinutes,
            streak: facts.streak,
            anchorLabel: r.anchorLabel,
            isAr: isAr,
            onTimeLine: onTimeLine,
            everyDay: facts.everyDay,
            // Same seed the on-time line rotates on, so one habit's reminder
            // keeps one voice for the day instead of two halves that drift.
            variantIndex: seed,
          );
    // What this slot will say and when, so a wrong line can be read off the
    // run log at schedule time instead of waited for on a lock screen.
    debugPrint('[NotificationService] ${r.name} (${r.id}#${r.slot}'
        '${r.depth == 0 ? '' : '+${r.depth}'}) at ${r.fireTime}: $body');
    final slotId = _habitReminderId(r.id, r.slot, r.depth);
    // A habit switched to alarm rings through AlarmService where that
    // exists (iOS 26+, permission granted). The alarm replaces the
    // notification for this slot, so the notification under the same id is
    // cleared; and if the alarm could not be made, the notification below
    // takes over, Time Sensitive so the person still gets what they asked
    // for as nearly as the platform allows.
    if (!r.isQuit &&
        r.alarm &&
        await AlarmService.instance.schedule(
          id: slotId,
          fireAt: r.fireTime,
          title: r.name,
          subtitle: body,
          kind: 'habit',
          targetId: r.id,
          stopLabel: alarmStopAction(isAr),
        )) {
      await _plugin.cancel(slotId);
      _armedHabitAlarmIds.add(slotId);
      _armedCopies.add((
        habitId: r.id,
        id: slotId,
        fireTime: r.fireTime,
        kind: ArmedReminderKind.alarm,
      ));
      debugPrint('[NotificationService] ${r.name} (${r.id}#${r.slot}'
          '${r.depth == 0 ? '' : '+${r.depth}'}) rings as an alarm');
      return false;
    }
    // A slot that was an alarm on an earlier pass and is a notification now.
    await AlarmService.instance.cancel(slotId);
    await _zonedSchedule(
      slotId,
      r.name,
      body,
      r.fireTime,
      r.isQuit
          ? _quitCheckInDetails(isAr)
          : _habitReminderDetails(
              isAr,
              timeSensitive: r.timeSensitive || r.alarm,
              alarmStyle: r.alarm,
            ),
      alarm: r.alarm,
      payload: r.id,
    );
    _armedCopies.add((
      habitId: r.id,
      id: slotId,
      fireTime: r.fireTime,
      kind: ArmedReminderKind.notification,
    ));
    return true;
  }

  /// [reminderFactsAtFireDay] for one resolved reminder, re-based from today
  /// onto the day [r] fires on, at the instant it fires (yesterday is still
  /// open until kDayCutoffHour). Shared by a single reminder and a bundle, so
  /// a bundle's praise is measured exactly the way each member's own reminder
  /// would have been.
  ({
    int streak,
    int completedCount,
    int? lastDoneDaysAgo,
    int missedSinceLastDone,
    int? weekDone,
    bool owedOnFireDay,
    bool everyDay,
  }) _factsAtFireDay(_ResolvedReminder r) => reminderFactsAtFireDay(
        today: tz.TZDateTime.now(tz.local).effectiveDay,
        fireDay: r.fireTime.effectiveDay,
        fireTime: r.fireTime,
        streak: r.streak,
        completedCount: r.completedCount,
        lastDoneDaysAgo: r.lastDoneDaysAgo,
        scheduledWeekdays: r.scheduledWeekdays,
        weekTarget: r.weekTarget,
        weekDoneDays: r.weekDoneDays,
        runsOn: _runsOnById[r.id],
      );

  /// One bundle member as [habitBundleBody] reads it: its moment, and the
  /// streak and cadence from the same [_factsAtFireDay] its own reminder
  /// would use, so a bundle never praises a run that member's own reminder
  /// on that day would not.
  BundleMember _bundleMemberAtFireDay(_ResolvedReminder r) {
    final facts = _factsAtFireDay(r);
    return (
      offsetMinutes: r.offsetMinutes,
      anchorLabel: r.anchorLabel,
      fireTime: r.fireTime,
      streak: facts.streak,
      everyDay: facts.everyDay,
      isQuota: r.weekTarget != null,
    );
  }

  /// Stops between two reminders once [gaveWay] says a newer pass is
  /// waiting (see [scheduleSmartReminders]). One reminder, or one bundle
  /// with the cancels of its members, is the step it never stops inside.
  Future<void> _scheduleResolved(
    List<_ResolvedReminder> resolved,
    bool bundleEnabled,
    bool isAr,
    bool Function() gaveWay,
  ) async {
    // An alarm is one habit ringing on its own; folding it into a
    // «عادتان جاهزتان» bundle would lose that. Alarm slots are scheduled on
    // their own, first, and only the notification slots go through the
    // bundling and the 64-request budget below (AlarmKit has no such cap).
    // A quit habit's check-in is kept out of bundles for the same reason:
    // it carries التزام / ما التزمت, and a «عادتان جاهزتان» bundle carries Mark
    // Done. It is scheduled on its own through _scheduleOne, which knows
    // what a quit reminder says and which buttons it gets.
    final alone = <_ResolvedReminder>[];
    final notified = <_ResolvedReminder>[];
    for (final r in resolved) {
      (r.alarm || r.isQuit ? alone : notified).add(r);
    }
    // Sorted the same way the groups below are, and for the same reason:
    // whatever the budget cannot cover has to be the far end of the window,
    // never somebody's next reminder. See the groups sort.
    alone.sort((a, b) {
      final byDepth = a.depth.compareTo(b.depth);
      return byDepth != 0 ? byDepth : a.fireTime.compareTo(b.fireTime);
    });
    var scheduledCount = 0;
    var trimmed = 0;
    for (final r in alone) {
      if (gaveWay()) return;
      // A quit check-in is NOT an alarm — [_scheduleOne]'s alarm branch
      // excludes isQuit on purpose, because التزام / ما التزمت is not a thing to
      // be woken by — so it is always a notification and always spends one
      // of iOS's 64 pending requests. It used to spend them off the books:
      // this whole list skipped the budget below, so an account with enough
      // quit habits pushed the real total past 64, where iOS silently
      // discards the excess, AND left the trim under-counting, so ordinary
      // habits were measured against a number that was already wrong.
      // Anything that WILL spend a pending request is checked before it is
      // scheduled, not merely counted after. A quit check-in always will; so
      // does an alarm reminder on a device where alarms cannot be armed at
      // all, which falls back to a notification every time. Counting those
      // without also trimming them let the total run past the budget again,
      // and because this list is scheduled before the groups below, the
      // overrun came straight out of the ordinary habits' share.
      if ((r.isQuit || !_alarmsReady) &&
          scheduledCount >= kMaxPendingHabitSlots) {
        await _cancelHabitSlot(r.id, r.slot, r.depth);
        trimmed++;
        continue;
      }
      // Alarms are never trimmed here: AlarmKit has no such budget, so one
      // costs nothing to keep. It only counts when it could not be made and
      // fell through to a notification, which is exactly what the return
      // value reports.
      if (await _scheduleOne(r, isAr)) scheduledCount++;
    }
    final rawGroups = groupByFireTimeWindow<_ResolvedReminder>(
      notified,
      enabled: bundleEnabled,
      window: _bundleWindow,
      fireTimeOf: (r) => r.fireTime,
    );

    // Bundling asks "which reminders land close together", which is a question
    // about the CLOCK and knows nothing about habits. Two times of one habit
    // that sit inside the window — 12:00 and 12:10, both legal on the stepper
    // — therefore merged into a single «عادتان جاهزتان · بروتين، بروتين»
    // ping, naming the habit twice and losing the Mark Done action a single
    // habit's reminder carries. A group keeps at most one entry per habit; the
    // rest become their own singletons and keep their own actionable ping.
    final groups = <List<_ResolvedReminder>>[];
    for (final group in rawGroups) {
      final seen = <String>{};
      final head = <_ResolvedReminder>[];
      for (final r in group) {
        if (seen.add(r.id)) {
          head.add(r);
        } else {
          groups.add([r]);
        }
      }
      if (head.isNotEmpty) groups.add(head);
    }
    // Shallowest depth first, then by moment. NOT fire time alone, which
    // is what this used to be and what quietly broke the promise the trim
    // below makes: a Sun/Tue/Thu habit recomputed on a Wednesday has its
    // NEXT reminder six days out, so on absolute time it sorts behind every
    // daily habit's fourth-day copy and is the first thing dropped when the
    // budget runs out. Depth is exactly the "how much does losing this
    // cost" ordering — every habit's next reminder is spent before anyone's
    // day after, and the far end of the window is what a heavy user loses.
    //
    // The group's own minimum, because a bundle is scheduled as one
    // notification and is worth the most valuable thing in it.
    int shallowest(List<_ResolvedReminder> g) =>
        g.map((r) => r.depth).reduce((a, b) => a < b ? a : b);
    groups.sort((a, b) {
      final byDepth = shallowest(a).compareTo(shallowest(b));
      if (byDepth != 0) return byDepth;
      return a.first.fireTime.compareTo(b.first.fireTime);
    });

    final usedBundleIds = <int>{};
    var slot = 0;
    // iOS keeps only the 64 soonest pending notification requests and
    // SILENTLY discards the rest — easily reachable now that each slot
    // holds a window of days (6 habits at 12 times a day is 72 slots at
    // depth 0 alone, before the daily reminder, nudges, snoozes and task
    // reminders join in). Groups are sorted shallowest-depth-first above,
    // so the budget is spent on every habit's NEXT reminder before anyone's
    // day after, and what is dropped is the far end of the window.
    //
    // Dropping them OURSELVES rather than letting iOS do it means their
    // possibly-stale previous schedules get cancelled instead of lingering,
    // and the next recompute re-creates them once earlier slots have fired.
    // Headroom under 64 is reserved for everything that is not a habit
    // slot.
    //
    // scheduledCount and trimmed are carried over from the alone loop
    // above, not restarted: quit check-ins and refused alarms are pending
    // notifications like any other, and counting them separately is what
    // let the real total run past 64.
    for (final group in groups) {
      if (gaveWay()) return;
      if (scheduledCount >= kMaxPendingHabitSlots) {
        for (final r in group) {
          await _cancelHabitSlot(r.id, r.slot, r.depth);
          trimmed++;
        }
        continue;
      }
      scheduledCount++;
      if (group.length == 1) {
        await _scheduleOne(group.first, isAr);
        continue;
      }
      // 2+ habits due within the same short window: one combined ping
      // instead of several back-to-back. No Mark Done action here (there's
      // no single target habit for a tap to complete) — a plain tap just
      // opens the app, same as any notification with no registered action
      // id (see NotificationService._dispatch / main.dart's
      // _handleNotificationAction, which already no-ops safely on an empty
      // actionId).
      if (slot >= _maxBundleSlots) {
        // Extremely unlikely in practice — would need 7+ distinct bundles in a
        // single day. Past the last bundle id, every member falls back to its
        // own individual reminder rather than being CANCELLED, which is what
        // used to happen: overflow silently cost those habits their reminder
        // entirely, and the id range stays bounded either way because an
        // individual reminder uses the habit's own slot id.
        for (final r in group) {
          await _scheduleOne(r, isAr);
        }
        continue;
      }
      final bundleId = _bundleSlotBase + slot;
      usedBundleIds.add(bundleId);
      slot++;
      // A member that was scheduled INDIVIDUALLY on a previous recompute and
      // joined a bundle on this one still holds its old standalone
      // notification: the pre-schedule cleanup skips kept slots, and the
      // bundle only writes to its own 7000-band id. Without this cancel the
      // user gets both the stale solo ping and the bundle at the same
      // minute. Only the exact (habit, slot) pairs in THIS bundle are
      // cancelled — never the habit's other slots, which is what the old
      // per-member _cancelAllHabitReminderSlots did and what made it
      // order-dependently destroy reminders scheduled by earlier groups. A
      // bundled slot is by definition not individually scheduled this pass,
      // so this cancel can never race a _scheduleOne for the same id.
      // Snoozes (6000 band) are left alone: a pending snooze is something
      // the user explicitly asked for from a delivered reminder.
      for (final r in group) {
        await _cancelHabitSlot(r.id, r.slot, r.depth);
      }
      // The habits by name in the title, and the moment, the ask and the
      // praise in the body, with each member's streak re-based onto the day
      // the bundle fires (see habitBundleBody). It used to be a count titled
      // «عادتين بانتظارك» over a body that only listed the names.
      final title = habitBundleTitle(
        names: [for (final r in group) r.name],
        isAr: isAr,
      );
      final body = habitBundleBody(
        members: [for (final r in group) _bundleMemberAtFireDay(r)],
        isAr: isAr,
      );
      debugPrint('[NotificationService] bundle of ${group.length} at '
          '${group.first.fireTime}: $title / $body');
      await _zonedSchedule(
        bundleId,
        title,
        body,
        group.first.fireTime,
        _bundleDetails(timeSensitive: group.any((r) => r.timeSensitive)),
      );
      _armedBundles.add((
        id: bundleId,
        fireTime: group.first.fireTime,
        habitIds: [for (final r in group) r.id],
      ));
      // Whole-habit cancellation stays banished from this branch — the
      // per-member cancel above touches only the exact slots bundled HERE.
      // Groups are walked in fire-time order, so the old per-member
      // _cancelAllHabitReminderSlots destroyed a habit's 08:00 scheduled
      // alone in group 1 the moment its own 20:00 bundled with another habit
      // in group 2 — order-dependent, silent, and only reachable once a
      // habit can hold two times. Slot cleanup otherwise happens in ONE pass
      // before anything is scheduled (see scheduleSmartReminders), which is
      // also the ordering this file's own comment above the stale sweep
      // argues for: cancel first, schedule second, so an id collision is
      // harmless.
    }
    // A bundle slot not used this round might still hold a stale
    // notification from a previous recompute (fewer bundles today than
    // last time) — clear anything unused so nothing orphaned lingers.
    for (var i = 0; i < _maxBundleSlots; i++) {
      final id = _bundleSlotBase + i;
      if (!usedBundleIds.contains(id)) await _cancelIfHeld(id);
    }
    if (trimmed > 0) {
      debugPrint('[NotificationService] trimmed $trimmed latest-firing '
          'slot(s) to stay under the iOS 64-pending budget');
    }
  }

  /// Arms the extended part of every alarm reminder's window, depth
  /// [kOccurrencesPerSlot] and deeper (see [kAlarmWindowDays]), in ONE native
  /// call that also cancels whatever that id range holds and [entries] no
  /// longer asks for: a habit deleted, switched back to a notification, given
  /// fewer reminders, or reminders switched off.
  ///
  /// One call rather than a schedule and a cancel per id, because the range
  /// holds a month of days for every slot of every habit, and cancelling each
  /// id blindly would be hundreds of round trips on every resume. The bridge
  /// compares with what AlarmKit actually holds and touches only what
  /// changed, which with ids keyed by day (see [windowAlarmId]) is the one
  /// day per slot that came into range since the last open. It runs after
  /// [_scheduleResolved], so no day is ever left without its alarm while it
  /// moves from this window into the ordinary one.
  ///
  /// The line under each alarm is plain on purpose. These ring up to a month
  /// out, so nothing about the habit's record can honestly be said about the
  /// day they land on; the ringing screen shows only the habit's name anyway,
  /// and the line is read only if the app happens to be open when it rings
  /// (see [showForegroundAlarm]). Each day is re-armed with the full wording
  /// once it comes within [kOccurrencesPerSlot].
  Future<void> _syncAlarmWindow(
    List<_ResolvedReminder> entries,
    bool isAr,
  ) async {
    final ordered = _alarmWindowOrder(entries);
    final armed = ordered.take(kMaxWindowAlarms).toList();
    final result = await AlarmService.instance.syncWindow(
      lowId: _alarmWindowLowId,
      highId: _alarmWindowHighId,
      alarms: [
        for (final r in armed)
          (
            id: windowAlarmId(r.id, r.slot, r.fireTime),
            fireAt: r.fireTime,
            title: r.name,
            subtitle: windowAlarmLine(
              offsetMinutes: r.offsetMinutes,
              anchorLabel: r.anchorLabel,
              isAr: isAr,
            ),
            kind: 'habit',
            targetId: r.id,
            stopLabel: alarmStopAction(isAr),
          ),
      ],
    );
    if (result == null) return;
    final capped = ordered.length - armed.length;
    debugPrint('[NotificationService] alarm window: ${armed.length} armed '
        'ahead $result${capped > 0 ? ', $capped past the cap' : ''}');
  }

  /// [entries] in the order the extended window arms them: shallowest depth
  /// first, the same "how much does losing this cost" order as
  /// _scheduleResolved's trim, so [kMaxWindowAlarms] takes the far days.
  /// Shared by the sync and by the record of what the pass armed, so the two
  /// can never disagree about which alarms made the cap.
  static List<_ResolvedReminder> _alarmWindowOrder(
    List<_ResolvedReminder> entries,
  ) =>
      [...entries]..sort((a, b) {
          final byDepth = a.depth.compareTo(b.depth);
          return byDepth != 0 ? byDepth : a.fireTime.compareTo(b.fireTime);
        });

  /// Hands what this pass armed to the App Group (ArmedReminderRecord), for
  /// the two Done paths that run outside the app: the Home Screen widget's
  /// checkmark (MarkHabitDoneIntent) and a lock screen or Watch «تمت»
  /// ([standDownHabitReminders]). Both take a habit finished for the day
  /// down with that day's reminders, and neither can compute an id: the ids
  /// are Dart hashes, and which of a slot's ids holds today depends on when
  /// this pass ran. [habitIds] is every habit the pass covered, whose snooze
  /// ids go in beside what was armed.
  ///
  /// iOS only, where both paths live; HomeWidgetService no-ops elsewhere.
  Future<void> _publishArmedReminders(Iterable<String> habitIds) =>
      HomeWidgetService.instance.saveArmedHabitReminders(
        ArmedReminderRecord.encode(
          copies: _armedCopies,
          bundles: _armedBundles,
          snoozeIds: {for (final id in habitIds) id: _snoozeId(id)},
        ),
      );

  /// The extended-window id of [habitId]'s [slot] on [fireTime]'s calendar
  /// day, see [_alarmWindowBase]. The same day always gets the same id, however
  /// far ahead it was armed.
  @visibleForTesting
  static int windowAlarmId(String habitId, int slot, DateTime fireTime) {
    final day = DateTime.utc(fireTime.year, fireTime.month, fireTime.day)
            .millisecondsSinceEpoch ~/
        Duration.millisecondsPerDay;
    return _alarmWindowBase +
        (day % _alarmWindowBands) * 1000 +
        reminderSlotOffset(habitId, slot);
  }

  /// What an alarm in the extended window says under the habit's name: only
  /// its timing («باقي ٣٠ دقيقة على الفجر.»), never the habit's record, see
  /// [_syncAlarmWindow]. Null for an on-time alarm: the habit's name on the
  /// ringing screen already says it.
  @visibleForTesting
  static String? windowAlarmLine({
    required int offsetMinutes,
    required String? anchorLabel,
    required bool isAr,
  }) =>
      offsetMinutes == 0
          ? null
          : habitReminderBody(
              offsetMinutes: offsetMinutes,
              streak: 0,
              anchorLabel: anchorLabel,
              isAr: isAr,
              onTimeLine: '',
            );

  /// Global ceiling on scheduled habit-reminder notifications, kept well
  /// under iOS's hard 64-pending limit so the daily reminder, streak-risk
  /// nudge, quit check-ins, snoozes and task reminders always have room.
  /// See _scheduleResolved for how the latest-firing overflow is trimmed.
  ///
  /// What the other 16 hold. The fixed ids take up to 9 at once: the daily
  /// reminder at most 7 (tonight's copy 1010 beside six weekday fallbacks,
  /// or all seven fallbacks 1001 to 1007 with no copy tonight, see
  /// scheduleDailyReminder), the evening streak note (8000) and the Friday
  /// note (9000). On a Friday before 19:00 whose week is worth numbering the
  /// Friday note takes 2 instead of 1: tonight's numbered copy (9001) and
  /// the claim-free copy for next Friday (9002), in place of 9000 (see
  /// [weeklyNotePlan]). They stay until the next recompute after that
  /// Friday's 19:00. So the fixed ids take 9 or 10, leaving 7 or 6 for quit
  /// check-ins (one per quit habit still open today), snoozes and task
  /// reminders.
  ///
  /// What iOS does when a 65th request is added is NOT known here. It is
  /// widely said to keep the soonest-firing 64, and it may instead refuse
  /// the newest add, which would cost a task reminder set on a Friday
  /// afternoon rather than a far Friday one-shot. Neither has been measured
  /// on a device, so the claim-free window is one Friday rather than four
  /// (see [kWeeklyRepeatFridaysAhead]): the widest the fixed ids ever get
  /// stays 10, and the question stays academic.
  ///
  /// This is what actually bounds [kOccurrencesPerSlot]: the window
  /// multiplies how many of these one habit takes, so a heavy user spends
  /// the budget on the near days and simply gets a shorter window. Which is
  /// the right way round — the trim drops the LATEST-firing groups, never
  /// the next reminder.
  static const kMaxPendingHabitSlots = 48;


  /// Friday-evening "how was your week" push — a proactive companion to
  /// Insights/Monthly Heatmap, which are both pull-only (someone has to go
  /// open them). Content is computed fresh every time this is called (from
  /// main.dart's _recomputeNotifications, alongside every other smart
  /// reminder) and baked into the text at schedule time — same constraint
  /// as every other schedule* method here, local notifications can't
  /// compute anything at fire time. The Friday timing (not Sunday) matches
  /// the app's own Sat→Fri grid week — see weekly_grid_notifier.dart's
  /// startOfGridWeek().
  ///
  /// Sent only to someone who turned it on ([NotificationSettings
  /// .weeklyNoteOn]) and who has at least one habit ([hasHabits]). With no
  /// habit it used to go out anyway, to an account with nothing to recap
  /// and to a phone signed out (whose habit list is empty), every week.
  Future<void> scheduleWeeklyDigest({
    required NotificationSettings settings,
    required bool hasHabits,
    required WeekTopHabit? topHabit,
    required int longestStreak,
    required bool isAr,
    // Stands in for the clock, so a test can watch weeklyNotePlan's two
    // copies reach the plugin on a Friday of its choosing; the real clock
    // when null.
    DateTime? now,
  }) async {
    if (kIsWeb) return;
    await init();

    final shouldFire =
        settings.masterEnabled && settings.weeklyNoteOn && hasHabits;
    if (!shouldFire) {
      await cancelWeeklyDigest();
      return;
    }

    final plan = weeklyNotePlan(
      now: _clockAt(now),
      topHabit: topHabit,
      longestStreak: longestStreak,
      isAr: isAr,
    );
    // Pending only, the same rule every other note with a lifetime follows
    // (see [_cancelIfPending]). Nothing in this list is a note being
    // switched off: the only reason to clear any of these ids is that a copy
    // is ARMED for a 19:00 this plan is about to arm something else for, and
    // that reason applies to a request still waiting and to nothing else.
    // [_weeklyAheadBase] (9002) is the id it matters most for, being a
    // one-shot whose normal case is having been delivered: it exists
    // precisely for a phone left closed for a week, so a plain cancel took
    // that delivered «أسبوع جديد بدأ» off the notification list the moment
    // the app was next opened.
    //
    // [_weeklyDigestId] (9000) is in the list too, and for it the read
    // changes nothing: a weekly repeat stays PENDING for as long as it is
    // armed, delivered copies behind it and all, so a pending read cannot
    // tell the two apart and the repeat is cleared exactly as before. It
    // goes through here for one rule rather than two, not for a protection
    // it cannot have.
    await _cancelIfPending({...plan.cancel});
    for (final slot in plan.arm) {
      final at = slot.fireAt;
      await _zonedSchedule(
        slot.id,
        slot.copy.title,
        slot.copy.body,
        tz.TZDateTime(tz.local, at.year, at.month, at.day, at.hour, at.minute),
        _details,
        matchDateTimeComponents:
            slot.repeatsWeekly ? DateTimeComponents.dayOfWeekAndTime : null,
        // Body-tap routing (main.dart's _handleNotificationBodyTap). The
        // numbered copy counts the week that has just sealed, and opens
        // Profile, where that week's recap card appears at the same instant
        // (recapWeekStartAt). The claim-free copy asks for a square, so it
        // opens the Grid.
        payload: slot.id == _weeklyNumberedId
            ? openWeeklyRecapPayload
            : openTodayPayload,
      );
    }
    final armed = [
      for (final s in plan.arm)
        '#${s.id}${s.repeatsWeekly ? ' weekly' : ''} ${s.fireAt}: '
            '${s.copy.body}',
    ];
    debugPrint('[NotificationService] Friday note: ${armed.join(' | ')}');
  }

  /// Clears every id the Friday note can hold: the weekly repeat (9000),
  /// this week's numbered copy (9001) and the [kWeeklyRepeatFridaysAhead]
  /// claim-free one-shots behind it (9002 up). Exactly the ids
  /// [weeklyNotePlan] can arm, so the note switched off leaves nothing armed
  /// anywhere.
  ///
  /// Plain cancels, not [_cancelIfPending]: this is the note being switched
  /// off, not a count going stale.
  Future<void> cancelWeeklyDigest() async {
    if (kIsWeb) return;
    await _plugin.cancel(_weeklyDigestId);
    await _plugin.cancel(_weeklyNumberedId);
    for (var k = 0; k < kWeeklyRepeatFridaysAhead; k++) {
      await _plugin.cancel(_weeklyAheadBase + k);
    }
  }

  /// The Friday note's other ids. [_weeklyDigestId] (9000) stays the weekly
  /// repeat; the numbered copy for this week is a one-shot of its own, and
  /// while it is armed the claim-free copy rides on one-shots for the Fridays
  /// after. See [weeklyNotePlan].
  static const _weeklyNumberedId = 9001;
  static const _weeklyAheadBase = 9002;

  /// How many Fridays after a numbered note still hear the claim-free copy
  /// if the app is not opened again in between. See [weeklyNotePlan].
  ///
  /// One, because each of these is a pending request against iOS's 64 on
  /// exactly the afternoon the fixed ids are at their widest, and what iOS
  /// does past 64 has not been measured (see [kMaxPendingHabitSlots]). Four
  /// bought three more silent-phone Fridays for three more requests in the
  /// tightest window there is, which is the wrong trade while the ceiling's
  /// behaviour is a guess.
  ///
  /// A limit the old repeat did not have either way: a phone never opened
  /// again after that Friday afternoon hears nothing on the Friday after the
  /// next, where the old repeat went on for ever.
  static const kWeeklyRepeatFridaysAhead = 1;

  /// The hour on Saturday the week's note goes out: [kDayCutoffHour], the
  /// instant Friday stops being payable.
  ///
  /// It used to be Friday 19:00, and that was wrong twice over. It landed
  /// in the middle of the evening's own notifications, and it counted a
  /// week that was not over: Friday runs until Saturday 10:00 (see
  /// DateTimeGameExt.closesAt), so «٥ أيام خضرا هذا الأسبوع» could be made
  /// false by a habit finished after it was read, and the app's weekly
  /// screens would then disagree with the banner the person was looking at.
  ///
  /// At the cutoff the week is sealed, the number can no longer move, and
  /// the note is a morning on a fresh day rather than a fourth banner in
  /// one evening. It is also clear of the default quiet window (22:00 to
  /// 07:00), which a midnight note would have sat inside.
  static const kWeeklyNoteHour = kDayCutoffHour;

  /// Whether tonight's evening streak note goes out, and what it says.
  ///
  /// Null, so nothing is sent, when:
  ///   - there is no streak, or nothing is left today;
  ///   - today's streak point is already earned. The note used to keep
  ///     firing once 80% was done, asking for a streak that was already
  ///     safe;
  ///   - [fireTime] is not tonight. A recompute after the note's time used
  ///     to arm TOMORROW's note with today's counts; this is the same guard
  ///     the daily reminder has (see scheduleDailyReminder's firesTonight);
  ///   - the build habits left cannot cover what the streak still needs. The
  ///     note asks for habits to be done, and a quit habit is not done but
  ///     answered, by its own check-in at the same minute.
  @visibleForTesting
  static ReminderLine? eveningStreakNoteFor({
    required DateTime now,
    required DateTime fireTime,
    required int streak,
    required bool streakEarnedToday,
    required int doneHabitCount,
    required int pendingHabitCount,
    required int pendingBuildHabitCount,
    required int urgentTasks,
    required bool isAr,
  }) {
    if (streak <= 0 || pendingHabitCount <= 0 || streakEarnedToday) {
      return null;
    }
    final firesTonight = fireTime.year == now.year &&
        fireTime.month == now.month &&
        fireTime.day == now.day;
    if (!firesTonight) return null;
    final total = doneHabitCount + pendingHabitCount;
    final needed =
        habitsStillNeededForStreak(done: doneHabitCount, total: total);
    if (needed > pendingBuildHabitCount) return null;
    return streakRiskCopy(
      done: doneHabitCount,
      total: total,
      streak: streak,
      urgentTasks: urgentTasks,
      isAr: isAr,
    );
  }

  /// What the Friday note arms, and what it clears, on a recompute at [now].
  ///
  /// Two copies with different lifetimes (Aziz's pick of 2026-09-11):
  ///   - the numbered copy for THIS week ([weeklyNoteCopy]), worded from this
  ///     week's squares, so it is only ever armed on the Friday it counts,
  ///     before 19:00, as a one-shot for 19:00 that same evening. Sent once;
  ///   - the claim-free copy ([weeklyRepeatCopy]), true on any Friday, as the
  ///     weekly repeat.
  ///
  /// iOS builds a weekly repeat from the weekday and the time alone
  /// (DateTimeComponents.dayOfWeekAndTime), so a repeat armed on a Friday
  /// afternoon also fires that evening, and it cannot be told to skip a week.
  /// Android is no different in the plugin version this app ships
  /// (flutter_local_notifications 18.0.1): its zonedSchedule moves a
  /// repeat's first date to the next matching weekday and time counted from
  /// now, so a repeat dated next Friday still fires tonight. So on both, while
  /// tonight's numbered copy is armed the repeat is cleared, and the
  /// claim-free copy goes on one-shots for the [kWeeklyRepeatFridaysAhead]
  /// Fridays after. The next recompute after 19:00 puts the repeat back.
  ///
  /// The numbered id is only cleared inside its own window. After 19:00 it
  /// has already been delivered, and clearing it would remove it from the
  /// notification list.
  ///
  /// A null [topHabit] covers both "no week worth numbering" and "the Grid
  /// is not showing this week at all" ([WeeklyNoteBasis.claimFree]): either
  /// way this week's squares are not in hand, so the claim-free copy goes
  /// out, and a numbered copy an earlier recompute armed inside today's
  /// window is cleared rather than left to fire a count nothing here can
  /// still vouch for.
  @visibleForTesting
  static ({List<WeeklyNoteSlot> arm, List<int> cancel}) weeklyNotePlan({
    required DateTime now,
    required WeekTopHabit? topHabit,
    required int longestStreak,
    required bool isAr,
  }) {
    final repeat = weeklyRepeatCopy(longestStreak: longestStreak, isAr: isAr);
    // Saturday, before the note's own hour: whatever yesterday armed for
    // this morning is the truth about the week that just sealed, and this
    // pass cannot improve on it — the Grid has already rolled to the NEW
    // week, so nothing here can still count last week's squares. Arm
    // nothing, clear nothing, and let it fire.
    //
    // Without this hold the repeat branch below would arm the claim-free
    // copy for TODAY's 10:00, landing a second banner beside the numbered
    // one it is supposed to stand in for.
    if (now.weekday == DateTime.saturday && now.hour < kWeeklyNoteHour) {
      return (arm: const [], cancel: const []);
    }
    // Tomorrow morning, once the week has actually sealed. Built off the
    // Friday this runs on, so it is the Saturday right after it.
    final sealsAt = DateTime(now.year, now.month, now.day + 1, kWeeklyNoteHour);
    final inWindow = weeklyNumberedNoteAhead(now);
    final numbered = !inWindow || topHabit == null
        ? null
        : weeklyNoteCopy(
            habitName: topHabit.name,
            greenDays: topHabit.greenDays,
            isQuit: topHabit.isQuit,
            isAr: isAr,
          );
    final ahead = [
      for (var k = 0; k < kWeeklyRepeatFridaysAhead; k++) _weeklyAheadBase + k,
    ];
    if (numbered == null) {
      // Same rule as _nextInstanceOfWeekday: this Saturday if its hour is
      // still ahead, else the Saturday after.
      var next =
          DateTime(now.year, now.month, now.day, kWeeklyNoteHour);
      if (next.weekday != DateTime.saturday || !next.isAfter(now)) {
        do {
          next = DateTime(next.year, next.month, next.day + 1, kWeeklyNoteHour);
        } while (next.weekday != DateTime.saturday);
      }
      return (
        arm: [
          (id: _weeklyDigestId, copy: repeat, fireAt: next, repeatsWeekly: true),
        ],
        cancel: [if (inWindow) _weeklyNumberedId, ...ahead],
      );
    }
    return (
      arm: [
        (
          id: _weeklyNumberedId,
          copy: numbered,
          fireAt: sealsAt,
          repeatsWeekly: false,
        ),
        for (var k = 0; k < kWeeklyRepeatFridaysAhead; k++)
          (
            id: _weeklyAheadBase + k,
            copy: repeat,
            fireAt: DateTime(
              now.year,
              now.month,
              now.day + 1 + 7 * (k + 1),
              kWeeklyNoteHour,
            ),
            repeatsWeekly: false,
          ),
      ],
      cancel: [_weeklyDigestId],
    );
  }

  /// Which copy of the Friday note a recompute may arm, given what the Grid
  /// is showing. Pure, because getting it wrong is silent: the note is only
  /// re-armed by a recompute, and a copy an earlier recompute armed keeps
  /// whatever count it was armed with until one does.
  ///
  /// The case this exists for: the Grid can be PINNED to a past week
  /// (previousWeek() in weekly_grid_notifier.dart, which refresh() respects),
  /// and it stays there across recomputes. Skipping the note there, as a
  /// mid-load Grid is skipped, leaves this morning's numbered copy armed with
  /// a count that a habit finished since has made false, and 19:00 delivers
  /// it. So a loaded Grid on another week arms the claim-free copy instead,
  /// which is true on any Friday, and that clears the numbered one. Only a
  /// Grid still LOADING is skipped, because its own recompute lands moments
  /// later.
  static WeeklyNoteBasis weeklyNoteBasis({
    required bool gridLoading,
    required bool gridOnCurrentWeek,
  }) {
    if (gridLoading) return WeeklyNoteBasis.skip;
    return gridOnCurrentWeek
        ? WeeklyNoteBasis.numbered
        : WeeklyNoteBasis.claimFree;
  }

  /// The habit that names Friday's numbered note: the most GREEN days in the
  /// week [habits] carry, and on a tie the FIRST of them, which main.dart
  /// hands over in habit order.
  ///
  /// Green only. A جزئي square is a day the habit was touched and not
  /// finished, and a red one is a day it was not kept, so neither is a day
  /// «٥ أيام خضرا هذا الأسبوع 👏🏼» may count. Bonus counts, because
  /// SquareState.isGreen counts it and the Grid draws it green.
  ///
  /// Null only when there are no habits at all: a habit with no green day is
  /// still returned, and [weeklyNoteCopy] is the one that refuses to number
  /// a thin week (under three days), so that refusal lives in one place.
  static WeekTopHabit? weekTopHabit(Iterable<WeekHabitRow> habits) {
    WeekTopHabit? top;
    for (final habit in habits) {
      final green = habit.squares.where((s) => s.isGreen).length;
      if (top == null || green > top.greenDays) {
        top = (name: habit.name, greenDays: green, isQuit: habit.isQuit);
      }
    }
    return top;
  }

  /// Today's board in the numbers the evening streak note is worded from
  /// («٢ من ٥ خلّصت 👏🏼 سوي عادتين بس، وتصير ٨ أيام.»), counted over one
  /// entry per habit due today.
  ///
  /// [TodayBoardCounts.pendingBuild] is the build habits among the pending
  /// ones, and it is what decides whether the note goes out at all: the note
  /// asks for habits to be DONE, and a quit habit is not done but answered,
  /// by its own check-in at the same minute (see [eveningStreakNoteFor]). A
  /// quit habit therefore counts in [TodayBoardCounts.pending] and never in
  /// [TodayBoardCounts.pendingBuild].
  /// The habits of today's board the evening note counts, both in «٥ من ٦»
  /// and in what is left: the build habits, less any marked «تخطّي» today.
  ///
  /// A quit habit sends nothing unless the person set it a reminder (Aziz,
  /// 2026-09-24). A skipped habit has left the day, the rule the streak is
  /// judged by (streakCreditOf). The skip used to leave only what is left,
  /// so a day with one habit skipped and the rest done read «٥ من ٦ خلّصت»
  /// and never counted as finished.
  static List<T> eveningNoteBoard<T>(
    Iterable<T> habits, {
    required bool Function(T habit) isQuit,
    required bool Function(T habit) isSkipped,
  }) =>
      [
        for (final habit in habits)
          if (!isQuit(habit) && !isSkipped(habit)) habit,
      ];

  static TodayBoardCounts todayBoardCounts(Iterable<TodayBoardHabit> habits) {
    var done = 0;
    var pending = 0;
    var pendingBuild = 0;
    for (final habit in habits) {
      if (habit.isDone) {
        done++;
        continue;
      }
      pending++;
      if (!habit.isQuit) pendingBuild++;
    }
    return (done: done, pending: pending, pendingBuild: pendingBuild);
  }

  // The RETIRED quit check-in band, 70000–70999. Nothing arms it any more:
  // a quit habit's evening ask is a sentence inside the one evening note
  // (see [scheduleEveningNote]). Kept as a named constant because a build
  // that shipped before the merge left ids in this band armed on real
  // phones, and [_cancelRetiredEveningIds] sweeps exactly this window.
  static const _quitCheckInBase = 70000;

  /// Kept clear of [_quitCheckInBase]'s 70000–70999 window. Both use a
  /// `base + hash % 1000` id, so overlapping bases means one feature can
  /// cancel the other's notification by coincidence.
  static const _foregroundRoomPushBase = 72000;

  /// True when [minuteOfDay] (0–1439) falls inside the [start]–[end] quiet
  /// window, correctly handling a window that wraps past midnight (e.g.
  /// 22:00–07:00). A zero-width window (start == end) is treated as
  /// "never quiet" rather than "always quiet" — matches
  /// [NotificationSettings.quietHoursEnabled] being the actual on/off
  /// switch; a degenerate same-value range shouldn't silently blank out
  /// every reminder. Pure and side-effect-free on purpose — one of two
  /// pieces of the scheduling logic (see [groupByFireTimeWindow] for the
  /// other) that are meaningfully unit-testable without a device, since
  /// neither touches the plugin or the network (see
  /// test/notification_scheduling_test.dart).
  ///
  /// No longer `@visibleForTesting`: AddHabitSheet's `_quietHoursWarning`
  /// now calls this for real, to tell someone *while they're picking a
  /// time* that it lands in their quiet window — the alternative was
  /// duplicating this wrap-past-midnight logic in the UI, where it could
  /// drift out of sync with the scheduler that actually enforces it. This
  /// stays the single definition of "is this minute quiet".
  static bool isMinuteWithinQuietHours(
    int minuteOfDay,
    TimeOfDay start,
    TimeOfDay end,
  ) {
    final s = start.hour * 60 + start.minute;
    final e = end.hour * 60 + end.minute;
    if (s == e) return false;
    if (s < e) return minuteOfDay >= s && minuteOfDay < e;
    return minuteOfDay >= s || minuteOfDay < e;
  }

  /// Groups [items] into clusters no wider than [window] apart, in
  /// fire-time order — [_scheduleResolved]'s "2+ habits due within the
  /// same short window combine into one notification" rule. Extracted out
  /// of that method (verbatim logic, just generic over [T] and taking a
  /// [fireTimeOf] extractor instead of reaching into `_ResolvedReminder`
  /// directly) so the windowing decision itself — which is the one part
  /// of that method with no plugin call in it — is unit-testable without
  /// scheduling a single real notification. When [enabled] is false, every
  /// item gets its own group regardless of how close together they are —
  /// mirrors the original inline `bundleEnabled &&` gate exactly, rather
  /// than e.g. passing `Duration.zero` as [window], which would still
  /// merge two items landing at the exact same instant.
  @visibleForTesting
  static List<List<T>> groupByFireTimeWindow<T>(
    List<T> items, {
    required bool enabled,
    required Duration window,
    required tz.TZDateTime Function(T) fireTimeOf,
  }) {
    final sorted = [...items]
      ..sort((a, b) => fireTimeOf(a).compareTo(fireTimeOf(b)));
    final groups = <List<T>>[];
    for (final item in sorted) {
      final current = groups.isEmpty ? null : groups.last;
      if (enabled &&
          current != null &&
          fireTimeOf(item).difference(fireTimeOf(current.first)) <= window) {
        current.add(item);
      } else {
        groups.add([item]);
      }
    }
    return groups;
  }

  /// Reschedules habit [habitId]'s reminder for an hour from now, as a
  /// one-off — uses a separate notification id from the regular per-habit
  /// reminder (see [_snoozeId]) so it doesn't clobber that schedule.
  Future<void> snoozeHabitReminder(
    String habitId,
    String habitName, {
    bool isAr = false,
  }) {
    if (kIsWeb) return Future.value();
    return _serialized(
      () => _snoozeHabitReminderNow(habitId, habitName, isAr: isAr),
      ahead: true,
    );
  }

  Future<void> _snoozeHabitReminderNow(
    String habitId,
    String habitName, {
    required bool isAr,
  }) async {
    await init();
    await _zonedSchedule(
      _snoozeId(habitId),
      habitName,
      snoozedReminderBody(isAr),
      tz.TZDateTime.now(tz.local).add(const Duration(hours: 1)),
      _habitReminderDetails(isAr),
      payload: habitId,
    );
    debugPrint('[NotificationService] Snoozed reminder for $habitId');
  }

  /// How many reminder slots a single task can occupy, and the bound
  /// [cancelTaskReminder] sweeps. Defined as kTaskReminderSlots beside the
  /// ids themselves (armed_task_record.dart), because the record the Matrix
  /// widget's checkmark reads has to name exactly the slots this app arms
  /// and cancels; see that file for the whole reasoning.
  static const kMaxTaskReminderSlots = kTaskReminderSlots;

  /// Notification id for a task's [index]-th reminder, see [taskReminderId].
  /// The formula lives in armed_task_record.dart because the widget's task
  /// record has to name these ids and Swift cannot fold a Dart hash.
  int _taskReminderId(String taskId, [int index = 0]) =>
      taskReminderId(taskId, index);

  /// Schedules a one-off local notification for a single Matrix task at an
  /// exact, user-picked moment — see MatrixTask.reminderAt's doc comment
  /// for why this takes a plain absolute [fireTime] rather than a
  /// recurring TimeOfDay/HabitCue-style cue: a task is a single thing to
  /// do, not a daily routine, so there's exactly one moment worth firing
  /// at, ever, and nothing here re-derives or repeats the way
  /// [scheduleSmartReminders] does.
  ///
  /// Title states this reminder's TIMING rather than the task's own name —
  /// [taskTitle] carries the specifics in the body instead, the same
  /// title/body split every notification-list screenshot of this kind of app
  /// uses ("It's time" / "Buy groceries"), so what's glanceable from a lock
  /// screen is "something needs you" first, "here's what" second.
  ///
  /// It used to be the fixed string "It's time" for every slot, which is
  /// only ever true of the slot that lands on [anchorAt]. A reminder the
  /// user deliberately set for an hour BEFORE a 8:25 appointment arrived at
  /// 7:25 announcing that the time had come — see reminder_copy.dart's own
  /// doc comment. [anchorAt] is the moment the user actually picked
  /// (MatrixTask.reminderAnchorAt); each fire time is differenced against it
  /// for the signed offset the title is phrased from. Null (a task saved
  /// before that field existed, whose anchor is a guess we'd rather not
  /// phrase copy off) falls back to the original on-time wording.
  ///
  /// Deliberately does NOT check quiet hours the way habit/streak
  /// reminders do (see [scheduleSmartReminders]) — those are the app's own
  /// auto-generated nudges, but this fire time was explicitly hand-picked
  /// by the user for this exact task, down to the minute; silently moving
  /// or suppressing it would second-guess a decision they already made on
  /// purpose. Also doesn't request notification permission itself, unlike
  /// habit_plans.dart's ReminderTimeNotifier.set — that's the calling
  /// sheet's job (see AddTaskSheet._submit / TaskDetailSheet's reminder
  /// handler), since
  /// scheduling here has to succeed unconditionally for MatrixNotifier's
  /// fire-and-forget call style to stay consistent; if permission is
  /// actually denied, this silently schedules something the OS just won't
  /// display, exactly as flutter_local_notifications already behaves
  /// anywhere permission was never granted.
  ///
  /// Uses the plain notification styling ([_details], no actions) rather
  /// than [_habitReminderDetails] — there's no Mark Done/Snooze action that
  /// makes sense here (this isn't a habit), same reasoning as the bundled
  /// multi-habit notification in [_scheduleResolved].
  /// [fireTimes] is the task's full set of still-future reminder moments,
  /// already sorted (see MatrixTask.normalizeReminders) — not a delta.
  /// Anything beyond [kMaxTaskReminderSlots] is dropped, and every slot
  /// this task isn't using anymore is cancelled in the same pass, so the
  /// OS queue always ends up matching the task's list exactly rather than
  /// accumulating stale schedules from whatever it used to hold. That
  /// makes this safe to call on every resync, which is how MatrixNotifier
  /// uses it.
  ///
  /// [alarm] is the task's own choice to ring as an alarm (MatrixTask.alarm):
  /// each slot then goes through AlarmService (Stop, and «خلّصت المهمة»,
  /// which ticks the task at the next open), and falls back to an
  /// alarm-style notification where a real alarm cannot be made. Same
  /// slot ids either way, so switching a task between the two never leaves
  /// both scheduled; see [_cancelTaskSlot].
  Future<void> scheduleTaskReminders({
    required String id,
    required String taskTitle,
    required List<DateTime> fireTimes,
    required DateTime? anchorAt,
    required bool isAr,
    bool alarm = false,
  }) {
    if (kIsWeb) return Future.value();
    return _serialized(() => _scheduleTaskRemindersNow(
          id: id,
          taskTitle: taskTitle,
          fireTimes: fireTimes,
          anchorAt: anchorAt,
          isAr: isAr,
          alarm: alarm,
        ));
  }

  Future<void> _scheduleTaskRemindersNow({
    required String id,
    required String taskTitle,
    required List<DateTime> fireTimes,
    required DateTime? anchorAt,
    required bool isAr,
    required bool alarm,
  }) async {
    await init();
    final wanted = fireTimes.take(kMaxTaskReminderSlots).toList();
    for (var i = 0; i < wanted.length; i++) {
      final slotId = _taskReminderId(id, i);
      final title = taskReminderTitle(
        offsetMinutes:
            anchorAt == null ? 0 : signedOffsetMinutes(wanted[i], anchorAt),
        isAr: isAr,
      );
      if (alarm &&
          await AlarmService.instance.schedule(
            id: slotId,
            fireAt: wanted[i],
            title: taskTitle,
            subtitle: title,
            kind: 'task',
            targetId: id,
            doneLabel: taskDoneAction(isAr),
            stopLabel: alarmStopAction(isAr),
          )) {
        await _plugin.cancel(slotId);
        continue;
      }
      await AlarmService.instance.cancel(slotId);
      await _zonedSchedule(
        slotId,
        title,
        taskTitle,
        tz.TZDateTime.from(wanted[i], tz.local),
        _taskReminderDetails(alarmStyle: alarm),
        alarm: alarm,
        payload: id,
      );
    }
    for (var i = wanted.length; i < kMaxTaskReminderSlots; i++) {
      await _cancelTaskSlot(id, i);
    }
  }

  /// One task slot out of both systems, see [_cancelHabitSlot].
  Future<void> _cancelTaskSlot(String taskId, int index) async {
    final id = _taskReminderId(taskId, index);
    await _plugin.cancel(id);
    await AlarmService.instance.cancel(id);
  }

  /// Catches up a task reminder whose picked moment already passed without
  /// ever reaching the user — the app was closed straight through
  /// [fireTime], the device was off, or the OS just didn't deliver it.
  /// Rather than the task's reminder silently vanishing (which is what
  /// unconditionally cancelling a past-due schedule would mean from the
  /// user's side — a reminder they set that never once fired), this fires
  /// right away instead, the moment MatrixNotifier next resyncs this task
  /// (on load, or the next time it's touched) and finds it still open with
  /// notifications still enabled — see MatrixNotifier._syncReminderSchedule.
  /// Uses [_plugin.show] (immediate) rather than [_plugin.zonedSchedule]
  /// (future-dated) since there's no future moment left to aim at — "now"
  /// already *is* the catch-up moment. Same title/body convention as
  /// [scheduleTaskReminders], and deliberately reuses slot 0's id, so a
  /// catch-up simply replaces whatever (if anything) was still pending for
  /// this task. One notification regardless of how many of the task's
  /// reminders were missed — see MatrixNotifier's overdue handling for why
  /// firing one per missed moment would be the wrong behaviour.
  ///
  /// Says how late it is, which is the one thing this path can state that
  /// [scheduleTaskReminders] can't: lateness is only knowable at the moment
  /// of firing, and here "now" already *is* that moment. Measured from
  /// [dueAt] — the task's own anchor, not whichever reminder in the stack
  /// went missing last — so a +20 follow-up that never arrived still reports
  /// how long ago the TASK was due rather than how long ago its follow-up
  /// was. Never "It's time": by definition it isn't, and hasn't been for a
  /// while.
  Future<void> fireOverdueTaskReminder({
    required String id,
    required String taskTitle,
    required DateTime dueAt,
    required bool isAr,
  }) async {
    if (kIsWeb) return;
    await init();
    await _plugin.show(
      _taskReminderId(id),
      overdueTaskReminderTitle(
        minutesLate: signedOffsetMinutes(DateTime.now(), dueAt),
        isAr: isAr,
      ),
      taskTitle,
      _details,
    );
  }

  /// Cancels [id]'s reminder, if one is scheduled — a no-op otherwise.
  /// Called from MatrixNotifier whenever a task's reminder is cleared,
  /// the task itself is completed or deleted, or notifications are off
  /// entirely — see MatrixNotifier._syncReminderSchedule for the exact
  /// rules. A reminder whose moment has simply passed while the task is
  /// still open does NOT go through here — see [fireOverdueTaskReminder]
  /// for that case instead.
  /// Sweeps every slot rather than just index 0 — a task whose reminders
  /// were cleared (or which was completed or deleted) must not leave a
  /// later slot still armed, and by the time this is called the task's own
  /// list is usually already empty, so there's nothing left to tell us how
  /// many it used to have. Cancelling an id that was never scheduled is a
  /// no-op, so the fixed sweep costs nothing but guarantees no stragglers.
  Future<void> cancelTaskReminder(String id) {
    if (kIsWeb) return Future.value();
    return _serialized(() async {
      for (var i = 0; i < kMaxTaskReminderSlots; i++) {
        await _cancelTaskSlot(id, i);
      }
    });
  }

  /// [now] as a time in the app's zone, or the real clock when it is null.
  /// The seam by which the evening streak note and the Friday note take a
  /// test's clock. A plain DateTime is read as the instant it names.
  static tz.TZDateTime _clockAt(DateTime? now) => now == null
      ? tz.TZDateTime.now(tz.local)
      : tz.TZDateTime.from(now, tz.local);

  tz.TZDateTime _nextInstanceOf(int hour, int minute, {tz.TZDateTime? now}) {
    final at = now ?? tz.TZDateTime.now(tz.local);
    var scheduled =
        tz.TZDateTime(tz.local, at.year, at.month, at.day, hour, minute);
    if (scheduled.isBefore(at)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  /// Same idea as [_nextInstanceOf], but rolls forward to the next
  /// occurrence of [weekday] (1=Monday..7=Sunday, per [DateTime]'s own
  /// weekday constants) instead of stopping at the next occurrence of the
  /// clock time alone — used by [scheduleWeeklyDigest] to land on Friday
  /// evening specifically.
  tz.TZDateTime _nextInstanceOfWeekday(int weekday, int hour, int minute) {
    var scheduled = _nextInstanceOf(hour, minute);
    while (scheduled.weekday != weekday) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  /// Manually shows the room-finish push's title/body while this device is
  /// in the foreground - see PushNotificationService's own doc comment for
  /// Since 2026-09-08 this is the FALLBACK only: PushNotificationService
  /// hands a foreground room push to main.dart first, which shows it as a
  /// tappable in-app notice (showOverlayNotice) over whatever is on screen;
  /// this system banner is used when no navigator context exists yet.
  ///
  /// why: iOS's foreground-presentation option is deliberately left off
  /// for that one push category (unlike every local notification in this
  /// file, which doesn't need the choice - there's nothing else on screen
  /// for a scheduled reminder to duplicate), so a push about a room this
  /// device is already looking at can be skipped entirely instead of
  /// showing right on top of room_reactions.dart's own in-app reaction for
  /// the exact same moment. Bypasses master-switch gating on purpose -
  /// functions/index.js already checked
  /// NotificationSettings.roomActivityEnabled and quiet hours server-side
  /// before ever sending this, so re-checking local settings here would
  /// just be double-gating the same decision against a copy that might be
  /// stale.
  Future<void> showForegroundRoomPush({
    required String title,
    required String body,
  }) async {
    if (kIsWeb) return;
    await init();
    // 72000, not 70000: _quitCheckInBase is 70000 with a 0–999 hash spread,
    // so this shared that exact range. A foreground room push whose title
    // hashed into the same slot as a scheduled quit check-in replaced it —
    // silently cancelling a reminder the person had set.
    await _plugin.show(
      _foregroundRoomPushBase + title.hashCode.abs() % 1000,
      title,
      body,
      _details,
    );
  }

  /// Fires immediately, bypassing every setting on purpose — this
  /// is the Notification Settings screen's "Send a test notification"
  /// button, whose entire point is letting someone confirm permissions and
  /// appearance are working right now. Gating a diagnostic action behind
  /// the very settings it's meant to help verify would make it silently
  /// useless exactly when it's most likely to be tapped (right after
  /// turning categories off to investigate).
  Future<void> showTest({required bool isAr}) async {
    if (kIsWeb) return;
    await init();
    await _plugin.show(
      // Its own id, NOT 9000: that is _weeklyDigestId, and show() replaces
      // any pending schedule carrying the same id — so the test button was
      // quietly cancelling the scheduled Friday digest every time it was
      // tapped (until the next recompute happened to reschedule it). A
      // diagnostic must never eat a real notification.
      9990,
      isAr ? 'إشعار تجريبي' : 'Test notification',
      isAr
          ? 'هكذا تبدو إشعارات Grow Daily على جهازك.'
          : "This is what Grow Daily's notifications look like on your device.",
      _details,
    );
  }
}

/// One piece of work waiting in [NotificationService]'s lane, and the Future
/// its caller holds. See NotificationService._serialized.
class _LaneJob<T> {
  _LaneJob(this._work, {required this.ahead}) {
    // A failure nobody awaits stays quiet, as it did when the lane was a
    // chain of Futures whose next link handled every error: most callers
    // fire and forget (main.dart's recompute among them), and a caller that
    // does await still gets the error.
    _completer.future.then<void>((_) {}, onError: (Object _) {});
  }

  final Future<T> Function() _work;

  /// Goes before every task job still waiting (see _serialized).
  final bool ahead;

  final Completer<T> _completer = Completer<T>();

  Future<T> get done => _completer.future;

  /// Never throws, so one failed job cannot stop the lane: the failure goes
  /// to its own caller's Future and the next job runs, as it did when the
  /// lane was a chain of Futures.
  Future<void> run() async {
    try {
      _completer.complete(await _work());
    } catch (e, st) {
      _completer.completeError(e, st);
    }
  }
}

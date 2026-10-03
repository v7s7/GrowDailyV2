import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/day_clock_provider.dart';
import '../../../core/services/prayer_times_service.dart';
import '../../../core/services/prayer_widget_feed.dart';
import '../../../core/theme/game_theme.dart';
import '../../../core/utils/western_digits.dart';
import '../../habits/models/habit_cue.dart';

/// Today's prayer times for the saved place, on Settings › موقع الصلاة.
///
/// Aziz, 2026-10-01: a tap on the prayer widget already lands on that page
/// (prayerPlaceOpenURL in PrayerCountdownWidget.swift), and he wanted the
/// page itself to show the times, "so user can check the prayers, when he
/// choose the country". So this sits right under the place card: pick a
/// city and its day appears here at once.
///
/// Two parts, one card:
///  - The sky: the widget's own face, carried into the app. The same four
///    skies (assets/images/prayer_sky_*.jpg are copies of the widget's
///    imagesets), the same rule for which one shows (the stretch of the day
///    outside, not the prayer on the face), the same words («باقي على
///    الأذان» / «مضى على الأذان», «الشروق» with its own pair) and the same
///    minutes after each moment ([PrayerWidgetFeed.elapsedWindowFor]). So
///    the page a widget tap opens starts with the face that was tapped.
///    After Isha it counts to tomorrow's Fajr, and its time says «باجر».
///  - The list: all six moments of today, sunrise included and quieter
///    (no adhan is called for it), with the one the sky is counting to or
///    from marked, and the ones already behind read in a lighter ink.
///
/// The times are [PrayerTimesService.calculateDays], the source the widget
/// and the prayer reminders read, so the three can never disagree. They
/// paint first from [PrayerTimesService.calculateOfflineCorrected] (exact
/// inside Bahrain, where it reads the bundled official table, and within a
/// minute or two elsewhere) and are replaced when the live month answers,
/// which is memoized and usually already in hand from the widget's push.
///
/// Times are on the phone's clock, like every prayer time in the app
/// (Aladhan is asked in tz.local), so they always agree with the widget and
/// the reminders: a city in another time zone shows its moments as they
/// fall where the phone is. When a picked city keeps a different clock
/// today, one line under the list says so (Aziz, 2026-10-01, asked to
/// pick the best fix and keep it small).
///
/// Kept compact on purpose ("dont make it to big"): the two ways to choose
/// a place sit below this card, and should still be in view.
class PrayerTodayCard extends ConsumerStatefulWidget {
  const PrayerTodayCard({
    super.key,
    required this.latitude,
    required this.longitude,
    this.countryCode,
    this.cityZone,
  });

  final double latitude;
  final double longitude;

  /// A hand-picked city's IANA time zone ([NotificationLocation.zone]),
  /// or null for the phone's own location.
  final String? cityZone;

  /// The saved place's resolved country, for
  /// [PrayerTimesService.resolveRegion]'s country tier.
  final String? countryCode;

  @override
  ConsumerState<PrayerTodayCard> createState() => _PrayerTodayCardState();
}

class _PrayerTodayCardState extends ConsumerState<PrayerTodayCard> {
  Timer? _ticker;
  late DateTime _now;

  /// Today and tomorrow: tomorrow's Fajr is what the sky counts to once
  /// today's Isha has had its minutes.
  List<PrayerDayTimes>? _days;

  /// The place, country and calendar day [_days] were worked out for.
  String? _loadedKey;

  DateTime _clock() => ref.read(dayClockSourceProvider)();

  @override
  void initState() {
    super.initState();
    _now = _clock();
    _load();
    // Repaints the counter each second. Only while this page is open: the
    // timer goes with the page.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void didUpdateWidget(PrayerTodayCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _load();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _tick() {
    if (!mounted) return;
    setState(() {
      _now = _clock();
      // Past midnight with the page still open: the list is a new day's.
      _load();
    });
  }

  /// Works out [_days] when the place or the day changed. Called from
  /// initState, didUpdateWidget and inside [_tick]'s setState, all of which
  /// build next, so the first answer is assigned rather than set.
  void _load() {
    final day = DateTime(_now.year, _now.month, _now.day);
    final key = '${widget.latitude},${widget.longitude},'
        '${widget.countryCode},${day.year}-${day.month}-${day.day}';
    if (key == _loadedKey) return;
    _loadedKey = key;
    final first = [
      for (var i = 0; i < 2; i++)
        PrayerTimesService.calculateOfflineCorrected(
          latitude: widget.latitude,
          longitude: widget.longitude,
          date: DateTime(day.year, day.month, day.day + i),
          countryCode: widget.countryCode,
        ),
    ];
    _days = first;
    PrayerTimesService.calculateDays(
      latitude: widget.latitude,
      longitude: widget.longitude,
      from: day,
      days: 2,
      countryCode: widget.countryCode,
    ).then(
      (days) {
        // A newer place or day replaced this one while it was out.
        if (!mounted || key != _loadedKey || days.length < 2) return;
        setState(() => _days = days);
      },
      // Documented never to throw; if it ever did, the first answer stays.
      onError: (Object _) {},
    );
  }

  @override
  Widget build(BuildContext context) {
    final days = _days;
    if (days == null || days.length < 2) return const SizedBox.shrink();
    final gp = context.gp;
    final s = S.of(context);
    final view = PrayerToday.resolve(
      today: days[0],
      tomorrow: days[1],
      now: _now,
    );
    return Container(
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: gp.border, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SkyPanel(view: view, now: _now),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    s.prayerTodayTitle,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: gp.textPrimary,
                    ),
                  ),
                ),
                Text(
                  weekdayDateLabel(
                    _now,
                    isAr: s.isAr,
                    locale: Localizations.localeOf(context).languageCode,
                  ),
                  style: TextStyle(fontSize: 12.5, color: gp.textSec),
                ),
              ],
            ),
          ),
          for (var i = 0; i < view.today.length; i++)
            _MomentRow(
              moment: view.today[i],
              focused: i == view.focusIndex,
              passed: !_now.isBefore(view.today[i].at) && i != view.focusIndex,
            ),
          if (cityClockDiffers(widget.cityZone, _now))
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 4, 22, 0),
              child: Row(
                children: [
                  Icon(Icons.schedule_rounded, size: 14, color: gp.textSec),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      s.prayerTimesPhoneClock,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: gp.textSec,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

/// One moment of the day: a prayer, or sunrise.
@immutable
class PrayerMoment {
  const PrayerMoment(this.key, this.at);

  /// [PrayerDayTimes]' own field name: 'fajr', 'sunrise', 'dhuhr', 'asr',
  /// 'maghrib' or 'isha'.
  final String key;

  /// On the phone's clock.
  final DateTime at;

  /// No adhan is called at sunrise, so its words name the sun instead.
  bool get hasAdhan => key != 'sunrise';
}

/// What the card shows at one instant. Pure, so the rules are pinned by
/// tests without a widget or a clock (test/features/settings/
/// prayer_today_card_test.dart).
@immutable
class PrayerToday {
  const PrayerToday._({
    required this.today,
    required this.focus,
    required this.focusIndex,
    required this.elapsed,
    required this.periodKey,
  });

  /// In the order the moments occur, as the widget's list orders them.
  static const keys = ['fajr', 'sunrise', 'dhuhr', 'asr', 'maghrib', 'isha'];

  /// Today's six moments, in [keys] order.
  final List<PrayerMoment> today;

  /// The moment the sky counts to, or up from inside its minutes after.
  final PrayerMoment focus;

  /// [focus]'s place in [today], or -1 when it is tomorrow's Fajr.
  final int focusIndex;

  /// Whether [focus] has passed and the counter runs up from it.
  final bool elapsed;

  /// Which sky: the last moment of today already behind, 'isha' before
  /// today's Fajr (the night before it).
  final String periodKey;

  /// The widget's rule, applied to today and tomorrow: the first moment
  /// whose own minutes after it ([PrayerWidgetFeed.elapsedWindowFor]) have
  /// not yet run out. Inside those minutes the counter runs up from it
  /// («مضى على الأذان»), otherwise it counts down to it. The same moment
  /// the widget's face shows at [now], which is what PrayerWidgetFeed.
  /// flatten and the Swift picker agree on.
  static PrayerToday resolve({
    required PrayerDayTimes today,
    required PrayerDayTimes tomorrow,
    required DateTime now,
  }) {
    final todays = [
      for (final key in keys) PrayerMoment(key, _local(_momentOf(today, key))),
    ];
    final ahead = [...todays, PrayerMoment('fajr', _local(tomorrow.fajr))];
    var index = ahead.indexWhere(
      (m) => now.isBefore(m.at.add(PrayerWidgetFeed.elapsedWindowFor(m.key))),
    );
    if (index < 0) index = ahead.length - 1;
    final focus = ahead[index];
    var period = 'isha';
    for (final m in todays) {
      if (!now.isBefore(m.at)) period = m.key;
    }
    return PrayerToday._(
      today: todays,
      focus: focus,
      focusIndex: index < todays.length ? index : -1,
      elapsed: !now.isBefore(focus.at),
      periodKey: period,
    );
  }

  static DateTime _momentOf(PrayerDayTimes day, String key) =>
      key == 'sunrise' ? day.sunrise : day.forKey(key)!;

  /// A local DateTime, not the tz.TZDateTime as-is, the way the widget's
  /// feed hands it over: only the instant matters, shown on the phone's
  /// clock.
  static DateTime _local(DateTime at) =>
      DateTime.fromMillisecondsSinceEpoch(at.millisecondsSinceEpoch);
}

/// Whether a city in [zone] reads a different clock from the phone's at
/// [now]. Offsets, not names: Asia/Riyadh and Asia/Bahrain are one clock.
/// An unknown or missing zone says nothing.
@visibleForTesting
bool cityClockDiffers(String? zone, DateTime now) {
  if (zone == null) return false;
  try {
    final there = tz.TZDateTime.from(now, tz.getLocation(zone));
    return there.timeZoneOffset != now.timeZoneOffset;
  } catch (_) {
    return false;
  }
}

/// The counter, as the widget's ticker draws it: «1:23:45», and «23:45»
/// under an hour. Counting down it rounds up, so it reads 0:00 at the
/// moment itself and not a second early; counting up it rounds down.
@visibleForTesting
String prayerCounterText(Duration d, {required bool up}) {
  final ms = d.inMilliseconds.abs();
  final total = up ? ms ~/ 1000 : (ms + 999) ~/ 1000;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final sec = total % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(sec)}' : '$m:${two(sec)}';
}

/// Each moment's mark in the list, and on its adhan alarm switch
/// (PrayerAlarmCard), so the two cards draw a prayer the same way.
IconData prayerMomentIcon(String key) => switch (key) {
      'fajr' => Icons.nights_stay_rounded,
      'sunrise' => Icons.wb_twilight_rounded,
      'dhuhr' => Icons.wb_sunny_rounded,
      'asr' => Icons.wb_sunny_outlined,
      'maghrib' => Icons.wb_twilight_rounded,
      _ => Icons.dark_mode_rounded, // isha
    };

/// «الفجر» … «العشاء» as every other screen names them (HabitCue's preset
/// labels), and «الشروق».
String _nameOf(String key, S s) =>
    key == 'sunrise' ? s.prayerSunrise : HabitCue.preset(key).labelForLocale(s.isAr);

/// «4:12 ص», the clock format the Add Habit prayer pills use.
String _clockOf(DateTime at, S s) =>
    HabitCue.time(at.hour, at.minute).labelForLocale(s.isAr);

/// One of the widget's four skies and the only colours allowed on it.
///
/// The values are PrayerSky.swift's, where each was measured against the
/// worst pixel under the row it sits on and holds 4.5:1 (the name 3:1, as
/// large text). This panel centres the same four lines on the same images,
/// so those measurements carry over. IF A SKY OR ITS COLOURS CHANGE THERE,
/// CHANGE THEM HERE.
class _Sky {
  const _Sky({
    required this.asset,
    required this.ground,
    required this.ink,
    required this.secondary,
    required this.name,
    required this.mosqueOpacity,
  });

  final String asset;

  /// The image's mean colour, painted under it in case it fails to load.
  final Color ground;

  /// The counter before the moment.
  final Color ink;

  /// The time beside the name, and the line under it.
  final Color secondary;

  /// The name, the mosque, and the counter once the moment has passed.
  final Color name;
  final double mosqueOpacity;

  static _Sky forPeriod(String key) => switch (key) {
        'sunrise' => sunrise,
        'dhuhr' => midday,
        'asr' => afternoon,
        _ => night, // fajr, maghrib, isha
      };

  static const midday = _Sky(
    asset: 'assets/images/prayer_sky_midday.jpg',
    ground: Color(0xFFFCF3E7),
    ink: Color(0xFF2B2017),
    secondary: Color(0xFF6E5C47),
    name: Color(0xFF8C5A10),
    mosqueOpacity: 0.13,
  );

  static const afternoon = _Sky(
    asset: 'assets/images/prayer_sky_afternoon.jpg',
    ground: Color(0xFFDDA065),
    ink: Color(0xFF2E150A),
    secondary: Color(0xFF4A2311),
    name: Color(0xFF6E2810),
    mosqueOpacity: 0.22,
  );

  static const sunrise = _Sky(
    asset: 'assets/images/prayer_sky_sunrise.jpg',
    ground: Color(0xFFD29451),
    ink: Color(0xFF2A1407),
    secondary: Color(0xFF2B1407),
    name: Color(0xFF532208),
    mosqueOpacity: 0.22,
  );

  static const night = _Sky(
    asset: 'assets/images/prayer_sky_night.jpg',
    ground: Color(0xFF10262C),
    ink: Color(0xFFF4ECDF),
    secondary: Color(0xFFB8AA96),
    name: Color(0xFFE4B45F),
    mosqueOpacity: 0.16,
  );
}

/// The widget's medium face, in the app: the moment and its time, what the
/// counter means, the counter, the mosque on the bottom edge.
class _SkyPanel extends StatelessWidget {
  const _SkyPanel({required this.view, required this.now});

  final PrayerToday view;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final sky = _Sky.forPeriod(view.periodKey);
    final focus = view.focus;
    final name = _nameOf(focus.key, s);
    // Tomorrow's Fajr says it is tomorrow's: the list under the sky is
    // still today's, and its Fajr can be a minute off this one.
    final clock = view.focusIndex < 0
        ? s.prayerTomorrowAt(_clockOf(focus.at, s))
        : _clockOf(focus.at, s);
    final label = focus.hasAdhan
        ? (view.elapsed ? s.prayerSinceAdhan : s.prayerUntilAdhan)
        : (view.elapsed ? s.prayerSinceSunrise : s.prayerUntilSunrise);
    final counter = prayerCounterText(
      focus.at.difference(now),
      up: view.elapsed,
    );
    return Semantics(
      container: true,
      // The ticking counter stays out of what a screen reader says: it
      // would change under the reader every second.
      label: '$name $clock${s.isAr ? '،' : ','} $label',
      excludeSemantics: true,
      child: SizedBox(
        height: 146,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: sky.ground),
            Image.asset(
              sky.asset,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
            PositionedDirectional(
              end: 18,
              bottom: 0,
              child: Image.asset(
                'assets/images/prayer_mosque.png',
                height: 58,
                color: sky.name.withValues(alpha: sky.mosqueOpacity),
                colorBlendMode: BlendMode.srcIn,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Center(
                // Large text sizes shrink the face rather than spill out of
                // the sky.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            name,
                            style: TextStyle(
                              fontSize: 23,
                              fontWeight: FontWeight.w600,
                              color: sky.name,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            clock,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: sky.secondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        label,
                        style: TextStyle(fontSize: 13, color: sky.secondary),
                      ),
                      Text(
                        counter,
                        textDirection: TextDirection.ltr,
                        style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w500,
                          height: 1.15,
                          // After the moment the counter takes the name's
                          // colour, as on the widget (Aziz, 2026-09-25).
                          color: view.elapsed ? sky.name : sky.ink,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One line of today's list.
class _MomentRow extends StatelessWidget {
  const _MomentRow({
    required this.moment,
    required this.focused,
    required this.passed,
  });

  final PrayerMoment moment;

  /// The moment the sky is counting to or from.
  final bool focused;

  /// Already behind, and not the one inside its minutes after.
  final bool passed;

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final quiet = !moment.hasAdhan;
    final ink = focused
        ? gp.goldInk
        : passed
            ? gp.textSec
            : gp.textPrimary;
    final name = _nameOf(moment.key, s);
    final clock = _clockOf(moment.at, s);
    return Semantics(
      container: true,
      selected: focused,
      label: '$name $clock',
      excludeSemantics: true,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: focused
            ? BoxDecoration(
                color: gp.goldInk.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              )
            : null,
        child: Row(
          children: [
            Icon(
              prayerMomentIcon(moment.key),
              size: 18,
              color: focused ? gp.goldInk : (passed ? gp.textTert : gp.textSec),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                name,
                style: TextStyle(
                  fontSize: quiet ? 14 : 15,
                  fontWeight: focused ? FontWeight.w700 : FontWeight.w500,
                  color: quiet && !focused ? gp.textSec : ink,
                ),
              ),
            ),
            Text(
              clock,
              style: TextStyle(
                fontSize: quiet ? 14 : 15,
                fontWeight: focused ? FontWeight.w700 : FontWeight.w600,
                color: quiet && !focused ? gp.textSec : ink,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart' show Geolocator, LocationPermission;

import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/day_clock_provider.dart';
import '../../../core/services/bahrain_prayer_table.dart';
import '../../../core/services/country_lookup_service.dart';
import '../../../core/services/device_location_service.dart';
import '../../../core/services/prayer_times_service.dart';
import '../../../core/theme/game_theme.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../models/notification_settings.dart';
import '../notifiers/notification_settings_notifier.dart';
import '../widgets/city_search_sheet.dart';

/// Settings › موقع الصلاة: the place prayer times are worked out from, and
/// the one place to change it.
///
/// A page of its own since 2026-09-25 (Aziz: "make it out, not inside the
/// notification section, better and easier flow"). It was one row in
/// Notification Settings, where a tap on the row read the GPS and a small
/// search icon beside it was the only way to a city, under a heading about
/// reminders. But the place feeds more than reminders: the prayer widget,
/// prayer habits and every prayer time the app shows. So it sits in Settings
/// under Language, where the prayer widget's «حدّد موقعك» lands too (the
/// widget opens Settings).
///
/// Two ways, said plainly, one of them ticked:
///  - «موقعي الحالي»: the phone's own location, which the app keeps current
///    by itself (autoLocatePrayerPlace moves it once the phone is 10 km
///    away), so a trip abroad brings that city's prayers with it.
///  - «اختر مدينة»: a city picked by hand, which never moves on its own.
/// Choosing «موقعي الحالي» again is how a hand-picked city goes back to
/// automatic.
class PrayerLocationScreen extends ConsumerStatefulWidget {
  const PrayerLocationScreen({super.key});

  @override
  ConsumerState<PrayerLocationScreen> createState() =>
      _PrayerLocationScreenState();
}

/// Which of the two ways the saved place follows.
enum _PlaceMode { none, phone, city }

class _PrayerLocationScreenState extends ConsumerState<PrayerLocationScreen> {
  bool _detecting = false;

  /// Whether the app may read the location without asking. Only matters for
  /// a place saved before `auto` was recorded (see [NotificationLocation.
  /// auto]), which follows the phone exactly when this is true.
  bool _locationAllowed = false;

  @override
  void initState() {
    super.initState();
    _readPermission();
  }

  Future<void> _readPermission() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (!mounted) return;
      setState(() {
        _locationAllowed = permission == LocationPermission.whileInUse ||
            permission == LocationPermission.always;
      });
    } catch (_) {
      // No answer (a platform without it): a legacy place reads as a city.
    }
  }

  _PlaceMode _modeOf(NotificationLocation? place) {
    if (place == null) return _PlaceMode.none;
    final auto = place.auto ?? _locationAllowed;
    return auto ? _PlaceMode.phone : _PlaceMode.city;
  }

  Future<void> _usePhoneLocation() async {
    if (_detecting) return;
    unawaited(HapticFeedback.selectionClick());
    setState(() => _detecting = true);
    final outcome = await DeviceLocationService.detect();
    if (!mounted) return;
    setState(() => _detecting = false);

    if (outcome.isSuccess) {
      setState(() => _locationAllowed = true);
      // Coordinates are never shown: the label starts as «جارٍ تحديد
      // الموقع…», becomes the place's name when the lookup answers, and
      // falls back to a plain "Location set" if it never does. The same save
      // the app makes on its own (savePhoneLocation), `auto: true`, so the
      // place follows the phone from now on.
      final s = S.of(context);
      await savePhoneLocation(
        ref.read,
        outcome.fix!,
        isAr: s.isAr,
        resolvingLabel: s.notifLocationResolving,
        genericLabel: s.notifLocationSetGeneric,
        isMounted: () => mounted,
      );
      return;
    }

    // Denied, location services off, or no fix in time: say so, then offer
    // the city search straight away rather than leaving a dead end.
    final s = S.of(context);
    ScaffoldMessenger.of(context).showOne(
      SnackBar(
        content: Text(s.notifLocationDetectFailed),
        duration: const Duration(seconds: 3),
      ),
    );
    await _chooseCity();
  }

  Future<void> _chooseCity() async {
    unawaited(HapticFeedback.selectionClick());
    final isAr = S.of(context).isAr;
    final picked = await showCitySearchSheet(context);
    if (!mounted || picked == null) return;
    // The old place's country code goes with it: until the new one
    // resolves, the city's own coordinates pick the method (see
    // savePhoneLocation for why a stale code is worse than none).
    await ref.read(notificationSettingsProvider.notifier).update(
          (c) => c.copyWith(clearLocation: true).copyWith(location: picked),
        );
    if (!mounted) return;
    await _resolveCountry(picked.lat, picked.lng, isAr: isAr);
  }

  /// The picked city's country code, for PrayerTimesService.resolveRegion's
  /// country tier. Quietly after the save: the city is already on screen,
  /// and a slow or failed lookup costs nothing but that tier. Dropped when a
  /// newer place has replaced this one meanwhile.
  Future<void> _resolveCountry(
    double lat,
    double lng, {
    required bool isAr,
  }) async {
    final place = await CountryLookupService.lookupPlace(
      lat,
      lng,
      languageCode: isAr ? 'ar' : 'en',
    );
    if (!mounted) return;
    final current = ref.read(notificationSettingsProvider).location;
    if (current == null || current.lat != lat || current.lng != lng) return;
    await ref.read(notificationSettingsProvider.notifier).update(
          (c) => c.copyWith(
            resolvedCountryCode: place.code ?? c.resolvedCountryCode,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final settings = ref.watch(notificationSettingsProvider);
    final place = settings.location;
    final mode = _modeOf(place);
    // Inside Bahrain the times are the Ministry's own published timetable
    // (BahrainPrayerTable, preloaded at launch), not a calculation, so that
    // is what the row names while the table covers today. Karachi, which
    // resolveRegion gives Bahrain, is only the fallback past its last day.
    final today = ref.watch(dayClockProvider);
    final official = place != null &&
        PrayerTimesService.isInBahrain(place.lat, place.lng) &&
        BahrainPrayerTable.lookup(today) != null;
    final method = place == null
        ? s.notifLocationNotSet
        : official
            ? s.prayerPlaceBahrainTable
            : PrayerTimesService.resolveRegion(
                place.lat,
                place.lng,
                countryCode: settings.resolvedCountryCode,
              ).method.label(s.isAr);

    return Scaffold(
      backgroundColor: gp.bg,
      appBar: AppBar(
        backgroundColor: gp.bg,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        title: Text(
          s.prayerPlaceTitle,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: gp.textPrimary,
          ),
        ),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        children: [
          _PlaceCard(
            label: place?.label,
            detail: _detecting
                ? s.notifDetectingLocation
                : switch (mode) {
                    _PlaceMode.none => s.prayerPlaceNeeded,
                    _PlaceMode.phone => s.prayerPlaceFromPhone,
                    _PlaceMode.city => s.prayerPlacePicked,
                  },
            busy: _detecting,
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              s.prayerPlaceUses,
              style: TextStyle(fontSize: 12, height: 1.5, color: gp.textSec),
            ),
          ),
          const SizedBox(height: 22),
          _Card(
            children: [
              _ChoiceRow(
                icon: Icons.my_location_rounded,
                title: s.prayerPlaceAuto,
                body: s.prayerPlaceAutoBody,
                chosen: mode == _PlaceMode.phone,
                busy: _detecting,
                onTap: _detecting ? null : _usePhoneLocation,
              ),
              const _Divider(),
              _ChoiceRow(
                icon: Icons.search_rounded,
                title: s.prayerPlaceCity,
                body: s.prayerPlaceCityBody,
                chosen: mode == _PlaceMode.city,
                busy: false,
                onTap: _detecting ? null : _chooseCity,
              ),
            ],
          ),
          const SizedBox(height: 22),
          _Card(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Icon(Icons.explore_rounded, size: 20, color: gp.textSec),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        s.notifCalcMethod,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: gp.textPrimary,
                        ),
                      ),
                    ),
                    Flexible(
                      child: Text(
                        method,
                        textAlign: TextAlign.end,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: gp.textSec,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              s.prayerLocationPrivacyNote,
              style: TextStyle(fontSize: 12, height: 1.5, color: gp.textTert),
            ),
          ),
        ],
      ),
    );
  }
}

/// The place prayer times come from now, and which way it was chosen.
class _PlaceCard extends StatelessWidget {
  const _PlaceCard({
    required this.label,
    required this.detail,
    required this.busy,
  });

  /// Null while nothing is saved.
  final String? label;
  final String detail;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: gp.border, width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: gp.surfaceHL,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: busy
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: gp.textSec,
                    ),
                  )
                : Icon(
                    label == null
                        ? Icons.location_off_rounded
                        : Icons.location_on_rounded,
                    size: 24,
                    color: label == null ? gp.textSec : gp.goldInk,
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label ?? s.prayerPlaceNotSet,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: gp.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: TextStyle(fontSize: 12.5, color: gp.textSec),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One of the two ways, with a tick on the one in use.
class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.icon,
    required this.title,
    required this.body,
    required this.chosen,
    required this.busy,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool chosen;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Semantics(
      button: true,
      selected: chosen,
      label: title,
      hint: body,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            children: [
              Icon(icon, size: 20, color: chosen ? gp.goldInk : gp.textSec),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: chosen ? FontWeight.w700 : FontWeight.w500,
                        color: gp.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      body,
                      style: TextStyle(fontSize: 12, color: gp.textSec),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (busy)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: gp.textSec,
                  ),
                )
              else
                Icon(
                  chosen
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 22,
                  color: chosen ? gp.goldInk : gp.textTert,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Material(
      color: gp.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        side: BorderSide(color: gp.border, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 0.5,
      thickness: 0.5,
      indent: 48,
      color: context.gp.divider,
    );
  }
}

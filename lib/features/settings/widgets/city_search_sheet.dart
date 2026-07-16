import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/services/geocoding_service.dart';
import '../../../core/theme/game_theme.dart';
import '../models/notification_settings.dart';

/// Bottom sheet for setting the location prayer times are calculated from
/// by typed city search (via [GeocodingService]), plus a manual lat/lng
/// fallback for anyone the search doesn't cover — the secondary path behind
/// on-device GPS auto-detection (see DeviceLocationService), reached by
/// long-pressing the location row in Notification Settings, or
/// automatically when a GPS attempt fails. Returns the picked
/// [NotificationLocation], or null if dismissed without picking one.
Future<NotificationLocation?> showCitySearchSheet(BuildContext context) {
  return showModalBottomSheet<NotificationLocation>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => const _CitySearchSheet(),
  );
}

class _CitySearchSheet extends StatefulWidget {
  const _CitySearchSheet();

  @override
  State<_CitySearchSheet> createState() => _CitySearchSheetState();
}

class _CitySearchSheetState extends State<_CitySearchSheet> {
  final _queryController = TextEditingController();
  final _latController = TextEditingController();
  final _lngController = TextEditingController();
  final _labelController = TextEditingController();

  List<CitySearchResult> _results = const [];
  bool _loading = false;
  bool _searched = false;
  bool _manualMode = false;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _queryController.dispose();
    _latController.dispose();
    _lngController.dispose();
    _labelController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value, bool isAr) {
    _debounce?.cancel();
    // Debounced rather than searching on every keystroke — the geocoding
    // endpoint is free, but there's no reason to fire a request for every
    // letter of a still-being-typed city name.
    _debounce = Timer(
      const Duration(milliseconds: 450),
      () => _runSearch(value, isAr),
    );
  }

  Future<void> _runSearch(String value, bool isAr) async {
    if (value.trim().length < 2) {
      if (!mounted) return;
      setState(() {
        _results = const [];
        _searched = false;
      });
      return;
    }
    setState(() => _loading = true);
    final results = await GeocodingService.search(value, isAr: isAr);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _searched = true;
      _results = results;
    });
  }

  void _pick(CitySearchResult r) {
    Navigator.pop(
      context,
      NotificationLocation(
        lat: r.latitude,
        lng: r.longitude,
        label: r.displayLabel,
      ),
    );
  }

  void _useManualCoordinates(S s) {
    final lat = double.tryParse(_latController.text.trim());
    final lng = double.tryParse(_lngController.text.trim());
    if (lat == null || lng == null || lat.abs() > 90 || lng.abs() > 180) return;
    final label = _labelController.text.trim();
    Navigator.pop(
      context,
      NotificationLocation(
        lat: lat,
        lng: lng,
        label: label.isEmpty ? '${lat.toStringAsFixed(2)}, ${lng.toStringAsFixed(2)}' : label,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final isAr = s.isAr;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        decoration: BoxDecoration(
          color: gp.surfaceHigh,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: gp.border, width: 0.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: gp.border,
                  borderRadius: BorderRadius.circular(100),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              s.prayerLocationTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700, color: gp.textPrimary),
            ),
            const SizedBox(height: 6),
            Text(
              s.prayerLocationPrivacyNote,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: gp.textSec, height: 1.35),
            ),
            const SizedBox(height: 16),
            if (!_manualMode) ...[
              TextField(
                controller: _queryController,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: (v) => _onQueryChanged(v, isAr),
                decoration: InputDecoration(
                  hintText: s.citySearchHint,
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _loading
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: _results.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        child: Text(
                          _searched
                              ? s.citySearchNoResults
                              : s.citySearchPrompt,
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: gp.textTert),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: _results.length,
                        separatorBuilder: (_, __) =>
                            Container(height: 0.5, color: gp.divider),
                        itemBuilder: (context, i) {
                          final r = _results[i];
                          return InkWell(
                            onTap: () => _pick(r),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 12),
                              child: Row(
                                children: [
                                  Icon(Icons.location_on_outlined,
                                      size: 18, color: gp.textSec),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      r.displayLabel,
                                      style: TextStyle(
                                          fontSize: 14,
                                          color: gp.textPrimary,
                                          fontWeight: FontWeight.w500),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => setState(() => _manualMode = true),
                child: Text(s.citySearchEnterManually),
              ),
            ] else ...[
              TextField(
                controller: _labelController,
                decoration: InputDecoration(hintText: s.locationLabelHint),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _latController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true, signed: true),
                      decoration: InputDecoration(hintText: s.latitude),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _lngController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true, signed: true),
                      decoration: InputDecoration(hintText: s.longitude),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: () => _useManualCoordinates(s),
                child: Text(s.useTheseCoordinates),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => setState(() => _manualMode = false),
                child: Text(s.citySearchBackToSearch),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

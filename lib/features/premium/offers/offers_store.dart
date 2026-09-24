import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../../../core/services/local_store_service.dart';
import 'paywall_offer.dart';

/// Reads the admin tool's offers document (`offers/live`) for the paywall.
///
/// Read once each time the paywall opens rather than followed by a
/// listener: the offers only matter on that one screen, so a listener on
/// every open app would cost a read per phone per edit for nothing. A copy
/// is kept on the device, so a phone that cannot reach Firestore (offline,
/// or a build older than the rule that opens the document) still shows
/// what it last knew. With no copy at all it uses [OffersConfig.fallback].
class OffersConfigStore {
  OffersConfigStore._();

  static const String docPath = 'offers/live';

  /// In the settings box, as a JSON string (see WordingEditsStore.cacheKey
  /// for why a string and not a nested map).
  static const String cacheKey = 'offers_live_v1';

  static Future<OffersConfig> load({
    FirebaseFirestore? firestore,
    Box<dynamic>? box,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    Box<dynamic>? settings;
    try {
      settings = box ?? await LocalStoreService.settingsBox();
    } catch (_) {}
    try {
      final db = firestore ?? FirebaseFirestore.instance;
      final snap = await db.doc(docPath).get().timeout(timeout);
      final config = snap.exists
          ? OffersConfig.fromData(snap.data())
          : OffersConfig.fallback;
      try {
        await settings?.put(cacheKey, jsonEncode(config.toJson()));
      } catch (_) {}
      return config;
    } catch (e) {
      debugPrint('[offers] could not read $docPath, using the last copy: $e');
      try {
        final raw = settings?.get(cacheKey);
        if (raw is String) return OffersConfig.fromData(jsonDecode(raw));
      } catch (_) {}
      return OffersConfig.fallback;
    }
  }
}

/// Where the paywall gets its offers: the two stores in this file. A widget
/// test hands in fixed answers instead (see PremiumScreen.offersSource).
class PaywallOffersSource {
  const PaywallOffersSource({
    required this.loadConfig,
    required this.readWelcomeStart,
    required this.ensureWelcomeStarted,
  });

  final Future<OffersConfig> Function() loadConfig;
  final Future<DateTime?> Function(String? uid) readWelcomeStart;
  final Future<DateTime> Function(DateTime now, String? uid)
      ensureWelcomeStarted;

  static final PaywallOffersSource live = PaywallOffersSource(
    loadConfig: () => OffersConfigStore.load(),
    readWelcomeStart: (uid) => WelcomeWindowStore.read(uid: uid),
    ensureWelcomeStarted: (now, uid) =>
        WelcomeWindowStore.ensureStarted(now: now, uid: uid),
  );
}

/// This person's one welcome window: when it started, if it ever did.
///
/// Kept in two places. The device (the settings box) covers guests and
/// offline opens; the account (`users/{uid}.welcomeOfferStartedAt`) makes
/// it one window per PERSON, so a second phone or a reinstall of a
/// signed-in account can never start a fresh one. The earlier of the two
/// always wins. Nothing in the app ever clears either record, and
/// firestore.rules refuses an account value in the future, so no window is
/// ever extended or restarted by the app.
///
/// A guest who reinstalls does get a new window: there is nothing left on
/// the device that could tell. That is the store's limit, not an app
/// restarting a timer.
class WelcomeWindowStore {
  WelcomeWindowStore._();

  static const String localKey = 'welcome_offer_started_at_v1';
  static const String accountField = 'welcomeOfferStartedAt';

  static Future<DateTime?> read({
    String? uid,
    FirebaseFirestore? firestore,
    Box<dynamic>? box,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final local = await _readLocal(box);
    final account = uid == null
        ? null
        : await _readAccount(uid, firestore, timeout);
    return _earliest(local, account);
  }

  /// Starts the window at [now] unless it already started, and makes sure
  /// both records carry the start in force, which it returns. The paywall
  /// calls this only when it can actually show the welcome price, so a
  /// window never runs down unseen.
  static Future<DateTime> ensureStarted({
    required DateTime now,
    String? uid,
    FirebaseFirestore? firestore,
    Box<dynamic>? box,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final local = await _readLocal(box);
    final account = uid == null
        ? null
        : await _readAccount(uid, firestore, timeout);
    final start = _earliest(local, account) ?? now;
    if (local == null || start.isBefore(local)) await _writeLocal(start, box);
    if (uid != null && account == null) {
      await _writeAccount(uid, start, firestore, timeout);
    }
    return start;
  }

  static DateTime? _earliest(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isBefore(b) ? a : b;
  }

  static Future<DateTime?> _readLocal(Box<dynamic>? box) async {
    try {
      final settings = box ?? await LocalStoreService.settingsBox();
      final raw = settings.get(localKey);
      if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
    } catch (e) {
      debugPrint('[offers] welcome start unreadable on this device: $e');
    }
    return null;
  }

  static Future<void> _writeLocal(DateTime start, Box<dynamic>? box) async {
    try {
      final settings = box ?? await LocalStoreService.settingsBox();
      await settings.put(localKey, start.millisecondsSinceEpoch);
    } catch (e) {
      debugPrint('[offers] could not keep the welcome start: $e');
    }
  }

  static Future<DateTime?> _readAccount(
    String uid,
    FirebaseFirestore? firestore,
    Duration timeout,
  ) async {
    try {
      final db = firestore ?? FirebaseFirestore.instance;
      final snap =
          await db.collection('users').doc(uid).get().timeout(timeout);
      final value = snap.data()?[accountField];
      if (value is Timestamp) return value.toDate();
    } catch (e) {
      debugPrint('[offers] account welcome start unreadable: $e');
    }
    return null;
  }

  /// Written once. A merge, like every other write to the user document,
  /// so it never replaces what is there. A failure (offline, or a device
  /// clock running ahead of the server, which the rule refuses) leaves the
  /// device record in charge until the next paywall open tries again.
  static Future<void> _writeAccount(
    String uid,
    DateTime start,
    FirebaseFirestore? firestore,
    Duration timeout,
  ) async {
    try {
      final db = firestore ?? FirebaseFirestore.instance;
      await db.collection('users').doc(uid).set(
        {accountField: Timestamp.fromDate(start)},
        SetOptions(merge: true),
      ).timeout(timeout);
    } catch (e) {
      debugPrint('[offers] could not save the welcome start: $e');
    }
  }
}

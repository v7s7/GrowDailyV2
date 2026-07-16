import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';

/// Outcome of a purchase or restore attempt - a plain result type rather
/// than throwing, so callers (PremiumScreen) can show the right UI for
/// each case (error banner vs. silent no-op on cancel) without a try/catch
/// of their own. [customerInfo] is only set on [success].
class PurchaseOutcome {
  final bool success;
  final bool cancelled;
  final CustomerInfo? customerInfo;
  final String? errorMessage;

  const PurchaseOutcome._({
    required this.success,
    required this.cancelled,
    this.customerInfo,
    this.errorMessage,
  });

  factory PurchaseOutcome.success(CustomerInfo info) =>
      PurchaseOutcome._(success: true, cancelled: false, customerInfo: info);

  factory PurchaseOutcome.cancelled() =>
      const PurchaseOutcome._(success: false, cancelled: true);

  factory PurchaseOutcome.failure(String message) => PurchaseOutcome._(
        success: false,
        cancelled: false,
        errorMessage: message,
      );
}

/// Thin wrapper around RevenueCat (purchases_flutter) - the trusted layer
/// PremiumNotifier reads entitlement from. This exists so a purchase is
/// "100% confirmed" the way real money should be: RevenueCat's servers
/// verify the receipt directly with Apple (not this device's own StoreKit
/// response, which a jailbroken/tampered device could fake), and
/// entitlement lives on RevenueCat's backend keyed by App User ID - not a
/// Firestore field this client could just edit to unlock Premium for free
/// (see firestore.rules' premiumFieldOk() comment, now historical: that
/// Cloud-Function-verification plan was the pre-RevenueCat design; this
/// service replaces the need for one entirely, since RevenueCat *is* the
/// trusted backend).
///
/// Identity: [logIn]/[logOut] tie RevenueCat's own App User ID to this
/// account's Firebase uid (see main.dart's authStateProvider listener) so
/// the same purchase is recognized across every device/reinstall signed
/// into that account - a guest who buys Premium before ever signing in
/// still keeps it, since RevenueCat auto-generates an anonymous id for
/// them and transfers its purchase history the moment they do sign in
/// (RevenueCat's own "restore on login" behavior, no code needed here for
/// that part).
///
/// ── One-time setup only YOU can do (this class cannot do it for you) ──
/// 1. Create a free account at https://app.revenuecat.com and a Project
///    for GrowDaily.
/// 2. Add an iOS app to that project with bundle id `com.growdaily.v2`
///    (see ios/Runner.xcodeproj) and connect it to App Store Connect.
/// 3. In App Store Connect, create the two real products under this same
///    bundle id: an auto-renewable subscription (`growdaily_monthly`) and
///    a non-consumable one-time purchase (`growdaily_lifetime`). Done -
///    both exist and are wired into the Offering below.
///    Requires an active Paid Applications Agreement (Agreements, Tax, and
///    Banking in App Store Connect) - subscriptions can't go live without
///    it even in sandbox/TestFlight review.
/// 4. In RevenueCat, add both products, create an Entitlement named
///    exactly [entitlementId] below and attach both products to it, then
///    build a default Offering with the subscription mapped to the
///    "Monthly" package type and the lifetime purchase mapped to the
///    "Lifetime" package type (PurchaseService reads `.monthly`/
///    `.lifetime` specifically - see [getCurrentOffering]'s callers).
/// 5. Copy the iOS "public app-specific API key" from RevenueCat ->
///    Project Settings -> API keys, and paste it over [_iosApiKey] below.
///    Done - [_iosApiKey] now holds the real `appl_...` production key.
/// 6. In Xcode, select Runner -> Signing & Capabilities -> + Capability ->
///    In-App Purchase (RevenueCat's own install docs call this out
///    explicitly; it's a 10-second toggle, not something worth hand-
///    editing project.pbxproj for).
/// Until a real key is in place, [configure] deliberately no-ops (see
/// [isConfigured]) so the app still boots and PremiumScreen shows an
/// honest "not available yet" state instead of crashing.
class PurchaseService {
  PurchaseService._();
  static final instance = PurchaseService._();

  /// RevenueCat's dashboard entitlement identifier that unlocks Premium.
  /// Confirmed against the real RevenueCat project setup - matches the
  /// Entitlement attached to both the `growdaily_monthly` and
  /// `growdaily_lifetime` products exactly.
  static const String entitlementId = 'Grow Daily Premium';

  /// RevenueCat iOS API key - the real **production** key (`appl_` prefix),
  /// pulled from RevenueCat -> Project Settings -> API keys. This talks to
  /// real StoreKit and the real `growdaily_monthly`/`growdaily_lifetime`
  /// products in App Store Connect.
  ///
  /// ⚠️ Real money now: any purchase made while signed into a normal Apple
  /// ID will actually charge that card. For TestFlight/simulator testing,
  /// sign the test device into a Sandbox Tester Apple ID (App Store Connect
  /// -> Users and Access -> Sandbox -> Testers) before tapping buy - the
  /// purchase sheet will visibly say "[Environment: Sandbox]" when it's
  /// safe.
  static const String _iosApiKey = 'appl_aGGLOTfxUScNrQwyIcetVUvyDRW';

  bool _configured = false;

  /// Whether [configure] actually initialized the SDK - false until a real
  /// API key replaces the placeholder above. PremiumScreen checks this to
  /// show "not available yet" instead of an empty/broken paywall.
  bool get isConfigured => _configured;

  final _customerInfoController = StreamController<CustomerInfo>.broadcast();

  /// Fires whenever RevenueCat sees new CustomerInfo - a purchase on this
  /// device, a renewal/expiry/refund picked up on next launch, or a
  /// restore. PremiumNotifier is the one subscriber that matters today,
  /// but this is a broadcast stream so anything else could listen too.
  Stream<CustomerInfo> get customerInfoUpdates =>
      _customerInfoController.stream;

  /// Call once at app boot (see main.dart). Safe to call more than once -
  /// only the first call does anything. Deliberately never throws: a
  /// misconfigured or not-yet-set-up store integration should never be
  /// able to crash app launch for every user.
  Future<void> configure() async {
    if (_configured) return;
    if (kIsWeb || !Platform.isIOS) return; // iOS-only for now, see pubspec.
    if (_iosApiKey.isEmpty) return; // safety net, not expected in practice
    try {
      if (kDebugMode) await Purchases.setLogLevel(LogLevel.debug);
      await Purchases.configure(PurchasesConfiguration(_iosApiKey));
      Purchases.addCustomerInfoUpdateListener(_customerInfoController.add);
      _configured = true;
      // Loud, debug-only reminder so a Test Store key never quietly rides
      // along into a release build - see [_iosApiKey]'s doc comment.
      if (kDebugMode && _iosApiKey.startsWith('test_')) {
        debugPrint(
          '⚠️ PurchaseService: configured with a RevenueCat TEST STORE key. '
          'Purchases are simulated - no real money, no real App Store '
          'prices. Swap _iosApiKey for the appl_... production key before '
          'shipping to TestFlight/the App Store.',
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('PurchaseService.configure failed: $e');
    }
  }

  /// Ties RevenueCat's App User ID to this Firebase account so Premium
  /// follows the account across devices/reinstalls. Call whenever
  /// authStateProvider reports a signed-in uid (see main.dart) - safe to
  /// call repeatedly with the same uid.
  ///
  /// Returns the fresh CustomerInfo for *this* identity so the caller can
  /// apply it to premiumProvider right away instead of waiting on
  /// [customerInfoUpdates] - same reasoning PremiumNotifier.
  /// applyCustomerInfo's own doc comment already gives for the purchase/
  /// restore flow. Without this, PremiumNotifier's own constructor-time
  /// refresh() has no guaranteed ordering against this call: it can read
  /// RevenueCat's *previous* identity (anonymous, or a different account
  /// on a shared device) a beat before this one lands, showing a real
  /// subscriber as "not Premium" for a moment on every cold start before
  /// self-correcting once the stream listener catches up. Null on failure
  /// or if the SDK isn't configured - callers should treat that as "no
  /// change to make," not "definitely not Premium."
  Future<CustomerInfo?> logIn(String uid) async {
    if (!_configured) return null;
    try {
      final result = await Purchases.logIn(uid);
      return result.customerInfo;
    } catch (e) {
      if (kDebugMode) debugPrint('PurchaseService.logIn failed: $e');
      return null;
    }
  }

  /// Detaches RevenueCat back to an anonymous id - call on sign-out (see
  /// main.dart) so the *next* account signed in on this device never sees
  /// the previous account's entitlement.
  Future<void> logOut() async {
    if (!_configured) return;
    try {
      await Purchases.logOut();
    } catch (e) {
      if (kDebugMode) debugPrint('PurchaseService.logOut failed: $e');
    }
  }

  /// Whether [info] grants Premium - the one place this check happens, so
  /// every caller (PremiumNotifier, PremiumScreen after a purchase) agrees
  /// on what "entitled" means.
  bool isEntitled(CustomerInfo info) =>
      info.entitlements.all[entitlementId]?.isActive ?? false;

  /// Latest known entitlement snapshot. Safe to call often - RevenueCat
  /// caches this on-device and only hits the network when the cache is
  /// stale (see RevenueCat's customer-info docs), so this is cheap enough
  /// to call on every app resume (see PremiumNotifier.refresh).
  Future<CustomerInfo?> getCustomerInfo() async {
    if (!_configured) return null;
    try {
      return await Purchases.getCustomerInfo();
    } catch (e) {
      if (kDebugMode) debugPrint('PurchaseService.getCustomerInfo failed: $e');
      return null;
    }
  }

  /// The Offering PremiumScreen builds its plan cards from - null if the
  /// SDK isn't configured yet, or nothing's been set up in the RevenueCat
  /// dashboard/App Store Connect yet (see the class doc comment).
  Future<Offering?> getCurrentOffering() async {
    if (!_configured) return null;
    try {
      final offerings = await Purchases.getOfferings();
      return offerings.current;
    } catch (e) {
      if (kDebugMode) debugPrint('PurchaseService.getCurrentOffering failed: $e');
      return null;
    }
  }

  /// Buys [package]. [customerInfoUpdates] also fires separately with the
  /// same CustomerInfo (RevenueCat's own SDK broadcasts it), but the caller
  /// (PremiumScreen) applies [PurchaseOutcome.customerInfo] to
  /// premiumProvider itself right away on success rather than waiting for
  /// that - see PremiumNotifier.applyCustomerInfo's doc comment for why
  /// (no guaranteed ordering between this call returning and the stream
  /// delivering the same update).
  Future<PurchaseOutcome> purchase(Package package) async {
    try {
      final result = await Purchases.purchase(PurchaseParams.package(package));
      return PurchaseOutcome.success(result.customerInfo);
    } on PlatformException catch (e) {
      final code = _safeErrorCode(e);
      if (code == PurchasesErrorCode.purchaseCancelledError) {
        return PurchaseOutcome.cancelled();
      }
      return PurchaseOutcome.failure(e.message ?? code?.name ?? 'unknown_error');
    } catch (e) {
      return PurchaseOutcome.failure(e.toString());
    }
  }

  /// Re-syncs this store account's past purchases - the "Restore" button
  /// on PremiumScreen. Deliberately only ever called from that explicit
  /// tap (see RestoringPurchases' own guidance: this can trigger OS-level
  /// sign-in prompts, so it must never fire on its own).
  Future<PurchaseOutcome> restore() async {
    try {
      final info = await Purchases.restorePurchases();
      return PurchaseOutcome.success(info);
    } on PlatformException catch (e) {
      final code = _safeErrorCode(e);
      return PurchaseOutcome.failure(e.message ?? code?.name ?? 'unknown_error');
    } catch (e) {
      return PurchaseOutcome.failure(e.toString());
    }
  }

  /// Wraps [PurchasesErrorHelper.getErrorCode] so a failure in error
  /// *parsing itself* can never escape uncaught. Dart's sibling `catch`
  /// clauses don't protect each other - a throw from inside `on
  /// PlatformException catch` would otherwise propagate straight past
  /// [purchase]/[restore] entirely, leaving PremiumScreen's loading
  /// spinner stuck forever instead of resolving to an error state. Returns
  /// null on that (unconfirmed, low-probability) failure path.
  PurchasesErrorCode? _safeErrorCode(PlatformException e) {
    try {
      return PurchasesErrorHelper.getErrorCode(e);
    } catch (_) {
      return null;
    }
  }

  /// Presents RevenueCat's own hosted Paywall UI - built server-side from
  /// the Offering configured in the RevenueCat dashboard, no Flutter UI
  /// code needed on this end at all.
  ///
  /// Not called anywhere by default. PremiumScreen (this app's hand-built
  /// paywall, matching GrowDaily's own branding and its exact
  /// Monthly/Lifetime layout) stays the app's primary purchase surface -
  /// swapping it out for a generic hosted paywall would lose that custom
  /// design for no real benefit right now. This wrapper exists so the
  /// hosted paywall is still available as a one-line drop-in wherever it's
  /// wanted later (e.g. a quick paywall for a screen that doesn't have
  /// custom UI yet, or an A/B test against PremiumScreen) without writing
  /// any new UI then either.
  Future<PaywallResult> presentPaywall({Offering? offering}) async {
    if (!_configured) return PaywallResult.error;
    try {
      return await RevenueCatUI.presentPaywall(offering: offering);
    } catch (e) {
      if (kDebugMode) debugPrint('PurchaseService.presentPaywall failed: $e');
      return PaywallResult.error;
    }
  }

  /// Same as [presentPaywall], but only actually presents anything if the
  /// current user *doesn't* already have [entitlementId] - existing
  /// Premium users get [PaywallResult.notPresented] instead of seeing a
  /// paywall for something they've already bought. Handy for "gate this
  /// one action behind Premium" call sites that don't want to write their
  /// own isPremium check first.
  Future<PaywallResult> presentPaywallIfNeeded({Offering? offering}) async {
    if (!_configured) return PaywallResult.error;
    try {
      return await RevenueCatUI.presentPaywallIfNeeded(
        entitlementId,
        offering: offering,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('PurchaseService.presentPaywallIfNeeded failed: $e');
      }
      return PaywallResult.error;
    }
  }

  /// Presents RevenueCat's hosted Customer Center - self-serve subscription
  /// management (view renewal date, cancel, switch plan) as a ready-made
  /// screen, no custom UI needed. See PremiumScreen's "Manage Subscription"
  /// button for the app's one call site. Returns false (rather than
  /// throwing) if presenting it failed for any reason, same "plain result,
  /// never throw" shape as every other call in this class - the screen
  /// shows its normal error snackbar in that case.
  Future<bool> presentCustomerCenter() async {
    if (!_configured) return false;
    try {
      await RevenueCatUI.presentCustomerCenter();
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('PurchaseService.presentCustomerCenter failed: $e');
      }
      return false;
    }
  }
}

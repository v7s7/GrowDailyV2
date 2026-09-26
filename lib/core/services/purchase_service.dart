import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';

/// Every product that unlocks Premium for life: the regular Lifetime and
/// `growdaily_lifetime_offer`, the same unlock at the welcome and sale
/// price (see lib/features/premium/offers/paywall_offer.dart). A buyer of
/// either owns the same thing, so "is this a lifetime owner" accepts both.
const Set<String> kLifetimeProductIds = {
  'growdaily_lifetime',
  'growdaily_lifetime_offer',
};

/// Whether [productId] is a lifetime product. RevenueCat can append a Play
/// purchase option to an id (`growdaily_lifetime_offer:lifetime`), so only
/// the part before the colon is compared.
bool isLifetimeProductId(String productId) =>
    kLifetimeProductIds.contains(productId.split(':').first);

/// Whether [info] holds a subscription that is still set to renew.
///
/// A lifetime owner can have one too, and then pays twice: the entitlement
/// names only the lifetime (its open expiry beats any month end), while the
/// store keeps charging the Monthly until it is cancelled. That happens when
/// a Monthly stuck on a failed payment goes through after Lifetime was
/// bought, since updating the card to buy Lifetime is exactly what retries
/// it, or when Lifetime came from a creator's App Store link.
///
/// RevenueCat keys a Play subscription in [CustomerInfo.activeSubscriptions]
/// with its base plan ("growdaily_monthly:monthly-autorenew") and in
/// [CustomerInfo.subscriptionsByProductIdentifier] without it, so both are
/// tried. An active subscription with no detail at all counts as renewing:
/// wrongly telling someone to check a subscription costs a tap, wrongly
/// telling them there is nothing to cancel costs money every month.
bool subscriptionStillRenews(CustomerInfo info) {
  final byId = info.subscriptionsByProductIdentifier;
  for (final sub in byId.values) {
    if (sub.isActive && sub.willRenew) return true;
  }
  for (final id in info.activeSubscriptions) {
    if (!byId.containsKey(id) && !byId.containsKey(id.split(':').first)) {
      return true;
    }
  }
  return false;
}

/// Whether [info]'s Premium is a store subscription (Monthly, or an annual
/// if one is ever sold) rather than Lifetime or a grant, i.e. whether
/// Lifetime is still something this person could buy.
///
/// The Premium page hides its plans from anyone entitled, which left a
/// Monthly subscriber with no way to Lifetime from the app at all (Aziz,
/// 2026-09-25: "do 4"). This decides who gets the Lifetime card instead.
/// Only an App Store or Play entitlement counts: a hand grant (RevenueCat
/// promotional, the store Aziz's own account and three others hold until
/// 2226) has no Monthly to replace, and an unknown store is not offered a
/// purchase on a guess.
bool premiumFromStoreSubscription(CustomerInfo info) {
  final e = info.entitlements.all[PurchaseService.entitlementId];
  if (e == null || !e.isActive) return false;
  if (isLifetimeProductId(e.productIdentifier)) return false;
  return e.store == Store.appStore || e.store == Store.playStore;
}

/// Outcome of a purchase or restore attempt - a plain result type rather
/// than throwing, so callers (PremiumScreen) can show the right UI for
/// each case (error banner vs. silent no-op on cancel) without a try/catch
/// of their own. [customerInfo] is only set on [success].
class PurchaseOutcome {
  final bool success;
  final bool cancelled;

  /// The store took the order but is waiting on someone else to finish it:
  /// a parent's Ask to Buy approval on iPhone, or a cash payment Google Play
  /// lets people complete later. No money has moved yet. When it completes
  /// it arrives through [PurchaseService.customerInfoUpdates] like any
  /// other purchase, so there is nothing to retry.
  final bool pending;
  final CustomerInfo? customerInfo;
  final String? errorMessage;

  const PurchaseOutcome._({
    required this.success,
    required this.cancelled,
    this.pending = false,
    this.customerInfo,
    this.errorMessage,
  });

  factory PurchaseOutcome.success(CustomerInfo info) =>
      PurchaseOutcome._(success: true, cancelled: false, customerInfo: info);

  factory PurchaseOutcome.cancelled() =>
      const PurchaseOutcome._(success: false, cancelled: true);

  factory PurchaseOutcome.pending() =>
      const PurchaseOutcome._(success: false, cancelled: false, pending: true);

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
///
/// ── The Android half of the same setup (DONE 2026-09-08, except step 9's
///    service-account upload - see the note under step 10) ──
/// 7. In Play Console, create the app under package `com.growdaily.v2` and
///    upload a build to any track. Play will not let you create products
///    until a release with the Billing library in it has been uploaded
///    once, so this genuinely has to come first.
/// 8. Create the two products, mirroring step 3 but in Play's own model:
///    `growdaily_monthly` as a Subscription with a single base plan, and
///    `growdaily_lifetime` as a one-time In-app product. Play has no
///    "non-consumable" toggle - a one-time product simply is not consumed
///    unless the app consumes it, and this app never does.
/// 9. In RevenueCat, add a Play Store app to the SAME project, upload the
///    Google Cloud service-account JSON it asks for (that credential is
///    what lets RevenueCat verify Play receipts server-side), then attach
///    both new products to the SAME [entitlementId] entitlement and the
///    same default Offering used for iOS. Reusing one entitlement is what
///    makes Premium bought on one platform recognised on the other.
/// 10. Copy the Android public API key (`goog_...`) into [_androidApiKey].
///     Done. Steps 7 and 8 are done too: `growdaily_monthly` is a
///     subscription with the single base plan `monthly-autorenew` at
///     USD 4.99, and `growdaily_lifetime` is a one-time product at
///     USD 29.99, both Active across 177 regions and both matching the
///     App Store prices exactly. Note Play rejects underscores in base
///     plan and purchase option ids, hence the hyphen in
///     `monthly-autorenew`.
///
///     STILL OUTSTANDING from step 9: the Google Cloud service-account
///     JSON has not been uploaded to RevenueCat. Without it RevenueCat
///     cannot verify Play receipts server-side, so an Android purchase
///     will not grant the entitlement even though the paywall now loads
///     and the products resolve. That upload is a credential handover and
///     has to be done by hand in the RevenueCat dashboard.
///
/// Until a real key is in place, [configure] deliberately no-ops (see
/// [isConfigured]) so the app still boots and PremiumScreen shows an
/// honest "not available yet" state instead of crashing. Both platforms
/// now carry a real key, so that path is only reachable on web.
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

  /// RevenueCat **Android** API key (`goog_` prefix), from the same
  /// RevenueCat project -> Project Settings -> API keys, but issued only
  /// once a Play Store app has been added to that project.
  ///
  /// The real production key, from the "Grow Daily (Play Store)" app added
  /// to the same RevenueCat project on 2026-09-08 (app39b323bf0c, package
  /// com.growdaily.v2). Public by design, exactly like [_iosApiKey]: the
  /// RevenueCat SDK key ships inside every binary and is not a secret.
  ///
  /// This was an empty string until that app existed, which meant
  /// [configure] no-opped on Android and PremiumScreen showed its honest
  /// "not available yet" state rather than an empty paywall.
  static const String _androidApiKey = 'goog_egxJzSahAoRaipMjLhPFhrTJhdR';

  /// The key for the platform this build is running on, or null where
  /// purchases are not supported at all (web).
  ///
  /// This replaced a hard `if (kIsWeb || !Platform.isIOS) return;` in
  /// [configure]. That line predated the Android project existing and meant
  /// RevenueCat was never configured on Android under any circumstances -
  /// so every Android user saw "not available yet" no matter how complete
  /// the store setup was, and Premium could not be sold at all.
  static String? get _apiKeyForPlatform {
    if (kIsWeb) return null;
    // defaultTargetPlatform, not dart:io's Platform, which throws on the web.
    if (defaultTargetPlatform == TargetPlatform.iOS) return _iosApiKey;
    if (defaultTargetPlatform == TargetPlatform.android) return _androidApiKey;
    return null;
  }

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
    final apiKey = _apiKeyForPlatform;
    // Null on web (no store at all); empty on Android until [_androidApiKey]
    // is filled in. Both mean "no store integration here", which is a
    // supported state, not an error - PremiumScreen reads [isConfigured].
    if (apiKey == null || apiKey.isEmpty) return;
    try {
      if (kDebugMode) await Purchases.setLogLevel(LogLevel.debug);
      await Purchases.configure(PurchasesConfiguration(apiKey));
      Purchases.addCustomerInfoUpdateListener(_customerInfoController.add);
      _configured = true;
      // Loud, debug-only reminder so a Test Store key never quietly rides
      // along into a release build - see [_iosApiKey]'s doc comment. Checks
      // the key actually in use, so it covers the Android key too.
      if (kDebugMode && apiKey.startsWith('test_')) {
        debugPrint(
          '⚠️ PurchaseService: configured with a RevenueCat TEST STORE key. '
          'Purchases are simulated - no real money, no real store prices. '
          'Swap in the production key (appl_... on iOS, goog_... on '
          'Android) before shipping to TestFlight/Play.',
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

  /// Whether the active entitlement came from the one-time lifetime
  /// purchase rather than the subscription. PremiumScreen uses this to
  /// swap the "Manage subscription" Customer Center button, a surface
  /// full of renewal language, for a plain "yours for life" line: a
  /// non-consumable cannot lapse and has nothing to manage.
  ///
  /// Both lifetime products count (see kLifetimeProductIds): someone who
  /// bought at the welcome or sale price, or through a creator's Apple
  /// offer code, owns exactly the same thing.
  bool isLifetimeEntitled(CustomerInfo info) {
    final e = info.entitlements.all[entitlementId];
    if (e == null || !e.isActive) return false;
    return isLifetimeProductId(e.productIdentifier);
  }

  /// Opens Apple's own sheet for redeeming an offer code, the way a
  /// creator's code is used from inside the app (the creator's link opens
  /// the same thing in the App Store). Apple takes the code and the payment
  /// itself; a redeemed purchase then arrives through the SDK's normal
  /// CustomerInfo updates like any other. iOS only: Google Play codes
  /// cannot carry a discount, so Android has no such button. False when
  /// the SDK is not set up or the sheet could not be shown.
  Future<bool> presentCodeRedemptionSheet() async {
    if (!_configured || kIsWeb) return false;
    if (defaultTargetPlatform != TargetPlatform.iOS) return false;
    try {
      await Purchases.presentCodeRedemptionSheet();
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('PurchaseService.presentCodeRedemptionSheet failed: $e');
      }
      return false;
    }
  }

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
    // The SDK must be configured before this is called, and this guard is
    // not defensive tidiness: calling into RevenueCat unconfigured reaches
    // `Self.sharedInstance` in the native layer, which is a Swift
    // `fatalError`. That terminates the process. A Dart try/catch cannot
    // catch it, so the app does not show an error, it DIES.
    //
    // It is reachable in practice. configure() deliberately swallows every
    // exception so a store hiccup can never block launch, which means
    // _configured can legitimately be false at runtime, and the paywall
    // deliberately keeps Restore tappable in exactly that state so someone
    // who already paid is never stranded. App Review taps Restore as a
    // matter of routine. Every sibling method here already has this guard;
    // these two were the only ones without it.
    if (!_configured) return PurchaseOutcome.failure('not_configured');
    try {
      final result = await Purchases.purchase(PurchaseParams.package(package));
      return PurchaseOutcome.success(result.customerInfo);
    } on PlatformException catch (e) {
      final code = _safeErrorCode(e);
      if (code == PurchasesErrorCode.purchaseCancelledError) {
        return PurchaseOutcome.cancelled();
      }
      if (code == PurchasesErrorCode.paymentPendingError) {
        return PurchaseOutcome.pending();
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
    // See purchase() above: unconfigured, this is a native fatalError, not
    // a catchable Dart exception.
    if (!_configured) return PurchaseOutcome.failure('not_configured');
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

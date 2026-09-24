// A purchase the store holds for someone else to finish (a parent's Ask to
// Buy approval on iPhone, a cash payment Google Play lets people complete
// later) is not a failure. It used to come back as one, and the paywall said
// «تعذّرت العملية. حاول مرة أخرى.», which invites a second order for
// something that lands by itself once it completes.
//
// Runs the real PurchaseService against a stand-in for the native side, so
// the SDK is configured here, unlike purchase_service_guards_test.dart,
// which needs it unconfigured. Separate files, separate isolates.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/services/purchase_service.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

const _package = Package(
  r'$rc_lifetime',
  PackageType.lifetime,
  StoreProduct('growdaily_lifetime', '', '', 29.99, r'$29.99', 'USD'),
  PresentedOfferingContext('default', null, null),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('purchases_flutter');
  late PlatformException purchaseError;

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'purchasePackage') throw purchaseError;
      return null; // setupPurchases, setLogLevel and the like
    });
    await PurchaseService.instance.configure();
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  PlatformException storeError(PurchasesErrorCode code) =>
      PlatformException(code: '${code.index}', message: code.name);

  test('the stand-in native side configured the SDK', () {
    expect(PurchaseService.instance.isConfigured, isTrue);
  });

  test('a pending payment is pending: not cancelled, not a failure', () async {
    purchaseError = storeError(PurchasesErrorCode.paymentPendingError);
    final outcome = await PurchaseService.instance.purchase(_package);
    expect(outcome.pending, isTrue);
    expect(outcome.success, isFalse);
    expect(outcome.cancelled, isFalse);
    expect(outcome.errorMessage, isNull);
  });

  test('a cancel is still a silent cancel', () async {
    purchaseError = storeError(PurchasesErrorCode.purchaseCancelledError);
    final outcome = await PurchaseService.instance.purchase(_package);
    expect(outcome.cancelled, isTrue);
    expect(outcome.pending, isFalse);
  });

  test('a real store failure is still a failure', () async {
    purchaseError = storeError(PurchasesErrorCode.storeProblemError);
    final outcome = await PurchaseService.instance.purchase(_package);
    expect(outcome.success, isFalse);
    expect(outcome.pending, isFalse);
    expect(outcome.cancelled, isFalse);
    expect(outcome.errorMessage, isNotNull);
  });
}

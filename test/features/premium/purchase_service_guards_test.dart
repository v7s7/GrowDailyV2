// Calling RevenueCat before it is configured must not kill the app.
//
// ── Why this is not defensive tidiness ───────────────────────────────────
// purchase() and restore() were the only two public methods on
// PurchaseService without an `if (!_configured)` guard. Unconfigured, they
// reach `Self.sharedInstance` in the native layer, which is a Swift
// `fatalError`. That terminates the process: the Dart try/catch wrapped
// around the call cannot catch it, so the app does not show an error, it
// dies.
//
// And it is reachable. configure() deliberately swallows every exception so
// that a store problem can never block app launch, which means _configured
// can legitimately be false at runtime. The paywall then deliberately keeps
// Restore tappable in exactly that state, so somebody who already paid is
// never stranded without a way back. App Review taps Restore as a matter of
// routine.
//
// These tests run in an environment where the SDK was never configured,
// which is precisely the state the guard exists for.
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/services/purchase_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the SDK really is unconfigured here, or the rest proves nothing', () {
    expect(PurchaseService.instance.isConfigured, isFalse);
  });

  test('restore() refuses instead of reaching the native fatalError',
      () async {
    final outcome = await PurchaseService.instance.restore();
    expect(outcome.success, isFalse);
    expect(outcome.cancelled, isFalse);
    expect(outcome.errorMessage, 'not_configured',
        reason: 'the exact guard, not some other failure that happens to '
            'look the same: without it this call does not return at all');
  });

  test('restore() can be called repeatedly and stays harmless', () async {
    for (var i = 0; i < 3; i++) {
      final outcome = await PurchaseService.instance.restore();
      expect(outcome.success, isFalse);
    }
  });

  test('the read-only lookups were already guarded and still are', () async {
    // These four had the guard all along. Pinned so a future refactor cannot
    // quietly remove the pattern that purchase()/restore() were missing.
    expect(await PurchaseService.instance.getCustomerInfo(), isNull);
    expect(await PurchaseService.instance.getCurrentOffering(), isNull);
    expect(await PurchaseService.instance.logIn('u1'), isNull);
    expect(PurchaseService.instance.presentCustomerCenter(), completion(isFalse));
  });

  test('logOut() is a no-op rather than a crash', () async {
    await expectLater(PurchaseService.instance.logOut(), completes);
  });
}

// alarmChoiceProvider on an iPhone that has AlarmKit (iOS 26 or newer), with
// the alarm bridge answered by a stand-in. The permission decides whether
// «منبّه» is live or grey: grey only once it has been refused (Aziz,
// 2026-09-18, "gray only if user doesnt have ios 26, or it doesnt work for
// him"), and asked again whenever the app comes back to the front, which is
// where Settings sends people back from.
//
// A file of its own: AlarmService remembers for the whole process whether
// the bridge said alarms exist, and alarm_choice_test.dart asks it with no
// bridge at all.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/providers/alarm_choice_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.growdaily.v2/alarm');

  /// What the stand-in bridge answers for the alarm permission.
  var permission = 'notDetermined';

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      channel,
      (call) async => switch (call.method) {
        'isSupported' => true,
        'authorizationState' => permission,
        _ => null,
      },
    );
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<AlarmChoice> choiceWith(String state) async {
    permission = state;
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container.read(alarmChoiceProvider.future);
  }

  test('nobody asked yet: live, and the tap asks', () async {
    expect(await choiceWith('notDetermined'), AlarmChoice.available);
  });

  test('allowed: live', () async {
    expect(await choiceWith('authorized'), AlarmChoice.available);
  });

  test('refused: grey', () async {
    expect(await choiceWith('denied'), AlarmChoice.permissionDenied);
  });

  testWidgets('allowed again in Settings: live once the app is back in front',
      (tester) async {
    permission = 'denied';
    final container = ProviderContainer();
    // Held open, as an open sheet's watch holds it.
    final sub = container.listen(alarmChoiceProvider, (_, __) {});
    expect(await container.read(alarmChoiceProvider.future),
        AlarmChoice.permissionDenied);

    // Off to Settings, switched on there, and back.
    permission = 'authorized';
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(await container.read(alarmChoiceProvider.future),
        AlarmChoice.permissionDenied,
        reason: 'nothing is asked while the app is away');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(await container.read(alarmChoiceProvider.future),
        AlarmChoice.available);

    // A widget test checks, before its tearDown runs, that no timer is
    // left and the platform override is gone.
    sub.close();
    container.dispose();
    await tester.pump(const Duration(seconds: 1));
    debugDefaultTargetPlatformOverride = null;
  });
}

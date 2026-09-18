// What the reminder editors offer under «طريقة التنبيه» on each kind of
// phone (alarmChoiceProvider).
//
// Reported 2026-09-18: an iPhone 14 not yet updated to iOS 26 showed
// neither «إشعار» nor «منبّه», because the choice was hidden wherever
// AlarmKit was missing, and nothing said an update would bring it. An
// iPhone older than iOS 26 now draws the choice and explains the alarm
// cell; an iPhone already on iOS 26 whose alarm bridge did not answer
// still hides it, because telling that phone to update would be false.
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/providers/alarm_choice_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('iosMajorVersion', () {
    test('reads the major version out of dart:io\'s iOS string', () {
      expect(iosMajorVersion('Version 18.6 (Build 22G86)'), 18);
      expect(iosMajorVersion('Version 17.0 (Build 21A328)'), 17);
      expect(iosMajorVersion('Version 26.0.1 (Build 23A8464)'), 26);
      expect(iosMajorVersion('16.7.10'), 16);
    });

    test('is null when the string holds no number', () {
      expect(iosMajorVersion(''), isNull);
      expect(iosMajorVersion('Version unknown'), isNull);
    });
  });

  group('alarmChoiceWithoutAlarmKit', () {
    test('an iPhone older than iOS 26 is told what the alarm needs', () {
      for (final major in [15, 16, 17, 18]) {
        expect(alarmChoiceWithoutAlarmKit(major), AlarmChoice.needsNewerIos,
            reason: 'iOS $major');
      }
    });

    test('iOS 26 or newer without AlarmKit keeps the choice hidden', () {
      expect(alarmChoiceWithoutAlarmKit(26), AlarmChoice.hidden);
      expect(alarmChoiceWithoutAlarmKit(27), AlarmChoice.hidden);
    });

    test('a version it cannot read says nothing', () {
      expect(alarmChoiceWithoutAlarmKit(null), AlarmChoice.hidden);
    });
  });

  group('alarmChoiceProvider', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('Android offers both, with no permission to wait on', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(await container.read(alarmChoiceProvider.future),
          AlarmChoice.available);
    });

    // A test runs on a Mac with the iOS look switched on: the bridge does
    // not answer and the version dart:io reports is the Mac's, so the
    // provider must not read it as an iPhone's.
    test('the iOS look on a machine that is not an iPhone stays hidden',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(await container.read(alarmChoiceProvider.future),
          AlarmChoice.hidden);
    });
  });
}

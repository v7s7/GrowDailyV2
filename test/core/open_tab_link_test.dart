import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/constants/deep_links.dart';
import 'package:grow_daily_v2/core/providers/nav_layout_provider.dart';

/// The link a Lock Screen control taps.
///
/// Asked for by Aziz on 2026-09-10, pointing at the stock flashlight and
/// voice-memo buttons at the bottom of the lock screen: open the habit board
/// or the tasks page from there. One parameterised link rather than a path
/// per page, because the destinations are exactly NavTab's ids and a second
/// list of names that must agree with that enum is a list that will
/// eventually disagree with it. These tests are that agreement.
void main() {
  group('parseOpenTabLink', () {
    test('the custom scheme puts the target in the host', () {
      expect(parseOpenTabLink(Uri.parse('growdaily://open?tab=grid')), 'grid');
    });

    test('an https link puts it in the path', () {
      expect(
        parseOpenTabLink(Uri.parse('https://$linkHost/open?tab=matrix')),
        'matrix',
      );
    });

    test('the id is lower-cased and trimmed', () {
      expect(parseOpenTabLink(Uri.parse('growdaily://open?tab=GRID')), 'grid');
    });

    test('another link shape is not one of these', () {
      expect(parseOpenTabLink(Uri.parse('growdaily://matrix/add')), isNull);
      expect(parseOpenTabLink(Uri.parse('growdaily://reset?oobCode=x')), isNull);
      expect(
        parseOpenTabLink(Uri.parse('https://$linkHost/join/A8GEL7')),
        isNull,
      );
    });

    test('no tab is not a destination', () {
      expect(parseOpenTabLink(Uri.parse('growdaily://open')), isNull);
      expect(parseOpenTabLink(Uri.parse('growdaily://open?tab=')), isNull);
    });

    test('a foreign scheme is refused', () {
      expect(parseOpenTabLink(Uri.parse('otherapp://open?tab=grid')), isNull);
    });
  });

  group('the ids the Swift side hard-codes', () {
    // ControlDestination in ios/GrowDailyWidget/GrowDailyControls.swift
    // spells these two by hand, because an extension cannot read the Dart
    // enum. If either is ever renamed, this fails here rather than shipping
    // a control that opens the app on the wrong page.
    test('grid and matrix are both real tabs', () {
      expect(NavTab.byId('grid'), NavTab.grid);
      expect(NavTab.byId('matrix'), NavTab.matrix);
    });

    test('every tab id survives the round trip', () {
      for (final tab in NavTab.values) {
        expect(
          NavTab.byId(parseOpenTabLink(openTabUrl(tab.id))),
          tab,
          reason: tab.id,
        );
      }
    });

    test('an id this build does not know resolves to nothing, not a crash', () {
      // A control left on the lock screen after its tab was removed. The
      // handler opens the app on its usual tab instead of doing nothing.
      expect(parseOpenTabLink(Uri.parse('growdaily://open?tab=focus')),
          'focus');
      expect(NavTab.byId('focus'), isNull);
    });
  });
}

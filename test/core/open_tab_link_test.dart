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
    // ControlDestination in ios/Runner/ControlIntents.swift spells grid and
    // matrix by hand, and the Lock Screen widgets' lockScreenOpenURL calls in
    // ios/GrowDailyWidget/GrowDailyWidget.swift spell grid, matrix and
    // rooms, because Swift cannot read the Dart enum. If any is ever
    // renamed, this fails here rather than shipping a control or a widget
    // that opens the app on the wrong page.
    test('grid, matrix and rooms are all real tabs', () {
      expect(NavTab.byId('grid'), NavTab.grid);
      expect(NavTab.byId('matrix'), NavTab.matrix);
      expect(NavTab.byId('rooms'), NavTab.rooms);
    });

    test('the widget spelling, growdaily://open?tab=, resolves', () {
      for (final id in ['grid', 'matrix', 'rooms']) {
        expect(parseOpenTabLink(Uri.parse('growdaily://open?tab=$id')), id);
      }
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

    test('the built link is https, the spelling a control hands over', () {
      // ControlIntents.swift builds this same https link and hands it to the
      // app directly. It was https because OpenURLIntent in a ControlWidget
      // accepts a universal link only; the scheme also tells the analytics
      // a control apart from a Lock Screen widget, which sends growdaily://.
      final url = openTabUrl('grid');
      expect(url.scheme, 'https');
      expect(url.host, linkHost);
      expect(url.path, openPath);
    });

    test('the quick-add flag rides on the same link shape', () {
      final url = openTabUrl('matrix', quickAdd: true);
      expect(parseOpenTabLink(url), 'matrix');
      expect(openTabLinkWantsAdd(url), isTrue);
    });

    test('a plain open link does not want the add sheet', () {
      expect(openTabLinkWantsAdd(openTabUrl('grid')), isFalse);
      expect(
        openTabLinkWantsAdd(Uri.parse('https://\$linkHost/open?tab=matrix')),
        isFalse,
      );
    });

    test('the add flag alone, on a link that is not ours, is nothing', () {
      expect(
        openTabLinkWantsAdd(Uri.parse('https://\$linkHost/join/A8GEL7?add=1')),
        isFalse,
      );
    });

    test('an id this build does not know resolves to nothing, not a crash', () {
      // A control left on the lock screen after its tab was removed. The
      // handler opens the app on its usual tab instead of doing nothing.
      expect(parseOpenTabLink(Uri.parse('growdaily://open?tab=focus')),
          'focus');
      expect(NavTab.byId('focus'), isNull);
    });
  });

  group('isRepeatOpenLink', () {
    // app_links hands the link that launched the app over twice: once as the
    // launch link, then again to the stream main.dart listens to next.
    final at = DateTime(2026, 9, 21, 9, 0, 0);
    final tasks = openTabUrl('matrix').toString();

    test('the replayed copy a moment later is a repeat', () {
      expect(
        isRepeatOpenLink(
          link: tasks,
          now: at.add(const Duration(milliseconds: 300)),
          lastLink: tasks,
          lastAt: at,
        ),
        isTrue,
      );
    });

    test('the first link ever is not', () {
      expect(
        isRepeatOpenLink(link: tasks, now: at, lastLink: null, lastAt: null),
        isFalse,
      );
    });

    test('another page asked for straight after is not', () {
      expect(
        isRepeatOpenLink(
          link: openTabUrl('grid').toString(),
          now: at.add(const Duration(milliseconds: 300)),
          lastLink: tasks,
          lastAt: at,
        ),
        isFalse,
      );
    });

    test('Add Task after Tasks is not, though both open Tasks', () {
      expect(
        isRepeatOpenLink(
          link: openTabUrl('matrix', quickAdd: true).toString(),
          now: at.add(const Duration(milliseconds: 300)),
          lastLink: tasks,
          lastAt: at,
        ),
        isFalse,
      );
    });

    test('the same control tapped again later is heard', () {
      expect(
        isRepeatOpenLink(
          link: tasks,
          now: at.add(kRepeatOpenLinkWindow),
          lastLink: tasks,
          lastAt: at,
        ),
        isFalse,
      );
    });
  });
}

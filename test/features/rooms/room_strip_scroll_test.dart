// The room strip is one line of week columns that scrolls sideways, opens
// on the newest month, and never wraps.
//
// Aziz, 2026-09-08, with two screenshots of the same 43-day room. On his
// phone September's second week had wrapped onto a line of its own under
// the rest: a lone column with «اليوم» beside it and a card twice the
// height. On the simulator everything sat on one line. "It should never be
// like this double row, make it always the same as the second image, but
// scrollable": opened on the recent month whether the phone is in Arabic or
// English, with the older months a finger slide away.
//
// Pumps the real RoomStrip with a real room and participant (no Firestore,
// nothing else on the screen), at the 274pt the card leaves the strip on a
// 402pt phone and at narrower widths, in both directions.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/rooms/models/room_model.dart';
import 'package:grow_daily_v2/features/rooms/screens/room_detail_screen.dart'
    show RoomStrip, RoomStripMonthLabel;

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ar');
    await initializeDateFormatting('en');
  });

  // Mirrors RoomStrip._labelInset + _labelGap and _todayInset + _labelGap:
  // the reserve before the first column where «البداية» sits and the
  // narrower one after the last where «اليوم» sits. The assertions below
  // place the labels relative to the viewport's edges, so these must match.
  const startReserve = 64.0 + 7.0;
  const todayReserve = 32.0 + 7.0;

  final today = DateTime.now().effectiveDay;

  /// An open room that started [days] days ago and is still running, with
  /// one member in it since the first day.
  RoomModel roomOf(int days) {
    final start = today.subtract(Duration(days: days - 1));
    return RoomModel(
      code: 'STRIP1',
      name: 'الالتزام',
      createdBy: 'me',
      createdByName: 'Aziz',
      createdAt: start,
      habitMode: RoomHabitMode.own,
      duration: RoomDuration.open,
      startDate: start,
    );
  }

  RoomParticipant memberOf(RoomModel room) => RoomParticipant(
        uid: 'me',
        displayName: 'Aziz',
        // No catalog character: nothing here draws a face anyway.
        characterId: 'none',
        joinedAt: room.startDate,
        lastUpdated: today,
        linkedHabitIds: const ['h1'],
        linkedHabitNames: const ['الوتر'],
      );

  Widget app({
    required RoomModel room,
    required bool isAr,
    required double width,
  }) =>
      MaterialApp(
        locale: Locale(isAr ? 'ar' : 'en'),
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: GameTheme.light,
        home: Scaffold(
          // Inside a vertical list, like the leaderboard, so a sideways
          // slide has to win its arena against a vertical scrollable.
          body: ListView(
            children: [
              Center(
                child: SizedBox(
                  width: width,
                  child: RoomStrip(
                    room: room,
                    participant: memberOf(room),
                    isYou: true,
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  /// Pumps the strip and returns every layout error the framework reported.
  Future<List<String>> pumpStrip(
    WidgetTester tester, {
    required int days,
    required bool isAr,
    double width = 274,
  }) async {
    final errors = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (d) => errors.add(d.exceptionAsString());
    addTearDown(() => FlutterError.onError = previous);
    await tester.binding.setSurfaceSize(const Size(402, 874));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app(room: roomOf(days), isAr: isAr, width: width));
    await tester.pump();
    return errors;
  }

  Finder todayLabel(bool isAr) =>
      find.text(isAr ? 'اليوم' : 'Today', skipOffstage: false);
  Finder startLabel(bool isAr) =>
      find.textContaining(isAr ? 'البداية' : 'Start', skipOffstage: false);
  Rect stripRect(WidgetTester t) => t.getRect(find.byType(RoomStrip));

  /// Whether [r] lies inside the strip's viewport sideways. Labels outside
  /// it are laid out but clipped, so their rects say where they are.
  bool inView(Rect r, Rect viewport) =>
      r.left >= viewport.left - 0.5 && r.right <= viewport.right + 0.5;

  for (final isAr in const [true, false]) {
    final lang = isAr ? 'ar' : 'en';

    group('one line, never two ($lang)', () {
      for (final width in const [180.0, 274.0, 338.0]) {
        testWidgets('a 90-day room at ${width.toInt()}pt', (tester) async {
          final errors =
              await pumpStrip(tester, days: 90, isAr: isAr, width: width);
          expect(errors, isEmpty, reason: 'the strip must never overflow');
          // Every month name sits on the same line: the columns did not wrap.
          final labels = find.byType(RoomStripMonthLabel).evaluate();
          expect(labels.length, greaterThanOrEqualTo(3),
              reason: 'ninety days touch at least three months');
          final labelTops = labels
              .map((e) => tester.getRect(find.byWidget(e.widget)).top)
              .toSet();
          expect(labelTops, hasLength(1),
              reason: 'month names on different lines mean wrapped columns');
          // And the strip is exactly as wide as the room it was given, not
          // as wide as its content.
          expect(stripRect(tester).width, closeTo(width, 0.5));
        });
      }
    });

    group('opens on the newest month ($lang)', () {
      testWidgets('today is on screen, the start label stands down',
          (tester) async {
        await pumpStrip(tester, days: 90, isAr: isAr);
        final viewport = stripRect(tester);
        final todayRect = tester.getRect(todayLabel(isAr));
        expect(inView(todayRect, viewport), isTrue,
            reason: 'the newest month must be what a person sees first');
        // Not merely off screen: NOT BUILT. The reserve «البداية 07/28» sits
        // in is the first content the viewport hides, and the label is cut
        // from its outer side, so in an RTL line the Arabic word goes first
        // and «07/» is left floating beside the ring with nothing to say it
        // is a date. Aziz screenshotted exactly that fragment and asked what
        // it meant. A label that cannot be shown whole is not shown at all;
        // one slide toward the older months brings it back (next test).
        expect(startLabel(isAr), findsNothing,
            reason: 'ninety days cannot fit, so a partly hidden start label '
                'must not render as a fragment');
        // The «اليوم» label hugs the trailing edge, which is where the last
        // column lands when the viewport rests at the content's end: the
        // left in Arabic, the right in English.
        if (isAr) {
          expect(todayRect.right,
              closeTo(viewport.left + todayReserve - 7, 1.0));
        } else {
          expect(todayRect.left,
              closeTo(viewport.right - todayReserve + 7, 1.0));
        }
      });

      testWidgets('a slide toward the older months reaches the start',
          (tester) async {
        await pumpStrip(tester, days: 90, isAr: isAr);
        final viewport = stripRect(tester);
        // Older months lie past the leading edge (the right in Arabic), so
        // the finger moves the other way to pull them in.
        await tester.drag(
          find.byType(RoomStrip),
          Offset(isAr ? -2000 : 2000, 0),
        );
        await tester.pumpAndSettle();
        expect(inView(tester.getRect(startLabel(isAr)), viewport), isTrue,
            reason: 'the first day and its «البداية» label must come into view');
        // And the far end's label has stood down in its turn, for the same
        // reason «البداية» does at rest: a pinned label whose reserve the
        // viewport is cutting into would render as a fragment.
        expect(todayLabel(isAr), findsNothing,
            reason: 'ninety days still cannot fit, so today has left and its '
                'label must not be left behind as a fragment');
        // The drag was a scroll, not a tap: the strip's tap opens the
        // participant calendar, which must not appear.
        expect(find.byType(BottomSheet), findsNothing);
      });
    });

    group('a room that fits ($lang)', () {
      testWidgets('shows both ends and keeps its first column at the start',
          (tester) async {
        await pumpStrip(tester, days: 10, isAr: isAr);
        final viewport = stripRect(tester);
        final startRect = tester.getRect(startLabel(isAr));
        final todayRect = tester.getRect(todayLabel(isAr));
        expect(inView(startRect, viewport), isTrue);
        expect(inView(todayRect, viewport), isTrue);
        // The first column sits at the leading edge, just past the label's
        // reserve, and «البداية» hugs it from the leading side, 7pt away:
        // the shape the strip had before it could scroll, which a short room
        // never needs to. (The label's near edge is its END edge in
        // directional terms: the left of the text in Arabic, the right in
        // English.)
        if (isAr) {
          expect(startRect.left,
              closeTo(viewport.right - startReserve + 7, 1.0));
        } else {
          expect(startRect.right,
              closeTo(viewport.left + startReserve - 7, 1.0));
        }
        // Nothing to scroll: a slide leaves everything where it was.
        await tester.drag(find.byType(RoomStrip), const Offset(-300, 0));
        await tester.pumpAndSettle();
        expect(tester.getRect(startLabel(isAr)), startRect);
        expect(tester.getRect(todayLabel(isAr)), todayRect);
      });
    });
  }

  testWidgets('six week columns fit the room the leaderboard card leaves',
      (tester) async {
    // PBYAS5 on the simulator, 2026-09-08: 14 August to 8 September is six
    // columns (four August, two September). The card's row leaves the strip
    // about 245pt on a 402pt phone once the avatar and the percentage have
    // theirs, and with a 71pt reserve on BOTH sides the content ran 14pt
    // over, the viewport rested on the newest end, and the first letter of
    // «البداية» was cut off. Both labels must be whole at that width.
    final start = DateTime(2026, 8, 14);
    final room = RoomModel(
      code: 'PBYAS5',
      name: 'اذكار الصباح',
      createdBy: 'me',
      createdByName: 'Aziz',
      createdAt: start,
      habitMode: RoomHabitMode.own,
      duration: RoomDuration.open,
      startDate: start,
    );
    final errors = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (d) => errors.add(d.exceptionAsString());
    addTearDown(() => FlutterError.onError = previous);
    await tester.binding.setSurfaceSize(const Size(402, 874));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app(room: room, isAr: true, width: 245));
    await tester.pump();
    expect(errors, isEmpty);
    final viewport = stripRect(tester);
    final startRect = tester.getRect(startLabel(true));
    // The test font is wider than the device's, so only the label's near
    // edge is checked against the viewport: it sits 7pt off the first
    // column, and the column sits at the leading edge, inside its reserve.
    expect(startRect.left, closeTo(viewport.right - startReserve + 7, 1.0));
    expect(inView(tester.getRect(todayLabel(true)), viewport), isTrue);
    // Nothing hidden either way, so a slide moves nothing.
    await tester.drag(find.byType(RoomStrip), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(tester.getRect(startLabel(true)), startRect);
  });

  testWidgets('a day the room was paused on is drawn, not left as a hole',
      (tester) async {
    // PBYAS5, 2026-09-08: after its accidental pause was clipped, a 3-6
    // September span remained and those four cells painted nothing. Aziz:
    // "some days are missing in September, this should never happen". A
    // paused day now carries the same faint dash a member's own stand-down
    // does, so the column stays whole and the day reads as "not counted".
    final room = roomOf(30);
    final from = today.subtract(const Duration(days: 12));
    final to = today.subtract(const Duration(days: 9));
    final paused = RoomModel(
      code: room.code,
      name: room.name,
      createdBy: room.createdBy,
      createdByName: room.createdByName,
      createdAt: room.createdAt,
      habitMode: room.habitMode,
      duration: room.duration,
      startDate: room.startDate,
      pausedSpans: [(from: from.toDateKey(), to: to.toDateKey())],
    );
    await tester.binding.setSurfaceSize(const Size(402, 874));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: GameTheme.light,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 274,
              child: RoomStrip(
                room: paused,
                participant: memberOf(paused),
                isYou: true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    // The dash is a CustomPaint with the stand-down painter; a miss is a
    // CustomPaint with the cross painter. Four paused days, four dashes.
    final dashes = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint, skipOffstage: false))
        .where((w) => '${w.painter.runtimeType}'.contains('StandDownBar'))
        .length;
    expect(dashes, 4, reason: 'every paused day is drawn as stood down');
  });

  testWidgets('a year-long open room draws the whole year, not ninety days',
      (tester) async {
    // The cap was 90 while the strip wrapped, because every month cost a
    // line. Scrolling costs nothing, so an open room now shows a year.
    await pumpStrip(tester, days: 400, isAr: true);
    final names = find.byType(RoomStripMonthLabel).evaluate().length;
    expect(names, inInclusiveRange(12, 13),
        reason: '366 days touch twelve or thirteen months');
  });

  testWidgets('the strip is one button, and it does not read out its own axis',
      (tester) async {
    // The strip is a picture of days wrapped in a Semantics button. Without
    // excludeSemantics every descendant merged into that button's label, so
    // it announced its caption and then every month name and every week
    // number on the row: on this 400-day room that is a year of digits
    // standing between a listener and the next member on the board. None of
    // it is usable spoken, and the numbers it draws are already said by the
    // row around it (day count, percentage, streak).
    final handle = tester.ensureSemantics();
    await pumpStrip(tester, days: 400, isAr: true);
    // The button still says what tapping it does.
    expect(
      find.bySemanticsLabel(const S(Locale('ar')).roomStripOpenCalendar),
      findsOneWidget,
    );
    // And says nothing else. The marker is still DRAWN, it is just not part
    // of the button's announcement.
    //
    // «اليوم» rather than «البداية» for the on-screen half: a 400-day room
    // rests on its newest end, so the today marker is the one in view and
    // the start label has stood down (see the "stands down" tests above).
    expect(todayLabel(true), findsWidgets, reason: 'still on screen');
    expect(find.bySemanticsLabel(RegExp('البداية')), findsNothing);
    expect(find.bySemanticsLabel(RegExp('اليوم')), findsNothing);
    handle.dispose();
  });
}

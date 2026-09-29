// What main.dart's Room Race widget listener is told (roomRaceWidgetStateProvider).
//
// main.dart writes a null snapshot to the widget as "no room". A cold start
// passes through nulls that only mean "still loading", and writing those
// cleared the Home Screen to «ما في غرفة شغالة» on every launch. Skipping
// them inside the listener was the first fix, and review found the trap in
// it: a null followed by another null does not notify, so the settled null
// after the loading one never reached the listener, and a room that had
// ended or been left while the app was closed stayed on the Home Screen.
// These pin that the loading flag is part of the value, so the settled
// null arrives as its own change.
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/rooms/notifiers/room_race_widget_state.dart';
import 'package:grow_daily_v2/features/rooms/notifiers/rooms_notifier.dart';

class _User extends Fake implements User {
  @override
  String get uid => 'me';
}

void main() {
  late StreamController<User?> auth;
  late StreamController<List<String>> codes;
  late StreamController<List<String>> starred;

  ProviderContainer container() => ProviderContainer(overrides: [
        authStateProvider.overrideWith((ref) => auth.stream),
        myRoomCodesProvider.overrideWith((ref) => codes.stream),
        myStarredRoomCodesProvider.overrideWith((ref) => starred.stream),
        // No room ever picked: the case under test is the null.
        myRoomRaceSnapshotProvider.overrideWith((ref) => null),
      ]);

  setUp(() {
    auth = StreamController<User?>();
    codes = StreamController<List<String>>();
    starred = StreamController<List<String>>();
  });

  // Not awaited: a controller nobody ever listened to (the room codes of a
  // signed-out test) completes its close only once someone does.
  tearDown(() {
    auth.close();
    codes.close();
    starred.close();
  });

  test('the null after loading reaches the listener as its own change',
      () async {
    final c = container();
    addTearDown(c.dispose);
    final seen = <bool>[];
    c.listen(roomRaceWidgetStateProvider, (_, next) => seen.add(next.loading),
        fireImmediately: true);

    expect(seen, [true], reason: 'a cold start: nothing has arrived');

    auth.add(_User());
    await pumpEventQueue();
    expect(seen.last, isTrue, reason: 'signed in, room codes not yet');

    codes.add(const []);
    starred.add(const []);
    await pumpEventQueue();
    expect(seen.last, isFalse,
        reason: 'no rooms at all is settled, so the widget is cleared');
    expect(c.read(roomRaceWidgetStateProvider).snapshot, isNull);
  });

  test('signed out is settled at once', () async {
    final c = container();
    addTearDown(c.dispose);
    c.listen(roomRaceWidgetStateProvider, (_, __) {}, fireImmediately: true);
    auth.add(null);
    await pumpEventQueue();
    expect(c.read(roomRaceWidgetStateProvider).loading, isFalse);
  });

  test('a room list that failed to load does not hold the widget forever',
      () async {
    final c = container();
    addTearDown(c.dispose);
    c.listen(roomRaceWidgetStateProvider, (_, __) {}, fireImmediately: true);
    auth.add(_User());
    codes.addError(StateError('offline'));
    starred.add(const []);
    await pumpEventQueue();
    expect(c.read(roomRaceWidgetStateProvider).loading, isFalse);
  });
}

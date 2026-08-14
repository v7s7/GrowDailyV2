// Room invite links.
//
// The reported bug: a shared invite "doesn't open when the user sends it".
// Cause was the link itself — `growdaily://join/CODE`. WhatsApp, iMessage and
// every other messenger only auto-linkify http/https, so a custom scheme
// arrives as plain grey text nobody can tap, and there is no fallback of any
// kind for someone who does not have the app yet. Invites now go out as
// https Universal Links.
//
// The two invariants that matter here:
//   - a NEW https invite resolves to the right code, and
//   - an OLD growdaily:// invite still resolves, because those links are
//     already sitting in people's chat histories and must not break.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/constants/deep_links.dart';
import 'package:grow_daily_v2/features/rooms/notifiers/rooms_notifier.dart';

void main() {
  group('roomJoinUrl', () {
    test('builds an https link on the configured host', () {
      final url = roomJoinUrl('pbyas5');
      expect(url.scheme, 'https');
      expect(url.host, linkHost);
      expect(url.path, '/join/PBYAS5');
    });

    test('upper-cases the code so a link matches typing it by hand', () {
      expect(roomJoinUrl('abc123').toString(), endsWith('/join/ABC123'));
    });

    test('round-trips through the parser', () {
      expect(parseRoomJoinLink(roomJoinUrl('PBYAS5')), 'PBYAS5');
    });
  });

  group('parseRoomJoinLink — https (the new invite)', () {
    test('reads the code', () {
      expect(
        parseRoomJoinLink(Uri.parse('https://grow-daily-339ef.web.app/join/PBYAS5')),
        'PBYAS5',
      );
    });

    test('normalizes case', () {
      expect(
        parseRoomJoinLink(Uri.parse('https://grow-daily-339ef.web.app/join/pbyas5')),
        'PBYAS5',
      );
    });

    test('accepts a host we have never seen', () {
      // Host is deliberately not checked: iOS only delivers an https URL that
      // already matched the associated-domains entitlement, and matching on
      // path keeps every invite shared from an older host working after a
      // move to a custom domain.
      expect(
        parseRoomJoinLink(Uri.parse('https://growdaily.app/join/PBYAS5')),
        'PBYAS5',
      );
    });

    test('survives a trailing slash and a query string', () {
      // Messengers and link-preview bots append tracking parameters freely.
      expect(
        parseRoomJoinLink(
            Uri.parse('https://grow-daily-339ef.web.app/join/PBYAS5?utm_source=wa')),
        'PBYAS5',
      );
    });

    test('ignores an unrelated path on our own host', () {
      expect(
        parseRoomJoinLink(Uri.parse('https://grow-daily-339ef.web.app/privacy')),
        isNull,
      );
    });

    test('ignores /join with no code', () {
      expect(
        parseRoomJoinLink(Uri.parse('https://grow-daily-339ef.web.app/join')),
        isNull,
      );
      expect(
        parseRoomJoinLink(Uri.parse('https://grow-daily-339ef.web.app/join/')),
        isNull,
      );
    });
  });

  group('parseRoomJoinLink — growdaily:// (invites already in chat history)', () {
    test('still reads the code', () {
      expect(parseRoomJoinLink(Uri.parse('growdaily://join/PBYAS5')), 'PBYAS5');
    });

    test('still normalizes case', () {
      expect(parseRoomJoinLink(Uri.parse('growdaily://join/pbyas5')), 'PBYAS5');
    });

    test('ignores the widget\'s own unrelated deep link', () {
      // growdaily://matrix/add belongs to the home-screen widget and must
      // never be force-fit into a room-code lookup.
      expect(parseRoomJoinLink(Uri.parse('growdaily://matrix/add')), isNull);
    });

    test('ignores a foreign scheme', () {
      expect(parseRoomJoinLink(Uri.parse('otherapp://join/PBYAS5')), isNull);
    });
  });
}

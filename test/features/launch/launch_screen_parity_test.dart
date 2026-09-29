// The phone's launch screen and the app's first frame are the same picture:
// plain cream.
//
// iOS draws LaunchScreen.storyboard before any app code runs, Android its
// own splash; the moment Flutter draws, LaunchCurtain takes over with the
// same cream, and Doum arrives with his line (Aziz, 2026-09-29: no
// "Let’s Grow Daily" first). The hand from one to the other is invisible
// only while every one of them is the same cream and none of them draws
// anything on it. Each lives in a different file with a different owner
// (Xcode's asset catalogue and storyboard, pubspec.yaml, Android's
// resources, AppDelegate.swift, Dart), so these check them against each
// other.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/features/launch/launch_curtain.dart';

/// The one pixel of a 1x1 RGB PNG (LaunchBackground's ground).
(int, int, int) _singlePixel(List<int> b) {
  final idat = <int>[];
  var o = 8;
  while (o < b.length) {
    final len = (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
    final type = String.fromCharCodes(b.sublist(o + 4, o + 8));
    if (type == 'IDAT') idat.addAll(b.sublist(o + 8, o + 8 + len));
    o += 12 + len;
  }
  final raw = zlib.decode(idat);
  // One scanline: the filter byte, then R, G, B (filter 0 or 1 leave a
  // single pixel's bytes as they are).
  return (raw[1], raw[2], raw[3]);
}

void main() {
  test('iOS draws the cream and nothing on it', () {
    final board =
        File('ios/Runner/Base.lproj/LaunchScreen.storyboard').readAsStringSync();
    final images = RegExp(r'<imageView[^>]*image="([^"]+)"')
        .allMatches(board)
        .map((m) => m.group(1))
        .toList();
    expect(images, ['LaunchBackground']);
    expect(
      Directory('ios/Runner/Assets.xcassets/LaunchImage.imageset').existsSync(),
      isFalse,
      reason: 'the words picture left the launch on 2026-09-29',
    );
  });

  test('Android draws the cream and nothing on it', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final splash = pubspec.substring(
      pubspec.indexOf('flutter_native_splash:\n'),
      pubspec.indexOf('  android_12:', pubspec.indexOf('flutter_native_splash:\n')),
    );
    expect(splash, isNot(contains('image:')));
    final layers = File('android/app/src/main/res/drawable/launch_background.xml')
        .readAsStringSync();
    expect(layers, isNot(contains('@drawable/splash')));
  });

  test('every ground is the curtain cream', () {
    final bg = _singlePixel(File(
      'ios/Runner/Assets.xcassets/LaunchBackground.imageset/background.png',
    ).readAsBytesSync());
    expect(bg, (
      (kLaunchGround.r * 255).round(),
      (kLaunchGround.g * 255).round(),
      (kLaunchGround.b * 255).round(),
    ));
    // And the cream iOS paints under the Flutter view until its first frame
    // (AppDelegate.paintLaunchGroundUnderFlutter).
    final delegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final under = RegExp(
      r'UIColor\(red: (\d+) / 255, green: (\d+) / 255, blue: (\d+) / 255',
    ).firstMatch(delegate)!;
    expect(
      [for (var i = 1; i <= 3; i++) int.parse(under.group(i)!)],
      [bg.$1, bg.$2, bg.$3],
    );
    final hex = kLaunchGround.toARGB32().toRadixString(16).substring(2);
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final splash = pubspec.substring(pubspec.indexOf('flutter_native_splash:\n'));
    expect(
      RegExp('color: "#([0-9A-Fa-f]{6})"')
          .allMatches(splash)
          .map((m) => m.group(1)!.toLowerCase()),
      everyElement(hex),
    );
  });
}

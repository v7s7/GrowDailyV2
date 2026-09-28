// Every pose the app draws exists, is bundled, and is the size SproutPose
// says it is. Layout reserves each pose's box from those numbers before the
// image decodes, so a file re-cut at another size must fail here rather than
// quietly squash or crop the sprout on screen.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/mascot/sprout.dart';

/// Width and height from a WebP file's header (lossless VP8L or extended
/// VP8X), without decoding it.
(int, int) webpSize(Uint8List b) {
  expect(String.fromCharCodes(b.sublist(0, 4)), 'RIFF');
  expect(String.fromCharCodes(b.sublist(8, 12)), 'WEBP');
  final chunk = String.fromCharCodes(b.sublist(12, 16));
  switch (chunk) {
    case 'VP8L':
      expect(b[20], 0x2f, reason: 'VP8L signature');
      final bits = b[21] | (b[22] << 8) | (b[23] << 16) | (b[24] << 24);
      return ((bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1);
    case 'VP8X':
      return (
        1 + (b[24] | (b[25] << 8) | (b[26] << 16)),
        1 + (b[27] | (b[28] << 8) | (b[29] << 16)),
      );
    default:
      fail('not a lossless or extended WebP: $chunk');
  }
}

void main() {
  final pubspec = File('pubspec.yaml').readAsStringSync();

  for (final pose in SproutPose.values) {
    test('${pose.name}: on disk, in pubspec.yaml, ${pose.width}x${pose.height}',
        () {
      final file = File(pose.asset);
      expect(file.existsSync(), isTrue, reason: pose.asset);
      expect(pubspec, contains('    - ${pose.asset}\n'),
          reason: 'a pose the app draws must be bundled');
      final (w, h) = webpSize(file.readAsBytesSync());
      expect((w, h), (pose.width, pose.height),
          reason: 'SproutPose must carry the file\'s real size');
    });
  }

  test('only the poses the app draws are bundled, not the whole folder', () {
    expect(pubspec, isNot(contains('    - assets/images/mascot/\n')));
    final listed = RegExp(r'^    - assets/images/mascot/(\S+)$', multiLine: true)
        .allMatches(pubspec)
        .map((m) => 'assets/images/mascot/${m.group(1)}')
        .toSet();
    expect(listed, SproutPose.values.map((p) => p.asset).toSet());
  });

  test('every pose is drawn at one shared scale', () {
    // The pipeline normalised the sheet's three row sizes, so the reference
    // pose at 150pt and any other pose at 150pt share points-per-pixel.
    for (final pose in SproutPose.values) {
      final size = Sprout.sizeOf(pose, 150);
      expect(size.height / pose.height, closeTo(150 / 767, 1e-9));
      expect(size.width / pose.width, closeTo(150 / 767, 1e-9));
    }
  });
}

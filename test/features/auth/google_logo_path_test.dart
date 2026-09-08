import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/auth/widgets/brand_logos.dart';

/// The Google mark is transcribed as SVG path strings and read by a small
/// parser written for this file. Both halves can fail silently: a typo in the
/// data, or a command the parser bails on, still yields a perfectly valid
/// [Path] that simply draws nothing. Nothing about the running app would look
/// broken; the button would just have a blank square where the logo goes, in
/// release, on someone else's phone.
///
/// So these assert the shape, not the mechanism.
void main() {
  group('Google logo path data', () {
    late List<Path> paths;

    setUp(() {
      paths = googleLogoPathsForTest();
    });

    test('parses into four non-empty sub-paths', () {
      expect(paths, hasLength(4));
      for (var i = 0; i < paths.length; i++) {
        final bounds = paths[i].getBounds();
        expect(
          bounds.isEmpty,
          isFalse,
          reason: 'sub-path $i parsed to an empty path, so it draws nothing',
        );
      }
    });

    test('fills the 48x48 viewBox it was authored in', () {
      var union = paths.first.getBounds();
      for (final p in paths.skip(1)) {
        union = union.expandToInclude(p.getBounds());
      }
      // Google's asset spans roughly x 2..45, y 2..46 inside a 48 box. Loose
      // bounds on purpose: this is here to catch a path that collapsed to a
      // point or ran away by an order of magnitude, not to pin the artwork.
      expect(union.left, closeTo(2, 1.5));
      expect(union.top, closeTo(2, 1.5));
      expect(union.right, closeTo(45, 2));
      expect(union.bottom, closeTo(46, 2));
    });

    test('each colour covers a distinct region of the mark', () {
      // The four arcs of the G must not land on top of each other, which is
      // what a parser that lost its current point between sub-paths would
      // produce.
      final centres = paths.map((p) => p.getBounds().center).toList();
      for (var i = 0; i < centres.length; i++) {
        for (var j = i + 1; j < centres.length; j++) {
          expect(
            (centres[i] - centres[j]).distance,
            greaterThan(1),
            reason: 'sub-paths $i and $j share a centre, so the mark is '
                'collapsed rather than drawn',
          );
        }
      }
    });

    test('the blue sub-path contains the crossbar of the G', () {
      // The blue arc is the right-hand side plus the horizontal bar, so it
      // must reach past the centre of the box on the x axis. A mis-parsed
      // relative/absolute command is the failure this catches.
      final blue = paths.first.getBounds();
      expect(blue.right, greaterThan(40));
      expect(blue.left, lessThan(25));
    });
  });
}

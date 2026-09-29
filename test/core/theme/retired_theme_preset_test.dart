// A retired preset opens on the one that replaced it
// (lib/core/theme/theme_preset.dart, ThemePresets.canonicalId).
//
// Rose & Ink left on 2026-09-27 when Burgundy took its place (Aziz: the two
// sat too close). A device or an account that saved `rose_ink` must land on
// Burgundy, not fall back to the free default, and the account sync must not
// refuse it as an id written by some newer build.
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/theme/theme_preset.dart';

void main() {
  test('rose_ink opens on Burgundy', () {
    expect(ThemePresets.canonicalId('rose_ink'), 'burgundy');
    expect(ThemePresets.byId('rose_ink').id, 'burgundy');
    expect(ThemePresets.isKnown('rose_ink'), isTrue);
  });

  test('Rose & Ink is gone, and Burgundy stands where it stood', () {
    final ids = ThemePresets.all.map((p) => p.id).toList();
    expect(ids, isNot(contains('rose_ink')));
    expect(
      ids.indexOf('burgundy'),
      ids.indexOf('ocean') + 1,
      reason: 'right after Turquoise (ocean)',
    );
    expect(ids, hasLength(12));
  });

  test('Burgundy is Premium, named as Aziz wrote it, and carries a label', () {
    final b = ThemePresets.byId('burgundy');
    expect(b.isPremium, isTrue);
    expect(b.nameAr, 'برقندي');
    expect(b.nameEn, 'Burgundy');
    // The accent is the fill behind every FilledButton, whose label is dark:
    // inside the band, the label stays readable.
    expect(accentColourFits(b.gold), isTrue);
  });

  test('every other id passes through untouched', () {
    for (final p in ThemePresets.all) {
      expect(ThemePresets.canonicalId(p.id), p.id);
    }
    expect(ThemePresets.canonicalId(ThemePresets.customId),
        ThemePresets.customId);
    expect(ThemePresets.canonicalId(null), isNull);
    expect(ThemePresets.isKnown('from_a_newer_build'), isFalse);
  });
}

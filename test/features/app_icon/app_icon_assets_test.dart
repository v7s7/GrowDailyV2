// The Home Screen icons the phone can actually show are files in the iOS
// asset catalogue, written by tool/icons/make_alternate_icons.py from
// tool/icons/app_icon_art.json. These checks keep the three in step with
// the Dart catalogue: an icon the picker offers but the bundle lacks would
// fail on the phone with nothing but an alert.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/features/app_icon/app_icon_art.dart';
import 'package:grow_daily_v2/features/app_icon/app_icon_catalog.dart';

const _sets = 'ios/Runner/Assets.xcassets/AlternateIcons';

/// Width and height from a PNG's IHDR chunk.
(int, int) _pngSize(File f) {
  final b = f.readAsBytesSync();
  int be(int o) => (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
  return (be(16), be(20));
}

void main() {
  test('every icon is a 1024 set in the bundle, the shipped one too', () {
    final expected = <String>{};
    final choices = [
      for (final shape in PlantShape.values)
        for (final colour in kIconColours) AppIconChoice(shape, colour.id),
      AppIconChoice.ramadan,
    ];
    for (final choice in choices) {
      // The shipped icon is AppIcon to iOS, but its set is kept under its
      // own name too: a phone that picked Doum's sprout while it was an
      // alternate (builds 84 to the swap) still reports that name.
      final name = choice.iosName ??
          'AppIcon-${choice.shape.name}-${choice.colourId}';
      expected.add(name);
      final png = File('$_sets/$name.appiconset/icon.png');
      expect(png.existsSync(), isTrue, reason: name);
      expect(_pngSize(png), (1024, 1024), reason: name);
      // Colour type 2 is RGB without alpha: an icon with transparency is
      // what App Store review rejects.
      expect(png.readAsBytesSync()[25], 2, reason: '$name has alpha');
      final contents = jsonDecode(
        File('$_sets/$name.appiconset/Contents.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final image = (contents['images'] as List).single as Map;
      expect(image['filename'], 'icon.png');
    }
    expect(expected, hasLength(101), reason: '100 shape-and-colour, 1 Ramadan');
    final onDisk = Directory(_sets)
        .listSync()
        .whereType<Directory>()
        .map((d) => d.uri.pathSegments.where((p) => p.isNotEmpty).last)
        .map((n) => n.replaceAll('.appiconset', ''))
        .toSet();
    expect(onDisk, expected, reason: 'a stale or missing set');
  });

  test('the shipped icon is the same art as its own picker tile', () {
    const shipped = AppIconChoice.shipped;
    expect(
      shipped,
      const AppIconChoice(PlantShape.sprout, 'doum'),
      reason: "Doum's sprout is the main icon since 2026-09-30",
    );
    expect(shipped.iosName, isNull);
    expect(
      AppIconChoice.fromIosName('AppIcon-sprout-doum'),
      shipped,
      reason: 'a phone that picked it as an alternate reads as the shipped',
    );
    // The generator renders AppIcon's source from the same art, in one
    // save: byte for byte the tile's own icon set.
    final twin =
        '$_sets/AppIcon-${shipped.shape.name}-${shipped.colourId}.appiconset';
    expect(
      File('assets/images/icon_app.png').readAsBytesSync(),
      File('$twin/icon.png').readAsBytesSync(),
      reason: 'rerun tool/icons/make_alternate_icons.py',
    );
    // And the scripts that build AppIcon and Android's icon from it name
    // the same icon as the app does.
    final primary = File('tool/icons/primary_icon.py').readAsStringSync();
    expect(primary, contains('SHAPE = "${shipped.shape.name}"'));
    expect(primary, contains('COLOUR = "${shipped.colourId}"'));
  });

  test('the Dart art and the JSON it was generated from agree', () {
    final art =
        jsonDecode(File('tool/icons/app_icon_art.json').readAsStringSync())
            as Map<String, dynamic>;
    final colours = (art['colours'] as List).cast<Map<String, dynamic>>();
    expect(
      colours.map((c) => c['id']).toSet(),
      kIconColours.map((c) => c.id).toSet(),
      reason: 'the JSON and the catalogue list different colours',
    );
    Color hex(String h) => Color(int.parse('FF${h.substring(1)}', radix: 16));
    // The bloom's flower: the sprout lifted toward white by the colour's own
    // lift, or the file's. Rounded half up, as the generator rounds.
    Color flower(String sprout, num t) {
      final s = hex(sprout);
      int lift(double v) {
        final byte = (v * 255).round();
        return (byte + (255 - byte) * t + 0.5).floor();
      }

      return Color.fromARGB(255, lift(s.r), lift(s.g), lift(s.b));
    }

    for (final c in colours) {
      final id = c['id'] as String;
      expect(appIconGround(id), hex(c['ground'] as String), reason: id);
      expect(appIconSprout(id), hex(c['sprout'] as String), reason: id);
      expect(
        appIconFlower(id),
        flower(
          c['sprout'] as String,
          (c['flowerLift'] ?? art['flowerLift']) as num,
        ),
        reason: '$id flower',
      );
    }
    // The light colours' flower is the plant's own ink.
    expect(appIconFlower('lavender'), appIconSprout('lavender'));
    expect(
      (art['shapes'] as Map).keys,
      PlantShape.values.map((s) => s.name).toList(),
    );

    // The Ramadan icon: its own colours and crescent, on the shape the
    // picker says it is.
    final ramadan = (art['seasonal'] as Map)[kRamadanIconId] as Map;
    expect(ramadan['shape'], AppIconChoice.ramadan.shape.name);
    expect(appIconSeasonalShape(kRamadanIconId), ramadan['shape']);
    expect(appIconGround(kRamadanIconId), hex(ramadan['ground'] as String));
    expect(appIconSprout(kRamadanIconId), hex(ramadan['sprout'] as String));
    expect(
      appIconMarkColour(kRamadanIconId),
      hex(ramadan['markColour'] as String),
    );
    expect(appIconMarkColour('emerald_gold'), isNull);
  });

  test('the Runner ships them all, with the bridge that sets them', () {
    final project =
        File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    expect(
      'ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS = YES;'
          .allMatches(project)
          .length,
      3,
      reason: 'Debug, Release and Profile',
    );
    expect(project, contains('AppIconBridge.swift in Sources'));
    expect(
      File('ios/Runner/AppDelegate.swift').readAsStringSync(),
      contains('AppIconBridge.register('),
    );
  });
}

// The admin tool's Habit ideas page and the app read the admin's edits the
// same way: both run scripts/admin_lookup/test/fixtures/ideas_cases.json,
// the admin through wording/ideas_rules.js (test/ideas.test.js) and the app
// here through resolveIdeas / resolvePlans. What the page previews before
// Publish is what phones show after it.
//
// The file's own `about` says what each part of a case means.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/l10n/ideas_edits.dart';
import 'package:grow_daily_v2/features/habits/catalog/habit_ideas.dart';
import 'package:grow_daily_v2/features/habits/catalog/habit_plans.dart';

const _fixture = 'scripts/admin_lookup/test/fixtures/ideas_cases.json';

void main() {
  final data = jsonDecode(File(_fixture).readAsStringSync()) as Map;

  group('ideas, as the admin page previews them', () {
    for (final raw in data['cases'] as List) {
      final c = raw as Map;
      test(c['name'] as String, () {
        final builtIn = [
          for (final i in c['builtIn'] as List)
            HabitIdea.fromJson(Map<String, Object?>.from(i as Map))!,
        ];
        final shown = resolveIdeas(builtIn, IdeasEdits.fromData(c['edits']));
        final expect_ = c['expect'] as Map;
        expect([for (final s in shown) s.idea.id], expect_['ids']);
        expect(
          [for (final s in shown) if (s.featured) s.idea.id],
          expect_['featured'],
        );
        final byId = {for (final s in shown) s.idea.id: s.idea};
        for (final e in (expect_['names'] as Map).entries) {
          expect(byId[e.key]?.nameAr, e.value, reason: '${e.key} name');
        }
        for (final e in ((expect_['fields'] as Map?) ?? const {}).entries) {
          final json = byId[e.key]!.toJson();
          for (final f in (e.value as Map).entries) {
            expect(json[f.key], f.value, reason: '${e.key}.${f.key}');
          }
        }
      });
    }
  });

  group('plans, as the admin page previews them', () {
    for (final raw in data['planCases'] as List) {
      final c = raw as Map;
      test(c['name'] as String, () {
        final plans = [
          for (final p in c['builtIn'] as List)
            HabitPlan(
              id: (p as Map)['id'] as String,
              nameAr: p['nameAr'] as String,
              nameEn: p['nameEn'] as String,
              descAr: p['descAr'] as String,
              descEn: p['descEn'] as String,
              color: Colors.green,
              icon: Icons.star,
              catalogIds: List<String>.from(p['catalogIds'] as List),
            ),
        ];
        final shown = resolvePlans(plans, PlansEdits.fromData(c['edits']));
        final expect_ = c['expect'] as Map;
        expect([for (final s in shown) s.plan.id], expect_['ids']);
        final byId = {for (final s in shown) s.plan.id: s};
        for (final e in (expect_['names'] as Map).entries) {
          expect(byId[e.key]?.nameAr, e.value, reason: '${e.key} name');
        }
        for (final e in ((expect_['fields'] as Map?) ?? const {}).entries) {
          final p = byId[e.key]!;
          final json = {
            'nameAr': p.nameAr,
            'nameEn': p.nameEn,
            'descAr': p.descAr,
            'descEn': p.descEn,
          };
          for (final f in (e.value as Map).entries) {
            expect(json[f.key], f.value, reason: '${e.key}.${f.key}');
          }
        }
      });
    }
  });
}

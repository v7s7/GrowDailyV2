import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import '../../../core/constants/game_constants.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import 'period_report_section.dart';

/// سجلّي: the one record page (2026-09-21).
///
/// It replaced three destinations that answered the same question at
/// different zooms: التقارير (the أسبوعي / شهري / سنوي report), خط الحياة
/// الزمني (every year) and خريطة التقدّم (every month). Aziz called the
/// Profile card that listed them "like 4 dashboards"; each question had two
/// or three homes and the totals disagreed. The tabs here are zoom levels of
/// one record, and a tap goes one level down (see [RecordTab]).
///
/// Opens on the tab it was last left on, «الكل» the first time: the whole
/// record first, then zoom in. A caller that means one tab (a bottom-bar pin,
/// a link) names it and is not overridden.
class RecordScreen extends StatelessWidget {
  final RecordTab? initialTab;

  const RecordScreen({super.key, this.initialTab});

  static const String _lastTabKey = 'record_last_tab';

  /// The tab سجلّي was last left on, or null. Read straight from the
  /// already-open settings box, so the first frame is already the right tab;
  /// a box that is not open (a test, a first launch mid-restore) falls back
  /// to «الكل».
  static RecordTab? rememberedTab() {
    try {
      if (!Hive.isBoxOpen(GameConstants.boxSettings)) return null;
      final raw = Hive.box<dynamic>(GameConstants.boxSettings).get(_lastTabKey);
      for (final tab in RecordTab.values) {
        if (tab.name == raw) return tab;
      }
    } catch (_) {
      // A remembered tab is a convenience; never let it cost the page.
    }
    return null;
  }

  static void _remember(RecordTab tab) {
    try {
      if (!Hive.isBoxOpen(GameConstants.boxSettings)) return;
      Hive.box<dynamic>(GameConstants.boxSettings).put(_lastTabKey, tab.name);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    return Scaffold(
      backgroundColor: gp.bg,
      appBar: AppBar(
        backgroundColor: gp.bg,
        surfaceTintColor: Colors.transparent,
        title: Text(
          s.recordTitle,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: gp.textPrimary,
          ),
        ),
      ),
      // No bottom padding here: the section owns its own scroll view, so
      // padding it from outside would clip the pinned chrome instead.
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: PeriodReportSection(
          initialTab: initialTab ?? rememberedTab() ?? RecordTab.all,
          onTabChanged: _remember,
        ),
      ),
    );
  }
}

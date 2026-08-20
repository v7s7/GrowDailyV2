import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import 'period_report_section.dart';

/// التقارير: the أسبوعي / شهري / سنوي report, and nothing else.
///
/// This screen exists because the report and the trophy cabinet are two
/// different questions and they were sharing one scroll. Under the period
/// tabs sat a lifetime achievements strip, a lifetime category share and a
/// notes preview, none of which change when you step from August to July,
/// so scrolling past the month you were reading into a row of medals made
/// the medals look like part of that month's result.
///
/// [ProgressHubScreen] keeps all of that, unchanged. What moved here is
/// only what a period stepper actually governs.
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

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
          s.reportsTitle,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: gp.textPrimary,
          ),
        ),
      ),
      // No bottom padding here: the section owns its own scroll view, so
      // padding it from outside would clip the pinned chrome instead.
      body: const Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: PeriodReportSection(),
      ),
    );
  }
}

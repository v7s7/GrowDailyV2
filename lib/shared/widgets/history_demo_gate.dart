import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/game_theme.dart';
import '../../features/grid/screens/monthly_heatmap_screen.dart'
    show heatColor;

/// The demo gate: what a free user sees when they reach for history the
/// free window doesn't cover.
///
/// This replaces a SnackBar that said, in effect, "no". The problem with a
/// text refusal on a paywall boundary is that it sells nothing: the person
/// was reaching for a real thing, and the answer they got carried no image
/// of it. This sheet shows the thing instead — a decorated month card full
/// of obviously-fake perfect data, stamped مثال so nobody mistakes it for
/// their own — and puts the unlock line underneath. Feel it, then buy it.
/// (Pattern borrowed from apps that gate reports this way; the owner chose
/// it over the snackbar deliberately.)
///
/// The preview is deterministic on purpose: no Random, one hand-picked
/// pattern, so the sheet renders identically every time and in tests.
Future<void> showHistoryDemoGate(BuildContext context) {
  HapticFeedback.selectionClick();
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _HistoryDemoGateSheet(),
  );
}

class _HistoryDemoGateSheet extends StatelessWidget {
  const _HistoryDemoGateSheet();

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        decoration: BoxDecoration(
          color: gp.surfaceHigh,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: gp.border,
                  borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
                ),
              ),
            ),
            const _DemoMonthCard(),
            const SizedBox(height: 16),
            Text(
              s.premiumBenefitHistoryTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: gp.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              s.historyLockedBody,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: gp.textSec, height: 1.45),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                HapticFeedback.selectionClick();
                Navigator.pop(context);
                Navigator.pushNamed(context, '/premium');
              },
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
              child: Text(s.demoGateCta),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                s.demoGateNotNow,
                style: TextStyle(fontSize: 12.5, color: gp.textSec),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The fake month: a heat grid good enough to want, wrong enough to never
/// be mistaken for the viewer's own data — every week ends strong and the
/// مثال ribbon sits straight across the corner.
class _DemoMonthCard extends StatelessWidget {
  const _DemoMonthCard();

  /// Heat levels for 5 weeks x 7 days, hand-picked: an encouraging month
  /// with texture (a few misses early, a perfect final stretch).
  static const List<int> _levels = [
    2, 3, 1, 4, 3, 2, 4, //
    3, 4, 2, 3, 4, 4, 3, //
    1, 2, 4, 4, 3, 4, 4, //
    4, 3, 4, 4, 4, 3, 4, //
    4, 4, 4, 4, 4, 4, 4, //
  ];

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final dark = gp.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
      child: Stack(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: gp.surface,
              borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
              border: Border.all(color: GameColors.gold.withOpacity(0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.auto_awesome_rounded,
                        size: 16, color: GameColors.gold),
                    const SizedBox(width: 8),
                    Text(
                      s.demoGateMonthTitle,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: gp.textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    const gap = 4.0;
                    final cell = (constraints.maxWidth - gap * 6) / 7;
                    return Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        for (final level in _levels)
                          Container(
                            width: cell,
                            height: cell * 0.62,
                            decoration: BoxDecoration(
                              color: Color.alphaBlend(
                                heatColor(level, dark),
                                gp.surface,
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: GameColors.gold.withOpacity(0.14),
                        borderRadius:
                            BorderRadius.circular(GameSpacing.pillRadius),
                        border: Border.all(
                          color: GameColors.gold.withOpacity(0.5),
                        ),
                      ),
                      child: Text(
                        s.demoGatePerfectStamp,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: GameColors.gold,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      // ASCII digits by design, like every stat in the app.
                      '31 / 31',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: GameColors.emerald,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // The مثال ribbon. PositionedDirectional so it hugs the trailing
          // top corner in both directions; the quarter-turn rotation reads
          // as a corner banner without needing a custom painter.
          PositionedDirectional(
            top: 10,
            end: -26,
            child: Transform.rotate(
              angle: Directionality.of(context) == TextDirection.rtl
                  ? -0.785398
                  : 0.785398,
              child: Container(
                width: 96,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(vertical: 3),
                color: GameColors.gold,
                child: Text(
                  s.demoGateExample,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF14100A),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

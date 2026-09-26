import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';

import '../../../core/extensions/datetime_ext.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/services/analytics_service.dart';
import '../../../core/services/share_service.dart';
import '../../../core/theme/game_theme.dart';
import '../../../core/utils/western_digits.dart';
import '../../../shared/widgets/app_logo.dart';
import '../../../shared/widgets/overlay_notice.dart';

/// A picture of a month or a year to post (Aziz, 2026-09-25, "do 3").
///
/// Who gets which, his call the same day: a MONTH for everyone, since a free
/// account can already see its last three months, and the YEAR for Premium,
/// the same line the free history draws everywhere else ("Your full
/// history"). The report screen decides that before it opens this; nothing
/// in here knows about Premium.
///
/// The look is GrowDaily's own and fixed (reporting-roadmap decision 3:
/// "share cards stay GrowDaily identity, dark, gold and emerald, real Arabic
/// type, decorated to be screenshot-worthy"): the brand gold and green, not
/// the viewer's theme, so every card anyone posts reads as the same app.
/// The numbers are the report's own (ReportHeaderCard's three, its
/// vocabulary too) and the colours are the map's own rule (heatLevel over
/// what each day owed), so the picture never says something the screen did
/// not. Facts only, no title crowning anyone (no-hero-titles).
///
/// 4:5, the portrait shape both a WhatsApp status and an Instagram post or
/// story take without cropping, drawn at [ShareProgressCard.size] and
/// captured at 3x: 1080 by 1350.
enum ShareCardScope { month, year }

class ShareCardData {
  final ShareCardScope scope;

  /// The first day of the month, or of the year.
  final DateTime period;

  /// The report's own period line: «سبتمبر 2026», or «2026».
  final String periodLabel;

  /// Green squares in the period (PeriodSummary.totalDone).
  final int totalDone;

  /// Already formatted the way ReportHeaderCard formats them, placeholder
  /// included, so the two can never print the same number differently.
  final String rate;
  final String bestDay;
  final int longestRun;

  /// Every day of the period that has begun, by dateKey, as a heat level
  /// 0..4 (the map's heatLevel). A day missing here has not happened yet.
  final Map<String, int> levels;

  const ShareCardData({
    required this.scope,
    required this.period,
    required this.periodLabel,
    required this.totalDone,
    required this.rate,
    required this.bestDay,
    required this.longestRun,
    required this.levels,
  });

  String get fileName => scope == ShareCardScope.month
      ? 'growdaily-${period.year}-${period.month.toString().padLeft(2, '0')}.png'
      : 'growdaily-${period.year}.png';
}

// The brand palette, fixed on purpose (see the file comment).
const Color _bgTop = Color(0xFF17221D);
const Color _bgBottom = Color(0xFF0C1310);
const Color _gold = GameColors.iconGold;
const Color _green = GameColors.iconSuccess;
const Color _ink = Color(0xFFF5F0E4);
const Color _inkSoft = Color(0xB3F5F0E4);
const Color _empty = Color(0x17FFFFFF);
const Color _notYet = Color(0x08FFFFFF);

/// A day's cell colour on the card: the map's own opacity ramp over the
/// brand green (monthly_heatmap_screen.dart's heatColor), an unlit day as a
/// faint wash, and a day still to come fainter again.
@visibleForTesting
Color shareCellColor(int? level) {
  if (level == null) return _notYet;
  if (level <= 0) return _empty;
  const opacities = [0.30, 0.50, 0.70, 0.92];
  return _green.withValues(alpha: opacities[level.clamp(1, 4) - 1]);
}

/// Saturday first, left to right: the map's month (month-grid-direction).
int _columnOf(DateTime day) => (day.weekday + 1) % 7;

class ShareProgressCard extends StatelessWidget {
  static const Size size = Size(360, 450);

  final ShareCardData data;

  const ShareProgressCard({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return SizedBox.fromSize(
      size: size,
      child: DefaultTextStyle(
        style: TextStyle(
          fontFamily: GameTextStyles.fontFamily,
          color: _ink,
          decoration: TextDecoration.none,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_bgTop, _bgBottom],
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: _gold.withValues(alpha: 0.35)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const AppLogo(size: 26, borderRadius: 7),
                    const SizedBox(width: 8),
                    const Text(
                      'GrowDaily',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _ink,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      data.periodLabel,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _gold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      toWesternDigits('${data.totalDone}'),
                      style: const TextStyle(
                        fontSize: 52,
                        fontWeight: FontWeight.w700,
                        height: 1.05,
                        color: _ink,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        s.monthlyStoryGreenSquares,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: _gold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: data.scope == ShareCardScope.month
                      ? _MonthCells(month: data.period, levels: data.levels)
                      : _YearCells(
                          year: data.period.year,
                          levels: data.levels,
                        ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _Stat(value: data.rate, label: s.reportsRate, color: _green),
                    _Stat(
                      value: data.bestDay,
                      label: s.heatmapBestDay,
                      color: _gold,
                    ),
                    _Stat(
                      value: toWesternDigits('${data.longestRun}'),
                      label: s.reportsLongestRun,
                      color: _ink,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  s.tagline,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11.5, color: _inkSoft),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  final Color color;

  const _Stat({required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            maxLines: 1,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 10.5, color: _inkSoft),
          ),
        ],
      ),
    );
  }
}

/// One month, Saturday in the left column and the days left to right in
/// both languages, each cell the map's colour with its date in it.
class _MonthCells extends StatelessWidget {
  final DateTime month;
  final Map<String, int> levels;

  const _MonthCells({required this.month, required this.levels});

  @override
  Widget build(BuildContext context) {
    final daysIn = DateTime(month.year, month.month + 1, 0).day;
    final lead = _columnOf(DateTime(month.year, month.month));
    final rows = ((lead + daysIn) / 7).ceil();
    const gap = 5.0;
    return LayoutBuilder(builder: (context, box) {
      final cell = [
        (box.maxWidth - gap * 6) / 7,
        (box.maxHeight - gap * (rows - 1)) / rows,
      ].reduce((a, b) => a < b ? a : b);
      return Center(
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var r = 0; r < rows; r++) ...[
                if (r > 0) const SizedBox(height: gap),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var c = 0; c < 7; c++) ...[
                      if (c > 0) const SizedBox(width: gap),
                      _dayCell(r * 7 + c - lead + 1, daysIn, cell),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      );
    });
  }

  Widget _dayCell(int dayNumber, int daysIn, double cell) {
    if (dayNumber < 1 || dayNumber > daysIn) {
      return SizedBox(width: cell, height: cell);
    }
    final day = DateTime(month.year, month.month, dayNumber);
    final level = levels[day.toDateKey()];
    return Container(
      width: cell,
      height: cell,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: shareCellColor(level),
        borderRadius: BorderRadius.circular(cell * 0.24),
      ),
      child: Text(
        '$dayNumber',
        style: TextStyle(
          fontSize: cell * 0.32,
          fontWeight: FontWeight.w600,
          color: (level ?? 0) >= 3 ? _bgBottom : _inkSoft,
        ),
      ),
    );
  }
}

/// A year as twelve small months, in the reading order of the language
/// (a year runs like the year strips, oldest at the start), each month's
/// days left to right, Saturday first.
class _YearCells extends StatelessWidget {
  final int year;
  final Map<String, int> levels;

  const _YearCells({required this.year, required this.levels});

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    const cols = 4;
    const rows = 3;
    const outerGap = 10.0;
    return LayoutBuilder(builder: (context, box) {
      final monthW = (box.maxWidth - outerGap * (cols - 1)) / cols;
      final monthH = (box.maxHeight - outerGap * (rows - 1)) / rows;
      return Column(
        children: [
          for (var r = 0; r < rows; r++) ...[
            if (r > 0) const SizedBox(height: outerGap),
            Row(
              children: [
                for (var c = 0; c < cols; c++) ...[
                  if (c > 0) const SizedBox(width: outerGap),
                  SizedBox(
                    width: monthW,
                    height: monthH,
                    child: _MiniMonth(
                      month: DateTime(year, r * cols + c + 1),
                      levels: levels,
                      label: westernDate(
                        DateTime(year, r * cols + c + 1),
                        'MMM',
                        locale,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      );
    });
  }
}

class _MiniMonth extends StatelessWidget {
  final DateTime month;
  final Map<String, int> levels;
  final String label;

  const _MiniMonth({
    required this.month,
    required this.levels,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final daysIn = DateTime(month.year, month.month + 1, 0).day;
    final lead = _columnOf(month);
    const gap = 1.5;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          style: const TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w600,
            color: _inkSoft,
          ),
        ),
        const SizedBox(height: 3),
        Expanded(
          child: LayoutBuilder(builder: (context, box) {
            final cell = [
              (box.maxWidth - gap * 6) / 7,
              (box.maxHeight - gap * 5) / 6,
            ].reduce((a, b) => a < b ? a : b);
            return Directionality(
              textDirection: TextDirection.ltr,
              child: Align(
                alignment: AlignmentDirectional.topStart,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var r = 0; r < 6; r++) ...[
                      if (r > 0) const SizedBox(height: gap),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var c = 0; c < 7; c++) ...[
                            if (c > 0) const SizedBox(width: gap),
                            _cell(r * 7 + c - lead + 1, daysIn, cell),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _cell(int dayNumber, int daysIn, double cell) {
    if (dayNumber < 1 || dayNumber > daysIn) {
      return SizedBox(width: cell, height: cell);
    }
    final key = DateTime(month.year, month.month, dayNumber).toDateKey();
    return Container(
      width: cell,
      height: cell,
      decoration: BoxDecoration(
        color: shareCellColor(levels[key]),
        borderRadius: BorderRadius.circular(cell * 0.25),
      ),
    );
  }
}

/// The report's way into the card, under its three numbers. [locked] draws
/// the small lock a free account sees on the year's: the tap is the pitch,
/// as on every other Premium control in the app.
class ShareCardButton extends StatelessWidget {
  final String label;
  final bool locked;
  final VoidCallback onTap;

  const ShareCardButton({
    super.key,
    required this.label,
    required this.onTap,
    this.locked = false,
  });

  @override
  Widget build(BuildContext context) {
    final ink = context.gp.goldInk;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton.icon(
        onPressed: onTap,
        icon: Icon(Icons.ios_share_rounded, size: 16, color: ink),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: ink,
              ),
            ),
            if (locked) ...[
              const SizedBox(width: 6),
              Icon(Icons.lock_rounded, size: 12, color: ink),
            ],
          ],
        ),
      ),
    );
  }
}

/// Opens the card with a Share button under it. The card is shown first so
/// the person sees exactly what they are about to post.
Future<void> showShareCardSheet(BuildContext context, ShareCardData data) {
  HapticFeedback.selectionClick();
  AnalyticsService.instance
      .track('share_card_open', props: {'scope': data.scope.name});
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ShareCardSheet(data: data),
  );
}

class _ShareCardSheet extends StatefulWidget {
  final ShareCardData data;

  const _ShareCardSheet({required this.data});

  @override
  State<_ShareCardSheet> createState() => _ShareCardSheetState();
}

class _ShareCardSheetState extends State<_ShareCardSheet> {
  final _cardKey = GlobalKey();
  bool _sharing = false;

  Future<void> _share() async {
    if (_sharing) return;
    final s = S.of(context);
    HapticFeedback.lightImpact();
    setState(() => _sharing = true);
    try {
      final boundary =
          _cardKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      // 3x of the card's own size, whatever the preview is scaled to.
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (!mounted || bytes == null) return;
      await ShareService.shareImage(
        context,
        bytes.buffer.asUint8List(),
        fileName: widget.data.fileName,
        text: s.shareCardCaption,
      );
      AnalyticsService.instance
          .track('share_card_shared', props: {'scope': widget.data.scope.name});
    } catch (_) {
      if (mounted) {
        showOverlayNotice(
          context,
          s.shareCardFailed,
          icon: Icons.error_outline_rounded,
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.of(context).padding.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: gp.surfaceHigh,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: gp.border,
                borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
              ),
            ),
            const SizedBox(height: 14),
            FittedBox(
              child: RepaintBoundary(
                key: _cardKey,
                child: ShareProgressCard(data: widget.data),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _sharing ? null : _share,
                icon: _sharing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.ios_share_rounded, size: 18),
                label: Text(s.shareCardShare),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

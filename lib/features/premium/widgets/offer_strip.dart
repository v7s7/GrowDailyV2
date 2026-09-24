import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../offers/paywall_offer.dart';

/// The running offer's name and a live countdown to its real end, drawn
/// right above the Lifetime card (design canvas of 2026-09-22).
///
/// It ticks by itself once a second, so only this strip repaints, never
/// the whole paywall with its entrance animations. At zero it stops and
/// calls [onEnded] exactly once, and the paywall takes the offer away in
/// the same visit: a countdown that reaches zero while the price stays is
/// the pattern regulators fine.
///
/// Days, hours and minutes while a day or more is left; hours, minutes and
/// seconds on the last day (Aziz's call, see CountdownParts).
class PremiumOfferStrip extends StatefulWidget {
  const PremiumOfferStrip({
    super.key,
    required this.title,
    required this.subtitle,
    required this.endsAt,
    required this.onEnded,
    this.clock = DateTime.now,
  });

  final String title;
  final String subtitle;
  final DateTime endsAt;
  final VoidCallback onEnded;

  /// For tests.
  final DateTime Function() clock;

  @override
  State<PremiumOfferStrip> createState() => _PremiumOfferStripState();
}

class _PremiumOfferStripState extends State<PremiumOfferStrip> {
  Timer? _timer;
  bool _ended = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void didUpdateWidget(PremiumOfferStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.endsAt != widget.endsAt) {
      _ended = false;
      _timer ??= Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    }
  }

  void _tick() {
    if (!mounted) return;
    if (!widget.clock().isBefore(widget.endsAt)) {
      _timer?.cancel();
      _timer = null;
      if (!_ended) {
        _ended = true;
        widget.onEnded();
      }
      return;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final parts = CountdownParts.of(widget.endsAt.difference(widget.clock()));
    final boxes = parts.lastDay
        ? [
            (_two(parts.hours), s.premiumCountdownHours),
            (_two(parts.minutes), s.premiumCountdownMinutes),
            (_two(parts.seconds), s.premiumCountdownSeconds),
          ]
        : [
            ('${parts.days}', s.premiumCountdownDays),
            ('${parts.hours}', s.premiumCountdownHours),
            (_two(parts.minutes), s.premiumCountdownMinutes),
          ];
    final spoken = s.premiumCountdownSpoken(
      boxes.map((b) => '${b.$1} ${b.$2}').join(' '),
    );
    return Semantics(
      container: true,
      label: '${widget.title}. $spoken',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: GameColors.gold.withOpacity(0.10),
          borderRadius: BorderRadius.circular(GameSpacing.buttonRadius),
          border: Border.all(color: GameColors.gold.withOpacity(0.45)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(Icons.timer_outlined, size: 16, color: gp.goldInk),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: gp.goldInk,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    widget.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: gp.textSec),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            for (var i = 0; i < boxes.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              _CountdownBox(value: boxes[i].$1, unit: boxes[i].$2),
            ],
          ],
        ),
      ),
    );
  }
}

class _CountdownBox extends StatelessWidget {
  const _CountdownBox({required this.value, required this.unit});

  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Container(
      width: 46,
      padding: const EdgeInsets.only(top: 6, bottom: 5),
      decoration: BoxDecoration(
        color: gp.surfaceHigh,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: gp.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: gp.textPrimary,
              height: 1.15,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text(
            unit,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, color: gp.textSec),
          ),
        ],
      ),
    );
  }
}

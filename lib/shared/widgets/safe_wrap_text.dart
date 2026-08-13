import 'package:flutter/material.dart';

import '../../core/theme/game_theme.dart';

/// True when some whitespace-delimited "word" in [text] is, measured on its
/// own, wider than [maxWidth] — meaning a multi-line [Text] would have no
/// word-boundary option and would fall back to hyphenating that word
/// mid-character to fit it (Flutter's line breaker treats this as an
/// acceptable last resort, not a bug). Titles that only need multiple lines
/// because they have several words — each of which individually fits — are
/// unaffected; this only flags the specific case a plain `maxLines`/
/// `TextOverflow.ellipsis` pairing can't prevent on its own. Script-agnostic:
/// it only ever measures word pixel widths, so it works the same for Arabic
/// (and any other space-delimited script) as it does for English.
bool wordExceedsWidth(
  String text,
  double maxWidth, {
  required TextStyle style,
  required TextDirection textDirection,
  required TextScaler textScaler,
}) {
  for (final word in text.split(RegExp(r'\s+'))) {
    if (word.isEmpty) continue;
    final tp = TextPainter(
      text: TextSpan(text: word, style: style),
      maxLines: 1,
      textDirection: textDirection,
      textScaler: textScaler,
    )..layout();
    if (tp.size.width > maxWidth) return true;
  }
  return false;
}

/// True when laying [text] out at [maxLines] (within [maxWidth]) would clip
/// something — i.e. exactly the condition that produces the "…" a caller
/// sees. Reuses the same [TextPainter] machinery [wordExceedsWidth] already
/// needs, just carried one step further (an actual multi-line layout pass,
/// not just a per-word measurement) so ordinary "too many words, not just
/// one oversized one" overflow is caught too — see [SafeWrapText.
/// tapToRevealWhenTruncated]'s doc comment for why this matters: showing a
/// tap-to-reveal affordance requires knowing overflow happened at all,
/// not just which of the two ways it happened.
bool textOverflowsAt(
  String text,
  double maxWidth, {
  required int maxLines,
  required TextStyle style,
  required TextDirection textDirection,
  required TextScaler textScaler,
}) {
  final tp = TextPainter(
    text: TextSpan(text: text, style: style),
    maxLines: maxLines,
    textDirection: textDirection,
    textScaler: textScaler,
  )..layout(maxWidth: maxWidth);
  return tp.didExceedMaxLines;
}

/// Drop-in replacement for [Text] on user-entered titles (task names, habit
/// names, and the like) that guarantees it never produces an ugly forced
/// mid-word line break — e.g. "Record" splitting into "Recor" / "d". Flutter
/// only does that when a single word can't fit even on its own dedicated
/// line; this widget detects that case ahead of time (via [wordExceedsWidth])
/// and renders at maxLines: 1 with a clean "…" ellipsis instead, which reads
/// as an intentional truncation rather than a rendering bug. Ordinary
/// multi-word titles that merely need wrapping — where every individual word
/// fits — are untouched and still wrap at word boundaries across up to
/// [maxLines] lines, exactly like a plain [Text] would.
///
/// This matters even more for Arabic and other cursive scripts: a mid-word
/// break there doesn't just look like a bad line-wrap, it can visibly change
/// how the split letters are shaped, since Arabic letterforms depend on
/// their neighbors. Capping to one line with an ellipsis avoids that
/// entirely, and the check itself is script-agnostic (it only measures word
/// pixel widths, never inspects specific characters).
class SafeWrapText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final int maxLines;
  final TextAlign? textAlign;

  /// When true, a name that actually gets truncated (either the single-
  /// oversized-word case above, or plain "too many words for [maxLines]
  /// lines") becomes tappable: tapping it shows the full [text] in a small
  /// floating bubble for a few seconds, then it goes away on its own — or
  /// immediately if something else is tapped first. Built on Flutter's own
  /// [Tooltip] (with [TooltipTriggerMode.tap]) rather than a hand-rolled
  /// overlay, specifically so screen-edge clamping, scroll-position
  /// tracking, and dismiss-on-next-tap all come from tested framework code
  /// instead of new bespoke positioning math.
  ///
  /// Defaults to false so every existing caller (a row that already does
  /// something else on tap, e.g. opening a detail screen) keeps behaving
  /// exactly as before unless it opts in. A name that isn't actually
  /// truncated never gets wrapped in a [Tooltip] at all, even when this is
  /// true — nothing about a name that already reads in full should become
  /// tappable, since there'd be nothing new to reveal.
  final bool tapToRevealWhenTruncated;

  const SafeWrapText(
    this.text, {
    super.key,
    this.style,
    this.maxLines = 2,
    this.textAlign,
    this.tapToRevealWhenTruncated = false,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final effectiveStyle = DefaultTextStyle.of(context).style.merge(style);
        final textDirection = Directionality.of(context);
        final textScaler = MediaQuery.textScalerOf(context);

        int effectiveMaxLines = maxLines;
        bool overflowed = false;

        if (maxLines <= 1) {
          overflowed = textOverflowsAt(
            text,
            constraints.maxWidth,
            maxLines: 1,
            style: effectiveStyle,
            textDirection: textDirection,
            textScaler: textScaler,
          );
        } else {
          // A single word wider than the available space can't be helped by
          // more lines - it still won't fit on any one of them - so this
          // collapses to one line (with an ellipsis) rather than letting
          // Flutter's line breaker hyphenate mid-word as a last resort.
          final singleLine = wordExceedsWidth(
            text,
            constraints.maxWidth,
            style: effectiveStyle,
            textDirection: textDirection,
            textScaler: textScaler,
          );
          effectiveMaxLines = singleLine ? 1 : maxLines;
          overflowed = singleLine ||
              textOverflowsAt(
                text,
                constraints.maxWidth,
                maxLines: effectiveMaxLines,
                style: effectiveStyle,
                textDirection: textDirection,
                textScaler: textScaler,
              );
        }

        final textWidget = Text(
          text,
          style: style,
          maxLines: effectiveMaxLines,
          overflow: TextOverflow.ellipsis,
          textAlign: textAlign,
        );

        if (!tapToRevealWhenTruncated || !overflowed) return textWidget;

        final gp = context.gp;
        return Tooltip(
          message: text,
          triggerMode: TooltipTriggerMode.tap,
          // Material's own spec for a tap-triggered tooltip: stays up for
          // this long, but a tap anywhere else dismisses it immediately -
          // see Tooltip.showDuration's own doc comment. 3s (not the 1.5s
          // default) gives a longer name a real chance to be read once,
          // matching WCAG 1.4.13's "don't rely on a too-short timer"
          // guidance for hover/tap-revealed content.
          showDuration: const Duration(seconds: 3),
          textStyle: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: gp.textPrimary,
            height: 1.3,
          ),
          decoration: BoxDecoration(
            color: gp.surfaceHigh,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: gp.border, width: 0.5),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: textWidget,
        );
      },
    );
  }
}

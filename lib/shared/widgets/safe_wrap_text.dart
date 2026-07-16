import 'package:flutter/material.dart';

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

  const SafeWrapText(
    this.text, {
    super.key,
    this.style,
    this.maxLines = 2,
    this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    // Nothing to decide when only one line is ever allowed anyway.
    if (maxLines <= 1) {
      return Text(
        text,
        style: style,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        textAlign: textAlign,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final effectiveStyle = DefaultTextStyle.of(context).style.merge(style);
        final singleLine = wordExceedsWidth(
          text,
          constraints.maxWidth,
          style: effectiveStyle,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        );
        return Text(
          text,
          style: style,
          maxLines: singleLine ? 1 : maxLines,
          overflow: TextOverflow.ellipsis,
          textAlign: textAlign,
        );
      },
    );
  }
}

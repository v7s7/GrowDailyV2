import 'package:flutter/foundation.dart';
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
///
/// Each word's painter is disposed as soon as its width is read, the one
/// that answers true included, so its native paragraph is freed there and
/// then instead of whenever the garbage collector reaches it.
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
    );
    try {
      tp.layout();
      if (tp.size.width > maxWidth) return true;
    } finally {
      tp.dispose();
    }
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
/// not just which of the two ways it happened. The painter is disposed
/// once the answer is read, as in [wordExceedsWidth].
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
  );
  try {
    tp.layout(maxWidth: maxWidth);
    return tp.didExceedMaxLines;
  } finally {
    tp.dispose();
  }
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
class SafeWrapText extends StatefulWidget {
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
  State<SafeWrapText> createState() => _SafeWrapTextState();

  /// Stands in for [kIsWeb] in tests, which always run on the VM: true
  /// makes every build measure afresh and keep nothing, the path the web
  /// takes (the state's kept measurement says why). Null in the app.
  @visibleForTesting
  static bool? debugMeasureEveryBuild;
}

class _SafeWrapTextState extends State<SafeWrapText> {
  /// Held across rebuilds so the tap handler below always addresses the same
  /// Tooltip. Created here rather than in build for that reason.
  final GlobalKey<TooltipState> _tipKey = GlobalKey<TooltipState>();

  /// The last measurement this label took, with every input it was taken
  /// with. The builder below runs again whenever the parent rebuilds, and
  /// a measurement is one TextPainter layout per word, plus one more for
  /// the reveal check: on the Grid, every habit name on every square tap.
  /// When nothing the answer depends on has moved, neither has the answer,
  /// so it is read back instead of measured again. The LayoutBuilder still
  /// runs and the name is still laid out; only the measuring is skipped.
  /// A new week remounts the Grid's table, so it starts empty there.
  ///
  /// What the answer depends on is the key: the text, the width offered,
  /// the merged style, the direction, the text scaler, maxLines and the
  /// reveal flag, all compared with ==, plus the fonts the engine holds,
  /// which [_forgetMeasurement] covers. A style carrying a Paint compares
  /// by identity, so it simply measures again every time, the safe way
  /// round. The rendered Text gets exactly the maxLines, and the Tooltip
  /// exactly the verdict, a fresh measurement would give.
  ///
  /// Never kept on the web. The web engine announces a newly registered
  /// font from an animation-frame callback, after the font is already in
  /// use, so a board rebuild in the frame between would read an answer
  /// taken with the old face and hold it until the next rebuild. On iOS
  /// and Android the announcement lands in the same event-loop turn as
  /// the font itself, before any frame can run. The web measures on every
  /// build, as it always did.
  ///
  /// Written only inside the LayoutBuilder's builder, never through
  /// setState: keeping it must not cause a single extra build.
  _Measurement? _kept;

  String get text => widget.text;
  TextStyle? get style => widget.style;
  int get maxLines => widget.maxLines;
  TextAlign? get textAlign => widget.textAlign;
  bool get tapToRevealWhenTruncated => widget.tapToRevealWhenTruncated;

  @override
  void initState() {
    super.initState();
    PaintingBinding.instance.systemFonts.addListener(_forgetMeasurement);
  }

  /// A hot reload may bring new measuring code: measure again after it.
  @override
  void reassemble() {
    super.reassemble();
    _kept = null;
  }

  @override
  void dispose() {
    PaintingBinding.instance.systemFonts.removeListener(_forgetMeasurement);
    super.dispose();
  }

  /// Drops the kept measurement when the engine's fonts change (a
  /// GoogleFonts face finishing its load, say), so the next build measures
  /// with the face that is there now, the same build that would have
  /// measured it anyway. It only forgets. No setState and no rebuild of
  /// its own: nothing rebuilds a label on a font change, and this must not
  /// start to. Nor may it add or remove a listener, since PaintingBinding
  /// walks its listener set directly while calling them. A method rather
  /// than a closure, so dispose removes the very listener initState added.
  void _forgetMeasurement() => _kept = null;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final effectiveStyle = DefaultTextStyle.of(context).style.merge(style);
        final textDirection = Directionality.of(context);
        final textScaler = MediaQuery.textScalerOf(context);

        int effectiveMaxLines = maxLines;
        bool overflowed = false;

        // The kept measurement, only when it was taken with exactly these
        // inputs: see [_kept].
        final keeps = !(SafeWrapText.debugMeasureEveryBuild ?? kIsWeb);
        final previous = keeps ? _kept : null;
        final kept = previous != null &&
                previous.isFor(
                  text: text,
                  maxWidth: constraints.maxWidth,
                  style: effectiveStyle,
                  textDirection: textDirection,
                  textScaler: textScaler,
                  maxLines: maxLines,
                  tapToReveal: tapToRevealWhenTruncated,
                )
            ? previous
            : null;

        // [overflowed] is read for one thing only — whether to wrap this in
        // the tap-to-reveal Tooltip below — so measuring it when the caller
        // did not ask for that is a full TextPainter layout built, used for
        // nothing and thrown away, every time a label is measured. On the
        // Grid that is one per habit name per measuring pass, and on the
        // web every mark is one. [wordExceedsWidth] below runs on every
        // measurement: it decides effectiveMaxLines, which changes what
        // is actually rendered.
        if (kept != null) {
          effectiveMaxLines = kept.effectiveMaxLines;
          overflowed = kept.overflowed;
        } else if (maxLines <= 1) {
          overflowed = tapToRevealWhenTruncated &&
              textOverflowsAt(
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
              (tapToRevealWhenTruncated &&
                  textOverflowsAt(
                    text,
                    constraints.maxWidth,
                    maxLines: effectiveMaxLines,
                    style: effectiveStyle,
                    textDirection: textDirection,
                    textScaler: textScaler,
                  ));
        }

        if (keeps && kept == null) {
          _kept = _Measurement(
            text: text,
            maxWidth: constraints.maxWidth,
            style: effectiveStyle,
            textDirection: textDirection,
            textScaler: textScaler,
            maxLines: maxLines,
            tapToReveal: tapToRevealWhenTruncated,
            effectiveMaxLines: effectiveMaxLines,
            overflowed: overflowed,
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
        // Shown by our own onTap below rather than by TooltipTriggerMode.tap.
        // The trigger mode installs a tap recognizer *inside* the Tooltip,
        // which then has to win a gesture arena against whatever the caller
        // already wrapped this label in — on the Victory Grid that is an
        // opaque GestureDetector carrying a long-press for selection
        // (grid_screen_table.dart), and the reveal never fired there at all.
        // Driving the Tooltip explicitly takes the arena out of it: one
        // recognizer, owned here, so the affordance behaves the same wherever
        // it is embedded.
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _tipKey.currentState?.ensureTooltipVisible(),
          child: Tooltip(
            key: _tipKey,
            message: text,
            triggerMode: TooltipTriggerMode.manual,
          // Material's own spec for a tap-triggered tooltip: stays up for
          // this long, but a tap anywhere else dismisses it immediately -
          // see Tooltip.showDuration's own doc comment. 3s (not the 1.5s
          // default) gives a longer name a real chance to be read once,
          // matching WCAG 1.4.13's "don't rely on a too-short timer"
          // guidance for hover/tap-revealed content.
            showDuration: const Duration(seconds: 3),
            // The typeface spelled out: a Tooltip's textStyle replaces the
            // theme's text style instead of merging with it, so without a
            // family the bubble drew in the phone's own font.
            textStyle: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: gp.textPrimary,
              height: 1.3,
              fontFamily: GameTextStyles.fontFamily,
              fontFamilyFallback: GameTextStyles.fontFallback,
            ),
            decoration: BoxDecoration(
              color: gp.surfaceHigh,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: gp.border, width: 0.5),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: textWidget,
          ),
        );
      },
    );
  }
}

/// One measurement [_SafeWrapTextState] keeps: the inputs it was taken
/// with, and its two answers.
@immutable
class _Measurement {
  const _Measurement({
    required this.text,
    required this.maxWidth,
    required this.style,
    required this.textDirection,
    required this.textScaler,
    required this.maxLines,
    required this.tapToReveal,
    required this.effectiveMaxLines,
    required this.overflowed,
  });

  final String text;
  final double maxWidth;
  final TextStyle style;
  final TextDirection textDirection;
  final TextScaler textScaler;
  final int maxLines;
  final bool tapToReveal;

  final int effectiveMaxLines;
  final bool overflowed;

  /// Whether this was measured with exactly these inputs. Every one is
  /// compared with == and none with identical(): a style or scaler rebuilt
  /// with the same values is the same input, and one that compares by
  /// identity (a style carrying a Paint) just misses and measures again.
  bool isFor({
    required String text,
    required double maxWidth,
    required TextStyle style,
    required TextDirection textDirection,
    required TextScaler textScaler,
    required int maxLines,
    required bool tapToReveal,
  }) {
    return this.text == text &&
        this.maxWidth == maxWidth &&
        this.style == style &&
        this.textDirection == textDirection &&
        this.textScaler == textScaler &&
        this.maxLines == maxLines &&
        this.tapToReveal == tapToReveal;
  }
}

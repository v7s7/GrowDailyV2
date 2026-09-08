import 'package:flutter/material.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart' show AppleLogoPainter;

import '../../../core/theme/game_theme.dart';
import 'brand_logos.dart';

/// A Google or Apple sign-in button, sized and shaped exactly like the
/// app's own [FilledButton]s so the auth screen reads as one stack of
/// controls rather than two vendors' widgets dropped into a Flutter screen.
///
/// Built on [FilledButton] rather than a hand-rolled InkWell so it inherits
/// the theme's height (52), radius ([GameSpacing.buttonRadius]), splash,
/// hover and disabled behaviour for free, with only the colours overridden.
///
/// The layout is a [Stack], not a [Row], and that is the detail that makes it
/// look like every well-made sign-in button rather than an icon button: the
/// label is centred in the FULL width of the button while the logo sits
/// against the leading edge. A Row would centre the logo-plus-label pair as a
/// group, so the two buttons' words would not line up with each other or with
/// the app's other buttons, and would shift sideways as the label's length
/// changed between English and Arabic.
class SocialSignInButton extends StatelessWidget {
  const SocialSignInButton.google({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
  }) : _isApple = false;

  const SocialSignInButton.apple({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
  }) : _isApple = true;

  final String label;

  /// Null disables the button. Kept separate from [loading] so the OTHER
  /// provider's button can be disabled while this one spins.
  final VoidCallback? onPressed;

  /// Shows a spinner in place of the logo and label, at the same size, so the
  /// button does not resize or the column reflow mid-tap.
  final bool loading;

  final bool _isApple;

  @override
  Widget build(BuildContext context) {
    // Deliberately no context.gp here: both buttons are brand surfaces whose
    // colours are set by Apple and Google, not by this app's theme, so a
    // Premium user on another palette still gets a compliant pair.
    final dark = Theme.of(context).brightness == Brightness.dark;

    // Apple's HIG allows black, white, or white-with-outline, and asks for
    // the one that contrasts with the background: black on a light screen,
    // white on a dark one. Google's mark keeps its own four colours in both
    // themes, so its button follows the app's own surface instead.
    final Color background;
    final Color foreground;
    final BorderSide? border;
    if (_isApple) {
      background = dark ? Colors.white : Colors.black;
      foreground = dark ? Colors.black : Colors.white;
      border = null;
    } else {
      // Google's own colours, not the app's surface, and this is a
      // guideline rather than a taste call: their branding rules say the
      // standard four-colour "G" may only sit on white or on their dark
      // #131314, with the matching stroke. The app's cream #F5EFE3 is
      // neither, and on a cream background it also made the Google button
      // read as lighter and less clickable than the black Apple button
      // beside it, which is the "comparable prominence" clause both
      // companies ask for. Pure white on cream fixes both at once.
      background = dark ? const Color(0xFF131314) : Colors.white;
      foreground = dark ? const Color(0xFFE3E3E3) : const Color(0xFF1F1F1F);
      border = BorderSide(
        color: dark ? const Color(0xFF8E918F) : const Color(0xFF747775),
      );
    }

    return Semantics(
      button: true,
      label: label,
      child: FilledButton(
        onPressed: loading ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          // Without these, a disabled button falls back to the theme's grey
          // pair and an Apple button being disabled for two seconds while
          // Google's sheet is open would flash a completely different colour.
          // Dimming the real colours keeps it recognisably the same button.
          disabledBackgroundColor: background.withValues(alpha: 0.55),
          disabledForegroundColor: foreground.withValues(alpha: 0.55),
          side: border,
          padding: EdgeInsets.zero,
          textStyle: GameTextStyles.labelLarge,
        ),
        child: SizedBox(
          height: 52,
          child: loading
              ? Center(
                  child: SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: foreground,
                    ),
                  ),
                )
              : Stack(
                  alignment: Alignment.center,
                  children: [
                    // Directional so the logo hugs the leading edge in both
                    // scripts: left in English, right in Arabic. The MARK
                    // itself never mirrors, which is why it is positioned
                    // rather than transformed.
                    PositionedDirectional(
                      start: 18,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: _isApple
                            ? SizedBox(
                                width: 18,
                                // Apple's mark is taller than it is wide, and
                                // squaring it squashes the leaf. The 1.18
                                // ratio is the painter's own aspect.
                                height: 18 * 1.18,
                                child: CustomPaint(
                                  painter: AppleLogoPainter(color: foreground),
                                ),
                              )
                            : const GoogleLogo(size: 18),
                      ),
                    ),
                    // Reserved gutters on BOTH sides, equal to the logo's
                    // side, so the centred label is centred in the space that
                    // is actually free and can never run under the logo in
                    // either direction.
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                        start: 48,
                        end: 48,
                      ),
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GameTextStyles.labelLarge.copyWith(
                          color: foreground,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// A hairline rule with a word in the middle, for separating the one-tap
/// providers from the email form.
///
/// Its own widget because there was no such thing in this app before and an
/// auth screen is exactly where one belongs; keeping it here rather than in
/// shared/ until something else needs it.
class LabelledDivider extends StatelessWidget {
  const LabelledDivider({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final line = Expanded(child: Divider(color: gp.divider, height: 1));
    return Row(
      children: [
        line,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: GameSpacing.md),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: gp.textTert,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        line,
      ],
    );
  }
}

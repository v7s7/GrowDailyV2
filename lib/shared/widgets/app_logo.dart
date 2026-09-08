import 'package:flutter/material.dart';

import '../../core/theme/game_theme.dart';

/// The app's own icon, for use inside the app.
///
/// Two things about `assets/images/icon_app.png` make this worth having as a
/// widget rather than an `Image.asset` at each call site.
///
/// First, the file is a plain 1024x1024 square with NO rounded corners and no
/// alpha: every pixel of the border is the same #0F694A green, because iOS
/// and Android mask app icons into their own shape at install time. Dropped
/// straight into a screen it is a hard square, so the rounding has to be
/// applied here.
///
/// Second, it is 1024x1024 and gets drawn at 76 logical pixels. Without
/// [cacheWidth] Flutter decodes and holds the full bitmap, roughly 4 MB of
/// image cache for a logo the size of a thumbnail, on the very first screen
/// of the app. [cacheWidth] decodes it at the size actually needed.
class AppLogo extends StatelessWidget {
  const AppLogo({
    super.key,
    required this.size,
    this.borderRadius,
  });

  /// Side length in logical pixels. The icon is square.
  final double size;

  /// Defaults to a corner radius proportional to [size], matching the
  /// squircle-ish proportion the platforms themselves apply (roughly 29% of
  /// the side, Apple's own continuous-corner ratio) so a 76pt logo reads the
  /// same as the icon on the home screen next to it.
  final double? borderRadius;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? size * 0.29;
    // Decode at the real device resolution, not the asset's 1024.
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 3.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.asset(
        'assets/images/icon_app.png',
        width: size,
        height: size,
        cacheWidth: (size * dpr).round(),
        // Decorative: the wordmark beside it already says "Grow Daily", so a
        // screen reader announcing the logo too would just repeat itself.
        excludeFromSemantics: true,
      ),
    );
  }
}

/// The logo with the wordmark under it, as the opening screens use it.
class AppLogoLockup extends StatelessWidget {
  const AppLogoLockup({
    super.key,
    this.logoSize = 76,
    this.wordmarkSize = 32,
    this.gap = 18,
  });

  final double logoSize;
  final double wordmarkSize;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppLogo(size: logoSize),
        SizedBox(height: gap),
        // Never localised and never translated: it is the product's name.
        // Left in the ambient direction rather than forced, because a
        // Latin wordmark inside an RTL column centres correctly either way.
        Text(
          'Grow Daily',
          style: TextStyle(
            fontSize: wordmarkSize,
            fontWeight: FontWeight.w800,
            color: gp.textPrimary,
            letterSpacing: -0.8,
          ),
        ),
      ],
    );
  }
}

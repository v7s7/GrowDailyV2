import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';

/// Small enough to sit inside the auth screen's smallest top gap, which is
/// 40pt on a short phone at large text.
const double _toggleHeight = 32;

/// The «العربية / English» switch on the auth screen.
///
/// This is what replaced the full-screen first-launch language picker. The
/// app now opens in the phone's own language (see [resolveInitialLocale]), so
/// the language is no longer a question worth a whole screen before anyone
/// has seen what the app is; it is a correction, for the minority whose
/// phone language is not the language they read. A signed-in person changes
/// it in Profile instead, and iOS offers a per-app Language row of its own.
///
/// Both languages are always written in their own script, never as a flag
/// and never as the word for the OTHER language: someone who opened the app
/// in a language they cannot read has to be able to find their way out of it,
/// and «Arabic» set in English is no help to a person who reads only Arabic.
/// Same reason [LanguageOptionCard] is typography-only.
///
/// Each label carries its own [Directionality] and neither is ever joined to
/// the other inside one [Text]. A single Text holding both scripts is
/// reordered by the bidi algorithm around whatever direction it inherits, so
/// the pair renders in a different order on the Arabic side of the app than
/// on the English side.
///
/// Draws at a fixed [_toggleHeight] and is placed INSIDE the blank gap the
/// auth screen already leaves above its logo, rather than in a row of its
/// own. That screen's vertical budget is measured, not guessed, and already
/// overflows a small phone at large text, so a row added to its column would
/// push the guest button toward the fold.
class LanguageToggle extends ConsumerWidget {
  const LanguageToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final isAr = ref.watch(localeProvider).languageCode == 'ar';

    // LTR for the control itself, so the two halves keep the same physical
    // order whichever language is live. The switch is a fixed pair of
    // objects, not a sentence, and having it mirror itself the instant it is
    // tapped makes the half just tapped jump under the finger.
    return Directionality(
      textDirection: TextDirection.ltr,
      // The height is fixed HERE, on the whole control, and the segments
      // inherit it. Each segment centres its label with Container.alignment,
      // and a Container that has an alignment grows to fill any BOUNDED
      // constraint it is given rather than wrapping its child - so without a
      // fixed height here the segments stretch to whatever vertical space
      // they are handed, which on the auth screen is the entire 88pt gap
      // above the logo. That is what turned this pill into a blob.
      child: SizedBox(
        height: _toggleHeight,
        child: Container(
          decoration: BoxDecoration(
            color: gp.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: gp.border, width: 0.5),
          ),
          padding: const EdgeInsets.all(2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Segment(
                label: 'العربية',
                textDirection: TextDirection.rtl,
                selected: isAr,
                onTap: isAr ? null : () => _pick(ref, 'ar'),
              ),
              _Segment(
                label: 'EN',
                textDirection: TextDirection.ltr,
                selected: !isAr,
                onTap: isAr ? () => _pick(ref, 'en') : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Goes through [setLocale], which is what marks the language as CHOSEN.
  /// That flag is the whole point of the tap: until someone picks, the app
  /// keeps following the device's language and will still adopt the one on
  /// their account at sign-in. After it, neither overrules them again.
  void _pick(WidgetRef ref, String code) {
    HapticFeedback.selectionClick();
    setLocale(ref, Locale(code));
  }
}

class _Segment extends StatelessWidget {
  final String label;
  final TextDirection textDirection;
  final bool selected;
  final VoidCallback? onTap;

  const _Segment({
    required this.label,
    required this.textDirection,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: AnimatedContainer(
            duration: GameMotion.standard,
            curve: Curves.easeOut,
            // Width only. The height comes from the fixed-height parent, and
            // a minHeight here would fight it; a Row lays its children out
            // with an UNBOUNDED main axis, so the minWidth floor is safe and
            // the alignment cannot stretch this sideways.
            constraints: const BoxConstraints(minWidth: 46),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              // Gold as a tint and an edge only, never as ink: GameColors
              // .gold measures 1.86:1 on this cream background, so gold text
              // here would be unreadable in light mode.
              color: selected ? gp.goldEdge.withOpacity(0.14) : null,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Directionality(
              textDirection: textDirection,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected ? gp.textPrimary : gp.textSec,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

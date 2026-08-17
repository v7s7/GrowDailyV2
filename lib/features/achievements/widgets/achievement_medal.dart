import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../../core/utils/bidi_fraction.dart';
import '../models/achievement_model.dart';
import 'tier_palette.dart';

/// How a single medal should currently read to the eye — derived by the
/// caller from unlock state plus which tier is "next" in its family (see
/// AchievementsScreen/_MiniAchievementCard for how each computes this).
enum MedalState {
  /// Already earned — full tier color, icon on top, a gentle shimmer so it
  /// never looks like just a static icon in a circle.
  unlocked,

  /// Not yet earned, but the very next one in its family — a thin
  /// progress ring instead of a flat locked fill, so it reads as
  /// "in reach" rather than just another gray circle.
  inProgress,

  /// Not yet earned and not next up either — flat, muted, no progress
  /// ring (nothing meaningful to show yet).
  locked,
}

/// A single achievement medal: a circular, metal-toned badge for [tier],
/// carrying [icon] (the achievement's own trigger icon — a Material glyph,
/// never an emoji) and the tier's numeral. Used identically across the
/// achievements screen, the profile preview strip, and the unlock
/// celebration sheet so "what a medal looks like" is defined exactly once
/// and can't drift between them.
class AchievementMedal extends StatelessWidget {
  final AchievementTier tier;
  final IconData icon;
  final MedalState state;
  final double size;

  /// Only meaningful when [state] is [MedalState.inProgress].
  final double progress;

  /// Whether the unlocked shimmer loops forever (the unlock celebration
  /// sheet — one medal, the sole focus of the screen) or plays once on
  /// appear and settles (every other surface — a grid of up to 20 of
  /// these shimmering at once would be more distracting than "fun").
  final bool loopShimmer;

  /// Drawn under the icon at I/II/III/IV. On by default; the celebration
  /// sheet turns it off, since that medal is already captioned with the
  /// tier's full name directly beneath it.
  final bool showNumeral;

  /// Read out by VoiceOver in place of the medal's visuals. Callers that
  /// know the achievement should pass something specific — see
  /// [medalSemanticLabel]. Null falls back to the tier name plus state,
  /// which is still far better than the nothing this used to expose: the
  /// widget was a bare Container + Icon, so a screen reader moving through
  /// a family ladder announced four unlabelled circles.
  final String? semanticLabel;

  const AchievementMedal({
    super.key,
    required this.tier,
    required this.icon,
    required this.state,
    this.size = 56,
    this.progress = 0,
    this.loopShimmer = false,
    this.showNumeral = true,
    this.semanticLabel,
  });

  /// The medal's own footprint including the progress ring, so every slot in
  /// a row is the same width whatever state it's in.
  ///
  /// The ring used to be added *outside* the medal's box by wrapping it in a
  /// larger Stack only in the `inProgress` case, which made exactly one
  /// child of each ladder Row 8pt wider than its siblings. With
  /// `MainAxisAlignment.spaceBetween` that redistributed every gap in the
  /// row, so the medals in a card with an in-progress tier sat at a visibly
  /// different pitch from the cards without one, and the ring on a leading
  /// medal ran into the card's padding.
  static double slotFor(double size) => size + 10;

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final p = TierPalette.from(context, tier);
    final isLocked = state != MedalState.unlocked;
    final slot = slotFor(size);

    final label = semanticLabel ??
        _fallbackLabel(S.of(context).isAr);

    // ── The disc ─────────────────────────────────────────────
    //
    // Three-stop gradient shine → base → deep, not the two-stop
    // shine → base it was: the old ramp ended on the metal's mid-tone at
    // the bottom-right and rimmed the whole disc in the *shine* shade, so
    // a Silver medal on a white card was a pale circle with a near-white
    // outline. The deep stop and the deep-toned rim give every tier an
    // edge in both modes.
    Widget disc = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: isLocked
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [p.shine, p.base, p.deep],
                stops: const [0.0, 0.55, 1.0],
              ),
        color: isLocked ? gp.textTert.withOpacity(0.12) : null,
        border: Border.all(
          color: isLocked ? gp.border : p.deep.withOpacity(0.75),
          width: isLocked ? 1 : 1.5,
        ),
        boxShadow: isLocked
            ? null
            : [
                BoxShadow(
                  color: p.base.withOpacity(0.40),
                  blurRadius: size * 0.26,
                  spreadRadius: size * 0.01,
                ),
              ],
      ),
      child: _MedalFace(
        icon: icon,
        numeral: showNumeral ? tier.numeral : null,
        size: size,
        color: isLocked ? gp.textTert : p.onBase,
      ),
    );

    if (!isLocked) {
      disc = disc
          .animate(onPlay: (c) {
            if (loopShimmer) c.repeat();
          })
          .shimmer(duration: 1800.ms, color: p.shine.withOpacity(0.6));
    }

    // ── The slot ─────────────────────────────────────────────
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: SizedBox(
        width: slot,
        height: slot,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // A thin progress ring around an in-reach medal — the one thing
            // that separates "next up" from "locked and distant" at a
            // glance. Tweened rather than snapped so the ring draws itself
            // when the card scrolls in, and animates forward in place when
            // a completion moves the number underneath it.
            if (state == MedalState.inProgress)
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: progress.clamp(0.0, 1.0)),
                duration: 900.ms,
                curve: Curves.easeOutCubic,
                builder: (_, value, __) => SizedBox(
                  width: slot,
                  height: slot,
                  child: CircularProgressIndicator(
                    value: value,
                    strokeWidth: 3,
                    strokeCap: StrokeCap.round,
                    backgroundColor: gp.border,
                    valueColor: AlwaysStoppedAnimation(p.ink),
                  ),
                ),
              ),
            disc,
            // Sparkle fleck — Icons.auto_awesome_rounded, a vector glyph,
            // not an emoji — reserved for the two hardest tiers so
            // Gold/Platinum reads as genuinely more special than
            // Bronze/Silver, not just a recolor of the same badge. Inside
            // the slot now, so it can't push the row's layout around.
            if (!isLocked &&
                (tier == AchievementTier.gold ||
                    tier == AchievementTier.platinum))
              Positioned(
                top: 0,
                right: 0,
                child: Icon(Icons.auto_awesome_rounded,
                        size: size * 0.24, color: p.shine)
                    .animate(onPlay: (c) => c.repeat(reverse: true))
                    .fadeIn(duration: 900.ms)
                    .then()
                    .scale(
                        begin: const Offset(1, 1),
                        end: const Offset(1.18, 1.18),
                        duration: 1400.ms),
              ),
          ],
        ),
      ),
    );
  }

  String _fallbackLabel(bool isAr) {
    final t = tier.localizedName(isAr);
    return switch (state) {
      MedalState.unlocked => isAr ? 'ميدالية $t — مفتوحة' : '$t medal, earned',
      MedalState.inProgress => isAr
          ? 'ميدالية $t — قيد التقدّم'
          : '$t medal, in progress',
      MedalState.locked => isAr ? 'ميدالية $t — مقفلة' : '$t medal, locked',
    };
  }
}

/// Icon over numeral, stacked inside the disc.
class _MedalFace extends StatelessWidget {
  final IconData icon;
  final String? numeral;
  final double size;
  final Color color;

  const _MedalFace({
    required this.icon,
    required this.numeral,
    required this.size,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    if (numeral == null) {
      return Center(child: Icon(icon, size: size * 0.42, color: color));
    }
    // Numerals stay Latin in both languages on purpose: they're a
    // rank mark (I·II·III·IV), the same way a medal is stamped, not a
    // quantity to be read aloud — and Arabic has no distinct numeral form
    // for them anyway.
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: size * 0.36, color: color),
        SizedBox(height: size * 0.02),
        Text(
          numeral!,
          textDirection: TextDirection.ltr,
          style: TextStyle(
            fontSize: size * 0.19,
            height: 1,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
            color: color.withOpacity(0.85),
          ),
        ),
      ],
    );
  }
}

/// A specific, spoken-language label for one achievement's medal —
/// "Silver medal, Month of Mastery, 12 of 30". Callers that have the
/// achievement and the numbers should build the label with this rather than
/// leaving [AchievementMedal] to fall back to the generic tier-only string.
String medalSemanticLabel({
  required AchievementModel achievement,
  required MedalState state,
  required int current,
  required bool isAr,
}) {
  final tier = achievement.tier.localizedName(isAr);
  final name = achievement.localName(isAr);
  return switch (state) {
    MedalState.unlocked =>
      isAr ? 'ميدالية $tier: $name — مفتوحة' : '$tier medal: $name, earned',
    MedalState.inProgress => isAr
        ? 'ميدالية $tier: $name — ${progressFraction(current, achievement.threshold)}'
        : '$tier medal: $name, ${progressFraction(current, achievement.threshold)}',
    MedalState.locked =>
      isAr ? 'ميدالية $tier: $name — مقفلة' : '$tier medal: $name, locked',
  };
}

/// Maps an [AchievementTrigger]/family to the icon its medals show — one
/// place instead of the four call sites that used to each repeat this
/// switch (achievements_screen.dart, reaction_overlays.dart,
/// progress_hub_screen.dart, and now AchievementsScreen's family cards).
IconData achievementIconFor(AchievementTrigger trigger) => switch (trigger) {
      AchievementTrigger.streak => Icons.local_fire_department_rounded,
      AchievementTrigger.level => Icons.bolt_rounded,
      AchievementTrigger.totalCompletions => Icons.check_circle_rounded,
      AchievementTrigger.habitMastery => Icons.menu_book_rounded,
      AchievementTrigger.greenSquares => Icons.grid_view_rounded,
      AchievementTrigger.special => Icons.stars_rounded,
    };

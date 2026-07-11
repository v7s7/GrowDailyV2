import 'package:flutter/material.dart';

import '../models/accessory.dart';
import '../models/character_option.dart';

/// Renders a [CharacterOption], optionally with one [Accessory] layered on
/// top in the correct spot (in the character's hand, or centered/behind for
/// non-hand-held categories like frame/badge).
///
/// The positioning math (hand points, grip anchors, letterbox correction)
/// is ported as-is from a sibling project that uses the same character art
/// — every number below was measured directly off these specific PNGs, so
/// it isn't guesswork and shouldn't be "simplified" without re-measuring.
class CharacterAvatar extends StatelessWidget {
  final CharacterOption character;
  final double height;
  final double? width;
  final double opacity;
  final Accessory? accessory;

  const CharacterAvatar({
    super.key,
    required this.character,
    required this.height,
    this.width,
    this.opacity = 1,
    this.accessory,
  });

  @override
  Widget build(BuildContext context) {
    final boxWidth = width ?? height * 0.72;
    final placement = accessory == null ? null : _placements[accessory!.category];

    return Opacity(
      opacity: opacity,
      child: SizedBox(
        height: height,
        width: boxWidth,
        child: placement == null
            ? Image.asset(character.assetPath, fit: BoxFit.contain)
            : Stack(
                clipBehavior: Clip.none,
                children: [
                  if (placement.behindCharacter)
                    _accessoryLayer(placement, boxWidth, height),
                  Positioned.fill(
                    child: Image.asset(character.assetPath, fit: BoxFit.contain),
                  ),
                  if (!placement.behindCharacter)
                    _accessoryLayer(placement, boxWidth, height),
                ],
              ),
      ),
    );
  }

  /// Maps the placement's anchor to an exact pixel position inside the
  /// avatar box. The character is square and rendered with [BoxFit.contain],
  /// so its visible side equals the smaller of the box's two dimensions.
  ///
  /// Hand-held categories target that specific character's measured hand
  /// position ([_handsByCharacter]) instead of one fixed point shared by
  /// every character — poses and sleeve styles differ enough between
  /// characters that a single global point drifts off the hand for most of
  /// them. [_AccessoryPlacement.anchorDx]/[anchorDy] then say where the
  /// "grip" sits within the accessory's own artwork (e.g. the top of the
  /// misbah's loop, the lantern's top ring, the umbrella's handle hook) so
  /// that point — not the artwork's bounding-box center — lands on the
  /// hand. [_anchorOverrides] refines this per accessory id for cases like
  /// the misbah variants, whose loops are each drawn at a different
  /// rotation and so each need their own measured grip point.
  Widget _accessoryLayer(
    _AccessoryPlacement placement,
    double boxWidth,
    double boxHeight,
  ) {
    final squareSide = boxWidth < boxHeight ? boxWidth : boxHeight;
    final horizontalInset = (boxWidth - squareSide) / 2;
    final verticalInset = (boxHeight - squareSide) / 2;
    final size = squareSide * placement.scale;

    final target = placement.hand == null
        ? Offset(placement.dx, placement.dy)
        : _handPointFor(character.id, placement.hand!);
    final targetX = horizontalInset + target.dx * squareSide;
    final targetY = verticalInset + target.dy * squareSide;

    final anchor =
        _anchorOverrides[accessory!.id] ?? Offset(placement.anchorDx, placement.anchorDy);

    return Positioned(
      left: targetX - anchor.dx * size,
      top: targetY - anchor.dy * size,
      width: size,
      height: size,
      child: Image.asset(accessory!.imagePath, fit: BoxFit.contain),
    );
  }

  static Offset _handPointFor(String characterId, _Hand hand) {
    final hands = _handsByCharacter[characterId] ?? _defaultHands;
    return hand == _Hand.left ? hands.left : hands.right;
  }

  static const Map<AccessoryCategory, _AccessoryPlacement> _placements = {
    AccessoryCategory.frame: _AccessoryPlacement(
      dx: 0.5,
      dy: 0.5,
      // Was 1.05 (near full-box) — too dominant, the ring extended past the
      // character's own feet/shoulders. 0.80 still reads as a halo around
      // the character without swallowing the preview.
      scale: 0.80,
      behindCharacter: true,
    ),
    AccessoryCategory.misbah: _AccessoryPlacement(
      hand: _Hand.left,
      scale: 0.24,
      anchorDx: 0.513,
      anchorDy: 0.034,
      behindCharacter: false,
    ),
    AccessoryCategory.umbrella: _AccessoryPlacement(
      hand: _Hand.left,
      scale: 0.58,
      anchorDx: 0.28,
      anchorDy: 0.93,
      behindCharacter: false,
    ),
    AccessoryCategory.lantern: _AccessoryPlacement(
      hand: _Hand.right,
      scale: 0.30,
      anchorDx: 0.50,
      anchorDy: 0.06,
      behindCharacter: false,
    ),
    AccessoryCategory.badge: _AccessoryPlacement(
      dx: 0.5,
      dy: 0.40,
      scale: 0.11, // was 0.16 — read as too large a badge on the chest.
      behindCharacter: false,
    ),
    AccessoryCategory.notebook: _AccessoryPlacement(
      hand: _Hand.right,
      scale: 0.30,
      behindCharacter: false,
    ),
  };

  /// Per-accessory-id grip point, overriding the category default in
  /// [_placements]. The three misbah pieces are drawn as a loop at a
  /// different rotation each, so a single shared anchor lands on the top
  /// bead for one and drifts off it for the others — each variant's loop
  /// apex was measured individually instead (fraction of the accessory's
  /// own image box, letterbox-corrected the same way as [_handsByCharacter]).
  static const Map<String, Offset> _anchorOverrides = {
    'misbah_amber': Offset(0.5205, 0.0161),
    'misbah_wood': Offset(0.4350, 0.0689),
    'misbah_black': Offset(0.5831, 0.0163),
    // Ported from a sibling project without this override, and it showed:
    // notebook is much wider (69% of its canvas) than lantern (47%), so the
    // notebook category's dead-center default left it swallowing the torso
    // instead of hanging beside the hand like every other hand-held item.
    // Gripping near its right (page) edge instead of its center lets the
    // body of the book hang into the clear space beside the character —
    // verified against a rendered composite, not guessed.
    'notebook_teal': Offset(0.88, 0.12),
  };

  /// Hand positions measured directly from each character's artwork (512x512
  /// canvas, expressed as a fraction of width/height) by isolating the
  /// skin-toned blobs below the face. `right`/`left` are the character's own
  /// right/left hand (mirrored on screen: the character's right hand is the
  /// left side of the image).
  static const Map<String, _HandPoints> _handsByCharacter = {
    'male_ghutra_blue': _HandPoints(
      right: Offset(0.3609, 0.6533),
      left: Offset(0.6330, 0.6534),
    ),
    'male_bisht_gold': _HandPoints(
      right: Offset(0.3133, 0.6620),
      left: Offset(0.6827, 0.6619),
    ),
    'male_shmagh_red': _HandPoints(
      right: Offset(0.2736, 0.6304),
      left: Offset(0.7230, 0.6303),
    ),
    'female_hijab_pink': _HandPoints(
      right: Offset(0.3596, 0.5917),
      left: Offset(0.6433, 0.5921),
    ),
    'female_niqab': _HandPoints(
      right: Offset(0.3494, 0.6394),
      left: Offset(0.6432, 0.6393),
    ),
    'female_hijab_teal': _HandPoints(
      right: Offset(0.3112, 0.6045),
      left: Offset(0.6863, 0.6046),
    ),
  };

  /// Average of the six measured hand points — only used as a fallback if a
  /// character id isn't found above.
  static const _defaultHands = _HandPoints(
    right: Offset(0.3280, 0.6302),
    left: Offset(0.6686, 0.6303),
  );
}

enum _Hand { left, right }

class _HandPoints {
  final Offset right;
  final Offset left;

  const _HandPoints({required this.right, required this.left});
}

class _AccessoryPlacement {
  /// Fixed target as a fraction of the character box — used by categories
  /// that aren't hand-held (frame, badge) and so don't vary by character.
  final double dx;
  final double dy;

  /// Which measured hand to target instead of [dx]/[dy]. Null for
  /// non-hand-held categories.
  final _Hand? hand;

  final double scale;
  final bool behindCharacter;

  /// Where the "grip" point sits within the accessory's own rendered box
  /// (0.5, 0.5 is dead-center). Defaults to dead-center for items without a
  /// natural off-center grip (frame, badge, notebook).
  final double anchorDx;
  final double anchorDy;

  const _AccessoryPlacement({
    this.dx = 0.5,
    this.dy = 0.5,
    this.hand,
    required this.scale,
    required this.behindCharacter,
    this.anchorDx = 0.5,
    this.anchorDy = 0.5,
  });
}

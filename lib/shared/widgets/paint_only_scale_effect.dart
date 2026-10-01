import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// flutter_animate's [ScaleEffect], applied at paint time instead of by a
/// rebuild: the same scale on the same kind of render object, reached from
/// the animation's own listener.
///
/// ScaleEffect wraps its child in an AnimatedBuilder that builds a new
/// Transform.scale on every tick. That rebuild is harmless on its own, but an
/// element marked dirty under a LayoutBuilder makes the LayoutBuilder lay out
/// again, and a LayoutBuilder that is not a relayout boundary takes its
/// ancestors with it. The Grid's 2x flame (_BoostBadge in
/// grid_screen_table.dart) repeats forever under the board's LayoutBuilder,
/// so every frame it asked for rebuilt one widget, laid out 9 render objects
/// up to the page's viewport and repainted about 290, for a 9pt icon. Here
/// the tick only sets the transform, which marks paint and nothing else; put
/// a RepaintBoundary around the Animate this rides on and the repaint stays
/// with the icon.
///
/// Everything else is ScaleEffect's own, so each frame's matrix is the same
/// one: [buildAnimation] (the entry's CurvedAnimation over its Interval,
/// driven through Tween<Offset>(begin, end)), the scale clamped below at
/// [ScaleEffect.minScale], Matrix4.diagonal3Values as Transform.scale builds
/// it, [alignment] defaulting to the centre, no origin, no filter quality,
/// and the text direction read from the context as Transform reads it. The
/// value is set when the animation ticks rather than when a rebuild runs,
/// which is earlier in the same frame, before layout and paint.
/// test/shared/paint_only_scale_effect_test.dart holds it to ScaleEffect,
/// matrix and pixels, side by side.
@immutable
class PaintOnlyScaleEffect extends ScaleEffect {
  const PaintOnlyScaleEffect({
    super.delay,
    super.duration,
    super.curve,
    super.begin,
    super.end,
    super.alignment,
    super.transformHitTests,
  });

  @override
  Widget build(
    BuildContext context,
    Widget child,
    AnimationController controller,
    EffectEntry entry,
  ) =>
      _ListeningScale(
        animation: buildAnimation(controller, entry),
        alignment: alignment ?? Alignment.center,
        transformHitTests: transformHitTests,
        child: child,
      );
}

class _ListeningScale extends SingleChildRenderObjectWidget {
  const _ListeningScale({
    required this.animation,
    required this.alignment,
    required this.transformHitTests,
    super.child,
  });

  final Animation<Offset> animation;
  final Alignment alignment;
  final bool transformHitTests;

  @override
  _RenderListeningScale createRenderObject(BuildContext context) =>
      _RenderListeningScale(
        animation: animation,
        alignment: alignment,
        textDirection: Directionality.maybeOf(context),
        transformHitTests: transformHitTests,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderListeningScale renderObject,
  ) {
    renderObject
      ..animation = animation
      ..alignment = alignment
      ..textDirection = Directionality.maybeOf(context)
      ..transformHitTests = transformHitTests;
  }
}

/// A [RenderTransform] that follows [animation] for itself: listening while
/// attached, as RenderAnimatedOpacity does, so a detached one holds nothing.
class _RenderListeningScale extends RenderTransform {
  _RenderListeningScale({
    required Animation<Offset> animation,
    super.alignment,
    super.textDirection,
    super.transformHitTests,
  })  : _animation = animation,
        super(transform: _matrixFor(animation.value));

  Animation<Offset> _animation;

  /// A new animation each time the Animate above builds (flutter_animate
  /// builds one per build): the listener moves to it, and the transform takes
  /// its value, which is the same value on the same controller.
  set animation(Animation<Offset> value) {
    if (identical(value, _animation)) return;
    if (attached) _animation.removeListener(_tick);
    _animation = value;
    if (attached) _animation.addListener(_tick);
    _tick();
  }

  /// ScaleEffect's _normalizeScale: a zero scale is not invertible.
  static double _normalized(double scale) =>
      scale < ScaleEffect.minScale ? ScaleEffect.minScale : scale;

  static Matrix4 _matrixFor(Offset scale) => Matrix4.diagonal3Values(
        _normalized(scale.dx),
        _normalized(scale.dy),
        1.0,
      );

  /// RenderTransform's setter skips an equal matrix, as the AnimatedBuilder
  /// skipped an unchanged value.
  void _tick() => transform = _matrixFor(_animation.value);

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _animation.addListener(_tick);
    _tick();
  }

  @override
  void detach() {
    _animation.removeListener(_tick);
    super.detach();
  }
}

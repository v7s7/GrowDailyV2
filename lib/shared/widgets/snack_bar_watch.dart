import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

// ─── Where the SnackBar is ──────────────────────────────────────────────────
//
// Flutter has no public way to ask where a SnackBar is, or whether one is up
// at all: ScaffoldGeometry carries only the bottom bar and the FAB, a
// floating bar is invisible to FloatingActionButtonLocation, and the
// controller showSnackBar returns exposes nothing but `closed`. Something
// that has to stand ON the bar (Doum, when he waits above the bottom bar,
// see sprout_bottom.dart) therefore reads it from the tree itself.
//
// Which tree: a SnackBar is painted only by the ROOT Scaffold of a nested set
// (ScaffoldMessengerState._isRoot). The Grid is a Scaffold inside HomeShell's
// Scaffold, so the bar a person sees over the Grid belongs to HomeShell's,
// just above its bottom bar, painted over the Grid's body. Every bar in the
// app is an M3 floating one (the theme sets it), which enters by growing a
// ClipRect up from its bottom edge while it fades in, leaves by fading at
// full height, and can be swiped down (its surface slides).
//
// So the sighting is: under the root Scaffold's CustomMultiChildLayout, the
// child laid out in the 'snackBar' slot; the SnackBar widget under it (its
// `animation` says entering, up, leaving); and in its render subtree the
// transition's RenderClipRect (the growing edge) and the Material's
// RenderPhysicalShape (the surface, which the swipe moves). The visible top
// is the lower of the two tops. test/shared/snack_bar_watch_test.dart pins
// this against the SDK the app builds with: if a Flutter upgrade moves any
// of it, that test fails rather than Doum quietly standing behind the bar.

/// A SnackBar on screen, as [sightSnackBar] found it.
@immutable
class SnackBarSighting {
  const SnackBarSighting({
    required this.top,
    required this.surfaceTop,
    required this.value,
    required this.status,
    required this.offstage,
  });

  /// The global y of the bar's visible top edge: while it grows in, the
  /// growing edge; once up, its surface's top (which a swipe moves).
  /// Meaningless while [offstage].
  final double top;

  /// Where the surface's top is, whether or not all of it is showing yet:
  /// where [top] ends up once the bar has grown in. A swipe moves it.
  final double surfaceTop;

  /// The bar's own animation, 0 (gone) to 1 (up): it grows in (the edge
  /// rising, invisible until 0.4, opaque by 0.6), and leaves at full height,
  /// fading out between 0.6 and 0.4.
  final double value;

  /// The bar's own animation: forward while it grows in, completed while it
  /// is up, reverse while it fades out.
  final AnimationStatus status;

  /// The bar is in the tree but not drawn here: during a route transition
  /// its Hero flies it in the Overlay and this copy is a placeholder.
  final bool offstage;

  /// On its way in or up: something standing on it should stand on it.
  bool get showing =>
      !offstage &&
      (status == AnimationStatus.forward ||
          status == AnimationStatus.completed);

  @override
  bool operator ==(Object other) =>
      other is SnackBarSighting &&
      other.status == status &&
      other.offstage == offstage &&
      (other.value - value).abs() < 0.001 &&
      (other.top - top).abs() < 0.25 &&
      (other.surfaceTop - surfaceTop).abs() < 0.25;

  @override
  int get hashCode => Object.hash(status, offstage);

  @override
  String toString() =>
      'SnackBarSighting(top: ${top.toStringAsFixed(1)}, '
      'value: ${value.toStringAsFixed(2)}, $status'
      '${offstage ? ', offstage' : ''})';
}

/// The SnackBar the root Scaffold above [context] is showing, or null when
/// there is none. Only call it outside a build (a post-frame callback): it
/// walks elements and reads render boxes.
SnackBarSighting? sightSnackBar(BuildContext context) {
  // The root Scaffold of the nested set, the one that paints the bar.
  ScaffoldState? root = context.findAncestorStateOfType<ScaffoldState>();
  if (root == null) return null;
  while (true) {
    final up = root!.context.findAncestorStateOfType<ScaffoldState>();
    if (up == null) break;
    root = up;
  }
  final layout = _firstOnChain(
    root.context as Element,
    (e) => e.widget is CustomMultiChildLayout,
    maxDepth: 40,
  );
  if (layout == null) return null;
  Element? slot;
  layout.visitChildElements((child) {
    final w = child.widget;
    if (w is LayoutId && w.id is Enum && (w.id as Enum).name == 'snackBar') {
      slot = child;
    }
  });
  if (slot == null) return null;
  final barElement = _firstOnChain(
    slot!,
    (e) => e.widget is SnackBar,
    maxDepth: 8,
  );
  if (barElement == null) return null;
  final bar = barElement.widget as SnackBar;
  final status = bar.animation?.status ?? AnimationStatus.completed;
  final value = bar.animation?.value ?? 1.0;

  final top = barElement.renderObject;
  RenderClipRect? clip;
  RenderPhysicalShape? surface;
  var offstage = false;
  void visit(RenderObject node, int depth) {
    if (surface != null || depth > 48) return;
    if (node is RenderOffstage && node.offstage) {
      offstage = true;
      return;
    }
    if (clip == null && node is RenderClipRect) clip = node;
    if (node is RenderPhysicalShape) {
      surface = node;
      return;
    }
    node.visitChildren((child) => visit(child, depth + 1));
  }

  if (top != null) visit(top, 0);
  final shape = surface;
  if (offstage || shape == null || !shape.attached || !shape.hasSize) {
    return SnackBarSighting(
      top: double.infinity,
      surfaceTop: double.infinity,
      value: value,
      status: status,
      offstage: true,
    );
  }
  final surfaceTop = shape.localToGlobal(Offset.zero).dy;
  var edge = surfaceTop;
  final growing = clip;
  if (growing != null && growing.attached && growing.hasSize) {
    edge = math.max(edge, growing.localToGlobal(Offset.zero).dy);
  }
  return SnackBarSighting(
    top: edge,
    surfaceTop: surfaceTop,
    value: value,
    status: status,
    offstage: false,
  );
}

/// The first element at or below [from] that passes [test], following only
/// chains of single children: the Scaffold's own wrappers and a SnackBar's
/// slot are chains, and a branch means this is not the shape we know, so
/// the walk stops rather than wandering into the page.
Element? _firstOnChain(
  Element from,
  bool Function(Element) test, {
  required int maxDepth,
}) {
  Element? node = from;
  for (var depth = 0; node != null && depth <= maxDepth; depth++) {
    if (test(node)) return node;
    Element? only;
    var count = 0;
    node.visitChildElements((child) {
      count++;
      only = child;
    });
    if (count != 1) return null;
    node = only;
  }
  return null;
}

/// Calls each watcher after every frame the app draws, and only then: no
/// ticker of its own, so a screen that is still stays still and the phone
/// can idle. A frame is drawn whenever something on screen moves or
/// changes: a SnackBar arriving, growing, fading or being swiped; a page
/// scrolling; a card above something growing or folding away. What a
/// watcher reads after a frame is therefore never more than a frame old.
///
/// One persistent frame callback, added the first time anyone watches
/// (Flutter has no way to remove one), does nothing while nobody watches.
/// The work itself happens after the frame, where reading the tree is safe
/// and marking widgets dirty only asks for the next frame.
class FrameWatch {
  FrameWatch._();

  static final Set<VoidCallback> _watchers = <VoidCallback>{};
  static bool _hooked = false;

  /// Starts calling [onFrame] after every frame, and after the next one
  /// even if nothing else asks for it.
  static void add(VoidCallback onFrame) {
    _watchers.add(onFrame);
    if (!_hooked) {
      _hooked = true;
      SchedulerBinding.instance.addPersistentFrameCallback((_) {
        if (_watchers.isEmpty) return;
        SchedulerBinding.instance.addPostFrameCallback((_) => _run());
      });
    }
    SchedulerBinding.instance.addPostFrameCallback((_) => _run());
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  static void remove(VoidCallback onFrame) => _watchers.remove(onFrame);

  static void _run() {
    for (final watcher in _watchers.toList()) {
      if (_watchers.contains(watcher)) watcher();
    }
  }
}

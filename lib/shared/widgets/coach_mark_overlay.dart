import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/game_theme.dart';

/// A reusable coach-mark: dims the whole screen except a hole hugging
/// [targetKey]'s real on-screen bounds, with a small card (icon + title +
/// body + skip) pointing at it. Taps inside the hole fall straight through
/// to the real widget underneath (see [_CoachMarkInverseClipper]), so
/// tapping the highlighted target does the real thing instead of just
/// dismissing a popup that points at it. Taps anywhere outside the hole, or
/// "Skip", call [onDismiss].
///
/// The hole's shape is derived from the target's *actual* measured size,
/// not a one-size-fits-all circle: a small, roughly-square target (a FAB,
/// an icon button) gets a full circle matching its own round silhouette; a
/// wider or taller target (a settings row, a habit row, a Matrix quadrant
/// card) gets a rounded rectangle hugging its real shape instead. Two
/// mistakes this avoids: a circle sized off a wide row's diagonal
/// overshoots badly above and below it (this once pushed the card meant to
/// sit near a top-of-screen row entirely off the top of the screen), and a
/// fixed-radius rounded rectangle around a genuinely round button leaves
/// flat edges sitting outside its curve while barely clearing it at the
/// corners. Since it's all computed from the measured rect rather than a
/// per-lesson constant, it holds regardless of screen size or density.
///
/// Deliberately generic, unlike the first-run spotlight overlay it outlived
/// rather than a refactor of it: that widget is the proven, automatic,
/// shown-once habit/task tour, wired to its own persisted "seen" flag and
/// its own habitDone/taskDone step logic - this one is App Guide's
/// on-demand, replayable-any-number-of-times lesson spotlight, driven
/// entirely by whatever [targetKey]/[title]/[body]/[onDismiss] the caller
/// passes in, with no opinion of its own about when it should show or
/// whether it's been seen before. Keeping them separate means neither has
/// to renegotiate the other's timing or dismiss-persistence rules.
class CoachMarkOverlay extends StatefulWidget {
  final GlobalKey targetKey;
  final String title;
  final String body;
  final VoidCallback onDismiss;

  const CoachMarkOverlay({
    super.key,
    required this.targetKey,
    required this.title,
    required this.body,
    required this.onDismiss,
  });

  @override
  State<CoachMarkOverlay> createState() => _CoachMarkOverlayState();
}

class _CoachMarkOverlayState extends State<CoachMarkOverlay> {
  // This widget always renders as a `Positioned.fill` inside whichever
  // Stack the caller puts it in (see grid_screen.dart/matrix_screen.dart/
  // profile_screen.dart) — keyed here so its own on-screen box can be
  // measured the same way the target's is.
  final GlobalKey _selfKey = GlobalKey();
  // Target rect, already converted to *this overlay's own* local coordinate
  // space (see _scheduleMeasure) — everything downstream (painter, ring,
  // card) works in that same space, so it stays correct regardless of how
  // deeply this overlay ends up nested.
  Rect? _rect;
  // This overlay's own on-screen box, measured alongside the target — used
  // to convert MediaQuery's window-level height/insets into distances local
  // to this overlay (see build()'s cardTop/cardBottom clamp).
  Offset? _selfGlobalOffset;
  Size? _selfSize;
  // Set once this instance has asked its target to scroll into view — a
  // one-time nudge, not something to repeat on every re-measurement (that
  // would fight the person's own scrolling if they nudge the page while
  // the coach-mark is showing). A freshly-triggered lesson always gets a
  // brand-new CoachMarkOverlay (and State), so this naturally resets and
  // tries again next time the same lesson is activated.
  bool _didEnsureVisible = false;

  // Guards against stacking callbacks: build() and the tracking loop below
  // both ask for a measurement, and without this every build would add
  // another permanent frame-by-frame loop.
  bool _measureScheduled = false;

  // Measures the target's real on-screen box, then keeps doing it every
  // frame until this overlay is dismissed.
  //
  // Re-measuring used to happen only on build, on the reasoning that a
  // rebuild covers every way the target can move. It doesn't cover the way
  // that actually matters: this overlay is a SIBLING of the page's
  // CustomScrollView inside a Stack (see profile_screen.dart), so scrolling
  // the page never rebuilds it. The ring was measured once and then left
  // behind — and since the overlay's own first act is Scrollable.ensureVisible,
  // which animates for 380ms, the page is guaranteed to move right after.
  // On Profile that stranded the "Join a Room" ring hundreds of pixels below
  // the Rooms row, drawing it around the Monthly Story card instead, while
  // the card's text still said "tap here to join or create a room".
  //
  // Tracking every frame also picks up the cases a rebuild would have missed
  // anyway: the person scrolling the page themselves while the coach-mark is
  // up, and a banner above the target appearing or disappearing
  // (_DashboardSection's streak/night-review/recap cards all render
  // conditionally). setState still only fires when the rect genuinely
  // changed, so a settled overlay costs one no-op callback per frame and
  // zero rebuilds.
  void _scheduleMeasure() {
    if (_measureScheduled || !mounted) return;
    _measureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureScheduled = false;
      if (!mounted) return;
      final ctx = widget.targetKey.currentContext;
      final box = ctx?.findRenderObject() as RenderBox?;
      // Keep looking rather than giving up: the target may simply not be
      // laid out yet (a tab still animating in), and a single miss used to
      // end measurement for good.
      if (box == null || !box.hasSize) return _scheduleMeasure();
      // This overlay's own box, e.g. Grid's Scaffold (and this Stack) sits
      // *inside* HomeShell's PageView, which is shorter than the full
      // window because HomeShell's own GameNavBar lives outside it.
      // Comparing the target's raw global position against MediaQuery's
      // *window* height while positioning the card inside this shorter box
      // silently pushed the card away from the target by however much
      // chrome sits outside this overlay (the shared nav bar) — this is
      // what actually happened before (App Guide's "Add a habit" card
      // rendering a whole screen away from the FAB it's supposed to sit
      // next to). Converting the target's rect into *this overlay's own*
      // local space up front means the rest of build() never has to
      // reason about that outer nesting at all.
      final selfBox = _selfKey.currentContext?.findRenderObject() as RenderBox?;
      if (selfBox == null || !selfBox.hasSize) return _scheduleMeasure();
      // The target can be scroll-mounted but off-screen — e.g. Profile's
      // Rooms row when the page was last left scrolled down near Settings.
      // ensureVisible is a safe no-op when there's no scrollable ancestor,
      // or the target is already fully in view, so this is harmless to
      // call even for Grid/Matrix targets that never actually need it.
      if (!_didEnsureVisible) {
        _didEnsureVisible = true;
        Scrollable.ensureVisible(
          ctx!,
          alignment: 0.5,
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeOutCubic,
        );
      }
      final targetGlobalRect = box.localToGlobal(Offset.zero) & box.size;
      final selfGlobalOffset = selfBox.localToGlobal(Offset.zero);
      final rect = targetGlobalRect.shift(-selfGlobalOffset);
      if (rect != _rect ||
          selfGlobalOffset != _selfGlobalOffset ||
          selfBox.size != _selfSize) {
        setState(() {
          _rect = rect;
          _selfGlobalOffset = selfGlobalOffset;
          _selfSize = selfBox.size;
        });
      }
      // Keep following the target until this overlay goes away.
      _scheduleMeasure();
    });
  }

  void _dismiss() {
    HapticFeedback.selectionClick();
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    _scheduleMeasure();
    // _selfKey has to come back out of *some* rendered widget on every
    // single build, including this very first one before anything's been
    // measured — _scheduleMeasure's post-frame callback needs it to find
    // its own box next frame, and it can't do that if an unmeasured first
    // frame took the short-circuit-to-SizedBox.shrink path old code used
    // here instead of ever building the keyed Stack at all. So the Stack
    // itself is now unconditional; only its *contents* wait on _rect.
    return Positioned.fill(
      child: Stack(
        key: _selfKey,
        children: _rect == null ? const [] : _buildContent(context, _rect!),
      ),
    );
  }

  List<Widget> _buildContent(BuildContext context, Rect rect) {
    final gp = context.gp;
    final s = S.of(context);

    // Small, roughly-square targets (a FAB, an icon button) get a fully
    // circular hole matching their own round silhouette; anything wider or
    // taller than that (a settings row, a habit row, a quadrant card) gets
    // a rounded rectangle hugging its real shape instead. A fixed-radius
    // rounded rectangle around a *round* button leaves flat edges sitting
    // outside the button's curve at the top/bottom/sides while barely
    // clearing it at the corners — exactly the "doesn't quite match"
    // mismatch a shape-aware hole avoids. Computed straight from the
    // target's own measured size rather than a per-lesson constant, so it
    // holds on any device/screen size/density.
    final isCompact = rect.width < 90 && rect.height < 90;
    final inflated = rect.inflate(isCompact ? 10 : 8);
    final cornerRadius = isCompact ? inflated.shortestSide / 2 : 16.0;
    final hole = RRect.fromRectAndRadius(
      inflated,
      Radius.circular(cornerRadius),
    );

    // Local height of *this overlay's own* box, not MediaQuery's window
    // height — this overlay can sit inside a Scaffold that's shorter than
    // the full window (Grid/Matrix/Profile's own Scaffold lives inside
    // HomeShell's PageView, above HomeShell's shared GameNavBar), so using
    // the window height here would silently reintroduce the exact
    // mismatch _scheduleMeasure's rect conversion exists to avoid.
    final screenHeight = _selfSize!.height;
    final media = MediaQuery.of(context);
    final selfGlobalTop = _selfGlobalOffset!.dy;
    // media.padding.top/bottom are the status-bar/home-indicator insets in
    // *window* terms — shifted here by this overlay's own global offset so
    // the clamp below keeps the card off the notch/home-indicator using
    // the same local coordinate space as everything else, and clamped to
    // zero once this overlay's own box already starts below (or ends
    // above) that inset entirely, e.g. there's nothing left to avoid at
    // the bottom here when a shared nav bar outside this box already
    // covers the home-indicator inset.
    final topInset =
        (media.padding.top - selfGlobalTop).clamp(0.0, screenHeight);
    final bottomInset = (media.padding.bottom -
            (media.size.height - selfGlobalTop - screenHeight))
        .clamp(0.0, screenHeight);

    // Card sits below the hole when there's room, otherwise above it. The
    // 210/110 margins assume a roughly two-line body plus the bordered
    // Skip button below it — a little slack over the card's typical
    // measured height rather than cutting it exactly, since text can wrap
    // to an extra line on a narrow device or long translation.
    final belowSpace = screenHeight - hole.bottom;
    final showBelow = belowSpace > 210;
    final rawTop = showBelow ? hole.bottom + 16 : null;
    final rawBottom = showBelow ? null : (screenHeight - hole.top + 16);

    // Safety clamp: whatever the target's geometry works out to, the card
    // itself can never end up under the status bar/notch or the home-
    // indicator's safe area — this is what actually failed before (a wide,
    // short target near the top made "above the hole" resolve to a
    // position off the top of the screen).
    // `.clamp()` on a double returns `num`, not `double` — Positioned's
    // top/bottom need an actual `double?`, hence the explicit `.toDouble()`
    // on each; skipping it is a compile error, not a runtime one.
    final cardTop = rawTop == null
        ? null
        : rawTop.clamp(topInset + 8, screenHeight - bottomInset - 110).toDouble();
    final cardBottom = rawBottom == null
        ? null
        : rawBottom.clamp(bottomInset + 8, screenHeight - topInset - 110).toDouble();

    return [
          IgnorePointer(
            child: CustomPaint(
              size: Size.infinite,
              painter: _CoachMarkPainter(hole: hole),
            ),
          ).animate().fadeIn(duration: 280.ms),
          Positioned.fill(
            child: ClipPath(
              clipper: _CoachMarkInverseClipper(hole: hole),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _dismiss,
                child: const SizedBox.expand(),
              ),
            ),
          ),
          // The glowing outline itself, as a plain bordered box positioned
          // exactly over the hole — kept separate from the scrim's own
          // CustomPaint so it can gently pulse (a subtle breathing scale)
          // without that pulse ever touching the full-bleed scrim behind
          // it, which must always stay pinned edge-to-edge with no gaps.
          Positioned.fromRect(
            rect: hole.outerRect,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                      color: GameColors.gold.withOpacity(0.9), width: 2.2),
                  borderRadius: BorderRadius.circular(cornerRadius),
                ),
              ),
            )
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .scaleXY(
                    begin: 1, end: 1.035, curve: Curves.easeInOut, duration: 950.ms),
          ),
          Positioned(
            left: 24,
            right: 24,
            top: cardTop,
            bottom: cardBottom,
            child: GestureDetector(
              // Swallows the tap so pressing the card itself can't also
              // register as the scrim's dismiss-on-tap-outside — "Skip"
              // below is the one deliberate dismiss action here.
              onTap: () {},
              child: Container(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
                decoration: BoxDecoration(
                  // surfaceHL (surfaceHighlight), not surfaceHigh — this
                  // theme's dark surfaces sit close together in luminosity
                  // (surfaceHigh is barely lighter than the scrim behind
                  // it), so the card read as almost the same dark green as
                  // its own dimmed backdrop. surfaceHL plus a real shadow
                  // gives it actual lift instead of just a thin border
                  // separating two near-identical fills.
                  color: gp.surfaceHL,
                  borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
                  border:
                      Border.all(color: GameColors.gold.withOpacity(0.5)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.35),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Icon(Icons.touch_app_rounded,
                              size: 18, color: GameColors.gold),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.title,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              height: 1.3,
                              color: gp.textPrimary,
                              // Every text style in this app is meant to go
                              // through GameTextStyles' font — a bare
                              // TextStyle like this one leaves fontFamily
                              // null, which isn't guaranteed to resolve back
                              // to it through ambient DefaultTextStyle
                              // inheritance the way this codebase's own
                              // convention (see game_theme.dart's many
                              // one-off TextStyles) always sets it
                              // explicitly instead of assuming.
                              fontFamily: GameTextStyles.fontFamily,
                              fontFamilyFallback: GameTextStyles.fontFallback,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      widget.body,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        fontWeight: FontWeight.w500,
                        color: gp.textSec,
                        fontFamily: GameTextStyles.fontFamily,
                        fontFamilyFallback: GameTextStyles.fontFallback,
                      ),
                    ),
                    const SizedBox(height: 14),
                    // Skip as an actual bordered button, not underlined
                    // text sitting in the flow of a sentence — underlined
                    // inline text reads as a broken link at this size,
                    // especially in Arabic, and didn't look tappable
                    // enough on its own.
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: GestureDetector(
                        onTap: _dismiss,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                            color: gp.surface,
                            borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
                            border: Border.all(color: gp.border),
                          ),
                          child: Text(
                            s.coachMarkSkip,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: gp.textSec,
                              fontFamily: GameTextStyles.fontFamily,
                              fontFamilyFallback: GameTextStyles.fontFallback,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              )
                  .animate(delay: 150.ms)
                  .fadeIn(duration: 380.ms, curve: Curves.easeOut)
                  .slideY(
                      begin: 0.12,
                      end: 0,
                      duration: 380.ms,
                      curve: Curves.easeOutCubic),
            ),
          ),
        ];
  }
}

/// Dims everything except [hole] — built as "full rect minus rounded rect"
/// via even-odd path difference rather than a blend-mode punch, so it's one
/// simple drawPath with no saveLayer cost.
class _CoachMarkPainter extends CustomPainter {
  final RRect hole;
  const _CoachMarkPainter({required this.hole});

  @override
  void paint(Canvas canvas, Size size) {
    final outer =
        Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final cutout = Path()..addRRect(hole);
    final scrim = Path.combine(PathOperation.difference, outer, cutout);
    canvas.drawPath(scrim, Paint()..color = Colors.black.withOpacity(0.72));
  }

  @override
  bool shouldRepaint(covariant _CoachMarkPainter oldDelegate) =>
      oldDelegate.hole != hole;
}

/// Clips a full-screen hit-test area down to "everywhere except [hole]" —
/// Flutter's clip widgets restrict hit-testing to the clipped region, so
/// wrapping the dismiss-catching GestureDetector in this means taps inside
/// the hole never reach it at all and fall through to whatever's underneath
/// in the Stack (the real target widget), while taps outside are caught
/// normally.
class _CoachMarkInverseClipper extends CustomClipper<Path> {
  final RRect hole;
  const _CoachMarkInverseClipper({required this.hole});

  @override
  Path getClip(Size size) {
    final outer =
        Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final cutout = Path()..addRRect(hole);
    return Path.combine(PathOperation.difference, outer, cutout);
  }

  @override
  bool shouldReclip(covariant _CoachMarkInverseClipper oldClipper) =>
      oldClipper.hole != hole;
}

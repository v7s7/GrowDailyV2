import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/theme/game_theme.dart';
import '../../../core/theme/theme_preset.dart';

/// A read-only look at a not-yet-applied theme preset — reached from the
/// Appearance sheet's "Preview" action on any preset, including locked/
/// premium ones. Four full mock pages (Grid, Today, Tasks, Profile), swiped
/// horizontally, each vertically scrollable but completely un-tappable —
/// like screenshots you can scroll. The close button is the only live
/// control.
///
/// Deliberately does NOT mount the real screens (their providers/listeners
/// fire real side effects IgnorePointer can't stop) — these are static
/// mockups with nothing wired to any action.
///
/// ── Why apply/restore is timed the way it is (the old "leaky preview"
/// bug) ──
/// The palette swap works by mutating GameColors' statics. Flutter rebuilds
/// the route UNDERNEATH this one on every frame of the push and pop
/// transitions (secondaryAnimation), so the old version — which applied the
/// preset in initState and restored it in dispose — repainted the settings
/// screen behind in the preview's colors during the push, and left it
/// stuck that way after the pop (dispose runs after the pop transition,
/// and nothing rebuilds the screen below afterwards). The fix is pure
/// timing: apply only AFTER the push transition fully completes (the
/// screen below has stopped rebuilding), and restore BEFORE the pop begins
/// (so the pop transition's rebuild frames already see the original
/// palette). dispose keeps a restore as an idempotent safety net for any
/// exotic teardown path.
class ThemePreviewScreen extends ConsumerStatefulWidget {
  final ThemePreset preset;
  const ThemePreviewScreen({super.key, required this.preset});

  @override
  ConsumerState<ThemePreviewScreen> createState() =>
      _ThemePreviewScreenState();
}

class _ThemePreviewScreenState extends ConsumerState<ThemePreviewScreen> {
  late final String _originalPresetId;
  late final PageController _pageController;
  int _pageIndex = 0;
  bool _applied = false;
  bool _restored = false;
  Animation<double>? _routeAnimation;

  @override
  void initState() {
    super.initState();
    _originalPresetId = ref.read(themePresetProvider);
    _pageController = PageController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_applied || _routeAnimation != null) return;
    final anim = ModalRoute.of(context)?.animation;
    if (anim == null || anim.isCompleted) {
      _applyPreview();
      return;
    }
    _routeAnimation = anim;
    anim.addStatusListener(_onRouteAnimStatus);
  }

  void _onRouteAnimStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _applyPreview();
  }

  void _applyPreview() {
    if (_applied || !mounted) return;
    _applied = true;
    // setState so every mock below repaints in the previewed colors the
    // same frame the swap happens.
    setState(() => GameColors.applyPreset(widget.preset));
  }

  /// Idempotent — called from the close button, from PopScope (system
  /// back / swipe-back), and from dispose as the final safety net.
  void _restoreOriginal() {
    if (_restored) return;
    _restored = true;
    GameColors.applyPreset(ThemePresets.byId(_originalPresetId));
  }

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_onRouteAnimStatus);
    _restoreOriginal();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final name = s.isAr ? widget.preset.nameAr : widget.preset.nameEn;

    return PopScope(
      // Restore BEFORE the pop transition's frames rebuild the screen
      // below — see the class doc comment.
      onPopInvokedWithResult: (didPop, _) => _restoreOriginal(),
      child: Scaffold(
        backgroundColor: gp.bg,
        body: Stack(
          children: [
            // Horizontal swipe moves between pages; each page scrolls
            // vertically on its own. All CONTENT is pointer-ignored (the
            // scroll views themselves stay live, wrapping the ignored
            // content), so everything reads like a scrollable screenshot.
            PageView(
              controller: _pageController,
              onPageChanged: (i) => setState(() => _pageIndex = i),
              physics: const BouncingScrollPhysics(),
              children: const [
                _MockPage(child: _GridMock()),
                _MockPage(child: _TodayMock()),
                _MockPage(child: _TasksMock()),
                _MockPage(child: _ProfileMock()),
              ],
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: gp.surfaceHigh,
                                borderRadius: BorderRadius.circular(100),
                                border:
                                    Border.all(color: gp.border, width: 0.5),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.18),
                                    blurRadius: 16,
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.visibility_rounded,
                                      size: 16, color: GameColors.gold),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      s.previewingTheme(name),
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                        color: gp.textPrimary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          // The one live control on this whole screen.
                          GestureDetector(
                            onTap: () {
                              _restoreOriginal();
                              Navigator.of(context).pop();
                            },
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: gp.surfaceHigh,
                                shape: BoxShape.circle,
                                border:
                                    Border.all(color: gp.border, width: 0.5),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.18),
                                    blurRadius: 16,
                                  ),
                                ],
                              ),
                              child: Icon(Icons.close_rounded,
                                  size: 20, color: gp.textPrimary),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      IgnorePointer(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(4, (i) {
                            final active = i == _pageIndex;
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin:
                                  const EdgeInsets.symmetric(horizontal: 3),
                              width: active ? 18 : 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: active
                                    ? GameColors.gold
                                    : gp.textTert.withOpacity(0.4),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            );
                          }),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The "scrollable screenshot" shell every mock page sits in: the scroll
/// view itself is live (so the page scrolls), while everything inside it
/// ignores pointers (so nothing can be tapped).
class _MockPage extends StatelessWidget {
  final Widget child;
  const _MockPage({required this.child});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 100, 16, 40),
      child: IgnorePointer(child: child),
    );
  }
}

// ─── Shared mock building blocks ───────────────────────────────────────────

class _MockCard extends StatelessWidget {
  final Widget child;
  const _MockCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: gp.border, width: 0.5),
      ),
      child: child,
    );
  }
}

class _MockBar extends StatelessWidget {
  final double width;
  final double height;
  final Color? color;
  const _MockBar({required this.width, this.height = 10, this.color});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color ?? gp.surfaceHL,
        borderRadius: BorderRadius.circular(height / 2),
      ),
    );
  }
}

class _MockPageTitle extends StatelessWidget {
  final String Function(S s) label;
  const _MockPageTitle(this.label);

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Text(
      label(S.of(context)),
      style: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w900,
        color: gp.textPrimary,
        letterSpacing: -0.4,
      ),
    );
  }
}

// ─── Grid mock ──────────────────────────────────────────────────────────────

class _GridMock extends StatelessWidget {
  const _GridMock();

  static const _rows = [
    [true, true, false, true, true, false, true],
    [true, false, true, true, false, false, true],
    [false, true, true, false, true, true, false],
    [true, true, true, false, false, true, true],
    [false, false, true, true, true, false, true],
  ];

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MockPageTitle((s) => s.gridTitle),
        const SizedBox(height: 16),
        // Header summary card — ring + stat bars, like the real one.
        _MockCard(
          child: Row(
            children: [
              SizedBox(
                width: 56,
                height: 56,
                child: CircularProgressIndicator(
                  value: 0.7,
                  strokeWidth: 6,
                  color: GameColors.emerald,
                  backgroundColor: gp.surfaceHL,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _MockBar(width: 70, height: 22),
                    SizedBox(height: 8),
                    _MockBar(width: 120),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Week board: weekday header + today ring + habit rows.
        _MockCard(
          child: Column(
            children: [
              Row(
                children: [
                  const SizedBox(width: 60),
                  const Spacer(),
                  for (var d = 0; d < 7; d++)
                    Container(
                      margin: const EdgeInsets.only(left: 5),
                      width: 18,
                      alignment: Alignment.center,
                      child: d == 4
                          ? Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: GameColors.gold.withOpacity(0.16),
                                shape: BoxShape.circle,
                              ),
                            )
                          : _MockBar(width: 10, height: 6),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              for (final filled in _rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: GameColors.gold.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const _MockBar(width: 40),
                      const Spacer(),
                      for (final on in filled)
                        Container(
                          margin: const EdgeInsets.only(left: 5),
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: on
                                ? GameColors.emerald.withOpacity(0.3)
                                : gp.surfaceHL,
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                              color: on
                                  ? GameColors.emerald.withOpacity(0.6)
                                  : gp.border,
                              width: 0.8,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Streak banner strip.
        _MockCard(
          child: Row(
            children: [
              Icon(Icons.local_fire_department_rounded,
                  size: 18, color: GameColors.iconStreak),
              const SizedBox(width: 10),
              const _MockBar(width: 140),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Today mock ─────────────────────────────────────────────────────────────

class _TodayMock extends StatelessWidget {
  const _TodayMock();

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MockPageTitle((s) => s.navToday),
        const SizedBox(height: 16),
        // Progress summary strip.
        _MockCard(
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _MockBar(width: 90, height: 16),
                    SizedBox(height: 8),
                    _MockBar(width: 60, height: 8),
                  ],
                ),
              ),
              ClipRRect(
                borderRadius: BorderRadius.circular(100),
                child: SizedBox(
                  width: 90,
                  child: LinearProgressIndicator(
                    value: 0.4,
                    minHeight: 6,
                    backgroundColor: gp.surfaceHL,
                    valueColor:
                        AlwaysStoppedAnimation(GameColors.emerald),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final done in const [true, true, false, false, false])
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _TodayMockRow(done: done),
          ),
      ],
    );
  }
}

class _TodayMockRow extends StatelessWidget {
  final bool done;
  const _TodayMockRow({required this.done});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return _MockCard(
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color:
                  done ? GameColors.gold.withOpacity(0.15) : gp.surfaceHL,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MockBar(width: 90),
                SizedBox(height: 8),
                _MockBar(width: 60, height: 8),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 30,
            height: 26,
            decoration: BoxDecoration(
              color:
                  done ? GameColors.gold.withOpacity(0.12) : GameColors.gold,
              borderRadius: BorderRadius.circular(8),
            ),
            child: done
                ? Icon(Icons.check_rounded,
                    size: 14, color: GameColors.gold)
                : null,
          ),
        ],
      ),
    );
  }
}

// ─── Tasks (Goals Matrix) mock ──────────────────────────────────────────────

class _TasksMock extends StatelessWidget {
  const _TasksMock();

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    Widget quadrant(Color color, int rows) => Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: gp.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(0.4), width: 0.8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration:
                        BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  _MockBar(width: 46, height: 8, color: color.withOpacity(0.4)),
                ],
              ),
              const SizedBox(height: 10),
              for (var i = 0; i < rows; i++)
                const Padding(
                  padding: EdgeInsets.only(bottom: 7),
                  child: Row(
                    children: [
                      _MockBar(width: 12, height: 12),
                      SizedBox(width: 6),
                      Expanded(child: _MockBar(width: double.infinity, height: 8)),
                    ],
                  ),
                ),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MockPageTitle((s) => s.navMatrix),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: quadrant(GameColors.error, 3)),
            const SizedBox(width: 10),
            Expanded(child: quadrant(GameColors.iconXp, 2)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: quadrant(GameColors.iconStreak, 2)),
            const SizedBox(width: 10),
            Expanded(child: quadrant(GameColors.textTertiary, 1)),
          ],
        ),
      ],
    );
  }
}

// ─── Profile mock ───────────────────────────────────────────────────────────

class _ProfileMock extends StatelessWidget {
  const _ProfileMock();

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MockPageTitle((s) => s.profile),
        const SizedBox(height: 16),
        _MockCard(
          child: Column(
            children: [
              SizedBox(
                width: 84,
                height: 84,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: 0.55,
                      strokeWidth: 5,
                      color: GameColors.gold,
                      backgroundColor: gp.surfaceHL,
                    ),
                    Text(
                      '12',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: GameColors.gold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const _MockBar(width: 100, height: 14),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(100),
                child: LinearProgressIndicator(
                  value: 0.6,
                  minHeight: 5,
                  backgroundColor: gp.border,
                  valueColor: AlwaysStoppedAnimation(GameColors.gold),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            for (final c in [
              GameColors.iconStreak,
              GameColors.gold,
              GameColors.iconXp,
            ])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _ProfileMockStat(color: c),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        // Links list rows, like the real profile.
        _MockCard(
          child: Column(
            children: [
              for (var i = 0; i < 4; i++) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: gp.surfaceHL,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const _MockBar(width: 110),
                      const Spacer(),
                      Icon(Icons.chevron_right_rounded,
                          size: 16, color: gp.textTert),
                    ],
                  ),
                ),
                if (i != 3) Container(height: 0.5, color: gp.divider),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfileMockStat extends StatelessWidget {
  final Color color;
  const _ProfileMockStat({required this.color});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: gp.border, width: 0.5),
      ),
      child: Column(
        children: [
          Icon(Icons.circle, size: 14, color: color),
          const SizedBox(height: 8),
          const _MockBar(width: 28, height: 10),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/theme/game_theme.dart';
import '../../../core/theme/theme_preset.dart';

/// A read-only look at a not-yet-applied theme preset — reached from the
/// Appearance sheet's "Preview" action on any preset, including locked/
/// premium ones.
///
/// Deliberately does NOT mount the real Grid/Today/Focus/Profile screens.
/// Those screens carry real behavior with them — Riverpod providers,
/// `ref.listen` reactions (level-up/achievement/streak-freeze snackbars,
/// milestone dialogs), the Focus completion sheet, timers — and none of
/// that is something `IgnorePointer` can stop, since it only blocks touch
/// input, not provider state changes or side effects that fire on their
/// own. Instead this shows small static mockups: fixed, hardcoded content
/// laid out to resemble each tab, with no provider watched and nothing
/// wired to any real action, so there is nothing here that *can* trigger a
/// snackbar, dialog, timer, or write — regardless of what's tapped.
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

  @override
  void initState() {
    super.initState();
    _originalPresetId = ref.read(themePresetProvider);
    _pageController = PageController();
    // Swap the live palette *before* the first frame — every mock card
    // below reads GameColors fresh on its own first build, so it simply
    // renders in the previewed colors from the start. No app-wide rebuild
    // needed, and — unlike ThemePresetNotifier.set() — this never touches
    // themePresetProvider's state or Hive, so it's purely visual and fully
    // reversible.
    GameColors.applyPreset(widget.preset);
  }

  @override
  void dispose() {
    // Restore exactly what was actually applied. Backgrounding or killing
    // the app mid-preview can't strand it here, since nothing above was
    // ever persisted in the first place.
    GameColors.applyPreset(ThemePresets.byId(_originalPresetId));
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final name = s.isAr ? widget.preset.nameAr : widget.preset.nameEn;

    return Scaffold(
      backgroundColor: gp.bg,
      body: Stack(
        children: [
          // The PageView keeps its own drag/swipe gesture; only each
          // page's *content* is wrapped in IgnorePointer below, so swiping
          // still works but nothing inside a mock page responds to a tap —
          // though there's nothing wired to a real action in the first
          // place, so this is a second, independent guarantee rather than
          // the only one.
          PageView(
            controller: _pageController,
            onPageChanged: (i) => setState(() => _pageIndex = i),
            physics: const BouncingScrollPhysics(),
            children: const [
              IgnorePointer(child: _GridMock()),
              IgnorePointer(child: _TodayMock()),
              IgnorePointer(child: _FocusMock()),
              IgnorePointer(child: _ProfileMock()),
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
                              border: Border.all(color: gp.border, width: 0.5),
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
                          onTap: () => Navigator.of(context).pop(),
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: gp.surfaceHigh,
                              shape: BoxShape.circle,
                              border: Border.all(color: gp.border, width: 0.5),
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
                    // Page dots — purely informational, not interactive
                    // (swipe is the only way to move between pages here).
                    IgnorePointer(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(4, (i) {
                          final active = i == _pageIndex;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(horizontal: 3),
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
    );
  }
}

// ─── Shared mock building blocks ───────────────────────────────────────────
//
// Every mock widget below reads colors via `context.gp`/`GameColors`
// directly in its own build() — the same pattern the rest of the app
// already uses everywhere — rather than threading a palette object through
// constructors. None of these widgets take a WidgetRef or watch any
// provider; `BuildContext` is all they need.

/// The same rounded-card shell used everywhere in the real app, so mock
/// content reads as "this app" rather than a generic placeholder screen.
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

/// A neutral placeholder bar standing in for a line of text — mock content
/// is intentionally abstract (no invented habit names, no sample copy to
/// keep in sync with real strings), so only real, already-localized UI
/// chrome (the page titles) carries actual text.
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
  ];

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 90, 16, 40),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _MockPageTitle((s) => s.gridTitle),
        const SizedBox(height: 16),
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
        _MockCard(
          child: Column(
            children: [
              for (final filled in _rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      const _MockBar(width: 60),
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
      ],
    );
  }
}

// ─── Today mock ─────────────────────────────────────────────────────────────

class _TodayMock extends StatelessWidget {
  const _TodayMock();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 90, 16, 40),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _MockPageTitle((s) => s.navToday),
        const SizedBox(height: 16),
        for (final done in const [true, false, false])
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
              color: done
                  ? GameColors.gold.withOpacity(0.15)
                  : gp.surfaceHL,
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
              color: done ? GameColors.gold.withOpacity(0.12) : GameColors.gold,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Focus mock ─────────────────────────────────────────────────────────────

class _FocusMock extends StatelessWidget {
  const _FocusMock();

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 90, 16, 40),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _MockPageTitle((s) => s.focusDailyTitle),
        const SizedBox(height: 24),
        _MockCard(
          child: Column(
            children: [
              Row(
                children: const [
                  _MockBar(width: 64, height: 30),
                  SizedBox(width: 8),
                  _MockBar(width: 64, height: 30),
                  SizedBox(width: 8),
                  _MockBar(width: 64, height: 30),
                ],
              ),
              const SizedBox(height: 26),
              SizedBox(
                width: 150,
                height: 150,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: 0.42,
                      strokeWidth: 8,
                      color: GameColors.iconXp,
                      backgroundColor: gp.surfaceHL,
                    ),
                    Text(
                      '25:00',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: gp.textPrimary,
                        letterSpacing: -1,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 26),
              Container(
                width: double.infinity,
                height: 46,
                decoration: BoxDecoration(
                  color: GameColors.gold,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ],
          ),
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
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 90, 16, 40),
      physics: const NeverScrollableScrollPhysics(),
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

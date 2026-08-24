import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/theme/game_theme.dart';
import '../../../core/theme/theme_preset.dart';
import '../../premium/notifiers/premium_notifier.dart';
import '../../premium/screens/premium_screen.dart';

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

  /// Whether the previewed preset is one this account cannot apply.
  ///
  /// Computed in build with ref.WATCH (see below), not read from a getter:
  /// a getter using ref.read never subscribes, so the CTA kept saying
  /// "unlock with Premium" to somebody who had just bought it in another tab,
  /// and kept saying "use this theme" after a lapse. Preview itself is
  /// deliberately never gated — trying a look on the real screens is the best
  /// argument for buying it.
  bool _locked = false;

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
    _locked = widget.preset.isPremium && !ref.watch(premiumProvider);

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
            // The whole point of a preview is to decide. Before this there
            // was no way to act on that decision from here: you closed the
            // preview, reopened the sheet, found the preset again and tapped
            // it. Now the decision and the action are in the same place.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IgnorePointer(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(4, (i) {
                            final active = i == _pageIndex;
                            return AnimatedContainer(
                              duration: GameMotion.standard,
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
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: widget.preset.gold,
                            foregroundColor: widget.preset.darkBg,
                            minimumSize: const Size(double.infinity, 52),
                          ),
                          onPressed: () {
                            // Restore first, then act: _apply below re-applies
                            // properly through the notifier, and the premium
                            // route must not be painted in a theme the user
                            // has not bought.
                            _restoreOriginal();
                            Navigator.of(context).pop();
                            if (_locked) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const PremiumScreen(
                                    reason: PremiumReason.appearance,
                                  ),
                                ),
                              );
                              return;
                            }
                            ref
                                .read(themePresetProvider.notifier)
                                .set(widget.preset.id);
                          },
                          icon: Icon(
                            _locked
                                ? Icons.lock_rounded
                                : Icons.check_rounded,
                            size: 18,
                          ),
                          label: Text(_locked
                              ? s.themePreviewUnlock
                              : s.themePreviewApply),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
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
                                borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
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
                                  // The two colours the preset IS, so the
                                  // pill says which theme this is even before
                                  // the name is read.
                                  _HeaderDot(widget.preset.gold),
                                  const SizedBox(width: 4),
                                  _HeaderDot(widget.preset.emerald),
                                  const SizedBox(width: 9),
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
      padding: const EdgeInsets.fromLTRB(16, 118, 16, 128),
      child: IgnorePointer(child: child),
    );
  }
}


// ─── Sample content ─────────────────────────────────────────────────────────

/// Real words, not grey bars.
///
/// This screen used to render every piece of text as a neutral skeleton
/// rectangle, which made the preview almost useless for its one job: most of
/// what you were looking at was the SAME grey whatever theme you picked, and
/// a theme is mostly text on surfaces. Filling in plausible content means the
/// preview shows what the theme actually does to a screen you recognise.
class _Sample {
  final bool ar;
  const _Sample(this.ar);

  String get gridTitle => ar ? 'شبكة الانتصارات' : 'Victory Grid';
  String get todayTitle => ar ? 'اليوم' : 'Today';
  String get tasksTitle => ar ? 'المهام' : 'Tasks';
  String get profileTitle => ar ? 'الملف الشخصي' : 'Profile';

  String get squares => ar ? '٣ مربّعات ملوّنة' : '3 squares filled';
  String get squaresSub => ar ? 'كسبت ٣ مربّعات اليوم' : 'You filled 3 today';
  String get todaySub => ar ? '٣ من ٥ عادات' : '3 of 5 habits';
  String get streak => ar ? 'سلسلة ٨ أيام' : '8 day streak';
  String get name => ar ? 'عبدالعزيز' : 'Abdulaziz';
  String get level => ar ? 'المستوى ١٢' : 'Level 12';

  List<String> get habits => ar
      ? const ['صلاة الفجر', 'أذكار الصباح', 'تمرين', 'قراءة', 'شرب الماء']
      : const ['Fajr prayer', 'Morning dhikr', 'Workout', 'Reading', 'Water'];

  List<String> get tasks => ar
      ? const ['مراجعة التقرير', 'اتصال بالعميل', 'شراء البقالة']
      : const ['Review the report', 'Call the client', 'Buy groceries'];

  List<String> get weekdays =>
      ar ? const ['س', 'ح', 'ن', 'ث', 'ر', 'خ', 'ج'] : const ['S', 'S', 'M', 'T', 'W', 'T', 'F'];

  List<String> get stats => ar ? const ['٧٢٩٦', '١٦١٦', '١٠٦'] : const ['7296', '1616', '106'];

  /// Four, matching the four link rows the profile mock draws. Kept in step
  /// deliberately: a three-item list against a four-row loop is what crashed
  /// this page with a RangeError.
  List<String> get menu => ar
      ? const ['التقدّم', 'التقارير', 'خط الحياة الزمني', 'الغرف']
      : const ['Progress', 'Reports', 'Lifetime', 'Rooms'];

  String get priority => ar ? 'مهم وعاجل' : 'Urgent';
  String get doneLabel => ar ? 'تم اليوم' : 'Done today';
  String get cadence => ar ? 'يوميًا' : 'Daily';

  List<String> get statLabels => ar
      ? const ['مجموع XP', 'ذهب', 'المجموع']
      : const ['Total XP', 'Gold', 'Completed'];
}

_Sample _sample(BuildContext context) => _Sample(S.of(context).isAr);

/// Text inside a mock. Replaces the skeleton bars this screen used to draw.
class _MockLabel extends StatelessWidget {
  final String text;
  final double size;
  final FontWeight weight;
  final Color? color;
  const _MockLabel(
    this.text, {
    this.size = 12.5,
    this.weight = FontWeight.w600,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: size,
        fontWeight: weight,
        color: color ?? context.gp.textPrimary,
      ),
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
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        border: Border.all(color: gp.border, width: 0.5),
      ),
      child: child,
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
    final sample = _sample(context);
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _MockLabel(sample.squares,
                        size: 19, weight: FontWeight.w900),
                    const SizedBox(height: 6),
                    _MockLabel(sample.squaresSub,
                        size: 12, color: gp.textSec),
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
                          : Text(
                              sample.weekdays[d],
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: gp.textTert,
                              ),
                            ),
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
                      SizedBox(
                        width: 58,
                        child: _MockLabel(
                          sample.habits[_rows.indexOf(filled)],
                          size: 10.5,
                          color: gp.textSec,
                        ),
                      ),
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
              _MockLabel(sample.streak, size: 12.5, color: gp.textSec),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // A second strip so this page is not two cards floating above a gap.
        // Every mock page should reach the bottom bar: a preview with dead
        // space in it shows the theme's background more than its design.
        _MockCard(
          child: Row(
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0)
                  Container(width: 0.5, height: 34, color: gp.divider),
                Expanded(
                  child: Column(
                    children: [
                      _MockLabel(sample.stats[i],
                          size: 15, weight: FontWeight.w900),
                      const SizedBox(height: 4),
                      _MockLabel(sample.statLabels[i],
                          size: 10, color: gp.textTert),
                    ],
                  ),
                ),
              ],
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
    final sample = _sample(context);
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _MockLabel(sample.todayTitle,
                        size: 15, weight: FontWeight.w800),
                    const SizedBox(height: 5),
                    _MockLabel(sample.todaySub, size: 11.5, color: gp.textSec),
                  ],
                ),
              ),
              ClipRRect(
                borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
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
        for (var i = 0; i < 5; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _TodayMockRow(index: i, done: i < 2),
          ),
      ],
    );
  }
}

class _TodayMockRow extends StatelessWidget {
  final int index;
  final bool done;
  const _TodayMockRow({required this.index, required this.done});

  @override
  Widget build(BuildContext context) {
    final sample = _sample(context);
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MockLabel(sample.habits[index],
                    size: 13, weight: FontWeight.w700),
                const SizedBox(height: 4),
                _MockLabel(
                  done ? sample.doneLabel : sample.cadence,
                  size: 10.5,
                  color: gp.textTert,
                ),
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
              borderRadius: BorderRadius.circular(GameSpacing.chipRadius),
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
    final sample = _sample(context);
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
                  _MockLabel(_sample(context).priority,
                      size: 9.5, weight: FontWeight.w800, color: color),
                ],
              ),
              const SizedBox(height: 10),
              for (var i = 0; i < rows; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          border: Border.all(color: gp.textTert, width: 1.2),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: _MockLabel(
                          sample.tasks[i % sample.tasks.length],
                          size: 10.5,
                          color: gp.textSec,
                        ),
                      ),
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
    final sample = _sample(context);
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
              _MockLabel(sample.name, size: 16, weight: FontWeight.w900),
              const SizedBox(height: 4),
              _MockLabel(sample.level, size: 11.5, color: gp.textSec),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
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
            for (var i = 0; i < 3; i++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _ProfileMockStat(
                    color: [
                      GameColors.iconStreak,
                      GameColors.gold,
                      GameColors.iconXp,
                    ][i],
                    value: sample.stats[i],
                  ),
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
                      _MockLabel(sample.menu[i], size: 13),
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
  final String value;
  const _ProfileMockStat({required this.color, required this.value});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(GameSpacing.buttonRadius),
        border: Border.all(color: gp.border, width: 0.5),
      ),
      child: Column(
        children: [
          Icon(Icons.circle, size: 14, color: color),
          const SizedBox(height: 8),
          _MockLabel(value, size: 13, weight: FontWeight.w900),
        ],
      ),
    );
  }
}

/// One of the preset's two signature colours, in the header pill.
class _HeaderDot extends StatelessWidget {
  final Color color;
  const _HeaderDot(this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 11,
      height: 11,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: context.gp.border, width: 0.5),
      ),
    );
  }
}

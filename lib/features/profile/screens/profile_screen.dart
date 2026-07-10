import 'dart:math' show pi;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/theme/game_theme.dart';
import '../../../core/theme/theme_preset.dart';
import '../../../features/achievements/models/achievement_model.dart';
import '../../../features/auth/notifiers/auth_notifier.dart';
import '../../../features/dashboard/notifiers/dashboard_notifier.dart';
import '../../../features/habits/catalog/habit_plans.dart' show reminderTimeProvider;
import '../../../features/language/widgets/language_option_card.dart';
import '../../../features/premium/notifiers/premium_notifier.dart';
import '../../../shared/widgets/game_nav_bar.dart';
import '../widgets/delete_account_sheet.dart';
import 'achievements_screen.dart';
import 'progress_screen.dart';
import 'theme_preview_screen.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final state = ref.watch(dashboardProvider);
    final user = FirebaseAuth.instance.currentUser;
    final displayName = user?.email?.split('@').first ?? 'Warrior';
    final unlockedCount = state.unlockedAchievements.length;

    return Scaffold(
      backgroundColor: gp.bg,
      bottomNavigationBar: const GameNavBar(currentIndex: 1),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: gp.bg,
            surfaceTintColor: Colors.transparent,
            scrolledUnderElevation: 0,
            title: Text(s.profile,
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: gp.textPrimary,
                    letterSpacing: -0.3)),
            actions: [
              IconButton(
                icon: Icon(
                  Theme.of(context).brightness == Brightness.dark
                      ? Icons.light_mode_rounded
                      : Icons.dark_mode_rounded,
                  size: 22,
                  color: gp.textSec,
                ),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  ref.read(themeModeProvider.notifier).toggle();
                },
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _HeroHeader(state: state, displayName: displayName),
            )
                .animate()
                .fadeIn(duration: 500.ms)
                .slideY(begin: -0.04, curve: Curves.easeOut),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: _StatsRow(state: state),
            ).animate(delay: 100.ms).fadeIn(duration: 400.ms),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
              child: _ProfileLinksSection(
                unlockedCount: unlockedCount,
                totalAchievements: AchievementCatalog.all.length,
                streak: state.streak,
              ),
            ).animate(delay: 150.ms).fadeIn(duration: 400.ms),
          ),
          const SliverToBoxAdapter(child: _SettingsSection()),
          const SliverToBoxAdapter(child: SizedBox(height: 110)),
        ],
      ),
    );
  }
}

// ─── Hero Header ─────────────────────────────────────────────────────────────

class _HeroHeader extends StatelessWidget {
  final DashboardState state;
  final String displayName;
  const _HeroHeader({required this.state, required this.displayName});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        border: Border.all(color: gp.border, width: 0.5),
      ),
      child: Column(
        children: [
          SizedBox(
            width: 108,
            height: 108,
            child: CustomPaint(
              painter: _RingPainter(
                progress: state.levelProgress,
                trackColor: gp.border,
                arcColor: GameColors.gold,
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${state.level}',
                      style: TextStyle(
                        fontSize: 38,
                        fontWeight: FontWeight.w900,
                        color: GameColors.gold,
                        height: 1,
                        letterSpacing: -1.5,
                      ),
                    ),
                    Text(
                      S.of(context).level,
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                        color: gp.textTert,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            displayName,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: gp.textPrimary,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            S.of(context).xpProgress(state.currentLevelXp, state.xpToNext, state.level + 1),
            style: TextStyle(
                fontSize: 12,
                color: gp.textTert,
                fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: LinearProgressIndicator(
              value: state.levelProgress,
              backgroundColor: gp.border,
              valueColor:
                  AlwaysStoppedAnimation(GameColors.gold),
              minHeight: 5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${state.cumulativeXp} ${S.of(context).cumulativeXp}',
            style: TextStyle(
                fontSize: 11,
                color: gp.textTert,
                fontWeight: FontWeight.w400),
          ),
        ],
      ),
    );
  }
}

// ─── Ring Painter ─────────────────────────────────────────────────────────────

class _RingPainter extends CustomPainter {
  final double progress;
  final Color trackColor;
  final Color arcColor;
  const _RingPainter(
      {required this.progress,
      required this.trackColor,
      required this.arcColor});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 7;
    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    final arc = Paint()
      ..color = arcColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, track);
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -pi / 2,
        progress * 2 * pi,
        false,
        arc,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.arcColor != arcColor;
}

// ─── Stats Row ────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  final DashboardState state;
  const _StatsRow({required this.state});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Row(
      children: [
        _StatCell(
            icon: Icons.local_fire_department_rounded,
            color: GameColors.streakOrange,
            value: '${state.streak}',
            label: s.streak),
        const SizedBox(width: 8),
        _StatCell(
            icon: Icons.emoji_events_rounded,
            color: GameColors.gold,
            value: '${state.longestStreak}',
            label: s.best),
        const SizedBox(width: 8),
        _StatCell(
            icon: Icons.check_circle_rounded,
            color: GameColors.xpBlue,
            value: '${state.totalCompletions}',
            label: s.total),
        const SizedBox(width: 8),
        _StatCell(
            icon: Icons.toll_rounded,
            color: GameColors.gold,
            value: '${state.gold}',
            label: s.gold),
        const SizedBox(width: 8),
        _StatCell(
            icon: Icons.bolt_rounded,
            color: GameColors.xpBlue,
            value: '${state.cumulativeXp}',
            label: s.totalXp),
      ],
    );
  }
}

class _StatCell extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  const _StatCell(
      {required this.icon,
      required this.color,
      required this.value,
      required this.label});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: gp.surface,
          borderRadius: BorderRadius.circular(GameSpacing.chipRadius),
          border: Border.all(color: gp.border, width: 0.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: gp.textPrimary,
                  height: 1,
                  letterSpacing: -0.5),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w600,
                  color: gp.textTert,
                  letterSpacing: 1.2),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Profile Links (Achievements, Progress & Streak) ──────────────────────────

/// Two tap-through rows replacing what used to be a full achievements grid,
/// a 14-day chart, and a streak-freeze shop card living inline on Profile —
/// each now opens its own screen, so Profile itself reads like a settings
/// page (a short list of rows) under the profile header, not a scroll of
/// stacked cards.
class _ProfileLinksSection extends StatelessWidget {
  final int unlockedCount;
  final int totalAchievements;
  final int streak;

  const _ProfileLinksSection({
    required this.unlockedCount,
    required this.totalAchievements,
    required this.streak,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(s.profileSection,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: gp.textSec,
                letterSpacing: 1.5)),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: gp.surface,
            borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
            border: Border.all(color: gp.border, width: 0.5),
          ),
          child: Column(
            children: [
              InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AchievementsScreen()),
                  );
                },
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(GameSpacing.cardRadius),
                  topRight: Radius.circular(GameSpacing.cardRadius),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Icon(Icons.emoji_events_rounded,
                          size: 20, color: GameColors.gold),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(s.achievementsRowTitle,
                            style: TextStyle(
                                fontSize: 15,
                                color: gp.textPrimary,
                                fontWeight: FontWeight.w500)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: GameColors.gold.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(
                              color: GameColors.gold.withOpacity(0.3),
                              width: 0.5),
                        ),
                        child: Text(
                          '$unlockedCount / $totalAchievements',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: GameColors.gold),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(Icons.chevron_right_rounded,
                          size: 18, color: gp.textTert),
                    ],
                  ),
                ),
              ),
              Container(height: 0.5, color: gp.divider),
              InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ProgressScreen()),
                  );
                },
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(GameSpacing.cardRadius),
                  bottomRight: Radius.circular(GameSpacing.cardRadius),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Icon(Icons.show_chart_rounded,
                          size: 20, color: gp.textSec),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(s.progressStreakTitle,
                            style: TextStyle(
                                fontSize: 15,
                                color: gp.textPrimary,
                                fontWeight: FontWeight.w500)),
                      ),
                      Icon(Icons.local_fire_department_rounded,
                          size: 15, color: GameColors.streakOrange),
                      const SizedBox(width: 3),
                      Text('$streak',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: gp.textSec)),
                      const SizedBox(width: 6),
                      Icon(Icons.chevron_right_rounded,
                          size: 18, color: gp.textTert),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Settings ─────────────────────────────────────────────────────────────────

/// Opens the language picker sheet from Settings — same [LanguageOptionCard]
/// rows as the first-launch picker, just presented as a sheet since the
/// locale is already known here.
void _showLanguageSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const _LanguageSheet(),
  );
}

class _LanguageSheet extends ConsumerWidget {
  const _LanguageSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final isAr = ref.watch(localeProvider).languageCode == 'ar';
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        decoration: BoxDecoration(
          color: gp.surfaceHigh,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: gp.border, width: 0.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: gp.border,
                  borderRadius: BorderRadius.circular(100),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              s.language,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: gp.textPrimary,
              ),
            ),
            const SizedBox(height: 18),
            LanguageOptionCard(
              nativeName: 'English',
              selected: !isAr,
              onTap: () {
                Navigator.pop(context);
                setLocale(ref, const Locale('en'));
              },
            ),
            const SizedBox(height: 10),
            LanguageOptionCard(
              nativeName: 'العربية',
              selected: isAr,
              textDirection: TextDirection.rtl,
              onTap: () {
                Navigator.pop(context);
                setLocale(ref, const Locale('ar'));
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens the app-wide theme preset picker from Settings.
void _showThemePresetSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const _ThemePresetSheet(),
  );
}

class _ThemePresetSheet extends ConsumerWidget {
  const _ThemePresetSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final isAr = s.isAr;
    final selectedId = ref.watch(themePresetProvider);
    final isPremium = ref.watch(premiumProvider);

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        decoration: BoxDecoration(
          color: gp.surfaceHigh,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: gp.border, width: 0.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: gp.border,
                  borderRadius: BorderRadius.circular(100),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              s.appearanceSheetTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: gp.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              s.appearancePremiumHint,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: gp.textSec),
            ),
            const SizedBox(height: 18),
            ...ThemePresets.all.map((preset) {
              final selected = preset.id == selectedId;
              final locked = preset.isPremium && !isPremium;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ThemePresetTile(
                  preset: preset,
                  selected: selected,
                  locked: locked,
                  label: isAr ? preset.nameAr : preset.nameEn,
                  onTap: () {
                    if (locked) {
                      Navigator.pop(context);
                      Navigator.pushNamed(context, '/premium');
                      return;
                    }
                    HapticFeedback.selectionClick();
                    ref.read(themePresetProvider.notifier).set(preset.id);
                    Navigator.pop(context);
                  },
                  // Preview works even for locked/premium presets — trying
                  // the look on the real screens is not the same as
                  // unlocking it, so it doesn't need the premium gate onTap
                  // above uses.
                  onPreview: () {
                    HapticFeedback.selectionClick();
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ThemePreviewScreen(preset: preset),
                      ),
                    );
                  },
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _ThemePresetTile extends StatelessWidget {
  final ThemePreset preset;
  final bool selected;
  final bool locked;
  final String label;
  final VoidCallback onTap;
  final VoidCallback onPreview;

  const _ThemePresetTile({
    required this.preset,
    required this.selected,
    required this.locked,
    required this.label,
    required this.onTap,
    required this.onPreview,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? preset.gold.withOpacity(0.08) : gp.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? preset.gold.withOpacity(0.5) : gp.border,
            width: selected ? 1.2 : 0.5,
          ),
        ),
        child: Row(
          children: [
            _PresetDot(color: preset.gold, size: 18),
            const SizedBox(width: 4),
            _PresetDot(color: preset.xpBlue, size: 18),
            const SizedBox(width: 4),
            _PresetDot(color: preset.streakOrange, size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: gp.textPrimary,
                ),
              ),
            ),
            // Nothing to preview for the preset already applied — for
            // every other tile (locked or not) this is a second tap target
            // nested inside the row's own tap target, which Flutter's
            // gesture arena resolves fine as long as this one claims the
            // hit first (HitTestBehavior.opaque).
            if (!selected) ...[
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onPreview,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.visibility_outlined,
                          size: 15, color: gp.textSec),
                      const SizedBox(width: 4),
                      Text(
                        s.preview,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: gp.textSec,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4),
            ],
            if (locked)
              Icon(Icons.lock_rounded, size: 16, color: gp.textTert)
            else if (selected)
              Icon(Icons.check_circle_rounded, size: 18, color: preset.gold),
          ],
        ),
      ),
    );
  }
}

class _PresetDot extends StatelessWidget {
  final Color color;
  final double size;
  const _PresetDot({required this.color, this.size = 12});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _SettingsSection extends ConsumerWidget {
  const _SettingsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locale = ref.watch(localeProvider);
    final isAr = locale.languageCode == 'ar';
    final reminderTime = ref.watch(reminderTimeProvider);
    final isGuest = ref.watch(guestModeProvider);
    final currentUser = ref.watch(authStateProvider).asData?.value;
    final canDeleteAccount = !isGuest && currentUser != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.settings,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: gp.textSec,
                  letterSpacing: 1.5)),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: gp.surface,
              borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
              border: Border.all(color: gp.border, width: 0.5),
            ),
            child: Column(
              children: [
                // GrowDaily Premium
                InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    Navigator.pushNamed(context, '/premium');
                  },
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(GameSpacing.cardRadius),
                    topRight: Radius.circular(GameSpacing.cardRadius),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        Icon(Icons.workspace_premium_rounded,
                            size: 20, color: GameColors.gold),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(s.premiumTitle,
                              style: TextStyle(
                                  fontSize: 15,
                                  color: gp.textPrimary,
                                  fontWeight: FontWeight.w600)),
                        ),
                        Icon(Icons.arrow_forward_ios_rounded,
                            size: 14, color: gp.textTert),
                      ],
                    ),
                  ),
                ),
                Container(height: 0.5, color: gp.divider),
                // Dark Mode toggle
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                        size: 20,
                        color: gp.textSec,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(s.darkMode,
                            style: TextStyle(
                                fontSize: 15,
                                color: gp.textPrimary,
                                fontWeight: FontWeight.w500)),
                      ),
                      Switch(
                        value: isDark,
                        onChanged: (_) {
                          HapticFeedback.selectionClick();
                          ref.read(themeModeProvider.notifier).toggle();
                        },
                      ),
                    ],
                  ),
                ),
                Container(height: 0.5, color: gp.divider),
                // Appearance (theme preset)
                InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    _showThemePresetSheet(context);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        Icon(Icons.palette_rounded, size: 20, color: gp.textSec),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(s.appearance,
                              style: TextStyle(
                                  fontSize: 15,
                                  color: gp.textPrimary,
                                  fontWeight: FontWeight.w500)),
                        ),
                        Consumer(builder: (context, ref, _) {
                          final presetId = ref.watch(themePresetProvider);
                          final preset = ThemePresets.byId(presetId);
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _PresetDot(color: preset.gold),
                              const SizedBox(width: 4),
                              _PresetDot(color: preset.xpBlue),
                              const SizedBox(width: 4),
                              _PresetDot(color: preset.streakOrange),
                              const SizedBox(width: 8),
                              Text(
                                isAr ? preset.nameAr : preset.nameEn,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: gp.textSec,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          );
                        }),
                        const SizedBox(width: 6),
                        Icon(Icons.chevron_right_rounded,
                            size: 18, color: gp.textTert),
                      ],
                    ),
                  ),
                ),
                Container(height: 0.5, color: gp.divider),
                // Language picker
                InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    _showLanguageSheet(context);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        Icon(Icons.language_rounded, size: 20, color: gp.textSec),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(s.language,
                              style: TextStyle(
                                  fontSize: 15,
                                  color: gp.textPrimary,
                                  fontWeight: FontWeight.w500)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: GameColors.gold.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(100),
                            border: Border.all(
                                color: GameColors.gold.withOpacity(0.3), width: 0.5),
                          ),
                          child: Text(
                            isAr ? 'العربية' : 'English',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: GameColors.gold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Container(height: 0.5, color: gp.divider),
                // Daily Reminder
                InkWell(
                  onTap: () async {
                    HapticFeedback.selectionClick();
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: reminderTime ?? const TimeOfDay(hour: 20, minute: 0),
                    );
                    if (picked != null) {
                      final granted = await ref
                          .read(reminderTimeProvider.notifier)
                          .set(picked);
                      if (!granted && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(s.reminderPermissionDenied),
                            duration: const Duration(seconds: 4),
                          ),
                        );
                      }
                    }
                  },
                  onLongPress: reminderTime == null
                      ? null
                      : () async {
                          HapticFeedback.mediumImpact();
                          await ref.read(reminderTimeProvider.notifier).clear();
                        },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        Icon(Icons.notifications_rounded, size: 20, color: gp.textSec),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(s.dailyReminder,
                              style: TextStyle(
                                  fontSize: 15,
                                  color: gp.textPrimary,
                                  fontWeight: FontWeight.w500)),
                        ),
                        Flexible(
                          child: Text(
                            reminderTime != null
                                ? reminderTime.format(context)
                                : s.tapToSetReminder,
                            textAlign: TextAlign.end,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: reminderTime != null ? GameColors.gold : gp.textTert,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Container(height: 0.5, color: gp.divider),
                // Sign Out
                InkWell(
                  onTap: () async {
                    HapticFeedback.mediumImpact();
                    await setGuestMode(ref, false);
                    await ref.read(authNotifierProvider.notifier).signOut();
                    if (context.mounted) {
                      Navigator.pushNamedAndRemoveUntil(
                          context, '/', (_) => false);
                    }
                  },
                  borderRadius: canDeleteAccount
                      ? null
                      : const BorderRadius.only(
                          bottomLeft: Radius.circular(GameSpacing.cardRadius),
                          bottomRight: Radius.circular(GameSpacing.cardRadius),
                        ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Icon(Icons.logout_rounded,
                            size: 20, color: GameColors.error),
                        const SizedBox(width: 12),
                        Text(s.signOut,
                            style: const TextStyle(
                                fontSize: 15,
                                color: GameColors.error,
                                fontWeight: FontWeight.w600)),
                        const Spacer(),
                        Icon(Icons.arrow_forward_ios_rounded,
                            size: 14, color: gp.textTert),
                      ],
                    ),
                  ),
                ),
                if (canDeleteAccount) ...[
                  Container(height: 0.5, color: gp.divider),
                  // Delete Account — required by App Store review guideline
                  // 5.1.1(v): account creation implies in-app account
                  // deletion.
                  InkWell(
                    onTap: () => showDeleteAccountSheet(context, ref),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(GameSpacing.cardRadius),
                      bottomRight: Radius.circular(GameSpacing.cardRadius),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Icon(Icons.delete_forever_rounded,
                              size: 20, color: GameColors.error),
                          const SizedBox(width: 12),
                          Text(s.deleteAccount,
                              style: const TextStyle(
                                  fontSize: 15,
                                  color: GameColors.error,
                                  fontWeight: FontWeight.w600)),
                          const Spacer(),
                          Icon(Icons.arrow_forward_ios_rounded,
                              size: 14, color: gp.textTert),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

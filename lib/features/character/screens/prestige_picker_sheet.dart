import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../dashboard/notifiers/dashboard_notifier.dart';
import '../models/prestige_tier.dart';
import '../notifiers/prestige_notifier.dart';
import '../widgets/prestige_mark.dart';

/// Opens [PrestigePickerSheet] — the one place to browse every Level
/// Prestige tier and choose which unlocked one to display. Reachable from
/// the Profile hero header's title chip (see _HeroHeader in
/// profile_screen_hero_dashboard.dart).
void showPrestigePicker(BuildContext context) {
  HapticFeedback.selectionClick();
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const PrestigePickerSheet(),
  );
}

/// Every [PrestigeTier], earned or not, with a plain gold/character-closet-
/// style locked/unlocked/equipped presentation — reusing that same visual
/// language (a colored icon tile, a title, a trailing state indicator)
/// rather than inventing a new one, even though the unlock rule underneath
/// (level, not gold) is completely different from CharacterClosetScreen's
/// shop rows. See PrestigeState.displayedTier for what "equipped" actually
/// resolves to when no explicit pick has been made.
class PrestigePickerSheet extends ConsumerWidget {
  const PrestigePickerSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final isAr = s.isAr;
    final level = ref.watch(dashboardProvider).level;
    final prestige = ref.watch(prestigeProvider);
    final displayed = prestige.displayedTier(level);
    final isAutoMode = prestige.equippedTierId == null;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        decoration: BoxDecoration(
          color: gp.surfaceHigh,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: gp.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              s.prestigeTitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: gp.textPrimary),
            ),
            const SizedBox(height: 4),
            Text(
              s.prestigeSubtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: gp.textSec, height: 1.4),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                physics: const BouncingScrollPhysics(),
                children: [
                  _PrestigeRow(
                    icon: Icons.auto_awesome_motion_rounded,
                    color: prestigeMarkFor(displayed)?.color(gp.dark) ??
                        displayed.color,
                    title: s.prestigeAutoOption,
                    subtitle: s.prestigeAutoOptionDesc(displayed.title(isAr)),
                    isLocked: false,
                    isSelected: isAutoMode,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      ref.read(prestigeProvider.notifier).equipTier(null, level);
                    },
                  ),
                  const SizedBox(height: 8),
                  Container(height: 0.5, color: gp.divider),
                  const SizedBox(height: 8),
                  for (final tier in PrestigeCatalog.tiers) ...[
                    _PrestigeRow(
                      icon: tier.icon,
                      // The rank mark, so this sheet shows the ACTUAL ladder
                      // rather than eight unrelated glyphs — a locked tier
                      // here is the real silhouette you are climbing toward,
                      // just dimmed.
                      mark: prestigeMarkFor(tier),
                      color: prestigeMarkFor(tier)?.color(gp.dark) ??
                          tier.color,
                      title: tier.title(isAr),
                      subtitle: level >= tier.minLevel
                          ? s.prestigeUnlockedAt(tier.minLevel)
                          : s.prestigeLockedUntil(tier.minLevel),
                      isLocked: level < tier.minLevel,
                      isSelected: !isAutoMode && prestige.equippedTierId == tier.id,
                      onTap: level < tier.minLevel
                          ? null
                          : () {
                              HapticFeedback.selectionClick();
                              ref
                                  .read(prestigeProvider.notifier)
                                  .equipTier(tier.id, level);
                            },
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 48pt is not a taste call: it is exactly the apex engraving threshold in
/// prestige_mark.dart (_kApexEngravingMinSize). One pixel under it and Legacy
/// falls back to a plain filled disc, which is what this sheet showed for the
/// whole life of the medal — the engraving existed but had nowhere to appear
/// outside the rank-up moment, which fires once, at level 100.
///
/// This is the surface that has to clear the gate because it is the only one
/// built for BROWSING the ladder. The other two marks stay small on purpose:
/// the room leaderboard (12pt) and the Profile hero chip (13pt) are inline
/// beside text, where the gate's own argument holds — an engraved figure at
/// that size is mud, and mud that costs a save layer per scrolling row.
const double _kMarkSize = 48;

/// The tinted tile behind it, leaving a 4pt margin on each side. It grew with
/// the mark rather than letting the mark overflow it, which puts 18pt on every
/// row. Affordable here: nine rows at the old 38pt tile already overran the
/// sheet's 80%-of-screen cap, so this list was always a scrolling one.
const double _kTileSize = 56;

class _PrestigeRow extends StatelessWidget {
  final IconData icon;

  /// The rank mark for a real tier; null for the "automatic" row, which is a
  /// mode rather than a rung and so has no place on the ladder.
  final PrestigeMarkSpec? mark;
  final Color color;
  final String title;
  final String subtitle;
  final bool isLocked;
  final bool isSelected;
  final VoidCallback? onTap;

  const _PrestigeRow({
    required this.icon,
    this.mark,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.isLocked,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isSelected ? color.withOpacity(0.10) : gp.surface,
            borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
            border: Border.all(
              color: isSelected ? color.withOpacity(0.5) : gp.border,
              width: isSelected ? 1 : 0.5,
            ),
          ),
          child: Row(
            children: [
              Opacity(
                opacity: isLocked ? 0.4 : 1,
                child: Container(
                  width: _kTileSize,
                  height: _kTileSize,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(GameSpacing.buttonRadius),
                  ),
                  child: Center(
                    child: mark == null
                        ? Icon(icon, size: 26, color: color)
                        // Deliberately NO flat colour. The base ink is the
                        // same either way — this row already passes the
                        // mark's own pinned ladder colour, and PrestigeMark
                        // falls back to exactly that — but a flat colour
                        // also switches off the metal gradient and the apex
                        // engraving, which are the things worth coming here
                        // to look at.
                        : PrestigeMark(spec: mark!, size: _kMarkSize),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isLocked ? gp.textTert : gp.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 11.5, color: gp.textTert),
                    ),
                  ],
                ),
              ),
              if (isLocked)
                Icon(Icons.lock_outline_rounded, size: 17, color: gp.textTert)
              else if (isSelected)
                Icon(Icons.check_circle_rounded, size: 20, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

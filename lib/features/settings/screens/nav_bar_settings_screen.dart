import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/nav_badges_setting_provider.dart';
import '../../../core/providers/nav_bar_hint_provider.dart';
import '../../../core/providers/nav_layout_provider.dart';
import '../../../core/services/analytics_service.dart';
import '../../../core/theme/game_theme.dart';
import '../../../shared/providers/nav_badges_provider.dart';
import '../../../shared/widgets/game_nav_bar.dart';
import '../../../shared/widgets/nav_tabs.dart';
import '../../premium/notifiers/premium_notifier.dart';
import '../../premium/screens/premium_screen.dart';

/// Settings › Personalization › Bottom bar: which tabs the bar holds, and
/// in what order.
///
/// Every change lands the moment it is made (the theme and font sheets set
/// the pattern: no Save button, the thing you are looking at IS the
/// setting), through [navLayoutProvider], which persists to this device and
/// to the account. HomeShell underneath rebuilds live, so the bar is
/// already right by the time this screen is popped.
///
/// Premium gate. Add, remove and reorder all go through [_Gate.edit],
/// which lets Premium (or the new-install trial) through and sends
/// everyone else to the paywall, led by this benefit. Two things are
/// deliberately NOT gated: opening the screen, so a free account sees what
/// it would get rather than a locked row it cannot explain, and Reset, so
/// an account whose access lapsed is never stuck with a bar it can no
/// longer change. That is the rule every other gate in the app follows,
/// access ending takes nothing away: a layout built during the trial keeps
/// working after it, and can always go back to the default.
class NavBarSettingsScreen extends ConsumerWidget {
  const NavBarSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final tabs = ref.watch(navLayoutProvider);
    final unlocked = ref.watch(premiumAccessProvider);
    final gate = _Gate(context, unlocked: unlocked);
    final notifier = ref.read(navLayoutProvider.notifier);
    final full = tabs.length >= kNavTabsMax;
    // Reaching this screen by any route is what the bar's one-time
    // coach-mark exists to cause, so arriving here retires it for good.
    // A microtask, because a provider cannot change mid-build.
    if (!ref.watch(navBarHintSeenProvider)) {
      Future.microtask(() => markNavBarHintSeen(ref));
    }
    final available = [
      for (final t in NavTab.values)
        if (!tabs.contains(t)) t,
    ];

    void add(NavTab tab) {
      if (!gate.edit()) return;
      HapticFeedback.selectionClick();
      notifier.add(tab);
    }

    return Scaffold(
      backgroundColor: gp.bg,
      appBar: AppBar(
        backgroundColor: gp.bg,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        title: Text(
          s.navBarSettingsTitle,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: gp.textPrimary,
          ),
        ),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            s.navBarSettingsIntro,
            style: TextStyle(fontSize: 13, color: gp.textSec, height: 1.4),
          ),
          const SizedBox(height: 14),
          // The preview draws the REAL badges, not sample ones: what the
          // switch below changes is exactly what the bar shows right now,
          // and a made-up "2" on Rooms would be a question, not a preview.
          _BarPreview(tabs: tabs, badges: ref.watch(navBadgesProvider)),
          const SizedBox(height: 10),
          _BadgesSwitchRow(
            enabled: ref.watch(navBadgesEnabledProvider),
            onChanged: (v) {
              HapticFeedback.selectionClick();
              ref.read(navBadgesEnabledProvider.notifier).set(v);
            },
          ),
          if (!unlocked) ...[
            const SizedBox(height: 14),
            _LockedCard(onTap: gate.edit),
          ],
          const SizedBox(height: 24),
          _SectionTitle('${s.navBarYourTabs}  ${tabs.length}/$kNavTabsMax'),
          const SizedBox(height: 12),
          _Card(
            child: ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: tabs.length,
              onReorder: (oldIndex, newIndex) {
                if (!gate.edit()) return;
                HapticFeedback.mediumImpact();
                notifier.move(oldIndex, newIndex);
              },
              proxyDecorator: (child, index, animation) => Material(
                color: Colors.transparent,
                child: child,
              ),
              itemBuilder: (context, i) {
                final tab = tabs[i];
                return _TabRow(
                  key: ValueKey(tab),
                  index: i,
                  tab: tab,
                  first: i == 0,
                  draggable: unlocked,
                  onTap: unlocked ? null : gate.edit,
                  trailing: tab.isPinned
                      ? _RowAction(
                          icon: Icons.lock_rounded,
                          tooltip: s.navBarPinned,
                          color: gp.textTert,
                        )
                      : _RowAction(
                          icon: Icons.remove_circle_outline_rounded,
                          tooltip: s.navBarRemove,
                          color: gp.textSec,
                          onTap: () {
                            if (!gate.edit()) return;
                            HapticFeedback.selectionClick();
                            notifier.remove(tab);
                          },
                        ),
                );
              },
            ),
          ),
          const SizedBox(height: 24),
          _SectionTitle(s.navBarAddTabs),
          const SizedBox(height: 12),
          if (full) ...[
            Text(
              s.navBarFull,
              style: TextStyle(fontSize: 12.5, color: gp.textSec, height: 1.35),
            ),
            const SizedBox(height: 10),
          ],
          _Card(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < available.length; i++)
                  _TabRow(
                    key: ValueKey(available[i]),
                    index: i,
                    tab: available[i],
                    first: i == 0,
                    draggable: false,
                    dimmed: full,
                    onTap: full ? null : () => add(available[i]),
                    trailing: _RowAction(
                      icon: Icons.add_circle_outline_rounded,
                      tooltip: full ? s.navBarFull : s.navBarAdd,
                      color: full ? gp.textTert : GameColors.gold,
                      onTap: full ? null : () => add(available[i]),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: TextButton.icon(
              onPressed: isDefaultNavTabs(tabs)
                  ? null
                  : () {
                      HapticFeedback.mediumImpact();
                      notifier.reset();
                    },
              icon: const Icon(Icons.restart_alt_rounded, size: 18),
              label: Text(s.navBarReset),
            ),
          ),
        ],
      ),
    );
  }
}

/// One funnel for every edit on the screen, see the class doc.
class _Gate {
  final BuildContext context;
  final bool unlocked;
  const _Gate(this.context, {required this.unlocked});

  /// True when the edit may go ahead. Otherwise opens the paywall, led by
  /// the bottom-bar benefit, and answers false so the caller changes
  /// nothing.
  bool edit() {
    if (unlocked) return true;
    AnalyticsService.instance
        .track('premium_gate_hit', props: {'gate': 'nav_bar'});
    HapticFeedback.selectionClick();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const PremiumScreen(
          reason: PremiumReason.navBar,
          source: 'nav_bar',
        ),
      ),
    );
    return false;
  }
}

/// The bar as it will look, drawn by the real [GameNavBar] so the preview
/// cannot drift from the thing it previews. A picture of the layout, not a
/// second navigator: pointer and semantics are both switched off.
class _BarPreview extends StatelessWidget {
  final List<NavTab> tabs;
  final Map<NavTab, NavBadge> badges;
  const _BarPreview({required this.tabs, this.badges = const {}});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: gp.bg,
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        border: Border.all(color: gp.border, width: 0.5),
      ),
      // The glass bar pads itself for the home indicator through SafeArea;
      // mid-screen that inset would just be a blank strip under the pill.
      child: MediaQuery.removePadding(
        context: context,
        removeBottom: true,
        child: ExcludeSemantics(
          child: IgnorePointer(
            child: GameNavBar(currentIndex: 0, tabs: tabs, badges: badges),
          ),
        ),
      ),
    );
  }
}

/// Badges on or off, directly under the preview they change. Not gated:
/// turning a thing off is never the paid part. Same anatomy as the
/// Settings screen's Dark Mode row (icon · label · Switch), with one line
/// under the label saying what "badges" are, since the word alone does
/// not: the row is the only place in the app that names them.
class _BadgesSwitchRow extends StatelessWidget {
  final bool enabled;
  final ValueChanged<bool> onChanged;
  const _BadgesSwitchRow({required this.enabled, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    return _Card(
      child: InkWell(
        onTap: () => onChanged(!enabled),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.notifications_active_outlined,
                  size: 20, color: gp.textSec),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.navBadgesTitle,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: gp.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      s.navBadgesDesc,
                      style: TextStyle(
                        fontSize: 12,
                        color: gp.textSec,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Switch(
                value: enabled,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: onChanged,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What a free account sees above the (locked) editor: the benefit, in
/// gold, with the one button that unlocks it.
class _LockedCard extends StatelessWidget {
  final VoidCallback onTap;
  const _LockedCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    return Material(
      color: GameColors.gold.withOpacity(0.10),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        side: BorderSide(color: GameColors.gold.withOpacity(0.35), width: 0.75),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.workspace_premium_rounded,
                  size: 26, color: context.gp.goldInk),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.navBarLockedTitle,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: gp.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      s.navBarLockedBody,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: gp.textSec,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 10),
                    FilledButton(
                      onPressed: onTap,
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      child: Text(s.navBarLockedCta),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: context.gp.textSec,
        letterSpacing: 1.5,
      ),
    );
  }
}

/// The surface card the rows sit in. A Material, not a Container, for the
/// reason SettingsScreen's _SettingsGroup gives: an InkWell paints its
/// ripple onto the nearest Material ancestor, and with a Container here the
/// rows would press with no visible feedback at all.
class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Material(
      color: gp.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        side: BorderSide(color: gp.border, width: 0.5),
      ),
      child: child,
    );
  }
}

/// One row: grip (when draggable) · icon · label · action. Shared by the
/// "your bar" list and the "add" list so the two read as one anatomy.
///
/// When [draggable], the grip starts a drag at once and the rest of the row
/// starts one on press-and-hold, so a thumb that lands anywhere on the row
/// can still move it; the grip stays as the visual cue.
class _TabRow extends StatelessWidget {
  final int index;
  final NavTab tab;
  final bool first;
  final bool draggable;
  final bool dimmed;
  final Widget trailing;
  final VoidCallback? onTap;

  const _TabRow({
    super.key,
    required this.index,
    required this.tab,
    required this.first,
    required this.draggable,
    required this.trailing,
    this.dimmed = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    Widget row = InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            if (draggable)
              ReorderableDragStartListener(
                index: index,
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: Icon(Icons.drag_handle_rounded,
                      size: 20, color: gp.textTert),
                ),
              ),
            Icon(tab.icon, size: 20, color: dimmed ? gp.textTert : gp.textSec),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                tab.label(s),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: dimmed ? gp.textTert : gp.textPrimary,
                ),
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
    if (draggable) {
      row = ReorderableDelayedDragStartListener(index: index, child: row);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!first) Container(height: 0.5, color: gp.divider),
        row,
      ],
    );
  }
}

/// The row's trailing glyph: a real button when it does something, a
/// plain (tooltipped) icon when it only says something, because a disabled
/// IconButton would paint the lock in the theme's disabled grey instead of
/// the colour the row asked for.
class _RowAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback? onTap;

  const _RowAction({
    required this.icon,
    required this.tooltip,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final glyph = Icon(icon, size: 22, color: color);
    if (onTap == null) {
      return Tooltip(
        message: tooltip,
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: glyph,
        ),
      );
    }
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      icon: glyph,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
    );
  }
}

import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/nav_layout_provider.dart';
import '../../features/character/screens/character_closet_screen.dart';
import '../../features/grid/screens/grid_screen.dart';
import '../../features/matrix/screens/matrix_screen.dart';
import '../../features/milestones/screens/life_timeline_screen.dart';
import '../../features/night_review/screens/night_review_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/profile/screens/progress_hub_screen.dart';
import '../../features/rewards/screens/custom_rewards_screen.dart';
import '../../features/rooms/screens/rooms_hub_screen.dart';
import '../../features/tasbih/tasbih_screen.dart';

export '../../core/providers/nav_layout_provider.dart'
    show NavTab, kDefaultNavTabs, kNavTabsMax;

/// A small mark on a bar tab: a count, or a dot for "something is waiting"
/// where a number would mean nothing. Computed by navBadgesProvider (see
/// shared/providers), drawn by GameNavBar.
///
/// Every badge here means "this needs you", never "this exists": a count of
/// rooms you are a member of would sit on the tab forever and teach people
/// to ignore it. So Rooms counts the live rooms still waiting on today's
/// habits, Tasks counts today's open tasks, and Night Review carries a dot
/// only in the evening window before tonight's review is saved. Each one
/// clears itself as the person does the thing.
class NavBadge {
  final int count;
  final bool dot;
  const NavBadge.count(this.count) : dot = false;
  const NavBadge.dot()
      : count = 0,
        dot = true;
  bool get isEmpty => count <= 0 && !dot;
}

/// The widget side of [NavTab]: what a tab looks like in the bar and what
/// it shows when selected. Split from the enum (see nav_layout_provider.dart)
/// so the layout rules stay widget-free and unit-testable, while this file
/// is the one place that has to know about every feature's screen, the way
/// home_shell.dart already did for three of them.
///
/// Icons are the SAME glyphs the app already uses for each destination
/// (Profile's link rows, the Grid header's tasbih shortcut), so a tab in
/// the bar reads as the thing the person already knows, not a new symbol
/// for it.
extension NavTabUi on NavTab {
  IconData get icon => switch (this) {
        NavTab.grid => Icons.grid_view_rounded,
        NavTab.profile => Icons.person_rounded,
        NavTab.matrix => Icons.view_quilt_rounded,
        NavTab.rooms => Icons.groups_rounded,
        NavTab.progress => Icons.dashboard_rounded,
        NavTab.settings => Icons.settings_rounded,
        NavTab.tasbih => Icons.blur_circular,
        NavTab.rewards => Icons.card_giftcard_rounded,
        NavTab.closet => Icons.checkroom_rounded,
        NavTab.nightReview => Icons.bedtime_rounded,
        NavTab.yearRecord => Icons.timeline_rounded,
      };

  /// The bar label: one short word where the screen title is two, because
  /// five of these share a phone's width at a 10pt label (see
  /// _GlassNavItem's text-scale cap for the exact arithmetic).
  String label(S s) => switch (this) {
        NavTab.grid => s.navGrid,
        NavTab.profile => s.navProfile,
        NavTab.matrix => s.navMatrix,
        NavTab.rooms => s.navRooms,
        NavTab.progress => s.navProgress,
        NavTab.settings => s.navSettings,
        NavTab.tasbih => s.navTasbih,
        NavTab.rewards => s.navRewards,
        NavTab.closet => s.navCloset,
        NavTab.nightReview => s.navNightReview,
        NavTab.yearRecord => s.navYearRecord,
      };

  /// The page HomeShell mounts for this tab, and the screen it pushes when
  /// a tab that is NOT in the bar is requested (see HomeShell.openTab).
  ///
  /// Every one of these is a screen that was already pushed as a route
  /// somewhere in the app, so each carries its own Scaffold and AppBar.
  /// Inside the shell, which is the root route, AppBar's implied back
  /// button simply does not appear (nothing to pop), and none of them pop
  /// themselves after an action: that was checked screen by screen before
  /// each was allowed in this list, and it is the bar for adding another.
  Widget page() => switch (this) {
        NavTab.grid => const GridScreen(),
        NavTab.profile => const ProfileScreen(),
        NavTab.matrix => const MatrixScreen(),
        NavTab.rooms => const RoomsHubScreen(),
        NavTab.progress => const ProgressHubScreen(),
        NavTab.settings => const SettingsScreen(),
        NavTab.tasbih => const TasbihScreen(),
        NavTab.rewards => const CustomRewardsScreen(),
        NavTab.closet => const CharacterClosetScreen(),
        NavTab.nightReview => const NightReviewScreen(),
        NavTab.yearRecord => const LifeTimelineScreen(),
      };
}

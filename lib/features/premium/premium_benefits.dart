/// The paywall's list of what Premium includes, as the code ships it, and
/// the list as phones show it once the admin tool's edits are laid over it.
///
/// Every row here is a claim about what the purchase delivers (guidelines
/// 2.3.1(a), 3.1.2(c), 5.6), which is why each one maps to a real,
/// currently enforced gate: see each string's doc comment in
/// app_strings.dart for the file and the check behind it, and
/// premium_benefit_copy_test.dart for what their words are held to. The last
/// row is the one promise rather than a gate: Premium features added later
/// come with it (see premiumBenefitFutureDesc for what keeps that true).
///
/// Since 2026-09-26 the admin tool can reorder this list, take a row off,
/// change a row's icon, and add a row of its own (see content_edits.dart).
/// A row's words are its S strings, edited like every other string, so a
/// built-in row edited on the admin tool still says what the code says
/// everywhere else it appears (the voice note player's lock, the history
/// demo gate).
library;

import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/l10n/content_edits.dart';

/// One built-in row: a stable id (the admin tool's edits are keyed by it,
/// so it is never renamed), an icon by name from [kBenefitIcons], and its
/// two S strings.
@immutable
class BuiltInBenefit {
  const BuiltInBenefit({
    required this.id,
    required this.icon,
    required this.title,
    required this.desc,
  });

  final String id;
  final String icon;
  final String Function(S s) title;
  final String Function(S s) desc;
}

/// The code's own list, in the order the paywall shows it.
///
/// scripts/admin_lookup reads this list (through the wording generator's
/// catalog), so keep each entry in this exact form: a string id, a string
/// icon, and `(s) => s.<member>` for the title and the description.
final List<BuiltInBenefit> kBuiltInPremiumBenefits = [
  BuiltInBenefit(
    id: 'habits',
    icon: 'grid_on',
    title: (s) => s.premiumBenefitHabitsTitle,
    desc: (s) => s.premiumBenefitHabitsDesc,
  ),
  // Second, beside habits: the two numbers a free account can reach.
  BuiltInBenefit(
    id: 'rooms',
    icon: 'groups',
    title: (s) => s.premiumBenefitRoomsTitle,
    desc: (s) => s.premiumBenefitRoomsDesc,
  ),
  BuiltInBenefit(
    id: 'history',
    icon: 'history',
    title: (s) => s.premiumBenefitHistoryTitle,
    desc: (s) => s.premiumBenefitHistoryDesc,
  ),
  BuiltInBenefit(
    id: 'insights',
    icon: 'insights',
    title: (s) => s.premiumBenefitInsightsTitle,
    desc: (s) => s.premiumBenefitInsightsDesc,
  ),
  BuiltInBenefit(
    id: 'appearance',
    icon: 'palette',
    title: (s) => s.premiumBenefitAppearanceTitle,
    desc: (s) => s.premiumBenefitAppearanceDesc,
  ),
  BuiltInBenefit(
    id: 'voice',
    icon: 'mic',
    title: (s) => s.premiumBenefitVoiceTitle,
    desc: (s) => s.premiumBenefitVoiceDesc,
  ),
  BuiltInBenefit(
    id: 'reminders',
    icon: 'notifications_active',
    title: (s) => s.premiumBenefitTaskRemindersTitle,
    desc: (s) => s.premiumBenefitTaskRemindersDesc,
  ),
  BuiltInBenefit(
    id: 'bottom-bar',
    icon: 'dashboard_customize',
    title: (s) => s.premiumBenefitNavBarTitle,
    desc: (s) => s.premiumBenefitNavBarDesc,
  ),
  // A heart read as charity; this row sells what comes next.
  BuiltInBenefit(
    id: 'future',
    icon: 'auto_awesome',
    title: (s) => s.premiumBenefitFutureTitle,
    desc: (s) => s.premiumBenefitFutureDesc,
  ),
];

/// Every icon a benefit row can wear, by the name the admin tool stores.
///
/// A fixed list on purpose: Flutter only ships the icons the code names
/// (the rest are tree-shaken out of the font), so an icon picked on the
/// admin tool has to be one of these to be drawn at all. The admin tool
/// offers exactly these names (the wording generator copies them into its
/// catalog), drawn from the same Material set. Adding a name here makes it
/// pickable once the admin tool's catalog is rebuilt; phones on an older
/// build draw a benefit's own icon instead (see resolveBenefits).
const Map<String, IconData> kBenefitIcons = {
  // Premium itself
  'workspace_premium': Icons.workspace_premium_rounded,
  'auto_awesome': Icons.auto_awesome_rounded,
  'star': Icons.star_rounded,
  'diamond': Icons.diamond_rounded,
  'verified': Icons.verified_rounded,
  'bolt': Icons.bolt_rounded,
  'rocket_launch': Icons.rocket_launch_rounded,
  'celebration': Icons.celebration_rounded,
  // Habits and progress
  'grid_on': Icons.grid_on_rounded,
  'check_circle': Icons.check_circle_rounded,
  'checklist': Icons.checklist_rounded,
  'all_inclusive': Icons.all_inclusive_rounded,
  'local_fire_department': Icons.local_fire_department_rounded,
  'trending_up': Icons.trending_up_rounded,
  'insights': Icons.insights_rounded,
  'bar_chart': Icons.bar_chart_rounded,
  'emoji_events': Icons.emoji_events_rounded,
  'event_repeat': Icons.event_repeat_rounded,
  'calendar_month': Icons.calendar_month_rounded,
  'history': Icons.history_rounded,
  // Making it yours
  'palette': Icons.palette_rounded,
  'dashboard_customize': Icons.dashboard_customize_rounded,
  'widgets': Icons.widgets_rounded,
  'tune': Icons.tune_rounded,
  'image': Icons.image_rounded,
  'photo_library': Icons.photo_library_rounded,
  'share': Icons.share_rounded,
  // Voice and notes
  'mic': Icons.mic_rounded,
  'headphones': Icons.headphones_rounded,
  'sticky_note_2': Icons.sticky_note_2_rounded,
  'format_quote': Icons.format_quote_rounded,
  'bookmark': Icons.bookmark_rounded,
  'menu_book': Icons.menu_book_rounded,
  // Reminders and time
  'notifications_active': Icons.notifications_active_rounded,
  'alarm': Icons.alarm_rounded,
  'timer': Icons.timer_rounded,
  'dark_mode': Icons.dark_mode_rounded,
  'wb_sunny': Icons.wb_sunny_rounded,
  'nightlight': Icons.nightlight_rounded,
  // People and worship
  'groups': Icons.groups_rounded,
  'volunteer_activism': Icons.volunteer_activism_rounded,
  'favorite': Icons.favorite_rounded,
  'mosque': Icons.mosque_rounded,
  'self_improvement': Icons.self_improvement_rounded,
  'spa': Icons.spa_rounded,
  'eco': Icons.eco_rounded,
  'mood': Icons.mood_rounded,
  // Devices and your data
  'cloud_done': Icons.cloud_done_rounded,
  'backup': Icons.backup_rounded,
  'sync': Icons.sync_rounded,
  'phone_iphone': Icons.phone_iphone_rounded,
  'watch': Icons.watch_rounded,
  'lock': Icons.lock_rounded,
  'lock_open': Icons.lock_open_rounded,
};

/// The icon an added benefit wears when its own is not in this build.
const String kBenefitFallbackIcon = 'auto_awesome';

/// One row of the paywall's benefit list, ready to draw.
@immutable
class PremiumBenefitView {
  const PremiumBenefitView({
    required this.id,
    required this.icon,
    required this.title,
    required this.desc,
  });

  /// A built-in benefit's id, or the admin tool's id for one it added.
  final String id;
  final IconData icon;
  final String title;
  final String desc;
}

/// The benefit list as phones show it, in [s]'s language: the code's list
/// with the admin's [edits] laid over it (see resolveBenefits), a built-in
/// row's words from [s] (so string edits apply too), an added row's own.
List<PremiumBenefitView> premiumBenefitsFor(S s, BenefitEdits? edits) {
  final byId = {for (final b in kBuiltInPremiumBenefits) b.id: b};
  final slots = resolveBenefits(
    builtIn: [
      for (final b in kBuiltInPremiumBenefits)
        BenefitBuiltIn(id: b.id, icon: b.icon),
    ],
    knownIcons: kBenefitIcons.keys.toSet(),
    fallbackIcon: kBenefitFallbackIcon,
    edits: edits,
  );
  return [
    for (final slot in slots)
      PremiumBenefitView(
        id: slot.id,
        icon: kBenefitIcons[slot.icon] ?? kBenefitIcons[kBenefitFallbackIcon]!,
        title: slot.added?.title(s.isAr) ?? byId[slot.id]!.title(s),
        desc: slot.added?.desc(s.isAr) ?? byId[slot.id]!.desc(s),
      ),
  ];
}

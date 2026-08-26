import 'dart:math' show pi;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
// hide TextDirection: intl's own TextDirection enum (LTR/RTL/UNKNOWN) would
// otherwise collide with dart:ui/material's TextDirection (ltr/rtl) the
// moment either is referenced unqualified anywhere in this library (this
// file's part files included, e.g. profile_screen_sheets.dart's
// TextDirection.rtl) - DateFormat and everything else this file uses from
// intl are unaffected. Same fix as room_detail_screen.dart's identical
// import, which hit this exact collision first.

import '../../../core/extensions/datetime_ext.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/app_guide_provider.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/theme/game_theme.dart';
import '../../../core/theme/theme_preset.dart';
import '../../../core/utils/bidi_fraction.dart';
import '../../../features/auth/notifiers/auth_notifier.dart';
import '../../../features/character/notifiers/character_notifier.dart';
import '../../../features/character/notifiers/prestige_notifier.dart';
import '../../../features/character/screens/character_closet_screen.dart';
import '../../../features/character/screens/prestige_picker_sheet.dart';
import '../../../features/character/widgets/character_avatar.dart';
import '../../../features/character/widgets/prestige_mark.dart';
import '../../habits/widgets/habit_color_picker.dart'
    show argbToHsv, hsvToArgb;
import '../../matrix/widgets/reminder_picker.dart' show arabicDigits;
import '../../../features/dashboard/notifiers/dashboard_notifier.dart';
import '../../../features/grid/notifiers/weekly_grid_notifier.dart';
import '../../../features/grid/widgets/weekly_recap_card.dart';
import '../../../features/habits/notifiers/custom_habits_notifier.dart';
import '../../../features/language/widgets/language_option_card.dart';
import '../../../features/night_review/notifiers/night_review_notifier.dart';
import '../../../features/premium/notifiers/premium_notifier.dart';
import '../../../features/premium/screens/premium_screen.dart';
import '../../../features/rooms/notifiers/rooms_notifier.dart';
import '../../../features/rooms/screens/rooms_hub_screen.dart';
import '../../../shared/widgets/coach_mark_overlay.dart';
import '../../milestones/reports/reports_screen.dart';
import '../../milestones/screens/life_timeline_screen.dart';
import '../widgets/delete_account_sheet.dart';
import '../widgets/edit_name_sheet.dart';
import '../widgets/stat_info_sheet.dart';
import 'progress_hub_screen.dart';
import 'theme_preview_screen.dart';

part 'profile_screen_hero_dashboard.dart';
part 'profile_screen_banners.dart';
part 'profile_screen_sheets.dart';
part 'profile_screen_settings.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final state = ref.watch(dashboardProvider);
    final user = FirebaseAuth.instance.currentUser;
    final savedName = state.displayName.trim();
    final displayName =
        savedName.isNotEmpty ? savedName : (user?.email?.split('@').first ?? 'Warrior');

    return Scaffold(
      backgroundColor: gp.bg,
      // Nav bar now owned by HomeShell — see that widget's doc comment.
      //
      // body is a Stack (not just CustomScrollView) so App Guide's
      // "Join a Room" coach-mark can render as a sibling overlay above the
      // real page — see the CoachMarkOverlay conditional right after the
      // slivers list closes below.
      body: Stack(
        children: [
          CustomScrollView(
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
                tooltip: s.darkMode,
                onPressed: () {
                  HapticFeedback.selectionClick();
                  ref.read(themeModeProvider.notifier).toggle();
                },
              ),
              // Settings used to be the tail of this tab's scroll, with no
              // shortcut anywhere in the app. One tap now, from wherever you
              // are on the page — and it's where every other app keeps it,
              // so nobody has to learn ours.
              IconButton(
                icon: Icon(Icons.settings_rounded, size: 22, color: gp.textSec),
                tooltip: s.settingsScreenTitle,
                onPressed: () {
                  HapticFeedback.selectionClick();
                  Navigator.pushNamed(context, '/settings');
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
          // Directly under the numbers it explains. Renders nothing unless
          // the load actually failed, which is the overwhelmingly common
          // case; when it did fail, this is the only thing on the whole
          // screen that says so.
          const SliverToBoxAdapter(child: _LoadFailedBanner()),
          // Streak-at-risk, night-review prompt, and the Friday recap card —
          // relocated here from the Grid screen so Grid can lead with the
          // habit squares themselves. Renders nothing (zero height, no
          // header) on a quiet morning with nothing to say.
          const SliverToBoxAdapter(child: _DashboardSection()),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
              child: const _ProfileLinksSection(),
            ).animate(delay: 150.ms).fadeIn(duration: 400.ms),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 110)),
        ],
      ),
          if (ref.watch(activeAppGuideLessonProvider) ==
              AppGuideLesson.discoverRooms)
            CoachMarkOverlay(
              targetKey: ref.watch(roomsRowKeyProvider),
              title: appGuideLessonCoachTitle(
                  AppGuideLesson.discoverRooms, s.isAr),
              body: appGuideLessonCoachBody(
                  AppGuideLesson.discoverRooms, s.isAr),
              onDismiss: () => ref
                  .read(activeAppGuideLessonProvider.notifier)
                  .state = null,
            ),
        ],
      ),
    );
  }
}

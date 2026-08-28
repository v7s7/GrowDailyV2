part of 'profile_screen.dart';


/// Settings, on its own screen at last.
///
/// This section used to be the last block of the Profile tab's scroll.
/// Changing your language meant scrolling past the character hero, the stats
/// row, the streak/night-review/recap banners and five history links before
/// the first setting appeared — and there was no gear icon anywhere in the
/// app to shortcut it. One tab was carrying three unrelated jobs: who you
/// are, what you did, and how the app behaves.
///
/// Declared here inside the profile_screen library rather than in a file of
/// its own: the rows lean on _showThemePresetSheet/_showFontSheet/
/// _showLanguageSheet, which are private to this library. Keeping the class
/// where those live makes this a move of one widget rather than a rewrite of
/// three sheets' visibility, and the body is the exact same
/// [_SettingsSection] it always was.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    return Scaffold(
      backgroundColor: gp.bg,
      appBar: AppBar(
        backgroundColor: gp.bg,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        title: Text(
          s.settingsScreenTitle,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: gp.textPrimary,
          ),
        ),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 32),
        children: const [_SettingsSection()],
      ),
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
    final isGuest = ref.watch(guestModeProvider);
    final currentUser = ref.watch(authStateProvider).asData?.value;
    final canDeleteAccount = !isGuest && currentUser != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // GrowDaily Premium — its own accented banner, not a row inside
          // the settings list below: it's a promo, not a utility setting,
          // and sharing a row style with "Dark Mode" undersold it.
          InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const PremiumScreen(source: 'settings_banner'),
          ),
        );
            },
            borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: GameColors.gold.withOpacity(0.08),
                borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
                border: Border.all(color: GameColors.gold.withOpacity(0.35)),
              ),
              child: Row(
                children: [
                  Icon(Icons.workspace_premium_rounded,
                      size: 22, color: GameColors.gold),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.premiumTitle,
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: gp.textPrimary)),
                        const SizedBox(height: 2),
                        Text(
                          isAr ? 'افتح كل الميزات' : 'Unlock every feature',
                          style: TextStyle(fontSize: 11, color: gp.textSec),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      size: 18, color: GameColors.gold),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // ── Personalization: how the app looks and reads ──
          Text(
            isAr ? 'التخصيص' : 'Personalization',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: gp.textSec,
                letterSpacing: 1.5),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: gp.surface,
              borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
              border: Border.all(color: gp.border, width: 0.5),
            ),
            child: Column(
              children: [
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
                              _PresetDot(color: preset.emerald),
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
                // Font
                InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    _showFontSheet(context);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        Icon(Icons.text_fields_rounded, size: 20, color: gp.textSec),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(s.appFont,
                              style: TextStyle(
                                  fontSize: 15,
                                  color: gp.textPrimary,
                                  fontWeight: FontWeight.w500)),
                        ),
                        Consumer(builder: (context, ref, _) {
                          final font = ref.watch(appFontProvider);
                          return Text(
                            font.label,
                            style: TextStyle(
                              fontSize: 13,
                              color: gp.textSec,
                              fontWeight: FontWeight.w600,
                            ),
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
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(GameSpacing.cardRadius),
                    bottomRight: Radius.circular(GameSpacing.cardRadius),
                  ),
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
                            borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
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
          const SizedBox(height: 20),

          // ── Support: notifications, help ──
          Text(
            isAr ? 'الدعم' : 'Support',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: gp.textSec,
                letterSpacing: 1.5),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: gp.surface,
              borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
              border: Border.all(color: gp.border, width: 0.5),
            ),
            child: Column(
              children: [
                // App Guide — hands-on, replayable lessons for the app's
                // four core actions (add a habit, track a day, add a task,
                // find a Room). First row here rather than its own 4th
                // settings group, so Settings doesn't re-fragment back into
                // more sections just for this. The gold dot is a one-time
                // "new" marker — see appGuideBadgeSeenProvider's doc
                // comment — cleared the first time this is opened.
                InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    markAppGuideBadgeSeen(ref);
                    Navigator.pushNamed(context, '/app-guide');
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
                        Icon(Icons.school_rounded,
                            size: 20, color: gp.textSec),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(isAr ? 'دليل التطبيق' : 'App Guide',
                              style: TextStyle(
                                  fontSize: 15,
                                  color: gp.textPrimary,
                                  fontWeight: FontWeight.w500)),
                        ),
                        if (!ref.watch(appGuideBadgeSeenProvider))
                          Container(
                            width: 7,
                            height: 7,
                            // Directional, not physical. The dot follows the
                            // label in the Row, so the gap belongs on the
                            // dot's leading edge: `right: 8` puts it there in
                            // English and on the far side of the dot in
                            // Arabic, where the Row has already mirrored.
                            margin: const EdgeInsetsDirectional.only(start: 8),
                            // Not `const` — GameColors.gold is a mutable
                            // `static Color` (theme-preset system), not a
                            // compile-time constant. See BUILD_LESSONS.md #6.
                            decoration: BoxDecoration(
                              color: GameColors.gold,
                              shape: BoxShape.circle,
                            ),
                          ),
                        Icon(Icons.chevron_right_rounded,
                            size: 18, color: gp.textTert),
                      ],
                    ),
                  ),
                ),
                Container(height: 0.5, color: gp.divider),
                // Notifications — see NotificationSettingsScreen for the
                // full surface (habit reminders, prayer-time setup, quiet
                // hours, streak-risk nudge, celebrations, matrix nudge).
                // The old inline Daily Reminder row that used to live here
                // now lives inside that screen instead, alongside every
                // other notification setting rather than off on its own.
                InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    Navigator.pushNamed(context, '/notification-settings');
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        Icon(Icons.notifications_rounded, size: 20, color: gp.textSec),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(s.notificationsTitle,
                              style: TextStyle(
                                  fontSize: 15,
                                  color: gp.textPrimary,
                                  fontWeight: FontWeight.w500)),
                        ),
                        Icon(Icons.chevron_right_rounded,
                            size: 18, color: gp.textTert),
                      ],
                    ),
                  ),
                ),
                Container(height: 0.5, color: gp.divider),
                // Help & Support — FAQ, plus Contact/Guides once
                // help_support_screen.dart's kSupportEmail/kSupportWhatsApp/
                // kSupportInstagram/kGuideVideos actually have real values.
                InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    Navigator.pushNamed(context, '/help-support');
                  },
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(GameSpacing.cardRadius),
                    bottomRight: Radius.circular(GameSpacing.cardRadius),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        Icon(Icons.help_outline_rounded, size: 20, color: gp.textSec),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(s.helpSupportRowTitle,
                              style: TextStyle(
                                  fontSize: 15,
                                  color: gp.textPrimary,
                                  fontWeight: FontWeight.w500)),
                        ),
                        Icon(Icons.chevron_right_rounded,
                            size: 18, color: gp.textTert),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Account: Sign Out keeps its own quiet card; Delete Account is
          // a plain text link below rather than a full row, so it can't be
          // mistaken for a routine setting or tapped as easily by accident.
          Text(
            isAr ? 'الحساب' : 'Account',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: gp.textSec,
                letterSpacing: 1.5),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: gp.surface,
              borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
              border: Border.all(color: gp.border, width: 0.5),
            ),
            child: InkWell(
              onTap: () async {
                // A destructive-feeling but instantly-reversible action
                // (sign back in anytime) still deserves a confirm - a stray
                // tap on this row used to sign someone out with zero warning,
                // unlike every other exit-this-thing action in the app (see
                // RoomDetailScreen's _confirmLeave/_confirmDelete for the
                // same title/body/cancel/action dialog shape).
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: Text(s.signOutConfirmTitle),
                    content: Text(s.signOutConfirmBody),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(s.signOutConfirmCancel),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: TextButton.styleFrom(
                            foregroundColor: GameColors.error),
                        child: Text(s.signOut),
                      ),
                    ],
                  ),
                );
                if (confirmed != true || !context.mounted) return;
                HapticFeedback.mediumImpact();
                await setGuestMode(ref, false);
                await ref.read(authNotifierProvider.notifier).signOut();
                if (context.mounted) {
                  Navigator.pushNamedAndRemoveUntil(
                      context, '/', (_) => false);
                }
              },
              borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
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
                    Icon(Icons.chevron_right_rounded,
                        size: 18, color: gp.textTert),
                  ],
                ),
              ),
            ),
          ),
          if (canDeleteAccount) ...[
            const SizedBox(height: 10),
            // Delete Account — required by App Store review guideline
            // 5.1.1(v): account creation implies in-app account deletion.
            // A quiet text link rather than a full row, so it reads as
            // "available if you need it" instead of as routine as Sign Out.
            Center(
              child: InkWell(
                onTap: () => showDeleteAccountSheet(context, ref),
                borderRadius: BorderRadius.circular(GameSpacing.buttonRadius),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  child: Text(
                    s.deleteAccount,
                    style: TextStyle(
                        fontSize: 12.5,
                        color: GameColors.error.withOpacity(0.8),
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

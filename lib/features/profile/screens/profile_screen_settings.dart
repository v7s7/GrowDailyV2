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
/// three sheets' visibility.
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

/// The settings list, rebuilt around ONE row anatomy on Aziz's "less
/// complex" call (2026-09-02). The old version hand-built every row, and
/// the seams showed: three different trailing treatments on one screen
/// (color dots for Appearance, a gold pill for Language, plain text for
/// Font), three different vertical paddings, and ripples that leaked past
/// the cards' corners on the middle rows. Every row now goes through
/// [_SettingsRow] inside a [_SettingsGroup], so the whole screen shares one
/// rhythm: icon · label · quiet value · chevron. The Language pill went
/// with it — a gold badge on a utility row shouted over the Premium banner,
/// which is the one element here that is MEANT to be gold.
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
    final presetId = ref.watch(themePresetProvider);
    final preset = ThemePresets.byId(presetId);

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
                  builder: (_) =>
                      const PremiumScreen(source: 'settings_banner'),
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
          _SettingsGroup(
            title: isAr ? 'التخصيص' : 'Personalization',
            children: [
              _SettingsRow(
                icon: isDark
                    ? Icons.dark_mode_rounded
                    : Icons.light_mode_rounded,
                label: s.darkMode,
                // A Switch is its own affordance, so this is the one row
                // with no chevron and no tap-anywhere navigation — tapping
                // the row still flips it, which is the larger target a
                // toggle deserves. shrinkWrap + the smaller padding is what
                // keeps this row the same height as its siblings; see
                // _SettingsRow.verticalPadding.
                trailing: Switch(
                  value: isDark,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: (_) {
                    HapticFeedback.selectionClick();
                    ref.read(themeModeProvider.notifier).toggle();
                  },
                ),
                showChevron: false,
                verticalPadding: 3,
                onTap: () {
                  HapticFeedback.selectionClick();
                  ref.read(themeModeProvider.notifier).toggle();
                },
              ),
              _SettingsRow(
                icon: Icons.palette_rounded,
                label: s.appearance,
                // The two preset dots stay: they are the one trailing
                // decoration that carries real information (the palette
                // you'd land on), unlike the Language pill this redesign
                // retired.
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _PresetDot(color: preset.gold),
                    const SizedBox(width: 4),
                    _PresetDot(color: preset.emerald),
                    const SizedBox(width: 8),
                    _SettingsValue(isAr ? preset.nameAr : preset.nameEn),
                  ],
                ),
                onTap: () {
                  HapticFeedback.selectionClick();
                  _showThemePresetSheet(context);
                },
              ),
              _SettingsRow(
                icon: Icons.text_fields_rounded,
                label: s.appFont,
                trailing: _SettingsValue(ref.watch(appFontProvider).label),
                onTap: () {
                  HapticFeedback.selectionClick();
                  _showFontSheet(context);
                },
              ),
              _SettingsRow(
                icon: Icons.language_rounded,
                label: s.language,
                trailing: _SettingsValue(isAr ? 'العربية' : 'English'),
                onTap: () {
                  HapticFeedback.selectionClick();
                  _showLanguageSheet(context);
                },
              ),
              // The bottom bar's tabs (NavBarSettingsScreen). Free accounts
              // can open it and see what Premium unlocks, since every edit
              // inside is gated; the PRO pill here is the honest signpost,
              // same as the one on Progress Hub's Insights header.
              _SettingsRow(
                icon: Icons.dashboard_customize_rounded,
                label: s.navBarSettingsTitle,
                trailing:
                    ref.watch(premiumAccessProvider) ? null : const _ProPill(),
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.pushNamed(context, '/nav-bar');
                },
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Support: learning the app, notifications, help ──
          _SettingsGroup(
            title: isAr ? 'الدعم' : 'Support',
            children: [
              // App Guide — hands-on, replayable lessons for the app's four
              // core actions. The gold dot is a one-time "new" marker — see
              // appGuideBadgeSeenProvider — cleared the first time this is
              // opened.
              _SettingsRow(
                icon: Icons.school_rounded,
                label: isAr ? 'دليل التطبيق' : 'App Guide',
                trailing: ref.watch(appGuideBadgeSeenProvider)
                    ? null
                    // Not `const` — GameColors.gold is a mutable
                    // `static Color` (theme-preset system), not a
                    // compile-time constant. See BUILD_LESSONS.md #6.
                    : Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: GameColors.gold,
                          shape: BoxShape.circle,
                        ),
                      ),
                onTap: () {
                  HapticFeedback.selectionClick();
                  markAppGuideBadgeSeen(ref);
                  Navigator.pushNamed(context, '/app-guide');
                },
              ),
              // See NotificationSettingsScreen for the full surface (habit
              // reminders, prayer-time setup, quiet hours, streak-risk
              // nudge, celebrations, matrix nudge).
              _SettingsRow(
                icon: Icons.notifications_rounded,
                label: s.notificationsTitle,
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.pushNamed(context, '/notification-settings');
                },
              ),
              _SettingsRow(
                icon: Icons.help_outline_rounded,
                label: s.helpSupportRowTitle,
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.pushNamed(context, '/help-support');
                },
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Account: Sign Out is an ACTION, not a destination, so it
          // carries no chevron; Delete Account stays a quiet text link
          // below rather than a full row, so it can't be mistaken for a
          // routine setting or tapped as easily by accident.
          _SettingsGroup(
            title: isAr ? 'الحساب' : 'Account',
            children: [
              _SettingsRow(
                icon: Icons.logout_rounded,
                label: s.signOut,
                tint: GameColors.error,
                showChevron: false,
                onTap: () => _confirmSignOut(context, ref, s),
              ),
            ],
          ),
          if (canDeleteAccount) ...[
            const SizedBox(height: 10),
            // Delete Account — required by App Store review guideline
            // 5.1.1(v): account creation implies in-app account deletion.
            Center(
              child: InkWell(
                onTap: () => showDeleteAccountSheet(context, ref),
                borderRadius:
                    BorderRadius.circular(GameSpacing.buttonRadius),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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

  /// A destructive-feeling but instantly-reversible action (sign back in
  /// anytime) still deserves a confirm — a stray tap on this row used to
  /// sign someone out with zero warning, unlike every other exit-this-thing
  /// action in the app (see RoomDetailScreen's _confirmLeave/_confirmDelete
  /// for the same title/body/cancel/action dialog shape).
  Future<void> _confirmSignOut(
      BuildContext context, WidgetRef ref, S s) async {
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
            style: TextButton.styleFrom(foregroundColor: GameColors.error),
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
      Navigator.pushNamedAndRemoveUntil(context, '/', (_) => false);
    }
  }
}

/// One titled card of settings rows: the section label, a surface card,
/// and hairline dividers interleaved automatically so a row can never
/// forget or double its divider.
///
/// A MATERIAL, not a Container, and that is load-bearing rather than
/// stylistic. An InkWell paints its ripple onto the nearest Material
/// ancestor; with a plain Container here the nearest one was the
/// Scaffold's own, so every ripple painted UNDERNEATH this card's opaque
/// surface fill and no settings row showed any pressed feedback at all —
/// including Sign Out. (A Container's clipBehavior cannot fix that: it
/// clips its own subtree, and the ink is drawn by an ancestor.) Material
/// paints its color below its ink features, so the ripple becomes visible
/// AND `clipBehavior` finally clips it to the rounded corners, which is
/// what the top and bottom rows need. Same idiom the grid header's
/// add-habit chip already uses.
class _SettingsGroup extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SettingsGroup({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: gp.textSec,
              letterSpacing: 1.5),
        ),
        const SizedBox(height: 12),
        Material(
          color: gp.surface,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
            side: BorderSide(color: gp.border, width: 0.5),
          ),
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) Container(height: 0.5, color: gp.divider),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The screen's single row anatomy: icon · label · optional trailing ·
/// chevron. [tint] colors icon and label together for the action rows
/// (Sign Out); [showChevron] is false for rows that act in place instead
/// of navigating (the Dark Mode toggle, Sign Out's confirm dialog).
///
/// [verticalPadding] exists for exactly one row and is not a general knob.
/// A Material 3 Switch carries its own 48pt padded tap target, so the
/// toggle row with the shared 12pt padding measured 68pt against its
/// siblings' 46pt — the first row of the first card, 48% taller than
/// everything under it, in a redesign whose whole point was one rhythm.
/// The toggle passes a smaller number alongside a shrink-wrapped Switch so
/// the heights match; nothing else should.
class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget? trailing;
  final VoidCallback onTap;
  final Color? tint;
  final bool showChevron;
  final double verticalPadding;
  const _SettingsRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
    this.tint,
    this.showChevron = true,
    this.verticalPadding = 12,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: verticalPadding),
        child: Row(
          children: [
            Icon(icon, size: 20, color: tint ?? gp.textSec),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 15,
                      color: tint ?? gp.textPrimary,
                      fontWeight:
                          tint == null ? FontWeight.w500 : FontWeight.w600)),
            ),
            if (trailing != null) trailing!,
            if (showChevron) ...[
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded,
                  size: 18, color: gp.textTert),
            ],
          ],
        ),
      ),
    );
  }
}

/// A row's quiet trailing value — one style for every "current choice" on
/// the screen, where there used to be three (plain text, colored pill,
/// dots-plus-text each formatting their own).
class _SettingsValue extends StatelessWidget {
  final String text;
  const _SettingsValue(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        color: context.gp.textSec,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

/// The small gold PRO pill, same recipe as Progress Hub's Insights header:
/// a signpost that a row leads somewhere Premium, never a lock that hides
/// the row.
class _ProPill extends StatelessWidget {
  const _ProPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: GameColors.gold.withOpacity(0.14),
        borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
      ),
      child: Text(
        'PRO',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: GameColors.gold,
        ),
      ),
    );
  }
}

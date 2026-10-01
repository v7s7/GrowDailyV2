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
/// **One tap deeper (2026-09-28).** Aziz found the page had grown "a lot of
/// options" and picked option C from the Settings canvas: the first page is
/// five rows, each with its current state written under it, and each opens
/// its own short page ([SettingsLookScreen], [SettingsLanguagePlaceScreen],
/// [SettingsHelpScreen], [SettingsAccountScreen], and the existing
/// Notifications page). The old single page had one «التخصيص» card of eight
/// rows, four of which were not about looks, and «الإشعارات» filed under
/// «الدعم». The line under each row is what keeps the extra tap honest: the
/// page answers "what is it set to?" without opening anything.
///
/// Declared here inside the profile_screen library rather than in a file of
/// its own: the rows lean on _showThemePresetSheet/_showFontSheet/
/// _showLanguageSheet, which are private to this library. Keeping the class
/// where those live makes this a move of one widget rather than a rewrite of
/// three sheets' visibility. The four inner pages live here for the same
/// reason.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    // A page asked for before this screen existed: the prayer widget's link
    // cold-started the app, or HomeShell pushed Settings in answer to it.
    // After the first frame, because a provider cannot be written while
    // widgets build and a route cannot be pushed mid-build either.
    WidgetsBinding.instance.addPostFrameCallback((_) => _openRequestedPage());
  }

  /// Opens the page a link asked for (requestedSettingsPageProvider) on top
  /// of this screen, so the back button lands on Settings.
  void _openRequestedPage() {
    if (!mounted) return;
    final page = ref.read(requestedSettingsPageProvider);
    if (page == null) return;
    ref.read(requestedSettingsPageProvider.notifier).state = null;
    if (page == kSettingsPagePrayerLocation) {
      Navigator.of(context).pushNamed('/prayer-location');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Settings already open as a bar tab when the link arrives.
    ref.listen<String?>(requestedSettingsPageProvider, (previous, next) {
      if (next == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) => _openRequestedPage());
    });

    final s = S.of(context);
    final isAr = ref.watch(localeProvider).languageCode == 'ar';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final preset = ThemePresets.byId(ref.watch(themePresetProvider));
    final isGuest = ref.watch(guestModeProvider);
    final signedIn =
        !isGuest && ref.watch(authStateProvider).asData?.value != null;
    final summary = _SettingsHubRow.summaryStyle(context);

    return _SettingsPage(
      title: s.settingsScreenTitle,
      children: [
        const _PremiumBanner(),
        _SettingsGroup(
          children: [
            // See NotificationSettingsScreen for the full surface (habit
            // reminders, the daily reminder, rooms and the week, quiet
            // hours).
            _SettingsHubRow(
              icon: Icons.notifications_rounded,
              label: s.notificationsTitle,
              summary: NotificationSummaryText(style: summary),
              onTap: () {
                HapticFeedback.selectionClick();
                Navigator.pushNamed(context, '/notification-settings');
              },
            ),
            _SettingsHubRow(
              icon: Icons.palette_rounded,
              label: s.settingsLookTitle,
              summary: Text(
                '${isDark ? s.settingsLookDark : s.settingsLookLight}'
                ' · ${isAr ? preset.nameAr : preset.nameEn}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: summary,
              ),
              onTap: () => _openSettingsPage(context, const SettingsLookScreen()),
            ),
            _SettingsHubRow(
              icon: Icons.language_rounded,
              label: s.settingsLanguagePlaceTitle,
              summary: _LanguagePlaceSummary(style: summary),
              onTap: () => _openSettingsPage(
                  context, const SettingsLanguagePlaceScreen()),
            ),
          ],
        ),
        _SettingsGroup(
          children: [
            _SettingsHubRow(
              icon: Icons.help_outline_rounded,
              label: s.settingsHelpTitle,
              summary: Text(s.settingsHelpSummary,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: summary),
              // The App Guide's one-time "new" dot, shown here too until the
              // guide is opened, or nobody would find it one page down.
              badge: ref.watch(appGuideBadgeSeenProvider)
                  ? null
                  : const _NewDot(),
              onTap: () => _openSettingsPage(context, const SettingsHelpScreen()),
            ),
            _SettingsHubRow(
              icon: Icons.person_rounded,
              label: s.settingsAccountTitle,
              // A guest has no sign-in methods and no account to delete:
              // Sign Out is all the page holds for them.
              summary: Text(
                signedIn ? s.settingsAccountSummary : s.signOut,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: summary,
              ),
              onTap: () =>
                  _openSettingsPage(context, const SettingsAccountScreen()),
            ),
          ],
        ),
      ],
    );
  }
}

void _openSettingsPage(BuildContext context, Widget page) {
  HapticFeedback.selectionClick();
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
}

/// Settings › «الشكل»: how the app looks, and what its pages show.
///
/// The first card is the look itself (dark mode, theme, the Home Screen
/// icon, font); the «الصفحات» card holds the bottom bar and Doum, which
/// decide what the pages show rather than how they are painted. Doum's
/// hide question on the Grid names this page (gridSproutHideBody), so its
/// switch must stay here.
class SettingsLookScreen extends ConsumerWidget {
  const SettingsLookScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isAr = ref.watch(localeProvider).languageCode == 'ar';
    final preset = ThemePresets.byId(ref.watch(themePresetProvider));
    final tabs = ref.watch(navLayoutProvider);
    final startTab = resolveStartTab(tabs, ref.watch(startPageProvider));

    return _SettingsPage(
      title: s.settingsLookTitle,
      children: [
        _SettingsGroup(
          children: [
            _SettingsRow(
              icon: isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
              label: s.darkMode,
              // A Switch is its own affordance, so this is a row with no
              // chevron and no tap-anywhere navigation — tapping the row
              // still flips it, which is the larger target a toggle
              // deserves. shrinkWrap + the smaller padding is what keeps
              // this row the same height as its siblings; see
              // _SettingsRow.verticalPadding.
              trailing: Switch.adaptive(
                value: isDark,
                activeTrackColor: GameColors.emerald,
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
              // you'd land on).
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
            // The Home Screen icon (lib/features/app_icon), right under the
            // theme it can follow. iPhone only: the provider answers false
            // everywhere else, so the row never draws on Android or the web.
            if (ref.watch(appIconsAvailableProvider).valueOrNull == true)
              _SettingsRow(
                icon: Icons.apps_rounded,
                label: s.appIconTitle,
                trailing: const _AppIconValue(),
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.pushNamed(context, '/app-icon');
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
          ],
        ),
        _SettingsGroup(
          title: s.settingsPagesSection,
          children: [
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
            // Which of Habits and Tasks the app opens on (startPageProvider).
            // Free, unlike the bar above it. Only while the bar holds both:
            // with one of them removed the app opens on the other, and there
            // is nothing to pick.
            if (tabs.contains(NavTab.grid) && tabs.contains(NavTab.matrix))
              _SettingsRow(
                icon: Icons.home_rounded,
                label: s.startPageTitle,
                trailing: _SettingsValue(startTab.label(s)),
                onTap: () {
                  HapticFeedback.selectionClick();
                  _showStartPageSheet(context);
                },
              ),
            // The sprout on the Grid's board (SproutLedge). Pulling it down
            // behind the board hides it after a question that names this
            // page, so this is the way back; it also hides it without the
            // gesture. A switch row, shaped like Dark Mode's above.
            _SettingsRow(
              icon: Icons.eco_rounded,
              label: s.gridSproutSetting,
              trailing: Switch.adaptive(
                value: ref.watch(gridSproutShownProvider),
                activeTrackColor: GameColors.emerald,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (shown) {
                  HapticFeedback.selectionClick();
                  ref.read(gridSproutShownProvider.notifier).set(shown);
                },
              ),
              showChevron: false,
              verticalPadding: 3,
              onTap: () {
                HapticFeedback.selectionClick();
                final notifier = ref.read(gridSproutShownProvider.notifier);
                notifier.set(!ref.read(gridSproutShownProvider));
              },
            ),
          ],
        ),
      ],
    );
  }
}

/// Settings › «اللغة وموقع الصلاة».
///
/// The prayer place (PrayerLocationScreen) sits right under Language, as it
/// has since it left Notifications on 2026-09-25: it feeds the prayer
/// widget and prayer habits, not only reminders. The prayer widget's taps
/// open the place page directly (openTabLinkPage), with Settings under it.
class SettingsLanguagePlaceScreen extends ConsumerWidget {
  const SettingsLanguagePlaceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final isAr = ref.watch(localeProvider).languageCode == 'ar';
    return _SettingsPage(
      title: s.settingsLanguagePlaceTitle,
      children: [
        _SettingsGroup(
          children: [
            _SettingsRow(
              icon: Icons.language_rounded,
              label: s.language,
              trailing: _SettingsValue(isAr ? 'العربية' : 'English'),
              onTap: () {
                HapticFeedback.selectionClick();
                _showLanguageSheet(context);
              },
            ),
            _SettingsRow(
              icon: Icons.location_on_rounded,
              label: s.prayerPlaceTitle,
              trailing: const _PrayerPlaceValue(),
              onTap: () {
                HapticFeedback.selectionClick();
                Navigator.pushNamed(context, '/prayer-location');
              },
            ),
          ],
        ),
      ],
    );
  }
}

/// Settings › «المساعدة»: the App Guide and Help & Support.
class SettingsHelpScreen extends ConsumerWidget {
  const SettingsHelpScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    return _SettingsPage(
      title: s.settingsHelpTitle,
      children: [
        _SettingsGroup(
          children: [
            // App Guide — hands-on, replayable lessons for the app's four
            // core actions. The gold dot is a one-time "new" marker — see
            // appGuideBadgeSeenProvider — cleared the first time this is
            // opened.
            _SettingsRow(
              icon: Icons.school_rounded,
              label: s.appGuideRowTitle,
              trailing:
                  ref.watch(appGuideBadgeSeenProvider) ? null : const _NewDot(),
              onTap: () {
                HapticFeedback.selectionClick();
                markAppGuideBadgeSeen(ref);
                Navigator.pushNamed(context, '/app-guide');
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
      ],
    );
  }
}

/// Settings › «الحساب».
///
/// Sign Out is an ACTION, not a destination, so it carries no chevron;
/// Delete Account stays a quiet text link below the card rather than a full
/// row, so it can't be mistaken for a routine setting or tapped as easily
/// by accident.
class SettingsAccountScreen extends ConsumerWidget {
  const SettingsAccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final isGuest = ref.watch(guestModeProvider);
    final currentUser = ref.watch(authStateProvider).asData?.value;
    final canDeleteAccount = !isGuest && currentUser != null;

    return _SettingsPage(
      title: s.settingsAccountTitle,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SettingsGroup(
              children: [
                // Every way into this account, and the way back in when
                // Firebase has quietly removed the password or Apple's
                // hidden address has opened a second, empty account. See
                // SignInMethodsScreen for why this is a standing row rather
                // than a prompt that appears only when something is wrong.
                // Same gate as Delete Account: a guest has no Firebase
                // account for it to describe.
                if (canDeleteAccount)
                  _SettingsRow(
                    icon: Icons.vpn_key_rounded,
                    label: s.signInMethodsTitle,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const SignInMethodsScreen(),
                        ),
                      );
                    },
                  ),
                // errorInk, not the raw error red: text on the light card
                // needs the ink (the raw red measured under 3:1 on cream).
                _SettingsRow(
                  icon: Icons.logout_rounded,
                  label: s.signOut,
                  tint: context.gp.errorInk,
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    child: Text(
                      s.deleteAccount,
                      style: TextStyle(
                          fontSize: 12.5,
                          color: context.gp.errorInk,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// A destructive-feeling but instantly-reversible action (sign back in
/// anytime) still deserves a confirm — a stray tap on this row used to
/// sign someone out with zero warning, unlike every other exit-this-thing
/// action in the app (see RoomDetailScreen's _confirmLeave/_confirmDelete
/// for the same title/body/cancel/action dialog shape).
Future<void> _confirmSignOut(BuildContext context, WidgetRef ref, S s) async {
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

/// One Settings page: the app bar and a scroll of blocks 24pt apart.
/// Shared by the first page and the four inside it, so they read as one
/// place.
class _SettingsPage extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SettingsPage({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Scaffold(
      backgroundColor: gp.bg,
      appBar: AppBar(
        backgroundColor: gp.bg,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        title: Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: gp.textPrimary,
          ),
        ),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 28, 16, 32),
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 24),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// GrowDaily Premium — its own accented banner, not a row: it's a promo,
/// not a utility setting, and sharing a row style with "Dark Mode"
/// undersold it. It stays the one gold element on the page.
///
/// Its line follows the account (Aziz, 2026-09-28): a free account is
/// offered Premium, an account that has it is told it has it, instead of
/// being sold what it already owns. Not "your subscription": a Lifetime
/// owner, granted Premium and a trial have none, and the Premium page says
/// so. Same page either way, with the same analytics source.
class _PremiumBanner extends ConsumerWidget {
  const _PremiumBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final hasPremium = ref.watch(premiumAccessProvider);
    return InkWell(
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
            Icon(Icons.workspace_premium_rounded, size: 22, color: gp.goldInk),
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
                    hasPremium
                        ? s.settingsPremiumManage
                        : s.settingsPremiumUnlock,
                    style: TextStyle(fontSize: 11, color: gp.textSec),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: gp.goldInk),
          ],
        ),
      ),
    );
  }
}

/// One card of settings rows, with an optional heading above it, and
/// hairline dividers interleaved automatically so a row can never forget
/// or double its divider.
///
/// The heading is 13pt with NO letter spacing (2026-09-28). It was 11pt
/// with letterSpacing 1.5, and letter spacing pulls joined Arabic letters
/// apart, so every heading read broken in the app's main language.
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
  final String? title;
  final List<Widget> children;
  const _SettingsGroup({this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              title!,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: gp.textSec),
            ),
          ),
          const SizedBox(height: 8),
        ],
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

/// A row on Settings' first page: icon · name · its current state on a
/// second line · chevron. Every one opens a page, so every one has the
/// chevron, and they all share one height at the default text size (the
/// summary is always one line, ellipsised), which keeps the first page one
/// rhythm the way [_SettingsRow] keeps the inner pages.
class _SettingsHubRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget summary;
  final Widget? badge;
  final VoidCallback onTap;
  const _SettingsHubRow({
    required this.icon,
    required this.label,
    required this.summary,
    required this.onTap,
    this.badge,
  });

  /// The second line's style, shared so NotificationSummaryText (which
  /// lives with the notification settings) draws the same line.
  static TextStyle summaryStyle(BuildContext context) => TextStyle(
        fontSize: 13,
        color: context.gp.textSec,
        fontWeight: FontWeight.w500,
      );

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: [
            Icon(icon, size: 22, color: gp.textSec),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Two lines, not one: at a larger text size the English
                  // "Language and prayer location" is wider than the row on
                  // a small phone, and the name is the only thing saying
                  // which page opens. At the default size every name fits
                  // on one line, so the rows still share one height.
                  Text(label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 16,
                          color: gp.textPrimary,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 1),
                  summary,
                ],
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 8),
              badge!,
            ],
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded, size: 18, color: gp.textTert),
          ],
        ),
      ),
    );
  }
}

/// The App Guide's one-time "new" dot.
class _NewDot extends StatelessWidget {
  const _NewDot();

  @override
  Widget build(BuildContext context) {
    // Not `const` — GameColors.gold is a mutable `static Color`
    // (theme-preset system), not a compile-time constant. See
    // BUILD_LESSONS.md #6.
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        color: GameColors.gold,
        shape: BoxShape.circle,
      ),
    );
  }
}

/// The inner pages' single row anatomy: icon · label · optional trailing ·
/// chevron. [tint] colors icon and label together for the action rows
/// (Sign Out); [showChevron] is false for rows that act in place instead
/// of navigating (the Dark Mode toggle, Sign Out's confirm dialog).
///
/// [verticalPadding] exists for the switch rows and is not a general knob.
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
/// the inner pages, where there used to be three (plain text, colored
/// pill, dots-plus-text each formatting their own).
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

/// The second line of «اللغة وموقع الصلاة» on Settings' first page: the
/// language, then the prayer place (or «غير محدد»), cut on one line like
/// every summary.
class _LanguagePlaceSummary extends ConsumerWidget {
  final TextStyle style;
  const _LanguagePlaceSummary({required this.style});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final isAr = ref.watch(localeProvider).languageCode == 'ar';
    final place = ref.watch(
      notificationSettingsProvider.select((n) => n.location?.label),
    );
    return Text(
      '${isAr ? 'العربية' : 'English'} · ${place ?? s.notifLocationNotSet}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }
}

/// The prayer place's name, cut short on one line: a searched city can carry
/// a long label ("Cairo, Al Qahirah, Egypt") and the row has the width of a
/// language name.
class _PrayerPlaceValue extends ConsumerWidget {
  const _PrayerPlaceValue();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final place = ref.watch(
      notificationSettingsProvider.select((n) => n.location?.label),
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 160),
      child: Text(
        place ?? s.notifLocationNotSet,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13,
          color: context.gp.textSec,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// The App icon row's current choice: the icon itself, small, and its colour's
/// name (or «مع المظهر» while it follows the theme). Nothing until iOS has
/// answered, rather than a guess that might be wrong.
class _AppIconValue extends ConsumerWidget {
  const _AppIconValue();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(appIconProvider);
    if (current == null) return const SizedBox.shrink();
    final s = S.of(context);
    final follows = ref.watch(appIconPrefsProvider).followTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIconArt(choice: current, size: 22),
        const SizedBox(width: 8),
        _SettingsValue(
          follows ? s.appIconFollowTitle : current.colourName(s),
        ),
      ],
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
          color: context.gp.goldInk,
        ),
      ),
    );
  }
}

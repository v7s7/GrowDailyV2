import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/app_guide_provider.dart'
    show activeAppGuideLessonProvider;
import '../../core/providers/home_tab_provider.dart';
import '../../core/providers/nav_bar_hint_provider.dart';
import '../../core/providers/nav_layout_provider.dart';
import '../../core/services/local_store_service.dart';
import '../../core/theme/game_theme.dart' show GameMotion;
import '../../features/dashboard/notifiers/dashboard_notifier.dart'
    show dashboardProvider;
import '../../features/habits/notifiers/custom_habits_notifier.dart'
    show habitListProvider;
import '../../features/premium/notifiers/premium_notifier.dart'
    show premiumAccessProvider;
import '../../features/habits/step_auto_complete.dart';
import '../../features/rooms/models/room_model.dart'
    show RoomModel, RoomParticipant;
import '../../features/rooms/notifiers/rooms_notifier.dart'
    show pendingSharedPlanPromptsProvider;
import '../../features/rooms/widgets/resolve_new_shared_habits_sheet.dart';
import '../providers/nav_badges_provider.dart';
import 'coach_mark_overlay.dart';
import 'game_nav_bar.dart';
import 'nav_tabs.dart';

/// The app's peer tabs — Grid, Profile, Matrix by default — in one
/// swipeable PageView under a single [GameNavBar], instead of separate
/// routes that pushReplacementNamed'd each other. Swiping between tabs is
/// the whole point (tap-only bottom nav reads as web-ish; horizontal swipe
/// is the native-feel win), but taps still work exactly as before through
/// the bar, now animating the same PageView instead of swapping routes.
///
/// WHICH tabs, and in what order, is [navLayoutProvider]'s to say: three
/// by default, up to five once a Premium account has arranged its own bar
/// in NavBarSettingsScreen. Pages are built from that list, in that order,
/// so the bar's currentIndex and the PageView always speak the same
/// language, and PageView follows the ambient text direction — in Arabic
/// the pages run right-to-left, mirroring the bar exactly like before.
/// Callers that want a particular tab ask for it by identity
/// ([initialTab], [requestedHomeTabProvider]), never by index, and a tab
/// that is not in the bar is pushed on top as a route so the ask is still
/// honoured — see [_openTab].
///
/// The old '/grid' / '/profile' / '/matrix' routes all resolve to this
/// shell at the matching tab (see main.dart's onGenerateRoute), so every
/// existing pushReplacementNamed call site anywhere in the app keeps
/// working unchanged. The tab screens themselves no longer carry their own
/// GameNavBar — the shell owns the one bar.
///
/// Also listens for [requestedHomeTabProvider]: GetStartedChecklistCard's
/// "other domain" row (e.g. "Add your first task" while looking at Grid)
/// can't reach across sibling pages of this same PageView directly, so it
/// just requests a tab switch here instead of trying to poke Matrix's
/// private state from outside - the checklist re-appears on the new tab
/// with its own, screen-owned "add" action already wired.
class HomeShell extends ConsumerStatefulWidget {
  final NavTab initialTab;
  const HomeShell({super.key, this.initialTab = NavTab.grid});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell>
    with WidgetsBindingObserver {
  /// The bar's tabs as of the last build, kept so the navLayoutProvider
  /// listener can find where the tab that was showing went, and so
  /// [_openTab] can answer "is this tab in the bar" without a watch.
  late List<NavTab> _tabs;
  late final PageController _controller;
  late int _index;

  /// The bar's own box, for the one-time "arrange your bar" coach-mark to
  /// measure (see shouldShowNavBarHint in build).
  final GlobalKey _barKey = GlobalKey();

  /// Hive settings key: room code -> the sharedHabits length this account
  /// was last prompted about. See [_maybePromptNewSharedHabits].
  static const _kPlanPromptsSeenKey = 'room_plan_prompts_seen_v1';

  /// Re-entrancy guard: the provider can emit while a prompt sheet is
  /// already up (the resolve itself changes the participant doc, which
  /// re-fires the listener) — one runner at a time keeps a single sheet on
  /// screen instead of stacking a second copy over it.
  bool _promptingSharedPlans = false;

  @override
  void initState() {
    super.initState();
    _tabs = ref.read(navLayoutProvider);
    // A requested tab that is not in the bar (a stale '/matrix' route after
    // Tasks was removed from it, say) opens the shell on home and pushes
    // the requested screen on top after the first frame, so the caller
    // still gets the screen it asked for.
    final initial = _tabs.indexOf(widget.initialTab);
    _index = initial < 0 ? 0 : initial;
    _controller = PageController(initialPage: _index);
    // For the steps auto-complete's app-resume trigger below.
    WidgetsBinding.instance.addObserver(this);
    // On a warm start the pending list can already be non-empty before the
    // first build's ref.listen ever fires (listeners only fire on CHANGES),
    // so check once after the first frame too.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (initial < 0) _push(widget.initialTab);
      unawaited(_maybePromptNewSharedHabits());
      unawaited(runStepAutoComplete(ref));
    });
  }

  /// Steps accumulate while the app is backgrounded (that is rather the
  /// point of walking), so resume is the natural moment a linked habit's
  /// goal turns out to have been reached. The call is a cheap no-op when
  /// nothing is linked, and self-throttled otherwise.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      unawaited(runStepAutoComplete(ref));
    }
  }

  /// The "leader added a habit to your room" prompt, on app open.
  ///
  /// The news used to live only inside Room Detail (_MyPlanCard's
  /// _NewHabitBanner) — a member who didn't open that screen never learned
  /// their plan grew, and every day until they did was silently graded
  /// against the new habit's slot. This surfaces the exact same
  /// resolve sheet the banner opens, but from the home shell, driven by
  /// [pendingSharedPlanPromptsProvider] (which reuses streams the Grid
  /// already holds open — no extra Firestore reads).
  ///
  /// Prompted at most once per (room, plan size): the seen marker is
  /// written BEFORE the sheet opens, so dismissing it is a real answer —
  /// the person was told, chose not to act, and still has the in-room
  /// banner (and this prompt again if the plan grows further) rather than
  /// a nag on every single app open.
  Future<void> _maybePromptNewSharedHabits() async {
    if (_promptingSharedPlans) return;
    _promptingSharedPlans = true;
    try {
      final pending = ref.read(pendingSharedPlanPromptsProvider);
      if (pending.isEmpty) return;
      final box = await LocalStoreService.settingsBox();
      for (final p in pending) {
        final seen =
            LocalStoreService.asStringMap(box.get(_kPlanPromptsSeenKey));
        final seenCount = (seen[p.room.code] as num?)?.toInt() ?? 0;
        if (p.room.sharedHabits.length <= seenCount) continue;
        if (!mounted) return;
        seen[p.room.code] = p.room.sharedHabits.length;
        await box.put(_kPlanPromptsSeenKey, seen);
        await showResolveNewHabitsSheet(context, room: p.room, mine: p.mine);
      }
    } finally {
      _promptingSharedPlans = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  void _onTabSelected(int i) {
    _controller.animateToPage(
      i,
      duration: GameMotion.relaxed,
      curve: Curves.easeOutCubic,
    );
  }

  /// Shows [tab]: as a page-turn when it is in the bar, pushed on top of
  /// the shell when it is not. The second case is what makes removing
  /// Tasks from the bar safe: the Grid checklist's "add your first task",
  /// the App Guide's lesson and the home-screen widget's quick-add link all
  /// still reach a Tasks screen, they just reach it as a route.
  void _openTab(NavTab tab, {required bool instant}) {
    final i = _tabs.indexOf(tab);
    if (i < 0) {
      _push(tab);
      return;
    }
    if (instant) {
      // See requestedHomeTabInstantProvider's doc comment — the caller is
      // a route that's mid-pop back onto this shell, so jump straight
      // there instead of racing an animated page-turn against that route's
      // own pop transition.
      _controller.jumpToPage(i);
    } else {
      _onTabSelected(i);
    }
  }

  void _push(NavTab tab) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => tab.page()),
    );
  }

  @override
  Widget build(BuildContext context) {
    // See requestedHomeTabProvider's doc comment. ref.listen (not read/
    // watch) since this is a one-shot side effect, not something the build
    // method's own output depends on - and it's safe to call unconditionally
    // on every build the way ConsumerStatefulWidget's build allows.
    ref.listen<NavTab?>(requestedHomeTabProvider, (previous, next) {
      if (next == null) return;
      HapticFeedback.selectionClick();
      final instant = ref.read(requestedHomeTabInstantProvider);
      ref.read(requestedHomeTabInstantProvider.notifier).state = false;
      ref.read(requestedHomeTabProvider.notifier).state = null;
      _openTab(next, instant: instant);
    });
    // The bar was just rearranged in NavBarSettingsScreen (which sits on
    // top of this shell while it happens). Pages are keyed by tab, so the
    // tab that was showing keeps its state wherever it moved to; what has
    // to move is the controller, or the PageView would stay on whatever
    // page NUMBER it was on and show a different screen there. The jump
    // waits a frame so the PageView has already rebuilt with the new
    // children, and lands on home if the showing tab was removed.
    ref.listen<List<NavTab>>(navLayoutProvider, (previous, next) {
      final showing = previous != null && _index < previous.length
          ? previous[_index]
          : null;
      final found = showing == null ? 0 : next.indexOf(showing);
      final index = found < 0 ? 0 : found;
      setState(() => _index = index);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_controller.hasClients) return;
        _controller.jumpToPage(index);
      });
    });
    // Fires when the rooms streams finish loading after a cold start (or a
    // leader adds a habit while the app is open) — the moment the pending
    // list becomes non-empty is exactly the moment to ask. The initState
    // post-frame check above covers the value already being non-empty
    // before this listener existed.
    ref.listen<List<({RoomModel room, RoomParticipant mine})>>(
        pendingSharedPlanPromptsProvider, (previous, next) {
      if (next.isEmpty) return;
      unawaited(_maybePromptNewSharedHabits());
    });
    // A habit just gained a steps link (typically: created/edited through
    // AddHabitSheet moments ago, permission freshly granted) — check the
    // count right now, so a goal the person already walked past today
    // completes on the spot instead of waiting for the next app resume.
    //
    // Keyed on the goal as well as the id, so LOWERING a goal counts as a
    // change too. Someone who drops 10,000 to 3,000 because they have already
    // walked 6,000 is asking the same question as someone who just linked the
    // habit, and on ids alone the set was identical and nothing fired: the
    // square sat empty until the next app resume, which is a strange way to
    // answer "I have already done this".
    ref.listen<Set<String>>(
        habitListProvider.select((habits) => {
              for (final h in habits)
                if (h.stepGoal != null) '${h.id}:${h.stepGoal}',
            }), (previous, next) {
      if (next.difference(previous ?? const {}).isEmpty) return;
      unawaited(runStepAutoComplete(ref, force: true));
    });
    // Android's system back button, which iOS has no equivalent of.
    //
    // The three tabs are pages of one PageView inside a SINGLE route, so
    // there is nothing on the navigator stack for back to pop: pressing it
    // on Profile or Matrix used to drop the user straight out to the
    // launcher. Verified on an Android 16 emulator before this was added -
    // back from the Matrix tab backgrounded the app and resumed
    // NexusLauncherActivity.
    //
    // Android's expectation is that back walks up to the primary
    // destination first and only leaves the app from there, so: on tab 0
    // let the pop through (leaving the app is then correct), and on any
    // other tab swallow it and animate home instead.
    //
    // Inert on iOS: this shell is the root route, so there is no back
    // gesture here for canPop to affect.
    final tabs = ref.watch(navLayoutProvider);
    _tabs = tabs;
    final badges = ref.watch(navBadgesProvider);
    // The one-time pointer at the press-and-hold gesture, once someone is
    // Premium (or on the trial) and a few days in. See
    // nav_bar_hint_provider.dart for every condition and why.
    final showHint = shouldShowNavBarHint(
      premium: ref.watch(premiumAccessProvider),
      seen: ref.watch(navBarHintSeenProvider),
      customised: !isDefaultNavTabs(tabs),
      lessonActive: ref.watch(activeAppGuideLessonProvider) != null,
      completions:
          ref.watch(dashboardProvider.select((d) => d.totalCompletions)),
    );
    final s = S.of(context);
    final shell = PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _onTabSelected(0);
      },
      child: Scaffold(
        // The shell owns the one nav bar; each page keeps its own Scaffold
        // (FABs, app bars, backgrounds) minus the bar it used to carry.
        // Keyed so the coach-mark below can measure the bar's real box.
        bottomNavigationBar: KeyedSubtree(
          key: _barKey,
          child: GameNavBar(
            // Clamped for the one frame between a layout shrinking and the
            // listener above catching up; NavigationBar asserts on an index
            // past its destinations.
            currentIndex: _index.clamp(0, tabs.length - 1),
            tabs: tabs,
            badges: badges,
            onSelect: _onTabSelected,
          ),
        ),
        body: PageView(
          controller: _controller,
          onPageChanged: (i) => setState(() => _index = i),
          // Keyed by tab, not by position, so rearranging the bar moves a
          // page's state (the Grid's week, the Matrix's lens) with it
          // instead of rebuilding whichever screen now sits at that index
          // from scratch.
          children: [
            for (final tab in tabs)
              KeyedSubtree(key: ValueKey(tab), child: tab.page()),
          ],
        ),
      ),
    );
    // The coach-mark has to sit ABOVE the Scaffold, not in a page's body:
    // the bar is the Scaffold's own bottomNavigationBar, outside every
    // page, and an overlay inside a page could neither cover it nor cut
    // its hole around it. Taps inside the hole reach the real bar (a tab
    // switches, a hold opens the customiser); anything else dismisses.
    return Stack(
      fit: StackFit.expand,
      children: [
        shell,
        if (showHint)
          CoachMarkOverlay(
            targetKey: _barKey,
            title: s.navBarHintTitle,
            body: s.navBarHintBody,
            onDismiss: () => markNavBarHintSeen(ref),
          ),
      ],
    );
  }
}

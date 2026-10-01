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
import '../../core/providers/start_page_provider.dart';
import '../../core/services/local_store_service.dart';
import '../../core/theme/game_theme.dart'
    show BuildContextGameTheme, GameMotion;
import '../../features/app_icon/app_icon_prompts.dart';
import '../../features/app_icon/app_icon_providers.dart';
import '../../features/dashboard/notifiers/dashboard_notifier.dart'
    show dashboardProvider;
import '../../features/dashboard/widgets/reaction_overlays.dart'
    show registerDashboardReactions;
import '../../features/habits/catalog/islamic_habit_catalog.dart'
    show IslamicHabitTemplate;
import '../../features/habits/notifiers/custom_habits_notifier.dart'
    show habitListProvider;
import '../../features/premium/notifiers/premium_notifier.dart'
    show premiumAccessProvider;
import '../../features/habits/step_auto_complete.dart';
import '../../features/launch/launch_curtain_up.dart';
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
/// Where it OPENS is the person's start page (startPageProvider, Habits
/// unless they picked Tasks in Settings › Look), as the bar allows it:
/// resolveStartTab. That page is also "home" for everything below that
/// used to mean page 0: Android's back button walks there before it leaves
/// the app, and a removed tab that was showing lands there.
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
  /// The tab to open on. Null, which is the app's own launch, means the
  /// start page (see the class doc); the legacy '/grid', '/profile' and
  /// '/matrix' routes name theirs.
  final NavTab? initialTab;
  const HomeShell({super.key, this.initialTab});

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

  /// The off-bar tab [_push] last put on top of the shell, and its route.
  /// See [_openTab] for the two things it is for.
  Route<void>? _pushed;
  NavTab? _pushedTab;

  /// Re-entrancy guard: the provider can emit while a prompt sheet is
  /// already up (the resolve itself changes the participant doc, which
  /// re-fires the listener) — one runner at a time keeps a single sheet on
  /// screen instead of stacking a second copy over it.
  bool _promptingSharedPlans = false;

  @override
  void initState() {
    super.initState();
    _tabs = ref.read(navLayoutProvider);
    // A tab asked for before this shell existed wins over [initialTab]: a
    // Lock Screen control or widget that cold-started the app, or a link
    // that arrived while sign-in or onboarding was still showing. The
    // listener in build only hears requests made AFTER it registers, so this
    // one used to sit unread: the app opened on Habits whatever was tapped
    // (Aziz, 2026-09-21), and the next tap asking for the same tab was not a
    // change either. Read here, consumed after the first frame below.
    final requested = ref.read(requestedHomeTabProvider);
    final target = requested ??
        widget.initialTab ??
        resolveStartTab(_tabs, ref.read(startPageProvider));
    // A requested tab that is not in the bar (a stale '/matrix' route after
    // Tasks was removed from it, say) opens the shell on the start page and
    // pushes the requested screen on top after the first frame, so the
    // caller still gets the screen it asked for.
    final initial = _tabs.indexOf(target);
    _index = initial < 0
        ? _homeIndex(_tabs, ref.read(startPageProvider))
        : initial;
    _controller = PageController(initialPage: _index);
    // For the steps auto-complete's app-resume trigger below.
    WidgetsBinding.instance.addObserver(this);
    // On a warm start the pending list can already be non-empty before the
    // first build's ref.listen ever fires (listeners only fire on CHANGES),
    // so check once after the first frame too.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // After the first frame because a provider cannot be written while
      // widgets build. Only if it is still the request this shell opened
      // on: a newer one has already been through the listener.
      if (requested != null && ref.read(requestedHomeTabProvider) == requested) {
        ref.read(requestedHomeTabProvider.notifier).state = null;
        ref.read(requestedHomeTabInstantProvider.notifier).state = false;
      }
      if (initial < 0) _push(target);
      unawaited(runStepAutoComplete(ref));
      // The two questions that open over the page wait for the launch
      // curtain to go, so neither plays unseen under Doum's scene.
      afterLaunchCurtain(ref, () {
        if (!mounted) return;
        unawaited(_maybePromptNewSharedHabits());
        unawaited(maybeShowIconCard(context, ref));
      });
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
      // A long return plays the launch curtain again (main.dart's observer
      // runs before this one, so it is already up here); the card waits for
      // it as the launch's does, rather than opening under Doum's scene.
      afterLaunchCurtain(ref, () {
        if (!mounted) return;
        unawaited(maybeShowIconCard(context, ref));
      });
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

  /// The start page's position in [tabs]: where the shell opens, and what
  /// it treats as home (see the class doc).
  int _homeIndex(List<NavTab> tabs, NavTab startPage) {
    final i = tabs.indexOf(resolveStartTab(tabs, startPage));
    return i < 0 ? 0 : i;
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
  ///
  /// A page this shell pushed that is still on top when a new ask comes in
  /// is where the ask came FROM (every ask from outside the app closes
  /// what is open first). Two cases, both reachable from the Get Started
  /// card on a pushed Habits page once Habits can leave the bar: asked for
  /// itself again, it is already showing and a second copy would stack on
  /// it; asked for a tab in the bar, the page-turn would happen underneath
  /// it, unseen. So the first does nothing, and the second closes the
  /// pushed page and lands without a page-turn (the pop is the motion).
  void _openTab(NavTab tab, {required bool instant}) {
    final pushed = _pushed;
    if (pushed != null && pushed.isCurrent) {
      if (_pushedTab == tab) return;
      Navigator.of(context).pop();
      instant = true;
    }
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
    final route = MaterialPageRoute<void>(
      builder: (_) => _PushedTabPage(tab: tab),
    );
    _pushed = route;
    _pushedTab = tab;
    Navigator.of(context).push<void>(route);
  }

  @override
  Widget build(BuildContext context) {
    // Level up, a new rank, medals, milestones, the streak point and the
    // streak freeze. Registered here, above every page, since 2026-09-30:
    // it used to be the Grid's, and the Grid is only built while it is the
    // page on screen, so a level reached from a task, a room bonus or a
    // widget tap while Tasks was showing played nothing, and a milestone
    // left unacknowledged blocked every later one. With Tasks as the start
    // page, or Habits out of the bar, that would have been every day.
    registerDashboardReactions(context, ref);
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
    // The Home Screen icon's plant grows with full days (app_icon_prompts.dart):
    // the count goes up when a day reaches its 80%, which is the moment
    // «نبتتك كبرت» belongs to, after that day's own «يوم كامل!». The same
    // call offers the Ramadan icon once each Ramadan.
    ref.listen<AsyncValue<int?>>(plantFullDaysProvider, (prev, next) {
      final was = prev?.valueOrNull;
      final now = next.valueOrNull;
      if (now != null && now != was) {
        // After the curtain: a long return's reload can move the count
        // while it is up (see didChangeAppLifecycleState).
        afterLaunchCurtain(ref, () {
          if (!mounted) return;
          unawaited(
            maybeShowIconCard(
              context,
              ref,
              dayJustFull: was != null && now > was,
            ),
          );
        });
      }
    });
    // A habit that has just BECOME linked to the step count, from the Add
    // Habit sheet or from Edit on an existing walking habit. Without this
    // the first read waited for the next app resume: somebody who had
    // already walked 9,000 steps by the time they created the habit linked
    // it, watched nothing happen, and had every reason to conclude the
    // link was broken. Reading here closes that gap in the one place that
    // survives every sheet, instead of each of those sheets having to
    // remember to ask (and being unable to, since they are gone by the
    // time the read would return).
    //
    // Forced past the two-minute throttle on purpose: this fires only when
    // the linked set actually GREW, which is a handful of times in an
    // account's life. Removing or unlinking one is not a reason to read.
    ref.listen<List<IslamicHabitTemplate>>(habitListProvider, (prev, next) {
      final before = <String>{
        for (final h in prev ?? const <IslamicHabitTemplate>[])
          if (h.stepGoal != null) h.id,
      };
      final grew = next.any((h) => h.stepGoal != null && !before.contains(h.id));
      if (grew) unawaited(runStepAutoComplete(ref, force: true));
    });
    // The bar was just rearranged in NavBarSettingsScreen (which sits on
    // top of this shell while it happens). Pages are keyed by tab, so the
    // tab that was showing keeps its state wherever it moved to; what has
    // to move is the controller, or the PageView would stay on whatever
    // page NUMBER it was on and show a different screen there. The jump
    // waits a frame so the PageView has already rebuilt with the new
    // children, and lands on the start page if the showing tab was removed.
    ref.listen<List<NavTab>>(navLayoutProvider, (previous, next) {
      final showing = previous != null && _index < previous.length
          ? previous[_index]
          : null;
      final found = showing == null ? -1 : next.indexOf(showing);
      final index =
          found < 0 ? _homeIndex(next, ref.read(startPageProvider)) : found;
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
    // destination first and only leaves the app from there, so: on the
    // start page let the pop through (leaving the app is then correct),
    // and on any other tab swallow it and animate there instead. The start
    // page, not page 0: with Tasks picked, or Habits out of the bar, the
    // app's home is wherever that page sits.
    //
    // Inert on iOS: this shell is the root route, so there is no back
    // gesture here for canPop to affect.
    final tabs = ref.watch(navLayoutProvider);
    _tabs = tabs;
    final home = _homeIndex(tabs, ref.watch(startPageProvider));
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
      canPop: _index == home,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _onTabSelected(home);
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

/// A tab [_HomeShellState._push]es because the bar does not hold it.
///
/// Every other tab's screen carries its own AppBar, so pushed it has a back
/// arrow like any page. Habits and Tasks do not: they were only ever root
/// pages and draw their own headers, so pushed as they are the only way
/// back was the edge swipe or Android's back button. Once Habits could
/// leave the bar (2026-09-30), a habit reminder or a Habits widget tap
/// opened it that way for anyone who had removed it. This gives the two the
/// same back arrow and name the rest have.
class _PushedTabPage extends StatelessWidget {
  final NavTab tab;
  const _PushedTabPage({required this.tab});

  @override
  Widget build(BuildContext context) {
    if (!tab.isHomePage) return tab.page();
    final gp = context.gp;
    return Scaffold(
      backgroundColor: gp.bg,
      appBar: AppBar(
        backgroundColor: gp.bg,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        title: Text(
          tab.label(S.of(context)),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: gp.textPrimary,
          ),
        ),
      ),
      body: tab.page(),
    );
  }
}

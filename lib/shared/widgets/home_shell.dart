import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/home_tab_provider.dart';
import '../../core/services/local_store_service.dart';
import '../../core/theme/game_theme.dart' show GameMotion;
import '../../features/grid/screens/grid_screen.dart';
import '../../features/matrix/screens/matrix_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/rooms/models/room_model.dart'
    show RoomModel, RoomParticipant;
import '../../features/rooms/notifiers/rooms_notifier.dart'
    show pendingSharedPlanPromptsProvider;
import '../../features/rooms/widgets/resolve_new_shared_habits_sheet.dart';
import 'game_nav_bar.dart';

/// The app's three peer tabs — Grid, Profile, Matrix — in one swipeable
/// PageView under a single [GameNavBar], instead of three separate routes
/// that pushReplacementNamed'd each other. Swiping between tabs is the
/// whole point (tap-only bottom nav reads as web-ish; horizontal swipe is
/// the native-feel win), but taps still work exactly as before through the
/// bar, now animating the same PageView instead of swapping routes.
///
/// Page order matches GameNavBar's route order (grid, profile, matrix) so
/// [initialIndex] and the bar's currentIndex speak the same language, and
/// PageView follows the ambient text direction — in Arabic the pages run
/// right-to-left, mirroring the bar exactly like before.
///
/// The old '/grid' / '/profile' / '/matrix' routes all resolve to this
/// shell at the matching page (see main.dart's onGenerateRoute), so every
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
  final int initialIndex;
  const HomeShell({super.key, this.initialIndex = 0});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  late final PageController _controller =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

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
    // On a warm start the pending list can already be non-empty before the
    // first build's ref.listen ever fires (listeners only fire on CHANGES),
    // so check once after the first frame too.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_maybePromptNewSharedHabits());
    });
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

  @override
  Widget build(BuildContext context) {
    // See requestedHomeTabProvider's doc comment. ref.listen (not read/
    // watch) since this is a one-shot side effect, not something the build
    // method's own output depends on - and it's safe to call unconditionally
    // on every build the way ConsumerStatefulWidget's build allows.
    ref.listen<int?>(requestedHomeTabProvider, (previous, next) {
      if (next == null) return;
      HapticFeedback.selectionClick();
      if (ref.read(requestedHomeTabInstantProvider)) {
        // See requestedHomeTabInstantProvider's doc comment — the caller is
        // a route that's mid-pop back onto this shell, so jump straight
        // there instead of racing an animated page-turn against that route's
        // own pop transition.
        _controller.jumpToPage(next);
        ref.read(requestedHomeTabInstantProvider.notifier).state = false;
      } else {
        _controller.animateToPage(
          next,
          duration: GameMotion.relaxed,
          curve: Curves.easeOutCubic,
        );
      }
      ref.read(requestedHomeTabProvider.notifier).state = null;
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
    return Scaffold(
      // The shell owns the one nav bar; each page keeps its own Scaffold
      // (FABs, app bars, backgrounds) minus the bar it used to carry.
      bottomNavigationBar: GameNavBar(
        currentIndex: _index,
        onSelect: _onTabSelected,
      ),
      body: PageView(
        controller: _controller,
        onPageChanged: (i) => setState(() => _index = i),
        children: const [
          GridScreen(),
          ProfileScreen(),
          MatrixScreen(),
        ],
      ),
    );
  }
}

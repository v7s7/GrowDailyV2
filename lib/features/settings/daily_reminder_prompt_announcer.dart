import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/first_run_offer_provider.dart';
import '../../core/providers/onboarding_provider.dart';
import '../../shared/widgets/app_snackbar.dart';
import '../habits/catalog/habit_plans.dart' show reminderTimeProvider;
import '../habits/models/habit_model.dart' show GoalType;
import '../habits/notifiers/custom_habits_notifier.dart' show habitListProvider;
import 'daily_reminder_prompt.dart';
import 'daily_reminder_prompt_dialog.dart';

/// How long after the app opens the question may still appear. Same idea
/// as the admin pop-up's window (BroadcastAnnouncer): asked as the app
/// opens, never in the middle of using it.
const Duration kDailyReminderPromptOpenWindow = Duration(seconds: 20);

/// Asks, once per app open at most, whether someone wants a daily reminder
/// (see daily_reminder_prompt.dart for when, and what the answers keep).
///
/// Waits for the home screen and never stacks: while a dialog, a sheet or a
/// pushed screen is on top it looks again every two seconds, and if anything
/// else claimed the screen during this open (the admin's pop-up, a room's
/// finale) it keeps quiet until the next open, so nobody meets two pop-ups
/// in a row. It settles later than the admin's pop-up for the same reason.
///
/// Renders nothing itself. Mounted in main.dart beside BroadcastAnnouncer.
class DailyReminderPromptAnnouncer extends ConsumerStatefulWidget {
  const DailyReminderPromptAnnouncer({
    super.key,
    required this.child,
    this.now = DateTime.now,
    this.settleDelay = const Duration(seconds: 4),
  });

  final Widget child;

  /// The clock, a parameter so a test can pin it.
  final DateTime Function() now;

  /// How long after an open before the question may appear.
  final Duration settleDelay;

  @override
  ConsumerState<DailyReminderPromptAnnouncer> createState() =>
      _DailyReminderPromptAnnouncerState();
}

class _DailyReminderPromptAnnouncerState
    extends ConsumerState<DailyReminderPromptAnnouncer> {
  static const _retryDelay = Duration(seconds: 2);

  late final AppLifecycleListener _lifecycle;
  late DateTime _openedAt;
  bool _wentAway = false;
  bool _showing = false;

  /// Something else held the screen during this open.
  bool _screenTakenThisOpen = false;

  /// Asked already in this run: never twice in one sitting, whatever the
  /// answer was.
  bool _askedThisRun = false;
  Timer? _timer;
  ModalRoute<Object?>? _route;

  @override
  void initState() {
    super.initState();
    _openedAt = widget.now();
    _lifecycle = AppLifecycleListener(
      onHide: () => _wentAway = true,
      onPause: () => _wentAway = true,
      onResume: _onResume,
    );
    _schedule(widget.settleDelay);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  void _onResume() {
    if (!_wentAway) return;
    _wentAway = false;
    _openedAt = widget.now();
    _screenTakenThisOpen = false;
    _schedule(widget.settleDelay);
  }

  void _schedule(Duration delay) {
    _timer?.cancel();
    _timer = Timer(delay, _tryShow);
  }

  bool _withinOpen() {
    final elapsed = widget.now().difference(_openedAt);
    return !elapsed.isNegative && elapsed <= kDailyReminderPromptOpenWindow;
  }

  /// The top route, read the usual way (popUntil that pops nothing).
  Route<dynamic>? _topRoute() {
    final navigator = Navigator.maybeOf(context);
    if (navigator == null) return null;
    Route<dynamic>? top;
    navigator.popUntil((route) {
      top = route;
      return true;
    });
    return top;
  }

  bool _homeOnTop(Route<dynamic>? top) =>
      top != null &&
      top is! PopupRoute &&
      (identical(top, _route) ||
          const {'/', '/grid', '/profile', '/matrix'}
              .contains(top.settings.name));

  Future<void> _tryShow() async {
    if (!mounted || _showing || _askedThisRun || !_withinOpen()) return;
    // Not loaded yet (or still in the first-run walkthrough): look again. A
    // cold start can take several seconds to read these back, and on
    // 2026-09-24 the question never came on a simulator launch because the
    // first look found the habit list still empty and gave up.
    if (!ref.read(onboardingSeenProvider) ||
        !ref.read(firstRunOfferAskedProvider) ||
        ref.read(habitListProvider).isEmpty) {
      _schedule(_retryDelay);
      return;
    }
    final top = _topRoute();
    if (top is PopupRoute) _screenTakenThisOpen = true;
    if (_screenTakenThisOpen) return;
    if (!_homeOnTop(top)) {
      _schedule(_retryDelay);
      return;
    }
    await ref.read(reminderTimeProvider.notifier).loaded;
    final state = await readDailyReminderPromptState();
    if (!mounted) return;
    final due = dailyReminderPromptDue(
      now: widget.now(),
      hasReminderTime: ref.read(reminderTimeProvider) != null,
      buildHabitCreatedAt: [
        for (final h in ref.read(habitListProvider))
          if (h.goalType != GoalType.quit) h.createdAt,
      ],
      state: state,
    );
    if (!due || !_homeOnTop(_topRoute())) return;

    _showing = true;
    _askedThisRun = true;
    try {
      // The second ask is the last: no «بعدين» on it (see the card).
      final answer = await showDailyReminderPrompt(context,
          lastAsk: state.laterCount >= 1);
      if (!mounted) return;
      switch (answer) {
        case DailyReminderPromptPicked(:final time):
          final granted =
              await ref.read(reminderTimeProvider.notifier).set(time);
          if (!mounted) return;
          final s = S.of(context);
          // Denied: the same note the Settings row shows. The time is kept,
          // and nothing can arrive until notifications are allowed.
          ScaffoldMessenger.of(context).showOne(SnackBar(
            content: granted
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.dailyReminderSetToast(time.format(context))),
                      Text(
                        s.dailyReminderPromptSettingsHint,
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ],
                  )
                : Text(s.reminderPermissionDenied),
          ));
        case DailyReminderPromptNever():
          await writeDailyReminderPromptState(state.afterNever());
        // «بعدين», or the person closed it (a tap outside the card, back).
        case DailyReminderPromptLater():
          await writeDailyReminderPromptState(state.afterLater(widget.now()));
        // The app closed it, not the person (a link from outside clears the
        // screen): nothing was answered, so nothing is kept, and a later
        // open asks again.
        case null:
          break;
      }
    } finally {
      _showing = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

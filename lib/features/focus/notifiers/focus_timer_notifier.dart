import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/local_store_service.dart';
import '../../dashboard/notifiers/dashboard_notifier.dart';
import '../models/focus_duration.dart';
import 'focus_plan_notifier.dart';

const _kStorageKey = 'focus_timer_v1';

class FocusTimerState {
  final FocusDuration duration;
  final DateTime? endTime;
  final int? pausedRemainingSeconds;
  final bool isDone;

  const FocusTimerState({
    required this.duration,
    this.endTime,
    this.pausedRemainingSeconds,
    this.isDone = false,
  });

  bool get isRunning => endTime != null && !isDone;

  /// Seconds left, always derived from the wall clock (or the frozen
  /// snapshot taken on pause) rather than a counter that only advances
  /// while something happens to tick it.
  int remainingSeconds([DateTime? at]) {
    if (isDone) return 0;
    if (endTime != null) {
      final left = endTime!.difference(at ?? DateTime.now()).inSeconds;
      return left.clamp(0, duration.seconds);
    }
    return pausedRemainingSeconds ?? duration.seconds;
  }
}

/// Drives the Focus sprint countdown.
///
/// This used to live entirely inside `_FocusScreenState` as plain `int`/
/// `bool` fields ticked by a `Timer.periodic`. That meant the countdown was
/// destroyed the moment the widget was disposed — which happens on every
/// nav-bar tab switch, since routes are swapped with
/// `pushReplacementNamed` rather than kept alive in an `IndexedStack`. A
/// user could start a 90-minute sprint, tap over to Dashboard to check a
/// habit, tap back, and find the timer silently reset to 90:00 with no
/// sprint ever recorded.
///
/// Fixing that means the countdown's source of truth has to live somewhere
/// that outlives the screen: a normal (non-autoDispose) Riverpod provider,
/// which stays alive for the app's lifetime regardless of navigation. It
/// also anchors on a wall-clock `endTime` instead of a decrementing tick
/// count, and persists that end time to Hive, so the sprint keeps correct
/// time across backgrounding and a full app restart too — if the sprint
/// actually finished while the app was closed, that's detected on restore
/// and the session is still awarded instead of quietly vanishing.
class FocusTimerNotifier extends StateNotifier<FocusTimerState> {
  final Ref _ref;
  Timer? _ticker;
  bool _awarded = false;

  FocusTimerNotifier(this._ref)
      : super(const FocusTimerState(duration: FocusDuration.short)) {
    _restore();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _restore() async {
    final saved = await LocalStoreService.getSettingsMap(_kStorageKey);
    if (saved.isEmpty) return;

    final durationIndex = (saved['durationIndex'] as int?) ?? 0;
    final duration = FocusDuration.values[
        durationIndex.clamp(0, FocusDuration.values.length - 1)];
    final endMillis = saved['endMillis'] as int?;
    final pausedRemaining = saved['pausedRemaining'] as int?;
    final storedDone = (saved['isDone'] as bool?) ?? false;
    _awarded = (saved['awarded'] as bool?) ?? false;

    if (endMillis == null) {
      if (!mounted) return;
      state = FocusTimerState(
        duration: duration,
        pausedRemainingSeconds: pausedRemaining,
        isDone: storedDone,
      );
      return;
    }

    final end = DateTime.fromMillisecondsSinceEpoch(endMillis);
    if (!end.isAfter(DateTime.now())) {
      // The sprint's time ran out while the app was backgrounded or fully
      // closed. Land on the completed state and still award it rather than
      // rewinding to a fresh, unstarted timer.
      if (!mounted) return;
      state = FocusTimerState(duration: duration, isDone: true);
      _persist().ignore();
      _maybeAward(duration);
      return;
    }

    if (!mounted) return;
    state = FocusTimerState(duration: duration, endTime: end);
    _startTicker();
  }

  Future<void> _persist() async {
    await LocalStoreService.putSettingsMap(_kStorageKey, {
      'durationIndex': FocusDuration.values.indexOf(state.duration),
      'endMillis': state.endTime?.millisecondsSinceEpoch,
      'pausedRemaining': state.pausedRemainingSeconds,
      'isDone': state.isDone,
      'awarded': _awarded,
    });
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (!mounted || state.endTime == null) return;
    if (state.remainingSeconds() <= 0) {
      _ticker?.cancel();
      final duration = state.duration;
      state = FocusTimerState(duration: duration, isDone: true);
      _persist().ignore();
      _maybeAward(duration);
      return;
    }
    // The countdown's truth is the wall-clock endTime; this just nudges
    // Riverpod to re-emit so watchers redraw the seconds-remaining label.
    state = FocusTimerState(duration: state.duration, endTime: state.endTime);
  }

  /// Awards the sprint's XP and logs it against today's ritual exactly once
  /// per sprint, whether completion was witnessed live (via [_tick]) or
  /// discovered after the fact (via [_restore]). Guarded by [_awarded] so a
  /// second cold start before the user resets doesn't double-pay.
  void _maybeAward(FocusDuration duration) {
    if (_awarded) return;
    _awarded = true;
    _persist().ignore();
    _ref.read(focusPlanProvider.notifier).addFocusSession();
    _ref
        .read(dashboardProvider.notifier)
        .awardBonus(xp: duration.xpReward, gold: 0);
  }

  void selectDuration(FocusDuration d) {
    if (state.isRunning) return;
    _ticker?.cancel();
    _awarded = false;
    state = FocusTimerState(duration: d);
    _persist().ignore();
  }

  void start() {
    if (state.isDone) return;
    final remaining = state.remainingSeconds();
    final end = DateTime.now().add(
      Duration(seconds: remaining == 0 ? state.duration.seconds : remaining),
    );
    state = FocusTimerState(duration: state.duration, endTime: end);
    _persist().ignore();
    _startTicker();
  }

  void pause() {
    _ticker?.cancel();
    final remaining = state.remainingSeconds();
    state = FocusTimerState(
      duration: state.duration,
      pausedRemainingSeconds: remaining,
    );
    _persist().ignore();
  }

  void reset() {
    _ticker?.cancel();
    _awarded = false;
    state = FocusTimerState(duration: state.duration);
    _persist().ignore();
  }
}

final focusTimerProvider =
    StateNotifierProvider<FocusTimerNotifier, FocusTimerState>(
        (ref) => FocusTimerNotifier(ref));

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/datetime_ext.dart';
import '../../../core/services/analytics_service.dart';
import '../../../core/services/local_store_service.dart';
import '../../auth/notifiers/auth_notifier.dart';
import '../models/daily_focus_plan.dart';

class FocusPlanState {
  final DailyFocusPlan plan;
  final bool isLoading;

  const FocusPlanState({required this.plan, this.isLoading = false});

  FocusPlanState copyWith({DailyFocusPlan? plan, bool? isLoading}) =>
      FocusPlanState(
        plan: plan ?? this.plan,
        isLoading: isLoading ?? this.isLoading,
      );
}

class FocusPlanNotifier extends StateNotifier<FocusPlanState> {
  final String? _uid;

  FocusPlanNotifier(this._uid)
      : super(
          FocusPlanState(
            plan: DailyFocusPlan.empty(DateTime.now().toDateKey()),
            isLoading: _uid != null,
          ),
        ) {
    if (_uid != null) {
      _load();
    } else {
      _loadGuest();
    }
  }

  DocumentReference<Map<String, dynamic>> get _doc => FirebaseFirestore.instance
      .collection('users')
      .doc(_uid)
      .collection('focus_plans')
      .doc(state.plan.dateKey);

  Future<void> _loadGuest() async {
    final dateKey = state.plan.dateKey;
    final box = await LocalStoreService.settingsBox();
    final raw = LocalStoreService.asStringMap(
      box.get('${LocalStoreService.guestFocusPrefix}$dateKey'),
    );
    if (!mounted) return;
    state = FocusPlanState(
      plan: raw.isEmpty
          ? DailyFocusPlan.empty(dateKey)
          : DailyFocusPlan.fromLocal(dateKey, raw),
    );
  }

  Future<void> _load() async {
    if (_uid == null) return;
    try {
      final snap = await _doc.get();
      if (!mounted) return;
      state = FocusPlanState(
        plan: snap.exists
            ? DailyFocusPlan.fromFirestore(snap)
            : DailyFocusPlan.empty(state.plan.dateKey),
      );
    } catch (_) {
      if (mounted) state = state.copyWith(isLoading: false);
    }
  }

  void saveFocus({
    required String topTask,
    required String cue,
    required String action,
  }) {
    final updated = state.plan.copyWith(
      topTask: topTask.trim(),
      cue: cue.trim(),
      action: action.trim(),
      planDone: topTask.trim().isNotEmpty,
    );
    AnalyticsService.instance.track('daily_focus_saved', props: {
      'hasCue': cue.trim().isNotEmpty,
      'hasAction': action.trim().isNotEmpty,
    });
    _setPlan(updated);
  }

  void togglePlan() => _setPlan(
        state.plan.copyWith(planDone: !state.plan.planDone),
      );

  void toggleSprint() => _setPlan(
        state.plan.copyWith(sprintDone: !state.plan.sprintDone),
      );

  void toggleReview() => _setPlan(
        state.plan.copyWith(reviewDone: !state.plan.reviewDone),
      );

  void addFocusSession() {
    AnalyticsService.instance.track('focus_session_completed');
    _setPlan(
        state.plan.copyWith(
          focusSessions: state.plan.focusSessions + 1,
          sprintDone: true,
        ),
      );
  }

  void resetToday() => _setPlan(DailyFocusPlan.empty(state.plan.dateKey));

  void _setPlan(DailyFocusPlan plan) {
    state = state.copyWith(plan: plan, isLoading: false);
    if (_uid == null) {
      LocalStoreService.settingsBox().then((box) => box
          .put('${LocalStoreService.guestFocusPrefix}${plan.dateKey}', plan.toLocal())
          .ignore());
      return;
    }
    _doc.set(plan.toFirestore(), SetOptions(merge: true)).ignore();
  }
}

final focusPlanProvider =
    StateNotifierProvider<FocusPlanNotifier, FocusPlanState>((ref) {
  final uid = ref.watch(authStateProvider).asData?.value?.uid;
  return FocusPlanNotifier(uid);
});

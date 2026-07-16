import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/datetime_ext.dart';
import '../../auth/notifiers/auth_notifier.dart';
import '../../dashboard/notifiers/dashboard_notifier.dart';

class WeeklyChallenge {
  final String id;
  final String title;
  final String description;
  final int target;
  final int xpReward;
  final int goldReward;
  final String iconType; // 'quran' | 'fast' | 'pray' | 'charity' | 'night'

  const WeeklyChallenge({
    required this.id,
    required this.title,
    required this.description,
    required this.target,
    required this.xpReward,
    required this.goldReward,
    required this.iconType,
  });
}

const List<WeeklyChallenge> weeklyChallengeCatalog = [
  WeeklyChallenge(
    id: 'quran_5x',
    title: 'Read Quran 5 Times',
    description: 'Open the Quran and read at least one page, 5 times this week.',
    target: 5,
    xpReward: 200,
    goldReward: 50,
    iconType: 'quran',
  ),
  WeeklyChallenge(
    id: 'sunnah_fast',
    title: 'Fast Monday & Thursday',
    description: 'Observe the Sunnah fast on both Monday and Thursday this week.',
    target: 2,
    xpReward: 300,
    goldReward: 75,
    iconType: 'fast',
  ),
  WeeklyChallenge(
    id: 'athkar_streak',
    title: 'Athkar All 7 Days',
    description: 'Complete your morning or evening athkar every day this week.',
    target: 7,
    xpReward: 250,
    goldReward: 60,
    iconType: 'pray',
  ),
  WeeklyChallenge(
    id: 'sadaqah_3x',
    title: 'Give Sadaqah 3 Times',
    description: 'Perform an act of charity or give sadaqah 3 times this week.',
    target: 3,
    xpReward: 200,
    goldReward: 50,
    iconType: 'charity',
  ),
  WeeklyChallenge(
    id: 'tahajjud_3x',
    title: 'Pray Tahajjud 3 Nights',
    description: 'Rise before Fajr for the night prayer, 3 times this week.',
    target: 3,
    xpReward: 350,
    goldReward: 100,
    iconType: 'night',
  ),
];

int _isoWeekNumber(DateTime date) {
  final startOfYear = DateTime(date.year, 1, 1);
  final startWeekday = startOfYear.weekday;
  final dayOfYear = date.difference(startOfYear).inDays + 1;
  return ((dayOfYear + startWeekday - 2) / 7).ceil();
}

WeeklyChallenge currentWeeklyChallenge() {
  final week = _isoWeekNumber(DateTime.now().effectiveDay);
  return weeklyChallengeCatalog[week % weeklyChallengeCatalog.length];
}

String _weekKey() {
  final now = DateTime.now().effectiveDay;
  return '${now.year}-W${_isoWeekNumber(now).toString().padLeft(2, '0')}';
}

class WeeklyChallengeState {
  final WeeklyChallenge challenge;
  final int progress;
  final bool isCompleted;
  final bool rewardClaimed;
  final bool isLoading;

  const WeeklyChallengeState({
    required this.challenge,
    this.progress = 0,
    this.isCompleted = false,
    this.rewardClaimed = false,
    this.isLoading = true,
  });

  WeeklyChallengeState copyWith({
    int? progress,
    bool? isCompleted,
    bool? rewardClaimed,
    bool? isLoading,
  }) =>
      WeeklyChallengeState(
        challenge: challenge,
        progress: progress ?? this.progress,
        isCompleted: isCompleted ?? this.isCompleted,
        rewardClaimed: rewardClaimed ?? this.rewardClaimed,
        isLoading: isLoading ?? this.isLoading,
      );
}

class WeeklyChallengeNotifier extends StateNotifier<WeeklyChallengeState> {
  final Ref _ref;
  final String? _uid;

  WeeklyChallengeNotifier(this._ref, this._uid)
      : super(WeeklyChallengeState(challenge: currentWeeklyChallenge())) {
    if (_uid != null) {
      _load();
    } else {
      state = state.copyWith(isLoading: false);
    }
  }

  DocumentReference<Map<String, dynamic>> get _doc => FirebaseFirestore.instance
      .collection('users')
      .doc(_uid)
      .collection('weekly_challenges')
      .doc(_weekKey());

  Future<void> _load() async {
    if (_uid == null) return;
    try {
      final snap = await _doc.get();
      if (!mounted) return;
      if (snap.exists) {
        final d = snap.data()!;
        state = state.copyWith(
          progress: (d['progress'] as int?) ?? 0,
          isCompleted: (d['completed'] as bool?) ?? false,
          rewardClaimed: (d['rewardClaimed'] as bool?) ?? false,
          isLoading: false,
        );
      } else {
        state = state.copyWith(isLoading: false);
      }
    } catch (_) {
      if (mounted) state = state.copyWith(isLoading: false);
    }
  }

  Future<void> logProgress() async {
    if (state.isCompleted) return;
    final newProgress = state.progress + 1;
    final completed = newProgress >= state.challenge.target;
    state = state.copyWith(progress: newProgress, isCompleted: completed);
    if (_uid == null) return;
    _doc.set({
      'challengeId': state.challenge.id,
      'progress': newProgress,
      'completed': completed,
      'weekKey': _weekKey(),
    }, SetOptions(merge: true)).ignore();
  }

  Future<void> claimReward() async {
    if (!state.isCompleted || state.rewardClaimed) return;
    state = state.copyWith(rewardClaimed: true);
    await _ref.read(dashboardProvider.notifier).awardBonus(
          xp: state.challenge.xpReward,
          gold: state.challenge.goldReward,
        );
    if (_uid == null) return;
    _doc.set({'rewardClaimed': true}, SetOptions(merge: true)).ignore();
  }
}

final weeklyChallengeProvider =
    StateNotifierProvider<WeeklyChallengeNotifier, WeeklyChallengeState>((ref) {
  final uid = ref.watch(authStateProvider).asData?.value?.uid;
  return WeeklyChallengeNotifier(ref, uid);
});

import 'dart:math' show max;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/services/local_store_service.dart';
import '../../../core/utils/western_digits.dart';
import '../../../shared/widgets/overlay_notice.dart';
import '../../auth/notifiers/auth_notifier.dart';

/// How many voice notes one account may record in a calendar month, tasks
/// and habit days together.
///
/// Aziz, 2026-09-26: "we need to set a limit for a monthly usage, think what
/// may people need, i dont want to pay a lot". Recordings live in Firestore
/// (a task's inside its task, a habit day's in square_voice), which bills
/// by the gigabyte stored, and until this nothing bounded one account: three
/// full takes on each of ten habits every day came to about 2.5 GB a year.
/// He picked 100 over the 60 recommended. A full 30-second take is about
/// 240 KB stored (AAC at 48 kbps, base64), so an account that uses every
/// one adds at most about 24 MB a month.
///
/// Counted when a take is KEPT (a second or longer, see
/// VoiceNoteService.stopRecording), never refunded by a delete: storage is
/// what costs, and record-delete-record would otherwise never end. The
/// month is the phone's calendar month, back on the 1st.
const int kVoiceNotesPerMonth = 100;

/// From this many left, the mic says how many remain
/// ([voiceNoteAllowanceHint]), so the limit is never met by surprise.
const int kVoiceNotesLeftHint = 5;

/// `users/{uid}/meta/{this}`: `{months: {'2026-09': 12}}`. The owner's
/// wildcard rule covers it, and account deletion already removes `meta`.
const String kVoiceUsageDoc = 'voice_usage';

/// A guest's count, on this phone (their recordings never leave it).
const String kGuestVoiceUsageKey = 'guest_voice_usage_v1';

/// The key a month is counted under: `2026-09`.
String voiceNoteMonthKey(DateTime now) =>
    '${now.year.toString().padLeft(4, '0')}-'
    '${now.month.toString().padLeft(2, '0')}';

/// This account's count for one month.
@immutable
class VoiceNoteAllowance {
  const VoiceNoteAllowance({
    required this.month,
    required this.used,
    this.loaded = false,
  });

  /// The month [used] counts ([voiceNoteMonthKey]).
  final String month;
  final int used;

  /// Whether [used] has been read back. Until it has, the count is what this
  /// session recorded, and recording is allowed: a count that could not be
  /// read is no reason to take the mic away.
  final bool loaded;

  /// [used], or 0 once [now] is in a later month than the one counted.
  int usedAt(DateTime now) => voiceNoteMonthKey(now) == month ? used : 0;

  int leftAt(DateTime now) => max(0, kVoiceNotesPerMonth - usedAt(now));

  bool canRecordAt(DateTime now) => leftAt(now) > 0;
}

/// Where the count is kept. A seam for tests, like SquareVoiceStore.
class VoiceNoteUsageStore {
  VoiceNoteUsageStore({FirebaseFirestore? firestore}) : _firestore = firestore;

  final FirebaseFirestore? _firestore;

  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _doc(String uid) => _db
      .collection('users')
      .doc(uid)
      .collection('meta')
      .doc(kVoiceUsageDoc);

  /// [month]'s count, 0 when there is none.
  Future<int> load(String? uid, String month) async {
    final Object? months;
    if (uid == null) {
      months = await LocalStoreService.getSettingsMap(kGuestVoiceUsageKey);
    } else {
      months = (await _doc(uid).get()).data()?['months'];
    }
    return months is Map ? (months[month] as num?)?.toInt() ?? 0 : 0;
  }

  /// One more for [month]. An increment, never a rewrite, so two phones
  /// recording in the same month add up instead of overwriting each other.
  Future<void> add(String? uid, String month) async {
    if (uid == null) {
      final months =
          await LocalStoreService.getSettingsMap(kGuestVoiceUsageKey);
      final n = (months[month] as num?)?.toInt() ?? 0;
      // Only the month in hand: the older ones count nothing any more.
      await LocalStoreService.putSettingsMap(kGuestVoiceUsageKey, {
        month: n + 1,
      });
      return;
    }
    await _doc(uid).set(
      {
        'months': {month: FieldValue.increment(1)},
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }
}

final voiceNoteUsageStoreProvider =
    Provider<VoiceNoteUsageStore>((ref) => VoiceNoteUsageStore());

class VoiceNoteAllowanceNotifier extends StateNotifier<VoiceNoteAllowance> {
  VoiceNoteAllowanceNotifier(
    this._store,
    this._uid, {
    DateTime Function()? clock,
  })  : _clock = clock ?? DateTime.now,
        super(VoiceNoteAllowance(
          month: voiceNoteMonthKey((clock ?? DateTime.now)()),
          used: 0,
        )) {
    _load();
  }

  final VoiceNoteUsageStore _store;
  final String? _uid;
  final DateTime Function() _clock;

  Future<void> _load() async {
    final month = voiceNoteMonthKey(_clock());
    try {
      final stored = await _store.load(_uid, month);
      if (!mounted) return;
      // A take kept while the read was out may or may not be in it; the
      // larger of the two is never an overcount of this month.
      final used = state.month == month ? max(stored, state.used) : stored;
      state = VoiceNoteAllowance(month: month, used: used, loaded: true);
    } catch (_) {
      // Offline, or the read failed: leave the mic open (see loaded).
    }
  }

  /// A take was kept. Counted here at once, and stored in the background.
  void recorded() {
    final month = voiceNoteMonthKey(_clock());
    state = VoiceNoteAllowance(
      month: month,
      used: state.month == month ? state.used + 1 : 1,
      loaded: state.loaded && state.month == month,
    );
    _store.add(_uid, month).catchError((Object _) {});
  }
}

final voiceNoteAllowanceProvider =
    StateNotifierProvider<VoiceNoteAllowanceNotifier, VoiceNoteAllowance>(
        (ref) {
  final uid = ref.watch(authStateProvider).asData?.value?.uid;
  return VoiceNoteAllowanceNotifier(
    ref.watch(voiceNoteUsageStoreProvider),
    uid,
  );
});

/// The day the count starts again: the 1st of the month after [now].
DateTime voiceNotesBackOn(DateTime now) => DateTime(now.year, now.month + 1);

/// Whether a new take may start. When it may not, the person is told why
/// and when the notes come back, over the sheet the mic sits in.
bool voiceNoteMonthAllows(BuildContext context, WidgetRef ref) {
  final now = DateTime.now();
  if (ref.read(voiceNoteAllowanceProvider).canRecordAt(now)) return true;
  final s = S.of(context);
  showOverlayNotice(
    context,
    s.voiceNotesMonthUsed(kVoiceNotesPerMonth, _backOnLabel(now, s)),
    icon: Icons.mic_off_rounded,
  );
  return false;
}

/// The mic row's second line: how many are left once [kVoiceNotesLeftHint]
/// or fewer are, when they come back once none are, and null otherwise (the
/// row keeps its own «tap to record»). Watches, so the line follows a take.
String? voiceNoteAllowanceHint(WidgetRef ref, S s) {
  final now = DateTime.now();
  final left = ref.watch(voiceNoteAllowanceProvider).leftAt(now);
  if (left <= 0) return s.voiceNotesBackOnHint(_backOnLabel(now, s));
  if (left <= kVoiceNotesLeftHint) return s.voiceNotesLeftThisMonth(left);
  return null;
}

/// «1 أكتوبر» / "1 October", in Latin digits like every date on screen.
String _backOnLabel(DateTime now, S s) =>
    westernDate(voiceNotesBackOn(now), 'd MMMM', s.isAr ? 'ar' : 'en');

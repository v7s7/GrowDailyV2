import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/extensions/datetime_ext.dart';
import '../models/square_state.dart';

/// Who changed a square. Threaded from every call site that can write one,
/// because a stored square records the VALUE and not the writer, and that is
/// exactly the gap that left "the previous day resets after 00:00"
/// unanswerable from noor's account on 2026-09-10: her walk was completed at
/// 15:38, paid 20 XP, then reversed, and nothing in the account could say by
/// what.
const String kSquareSourceTap = 'tap';
const String kSquareSourcePalette = 'palette';
const String kSquareSourceSteps = 'steps';
const String kSquareSourceStepsCatchUp = 'steps-catchup';
const String kSquareSourceHabitMirror = 'habit-mirror';
const String kSquareSourceNotification = 'notification';
const String kSquareSourceQuitAutoClean = 'quit-autoclean';
const String kSquareSourceTapUndo = 'tap-undo';
const String kSquareSourceTasbih = 'tasbih';

/// The default. Deliberately not one of the real sources: a trail row that
/// names the WRONG writer is worse than one that admits it does not know, so
/// an untagged call site says so instead of borrowing a plausible label.
const String kSquareSourceUnknown = 'unknown';

/// What a square is worth to a day, for the single purpose of deciding
/// whether a change TOOK something away.
///
/// Deliberately its own scale rather than [stepSquareRank]'s: that one ranks
/// فشل and تخطّي at -1 so a step count can never overwrite them, which is a
/// different question. Here a green day turning red has lost its credit and
/// is worth recording, whatever the intent behind it.
double squareCredit(SquareState s) => switch (s) {
      SquareState.complete || SquareState.bonus => 1,
      SquareState.partial => 0.5,
      SquareState.none || SquareState.failed || SquareState.skipped => 0,
    };

/// Whether a change is worth a trail entry: one that costs the day credit.
///
/// Only losses, on purpose. Every square in the app is written through this
/// choke point, so recording all of them would put a document behind every
/// tap for no gain: nobody has ever asked why a square turned GREEN. A
/// clear or a downgrade is the rare event and the one under suspicion.
bool squareChangeLosesCredit(SquareState from, SquareState to) =>
    from != to && squareCredit(to) < squareCredit(from);

/// Records a square that lost credit, under `users/{uid}/square_audit`.
///
/// The pair that answers the actual question is [dateKey] against
/// `appDayKey`: a square for the 9th cleared while the app believes it is
/// the 10th IS "the previous day reset after midnight", stated in one row
/// rather than inferred from a `lastUpdated` stamp.
///
/// The wildcard rule under `users/{uid}` already covers a new subcollection
/// (`allow read, write: if isOwner(uid) && subcollection != 'daily'`), so
/// this needs no rules change and no deploy.
class SquareAudit {
  SquareAudit._();

  /// Set false in tests that have no Firestore.
  static bool enabled = true;

  static void record({
    required String? uid,
    required String habitId,
    required DateTime day,
    required SquareState from,
    required SquareState to,
    required String source,
  }) {
    if (!enabled || uid == null) return;
    if (!squareChangeLosesCredit(from, to)) return;
    final now = DateTime.now();
    try {
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('square_audit')
          .add({
        'habitId': habitId,
        'dateKey': day.toDateKey(),
        // What the device thought the current day was at the moment of the
        // write. Differs from dateKey exactly when a past day is being
        // changed, which is the case under investigation.
        'appDayKey': now.effectiveDay.toDateKey(),
        'from': from.toJson(),
        'to': to.toJson(),
        'source': source,
        // Both clocks: the server's, which cannot be wrong, and the device's,
        // which is the one that decides what "today" means to the app. A gap
        // between them is itself worth seeing.
        'at': FieldValue.serverTimestamp(),
        'localAt': now.toIso8601String(),
      }).ignore();
    } catch (_) {
      // A trail that breaks a square write would be worse than no trail.
    }
  }
}

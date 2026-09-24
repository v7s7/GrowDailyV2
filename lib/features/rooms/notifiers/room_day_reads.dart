/// The member's own day documents, read once per pass however many rooms
/// grade them.
///
/// A pass grades several rooms one after another (resyncAllMyRooms on a
/// resume, a back-painted day reaching every room that counts its habit, a
/// weekly-quota tap), and each room's window is roughly the same 45 days of
/// the SAME member's `daily` documents. So a member in three rooms read each
/// of those days three times per pass, and Firestore bills every read:
/// measured on 2026-09-22 at about 56% of a typical account's reads.
///
/// Sharing them changes no grade. The grader only reads a day's
/// `squareStates` and `lastUpdated`, never changes them, and nothing in a pass
/// writes a `daily` document, so every room of one pass grading from one
/// snapshot is the grade each would have reached from its own.
///
/// Only CLOSED days are shared. A day still open (today, and yesterday until
/// kDayCutoffHour) can take a square between two rooms of a pass, so each
/// room still reads it for itself, exactly as before. A read that fails is
/// dropped, so the next room retries it instead of inheriting the failure.
/// It lives for one pass: the next pass reads everything fresh, which is how
/// a day back-painted meanwhile still reaches the rooms, as it always did.
///
/// Generic over what a read returns so the rule can be tested without
/// Firestore; the app uses it with DocumentSnapshot.
class RoomDayReads<T> {
  RoomDayReads(this.uid);

  /// Whose documents these are. A pass for one account never hands its days
  /// to another: the caller reads directly when the signed-in uid differs.
  final String uid;

  final _closed = <String, Future<T>>{};

  /// The day [dateKey], from [fetch] or, for a [closed] day already read in
  /// this pass, from that same read.
  Future<T> read(
    String dateKey, {
    required bool closed,
    required Future<T> Function() fetch,
  }) {
    if (!closed) return fetch();
    final existing = _closed[dateKey];
    if (existing != null) return existing;
    final started = fetch();
    _closed[dateKey] = started;
    // The caller still gets `started` with its error intact; this derived
    // future only forgets a failed read, and handles its own error so none
    // goes unhandled.
    started.then<void>((_) {}, onError: (Object _) {
      if (identical(_closed[dateKey], started)) _closed.remove(dateKey);
    });
    return started;
  }
}

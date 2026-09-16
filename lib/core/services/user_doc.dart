import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// One read of `users/{uid}` shared by everything that starts up wanting a
/// field from it.
///
/// Four notifiers each fetched this same document on every launch —
/// ActiveCatalogNotifier (which presets are on), CatalogOverridesNotifier
/// (what was changed about them), HabitOrderNotifier (the manual order) and
/// CustomHabitsNotifier (the stint history) — because each owns its own slice
/// and none of them knew about the others. Firestore bills per document read,
/// so that was four charges and four round trips for one document, per
/// launch, per person.
///
/// They are all constructed in the same synchronous pass (habitListProvider
/// watches all four), so in practice the first call starts the read and the
/// other three join it.
///
/// Deliberately memoises only the IN-FLIGHT read, never the result. A cache
/// with a lifetime would need an invalidation rule, and getting that wrong
/// means showing stale settings after a change made on another device — the
/// expensive kind of wrong. Once the read completes the memo is dropped, so
/// anything asking later gets a genuinely fresh answer, exactly as before.
/// The saving is real without anything having to be kept coherent.
class UserDoc {
  UserDoc._();

  static String? _uid;
  static Future<Map<String, dynamic>?>? _inFlight;

  static Future<Map<String, dynamic>?> read(String uid) {
    // A different account never joins the previous one's read.
    if (_uid != uid) {
      _uid = uid;
      _inFlight = null;
    }
    final existing = _inFlight;
    if (existing != null) return existing;
    final started = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get()
        .then((snap) => snap.data());
    _inFlight = started;
    // .ignore() on the DERIVED future, not on `started` itself. Without it
    // that derived future is an orphan with no error listener, so a failed
    // read — an ordinary offline launch — reaches runZonedGuarded and is
    // filed to Crashlytics as fatal, even though all four callers catch it.
    // `started` is still handed to every caller with its error intact, so
    // nothing real is swallowed.
    started.whenComplete(() {
      if (identical(_inFlight, started)) _inFlight = null;
    }).ignore();
    return started;
  }

  /// Forgets any in-flight read. For sign-out, so nothing can be handed the
  /// previous account's document.
  @visibleForTesting
  static void reset() {
    _uid = null;
    _inFlight = null;
  }
}

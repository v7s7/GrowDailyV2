import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/local_store_service.dart';

// ─── "Remind you every Saturday?" ──────────────────────────────────────────
//
// The Saturday note on the sealed week is sent only to someone who chose it
// (Aziz, 2026-09-24, the evening note's rule). The app asks where the note's
// subject already is: a line under the week's recap card on Profile,
// «نذكّرك بحصاد أسبوعك كل سبت الصبح؟» with «إيه» and «لا، شكرًا» (his words).
//
// Asked until answered, then never again. An answer is either button, or the
// person flipping the note's own switch in Settings: someone who turned it
// off there has answered, and meeting the question every Saturday after
// would be the app arguing with them. Left unanswered it stays a quiet line
// on one card, one day a week; it is never a pop-up.
//
// Stored on the device, like the daily reminder's question: it is a
// question about this phone's notifications.

const _kWeeklyNoteOfferAnsweredKey = 'weekly_note_offer_answered_v1';

/// Whether the Saturday-note question has been answered on this device.
///
/// Seeded at boot from [loadPersistedWeeklyNoteOfferAnswered] (see main.dart)
/// so the recap card never shows the line for one frame and then drops it.
final weeklyNoteOfferAnsweredProvider = StateProvider<bool>((ref) => false);

/// Records an answer: the line under the recap card goes and stays gone.
Future<void> markWeeklyNoteOfferAnswered(WidgetRef ref) async {
  if (ref.read(weeklyNoteOfferAnsweredProvider)) return;
  ref.read(weeklyNoteOfferAnsweredProvider.notifier).state = true;
  if (!LocalStoreService.settingsBoxOpen) return;
  try {
    final box = await LocalStoreService.settingsBox();
    await box.put(_kWeeklyNoteOfferAnsweredKey, true);
  } catch (_) {
    // No store (tests): the answer lasts for this run only.
  }
}

/// Reads the persisted answer, if any. Called once at boot (see main.dart).
Future<bool> loadPersistedWeeklyNoteOfferAnswered() async {
  if (!LocalStoreService.settingsBoxOpen) return false;
  try {
    final box = await LocalStoreService.settingsBox();
    return box.get(_kWeeklyNoteOfferAnsweredKey) as bool? ?? false;
  } catch (_) {
    return false;
  }
}

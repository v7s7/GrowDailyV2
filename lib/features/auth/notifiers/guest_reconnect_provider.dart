import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/local_store_service.dart';
import 'auth_notifier.dart';

/// Whether the signed-in account should be offered this device's guest
/// data, and how long is left to accept.
class GuestReconnectOffer {
  const GuestReconnectOffer({required this.uid, required this.daysLeft});

  final String uid;
  final int daysLeft;
}

/// Set the moment a registration succeeds, and consumed once by
/// [GuestReconnectPrompt] to push the sheet.
///
/// Separate from [guestReconnectOfferProvider] because the two answer
/// different questions. The offer is a standing fact - there is data here
/// and this account has not answered - and it stays true across launches,
/// which is exactly what the Profile banner wants. Showing a modal sheet
/// on that fact alone would put it in front of someone on every cold start
/// until they answered. Only a registration that just happened earns the
/// interruption.
final justRegisteredProvider = StateProvider<bool>((ref) => false);

/// The single source of truth for "is there an offer to make right now".
///
/// Both surfaces read this: the sheet shown once straight after
/// registration, and the Profile banner that keeps the offer available
/// afterwards. Deriving both from one provider is what stops them
/// disagreeing - a banner still advertising data the sheet already moved,
/// or an offer reappearing for an account that has answered.
///
/// Null means no offer, for any of the reasons it legitimately should not
/// be made: nobody signed in, in guest mode (the data is in active use,
/// not stranded), nothing on the device, or this account already answered.
final guestReconnectOfferProvider =
    FutureProvider<GuestReconnectOffer?>((ref) async {
  final uid = ref.watch(authStateProvider).asData?.value?.uid;
  final isGuest = ref.watch(guestModeProvider);
  if (uid == null || isGuest) return null;

  // Only an account that registered FRESH on this device is ever offered
  // the data — the persisted half of the rule GuestMigrationService's doc
  // states. Without this the banner made the offer to any plain sign-in:
  // a months-old account signing in on a device with a short guest trial
  // was invited to merge, and accepting field-replaced its level, XP, gold
  // and streak with the guest's smaller values. It also made phantom
  // offers out of pre-sync Hive leftovers, because the device-global
  // catalog keys a LEGACY signed-in account once wrote are
  // indistinguishable from guest progress to hasGuestProgress().
  if (!await LocalStoreService.isReconnectCandidate(uid)) return null;

  if (!await LocalStoreService.hasGuestProgress()) return null;
  if (await LocalStoreService.hasDecidedReconnect(uid)) return null;

  // No deadline yet means nobody has answered on this device, so the full
  // grace period is still ahead. Once one exists it is what the copy
  // quotes, rounded UP: telling someone "0 days" on the last afternoon
  // reads as already gone, when they in fact still have until midnight.
  // A deadline already PASSED must not round up the same way — ~/ on a
  // negative duration truncates toward zero, so an hour past the deadline
  // read as "1 day left" while the next cold start's sweep was about to
  // delete the data. Expired is expired.
  final deadline = await LocalStoreService.guestDiscardDeadline();
  final remaining = deadline?.difference(DateTime.now());
  final daysLeft = remaining == null
      ? LocalStoreService.guestDiscardGraceDays
      : remaining.isNegative
          ? 0
          : remaining.inHours ~/ 24 + 1;
  if (daysLeft <= 0) return null;

  return GuestReconnectOffer(uid: uid, daysLeft: daysLeft);
});

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/services/local_store_service.dart';
import '../../../core/theme/game_theme.dart';
import '../services/guest_migration_service.dart';
import '../services/reload_after_migration.dart';

/// Offers to move this device's guest data onto the account that just
/// signed in, and records the answer either way.
///
/// Deliberately NOT dismissible by tapping outside or swiping down. Every
/// other sheet in the app is, because every other sheet is asking about
/// something recoverable; this one starts a 7-day countdown on data that
/// cannot be recreated, and "I swiped it away by accident" must not be one
/// of the ways that countdown begins. The Profile banner exists for the
/// change of mind, not for the accident.
///
/// Returns true if the data was migrated.
Future<bool> showReconnectGuestSheet(
  BuildContext context,
  WidgetRef ref,
  String uid,
) async {
  HapticFeedback.mediumImpact();
  final moved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    useSafeArea: true,
    builder: (_) => _ReconnectSheet(uid: uid),
  );
  return moved ?? false;
}

class _ReconnectSheet extends ConsumerStatefulWidget {
  const _ReconnectSheet({required this.uid});

  final String uid;

  @override
  ConsumerState<_ReconnectSheet> createState() => _ReconnectSheetState();
}

class _ReconnectSheetState extends ConsumerState<_ReconnectSheet> {
  GuestSnapshot? _snapshot;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    GuestMigrationService.summarize().then((snapshot) {
      if (mounted) setState(() => _snapshot = snapshot);
    });
  }

  /// Both answers record the decision and start the same grace period.
  ///
  /// "Yes" gets the countdown too, on purpose: the migration writes to the
  /// profile document and four collections and can fail partway, so
  /// deleting the local copy the moment it claims success would make that
  /// unrecoverable. See GuestMigrationService's doc comment.
  Future<void> _answer({required bool bringItOver}) async {
    if (_working) return;
    // The uid this sheet was pushed for can stop being the signed-in user
    // while it is on screen: register()'s rollback path deletes the auth
    // account when the profile-doc write fails, after authStateChanges has
    // already emitted it and this sheet has already been pushed. Answering
    // then would migrate into (or start the discard countdown over) a uid
    // that no longer exists, and mark a phantom uid decided. The sheet is
    // deliberately non-dismissible, so this is also the only way out of it
    // on that path: close quietly, record nothing, and the Profile banner
    // remains the retry surface for whichever real account comes next.
    if (FirebaseAuth.instance.currentUser?.uid != widget.uid) {
      Navigator.pop(context, false);
      return;
    }
    setState(() => _working = true);
    HapticFeedback.mediumImpact();

    // Both captured before the first await, and the messenger before the
    // pop below. Reaching for either through `context` afterwards is
    // reading from a widget that is on its way out of the tree.
    final s = S.of(context);
    final messenger = ScaffoldMessenger.of(context);

    GuestMigrationResult? result;
    if (bringItOver) {
      result = await GuestMigrationService.migrate(widget.uid);
    }

    await LocalStoreService.markGuestDataForDiscard(DateTime.now());
    // Only a clean run counts as answered. A partial failure deliberately
    // leaves this account undecided so the Profile banner keeps offering
    // the retry, which is the entire reason the local copy is still there.
    if (!bringItOver || result?.failed != true) {
      await LocalStoreService.markReconnectDecided(widget.uid);
    }

    // Everything the migration wrote is on the server but not yet on
    // screen: these notifiers all loaded against an empty account moments
    // ago and cache that. Refresh before the sheet closes, so the grid
    // behind it is already right when it comes into view.
    if (bringItOver && result?.failed != true) reloadAfterGuestMigration(ref);

    if (!mounted) return;
    Navigator.pop(context, bringItOver && result?.failed != true);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          !bringItOver
              ? s.reconnectGrace(LocalStoreService.guestDiscardGraceDays)
              : result?.failed == true
                  ? s.reconnectPartial(LocalStoreService.guestDiscardGraceDays)
                  : s.reconnectDone,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final snapshot = _snapshot;

    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 0, 16, 40 + MediaQuery.of(context).padding.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        decoration: BoxDecoration(
          color: gp.surfaceHigh,
          borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
          border: Border.all(color: GameColors.gold.withOpacity(0.35)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: GameColors.gold.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.cloud_upload_rounded,
                  size: 28, color: context.gp.goldInk),
            ),
            const SizedBox(height: 16),
            Text(
              s.reconnectTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: gp.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            // Until the counts are read there is nothing honest to show, so
            // the sheet holds the space rather than naming numbers it does
            // not have yet.
            if (snapshot == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: CircularProgressIndicator(),
              )
            else ...[
              Text(
                s.reconnectFound(
                  snapshot.habitCount,
                  snapshot.dayCount,
                  snapshot.level,
                ),
                textAlign: TextAlign.center,
                style:
                    TextStyle(fontSize: 13, color: gp.textSec, height: 1.45),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  color: gp.surface,
                  borderRadius:
                      BorderRadius.circular(GameSpacing.buttonRadius),
                  border: Border.all(color: gp.border, width: 0.5),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: 15, color: gp.textTert),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        '${s.reconnectNotYours}\n\n'
                        '${s.reconnectGrace(LocalStoreService.guestDiscardGraceDays)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: gp.textSec,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: snapshot == null || _working
                    ? null
                    : () => _answer(bringItOver: true),
                child: Text(_working ? s.reconnectWorking : s.reconnectKeep),
              ),
            ),
            TextButton(
              onPressed: snapshot == null || _working
                  ? null
                  : () => _answer(bringItOver: false),
              child: Text(
                s.reconnectFresh,
                style: TextStyle(color: gp.textSec),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

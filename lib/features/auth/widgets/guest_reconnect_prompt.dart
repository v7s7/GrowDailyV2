import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../notifiers/guest_reconnect_provider.dart';
import 'reconnect_guest_sheet.dart';

/// Pushes the reconnect sheet once, over whatever the app just landed on
/// after a registration.
///
/// Wraps rather than living inside HomeShell so it survives the crossfade
/// between onboarding, the first-run offer and the grid without
/// remounting - the same reasoning RoomFinaleAnnouncer is wrapped for.
/// Remounting here would re-run the show-once logic mid-transition and
/// could put the sheet up twice.
class GuestReconnectPrompt extends ConsumerStatefulWidget {
  const GuestReconnectPrompt({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<GuestReconnectPrompt> createState() =>
      _GuestReconnectPromptState();
}

class _GuestReconnectPromptState extends ConsumerState<GuestReconnectPrompt> {
  /// Guards against a second push while the first sheet is still up.
  /// `justRegisteredProvider` is cleared before the await, but a rebuild
  /// landing between the read and that clear would otherwise slip through.
  bool _showing = false;

  @override
  Widget build(BuildContext context) {
    // Watched, not listened: the flag is set on the auth screen, which is a
    // DIFFERENT subtree that is torn down the instant authStateChanges
    // routes past it. By the time this widget first builds the value is
    // already sitting in the provider, so a listener registered here would
    // never see it change and would never fire.
    final armed = ref.watch(justRegisteredProvider);
    final offer = ref.watch(guestReconnectOfferProvider).asData?.value;

    if (armed && offer != null && !_showing) {
      // Set during build, but it is a plain field rather than provider
      // state on purpose: Riverpod throws if a provider is written while
      // the tree is building, and the flag has to be claimed synchronously
      // here or a second build before the post-frame callback runs would
      // queue the sheet twice.
      _showing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        // Consumed here rather than above for that same reason, and before
        // the await so a killed app never reopens onto this sheet.
        ref.read(justRegisteredProvider.notifier).state = false;
        await showReconnectGuestSheet(context, ref, offer.uid);
        if (!mounted) return;
        _showing = false;
        // The answer changed what the offer provider would now say, and
        // the Profile banner reads the same provider.
        ref.invalidate(guestReconnectOfferProvider);
      });
    }

    return widget.child;
  }
}

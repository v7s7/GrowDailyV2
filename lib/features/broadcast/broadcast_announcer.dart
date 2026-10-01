import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/first_run_offer_provider.dart';
import '../../core/providers/onboarding_provider.dart';
import '../../core/theme/game_theme.dart';
import '../auth/notifiers/auth_notifier.dart' show authStateProvider;
import '../launch/launch_curtain_up.dart';
import 'app_update.dart';
import 'broadcast_message.dart';

/// The signed-in account's uid, or null for a guest: what a test pop-up is
/// matched against. Its own provider so a widget test can name an account
/// without a Firebase user behind it.
final broadcastUidProvider = Provider<String?>(
  (ref) => ref.watch(authStateProvider).asData?.value?.uid,
);

/// How long after the app opens a pop-up may still appear. Long enough for
/// the live document to answer on a slow connection after a cold start (the
/// cached copy covers the fast case); short enough that it never lands in
/// the middle of someone using the app. One that arrives later waits for
/// the next open.
const Duration kBroadcastOpenWindow = Duration(seconds: 20);

/// Route names that ARE the home screen. main.dart's onGenerateRoute builds
/// '/grid', '/profile' and '/matrix' as a second HomeShell pushed over '/',
/// which is what a tapped reminder opens (_handleNotificationBodyTap). After
/// one such tap, '/' itself is never on top again for the rest of that run
/// even though home is what is on screen.
const Set<String> kBroadcastHomeRoutes = {'/', '/grid', '/profile', '/matrix'};

/// How long to wait before looking again when something is in the way.
const Duration _retryDelay = Duration(seconds: 2);

/// Shows the admin's pop-up ([BroadcastStore]) once, when the app opens.
///
/// "Opens" is a cold start (this widget mounting) or a return from the
/// background. A moment's inactive blip (Control Center, a permission
/// prompt, Face ID) is not one: the app never left the screen, the same
/// line main.dart's resume handling draws with `_awaySinceResume`.
///
/// Waits for the home screen: nothing is shown over the first-run
/// walkthrough or the question after it, so someone who just installed
/// meets it on their next open instead. And it never stacks: while a
/// dialog, a sheet or a pushed screen is on top it tries again every two
/// seconds, and if the open window passes first, the next open gets it.
///
/// What goes up is what the server says at that moment, not the copy on
/// the device (BroadcastStore.readFromServer): a pop-up stopped while the
/// phone was in a pocket must not show from a stale copy.
///
/// The same open also decides the update prompt (app_update.dart): a phone
/// on a build older than the one the admin says is live is sent to the store.
/// It goes before an ordinary message, which keeps for the next open, and
/// follows every rule above, the server's word included, so a phone that is
/// offline is never held up by it.
///
/// Renders nothing itself. Mount it once, below the app's providers and
/// inside the home route (see main.dart's _OnboardingOrGrid), the same place
/// RoomFinaleAnnouncer sits.
class BroadcastAnnouncer extends ConsumerStatefulWidget {
  const BroadcastAnnouncer({
    super.key,
    required this.child,
    this.now = DateTime.now,
    this.settleDelay = const Duration(milliseconds: 1200),
  });

  final Widget child;

  /// The clock, a parameter so a test can pin it.
  final DateTime Function() now;

  /// How long after an open before the pop-up may appear: the first frame's
  /// own work (the board loading, a finale or a reconnect offer claiming the
  /// screen) goes first.
  final Duration settleDelay;

  @override
  ConsumerState<BroadcastAnnouncer> createState() => _BroadcastAnnouncerState();
}

class _BroadcastAnnouncerState extends ConsumerState<BroadcastAnnouncer> {
  late final AppLifecycleListener _lifecycle;
  late DateTime _openedAt;
  bool _wentAway = false;
  bool _showing = false;
  Timer? _timer;
  ModalRoute<Object?>? _route;

  @override
  void initState() {
    super.initState();
    _openedAt = widget.now();
    BroadcastStore.live.addListener(_onDocument);
    _lifecycle = AppLifecycleListener(
      onHide: () => _wentAway = true,
      onPause: () => _wentAway = true,
      onResume: _onResume,
    );
    _schedule(widget.settleDelay);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _lifecycle.dispose();
    BroadcastStore.live.removeListener(_onDocument);
    super.dispose();
  }

  void _onResume() {
    if (!_wentAway) return;
    _wentAway = false;
    _openedAt = widget.now();
    _schedule(widget.settleDelay);
  }

  /// The live document answered, or changed. Worth a look only inside the
  /// open window; later than that it waits for the next open.
  void _onDocument() {
    if (_withinOpen()) _schedule(widget.settleDelay);
  }

  /// A clock set back since the open reads as outside the window, never
  /// as a window that stays open.
  bool _withinOpen() {
    final elapsed = widget.now().difference(_openedAt);
    return !elapsed.isNegative && elapsed <= kBroadcastOpenWindow;
  }

  /// Whether the home screen is what is on top: no dialog or sheet (a
  /// [PopupRoute]), and no pushed screen other than home itself (see
  /// [kBroadcastHomeRoutes]). Navigator has no getter for its top route;
  /// popUntil with a predicate that answers yes at once visits exactly the
  /// top route and pops nothing, the usual way to read it.
  bool _homeOnTop() {
    final navigator = Navigator.maybeOf(context);
    if (navigator == null) return false;
    Route<dynamic>? top;
    navigator.popUntil((route) {
      top = route;
      return true;
    });
    final route = top;
    if (route == null || route is PopupRoute) return false;
    return identical(route, _route) ||
        kBroadcastHomeRoutes.contains(route.settings.name);
  }

  BroadcastPopup? _pick(BroadcastState state, String? uid) => broadcastToShow(
        state,
        uid: uid,
        now: widget.now(),
        seen: BroadcastStore.seen,
      );

  void _schedule(Duration delay) {
    _timer?.cancel();
    _timer = Timer(delay, _tryShow);
  }

  bool _waitingForCurtain = false;

  /// Nothing opens under the launch curtain: it waits for the curtain to
  /// go, and this open's window starts from there (see afterLaunchCurtain).
  void _awaitCurtain() {
    if (_waitingForCurtain) return;
    _waitingForCurtain = true;
    afterLaunchCurtain(ref, () {
      _waitingForCurtain = false;
      if (!mounted) return;
      _openedAt = widget.now();
      _schedule(widget.settleDelay);
    });
  }

  /// What the update prompt would do for [state] on this phone: nothing when
  /// no gate is set, on a platform with no store, or when this build cannot
  /// be read (see [appUpdateNeed]). The build is only asked for once a gate
  /// exists, so a phone with none never touches the platform channel.
  Future<AppUpdateNeed> _updateNeed(BroadcastState state) async {
    if (state.update == null) return AppUpdateNeed.none;
    final platform = ref.read(updatePlatformProvider);
    if (platform == null) return AppUpdateNeed.none;
    final build = await ref.read(appBuildNumberProvider.future);
    return appUpdateNeed(
      gate: state.update,
      platform: platform,
      build: build,
      now: widget.now(),
      askedAt: BroadcastStore.updateAskedAt,
    );
  }

  Future<void> _tryShow() async {
    if (!mounted || _showing) return;
    if (ref.read(launchCurtainUpProvider)) return _awaitCurtain();
    if (!_withinOpen()) return;
    if (!ref.read(onboardingSeenProvider) ||
        !ref.read(firstRunOfferAskedProvider)) {
      return;
    }
    final uid = ref.read(broadcastUidProvider);
    // Set before the first await: the build number is one, and a second
    // timer must not start a second look while this one is still waiting.
    _showing = true;
    try {
      // Is anything owed at all? Judged on the copy this device holds, so a
      // phone with nothing to show never spends a read.
      if (await _updateNeed(BroadcastStore.current) == AppUpdateNeed.none &&
          _pick(BroadcastStore.current, uid) == null) {
        return;
      }
      if (!mounted) return;
      if (!_homeOnTop()) {
        _schedule(_retryDelay);
        return;
      }
      final fresh = await BroadcastStore.readFromServer();
      if (!mounted) return;
      if (fresh == null) {
        // Offline or slow: nothing is shown unconfirmed. Inside the open
        // window it asks again; after it, the next open will.
        _schedule(_retryDelay);
        return;
      }
      // An update outranks a message: the message keeps for the next open.
      final need = await _updateNeed(fresh);
      if (!mounted) return;
      if (need != AppUpdateNeed.none) {
        if (!_homeOnTop()) {
          _schedule(_retryDelay);
          return;
        }
        await _showUpdate(need);
        return;
      }
      final popup = _pick(fresh, uid);
      if (popup == null) return;
      if (!_homeOnTop()) {
        _schedule(_retryDelay);
        return;
      }
      BroadcastStore.markSeen(popup.id);
      await showBroadcastPopup(context, popup);
    } finally {
      _showing = false;
    }
  }

  /// Puts the update prompt up. The one that can be put off is remembered as
  /// offered as it goes up, for the reason markSeen gives; the one that
  /// cannot is offered again at every open, so it is not counted.
  Future<void> _showUpdate(AppUpdateNeed need) async {
    final platform = ref.read(updatePlatformProvider)!;
    final build = await ref.read(appBuildNumberProvider.future);
    if (!mounted) return;
    final mandatory = need == AppUpdateNeed.mandatory;
    if (!mandatory) BroadcastStore.markUpdateAsked(widget.now());
    final launch = ref.read(storeLauncherProvider);
    await showAppUpdateDialog(
      context,
      mandatory: mandatory,
      onUpdate: () => openStoreListing(platform, launch),
      stillMandatory: () =>
          appUpdateNeed(
            gate: BroadcastStore.current.update,
            platform: platform,
            build: build,
            now: widget.now(),
          ) ==
          AppUpdateNeed.mandatory,
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The pop-up itself: the same card as the app's other announcements
/// (RoomFinaleAnnouncer's dialog), one button, the admin's own words. The
/// words set the direction, not the app's language: an English app shown
/// the Arabic, because no English was written, still reads right to left.
Future<void> showBroadcastPopup(BuildContext context, BroadcastPopup popup) {
  final isAr = S.of(context).isAr;
  final direction =
      popup.showsArabic(isAr) ? TextDirection.rtl : TextDirection.ltr;
  final gp = context.gp;
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: gp.surfaceHigh,
      scrollable: true,
      icon: Icon(Icons.campaign_rounded, color: gp.goldInk, size: 32),
      title: Text(
        popup.title(isAr),
        textAlign: TextAlign.center,
        textDirection: direction,
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w800,
          color: gp.textPrimary,
        ),
      ),
      content: Text(
        popup.body(isAr),
        textAlign: TextAlign.center,
        textDirection: direction,
        style: TextStyle(fontSize: 14, height: 1.6, color: gp.textSec),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          style: FilledButton.styleFrom(
            backgroundColor: GameColors.gold,
            foregroundColor: GameColors.onGold,
          ),
          child: Text(
            popup.button(isAr) ?? MaterialLocalizations.of(ctx).okButtonLabel,
          ),
        ),
      ],
    ),
  );
}

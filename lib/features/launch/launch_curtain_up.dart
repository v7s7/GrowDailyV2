import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// True while the LaunchCurtain (launch_curtain.dart) covers the app. Seeded
/// true by main.dart on the platforms that show one, false everywhere else
/// (tests, the web), set false by the curtain the moment it starts to fade
/// (after the scene's ready moment, when the page underneath starts to
/// show), and true again by main.dart when a long return plays it again
/// (see [kLaunchReplayAfter]).
///
/// Read by what would otherwise happen unseen behind it: Doum's hello on the
/// Grid and a perfect day's celebration (GridScreen passes it to the day
/// card as `onScreen`), and everything that opens over the page, through
/// [afterLaunchCurtain].
///
/// Its own file, apart from the curtain, so the announcers that wait on it
/// do not import everything the curtain reads.
final launchCurtainUpProvider = StateProvider<bool>((ref) => false);

/// How long after the curtain starts to fade before something may open over
/// the page: the fade itself (480 ms) and a breath for the page to be seen.
const kLaunchSettle = Duration(milliseconds: 700);

/// How long the app has to have been away before a return plays the curtain
/// again (Aziz, 2026-09-30: "also after 30+ min away"). A new app day plays
/// it whatever the gap. A quicker return (a reply to a message, a glance at
/// another app) goes straight back to where the person was.
///
/// `--dart-define=GD_LAUNCH_REPLAY_AFTER_S=20` shortens it for a check on
/// the simulator, the way GD_LAUNCH_CYCLE walks the scenes.
const kLaunchReplayAfter = Duration(
  seconds: int.fromEnvironment('GD_LAUNCH_REPLAY_AFTER_S', defaultValue: 1800),
);

/// Bumped by main.dart each time a return plays the curtain again, so the
/// host builds a fresh one (LaunchCurtainHost). 0 is the launch's own.
final launchCurtainRunProvider = StateProvider<int>((ref) => 0);

/// True while the reminder pass this open asked for has not finished: the
/// launch's first, or the one a long return runs. Seeded true by main.dart
/// on the platforms with a curtain, since the launch always runs one, set
/// true again by main.dart when a pass starts under the curtain, and false
/// when the newest pass has finished.
///
/// The curtain holds for it: the pass is hundreds of calls into the phone's
/// notification system on iOS's main thread, the thread that hands touches
/// to the app, and run after the lift it was the Grid's first seconds of
/// lag (the launch audit, 2026-09-30: three passes back to back, from 0.5 s
/// before the lift to 25 s after it).
final launchRemindersArmingProvider = StateProvider<bool>((ref) => false);

/// True while a return's reloads are in flight: today's numbers, this week's
/// squares and the time zone, whose answer starts the reminder pass. Set by
/// main.dart around them, so a curtain played by a long return lifts onto
/// the fresh board rather than the one left behind.
final launchRefreshingProvider = StateProvider<bool>((ref) => false);

/// Runs [show] once the launch curtain has gone and the page has had a
/// moment ([settle]), or at once when no curtain is up.
///
/// For anything that opens over the page: a dialog, a sheet, a snackbar, a
/// haptic, a system prompt. The curtain sits above the Navigator, so what
/// opened while it was up played unseen under Doum's scene, or appeared the
/// instant it lifted (the launch audit, 2026-09-30: the admin pop-up, a
/// room's finale, the icon card, achievement sheets, the location prompt).
/// "The rest in the background", in Aziz's words: the page first, then its
/// messages.
///
/// [show] runs later than the call when it waits, so it checks its own
/// `mounted` before touching a context.
void afterLaunchCurtain(
  WidgetRef ref,
  void Function() show, {
  Duration settle = kLaunchSettle,
}) {
  if (!ref.read(launchCurtainUpProvider)) {
    show();
    return;
  }
  ProviderSubscription<bool>? sub;
  sub = ref.listenManual<bool>(launchCurtainUpProvider, (_, up) {
    if (up) return;
    sub?.close();
    Timer(settle, show);
  });
}

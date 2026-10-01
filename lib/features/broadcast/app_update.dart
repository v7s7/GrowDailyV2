/// The pop-up that sends someone on an old build to the store to update.
///
/// Aziz, 2026-09-30: whoever is not updating the app gets a pop-up that
/// sends them to update, with Doum in the pose that fits.
///
/// ── Where "the store has a newer build" comes from ─────────────────────
/// Not from the store. Apple's lookup only knows the marketing version
/// (1.1.0), and every build so far has shipped under one, so it cannot tell
/// build 83 from 84. The admin says it instead, once a build is live, on the
/// Messages page: `broadcast/live`'s `update` slot (see [AppUpdateGate]),
/// which this device already follows for the admin's pop-ups. Nothing is
/// asked of the store, and nothing shows until the admin has said so.
///
/// ── Two kinds ──────────────────────────────────────────────────────────
///   available  the newest build is above this one. Doum's pop-up with a way
///              to put it off, offered at most once a day ([kUpdateAskEvery]).
///   mandatory  this build is below the oldest one allowed. The same pop-up
///              with no way to put it off, every open, until it is updated.
///              Off unless the admin raises the minimum, which the tool
///              refuses to put above the newest build.
///
/// Both go up through BroadcastAnnouncer, so they keep its rules: only from
/// the home screen, once the launch curtain has gone, never over the first-run
/// walkthrough or another dialog, and only from what the server confirms
/// right then. That last rule is what keeps a phone that is offline from
/// being locked out: nothing unconfirmed is ever shown, least of all a wall.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/game_theme.dart';
import '../mascot/sprout.dart';
import 'broadcast_message.dart';

/// The App Store id and the Play package: the same two the join page
/// (public/join/index.html) sends people to.
const String kAppStoreId = '6788149393';
const String kAndroidPackage = 'com.growdaily.v2';

/// The least time between two offers of an update that can be put off.
const Duration kUpdateAskEvery = Duration(hours: 24);

/// Doum in the bulb pose: something new is ready. The pose the launch splash
/// already gives an update (LaunchScene.update), so the prompt and the
/// welcome after it are one story. Picked over the megaphone (shouts, and its
/// red is the loudest thing on the screen), the laptop (hides his face) and
/// the pointer and backpack (the coach marks' and the comeback card's).
const SproutPose kUpdatePose = SproutPose.idea;

enum AppUpdateNeed { none, available, mandatory }

/// What this open should do about an update. Pure, so the whole rule is
/// pinned by unit tests.
///
/// Never anything when it cannot be sure: no gate, a platform with no store
/// (web, desktop), or a build number that could not be read. A phone that
/// cannot read its own build must never be told it is out of date, least of
/// all by the kind that has no way out.
AppUpdateNeed appUpdateNeed({
  required AppUpdateGate? gate,
  required TargetPlatform? platform,
  required int? build,
  required DateTime now,
  DateTime? askedAt,
}) {
  if (gate == null || platform == null || build == null || build <= 0) {
    return AppUpdateNeed.none;
  }
  final min = gate.minFor(platform);
  if (min > 0 && build < min) return AppUpdateNeed.mandatory;
  final latest = gate.latestFor(platform);
  if (latest <= 0 || build >= latest) return AppUpdateNeed.none;
  if (askedAt != null) {
    // A clock set back since the last offer reads as long ago, never as a
    // day that has not passed yet.
    final since = now.difference(askedAt);
    if (!since.isNegative && since < kUpdateAskEvery) return AppUpdateNeed.none;
  }
  return AppUpdateNeed.available;
}

/// This app's build number (the `+N` of pubspec's version), or null when it
/// cannot be read.
final appBuildNumberProvider = FutureProvider<int?>((ref) async {
  try {
    return int.tryParse((await PackageInfo.fromPlatform()).buildNumber);
  } catch (e) {
    debugPrint('[update] could not read the build number: $e');
    return null;
  }
});

/// The platform whose store to send people to; null on the web, which is
/// always the newest build, so it is never asked.
final updatePlatformProvider = Provider<TargetPlatform?>(
  (ref) => kIsWeb ? null : defaultTargetPlatform,
);

typedef StoreLauncher = Future<bool> Function(Uri uri);

/// Opens a link outside the app. A provider so a widget test can stand in
/// for the phone's browser and store.
final storeLauncherProvider = Provider<StoreLauncher>(
  (ref) => (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

/// The app's page in the store, most direct first. Android tries the Play
/// app's own scheme and then the web page, since a phone with no Play app
/// (or one that refuses the scheme) still has a browser. iOS's https link is
/// opened by the App Store app itself.
List<Uri> storeListingUris(TargetPlatform platform) => switch (platform) {
      TargetPlatform.iOS => [Uri.parse('https://apps.apple.com/app/id$kAppStoreId')],
      TargetPlatform.android => [
          Uri.parse('market://details?id=$kAndroidPackage'),
          Uri.parse(
            'https://play.google.com/store/apps/details?id=$kAndroidPackage',
          ),
        ],
      _ => const [],
    };

/// Opens the store page through [launch]; true when one of the links opened.
Future<bool> openStoreListing(
  TargetPlatform platform,
  StoreLauncher launch,
) async {
  for (final uri in storeListingUris(platform)) {
    try {
      if (await launch(uri)) return true;
    } catch (e) {
      debugPrint('[update] $uri did not open: $e');
    }
  }
  return false;
}

/// The pop-up. [onUpdate] opens the store. A [mandatory] one has no "later",
/// no tap outside and no back, and closes itself only when
/// [stillMandatory] says the wall is gone (the admin lowered the minimum
/// while the app was open), so a minimum raised too early is undone within
/// a moment instead of at each phone's next cold start.
Future<void> showAppUpdateDialog(
  BuildContext context, {
  required bool mandatory,
  required Future<void> Function() onUpdate,
  bool Function()? stillMandatory,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: !mandatory,
    builder: (ctx) => _AppUpdateDialog(
      mandatory: mandatory,
      onUpdate: onUpdate,
      stillMandatory: stillMandatory,
    ),
  );
}

class _AppUpdateDialog extends StatefulWidget {
  const _AppUpdateDialog({
    required this.mandatory,
    required this.onUpdate,
    this.stillMandatory,
  });

  final bool mandatory;
  final Future<void> Function() onUpdate;
  final bool Function()? stillMandatory;

  @override
  State<_AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<_AppUpdateDialog> {
  @override
  void initState() {
    super.initState();
    if (widget.mandatory) BroadcastStore.live.addListener(_recheck);
  }

  @override
  void dispose() {
    BroadcastStore.live.removeListener(_recheck);
    super.dispose();
  }

  /// The document changed under an open wall. Navigator.pop, not maybePop:
  /// the PopScope below refuses the latter, which is the point of it.
  void _recheck() {
    final still = widget.stillMandatory;
    if (still == null || still() || !mounted) return;
    if (ModalRoute.of(context)?.isCurrent ?? false) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _update(BuildContext ctx) async {
    await widget.onUpdate();
    if (!widget.mandatory && ctx.mounted) Navigator.pop(ctx);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final gp = context.gp;
    final mandatory = widget.mandatory;
    return PopScope(
      canPop: !mandatory,
      child: AlertDialog(
        backgroundColor: gp.surfaceHigh,
        scrollable: true,
        // No entrance of its own, the dialog already arrives with one.
        icon: const Sprout(
          pose: kUpdatePose,
          height: 110,
          entrance: SproutEntrance.none,
        ),
        title: Text(
          mandatory ? s.updateRequiredTitle : s.updateAvailableTitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: gp.textPrimary,
          ),
        ),
        content: Text(
          mandatory ? s.updateRequiredBody : s.updateAvailableBody,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13.5, height: 1.5, color: gp.textSec),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          if (!mandatory)
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(s.updateLater, style: TextStyle(color: gp.textTert)),
            ),
          FilledButton(
            onPressed: () => _update(context),
            style: FilledButton.styleFrom(
              backgroundColor: GameColors.gold,
              foregroundColor: GameColors.onGold,
            ),
            child: Text(s.updateNow),
          ),
        ],
      ),
    );
  }
}

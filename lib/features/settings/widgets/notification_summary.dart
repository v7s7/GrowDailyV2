import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/services/notification_service.dart';
import '../notifiers/notification_settings_notifier.dart'
    show notificationSettingsProvider;

/// How Settings asks the phone whether this app may notify at all.
///
/// A provider rather than a direct call so a widget test can answer it: the
/// real check goes through the notifications plugin's platform channel.
/// null means the platform cannot say, which is read as "say nothing", the
/// same rule NotificationService.checkSystemPermission documents.
final systemNotificationPermissionProvider =
    Provider<Future<bool?> Function()>(
  (ref) => NotificationService.instance.checkSystemPermission,
);

/// Whether the phone has never been asked for notification permission.
///
/// iOS answers "not enabled" both for a permission the person refused and
/// for one the app has simply never asked for (notDetermined), and this app
/// only asks when someone sets a reminder or opens Rooms (notifications
/// only if chosen). The Notifications page's red banner is right to show in
/// both cases, because its button asks first. Settings' line is not: «موقوفة
/// من تلفونك» sends the person to a switch in the phone's Settings app that
/// does not exist yet, since iOS adds it only after the first ask. So the
/// line asks this too, and says nothing about the phone until it was asked.
///
/// iOS only: on Android 13+ a never-asked permission really does read as off
/// in the phone's App info, so there the words are true. A failed check is
/// read as "was asked", which keeps the old, plainer answer.
final notificationPermissionNeverAskedProvider =
    Provider<Future<bool> Function()>((ref) => () async {
          if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
            return false;
          }
          try {
            final settings =
                await FirebaseMessaging.instance.getNotificationSettings();
            return settings.authorizationStatus ==
                AuthorizationStatus.notDetermined;
          } catch (_) {
            return false;
          }
        });

/// The line under Settings › «الإشعارات».
///
/// Aziz turned down an ON word («شغّالة», 2026-09-28): while nothing is off,
/// the line says what the page holds. Only an OFF state is named, and it
/// names WHERE it is off, because the fix is in a different place for each:
///  - «موقوفة من تلفونك»: the phone blocks this app, so no switch in the app
///    can help (the page's own red banner says the same, with the button).
///    Not for a permission the phone was never asked for: see
///    [notificationPermissionNeverAskedProvider].
///  - «موقوفة»: the page's own «السماح بالإشعارات» switch.
/// The phone is checked first because it wins: with the phone blocking,
/// the app's switch being on changes nothing.
///
/// The phone is asked when this is built and again on every resume (the
/// fix happens in the phone's Settings app, outside this one), like the
/// permission banner on the Notifications page. Until it answers, the line
/// is the plain what-it-holds line, which claims nothing either way.
class NotificationSummaryText extends ConsumerStatefulWidget {
  const NotificationSummaryText({super.key, required this.style});

  final TextStyle style;

  @override
  ConsumerState<NotificationSummaryText> createState() =>
      _NotificationSummaryTextState();
}

class _NotificationSummaryTextState
    extends ConsumerState<NotificationSummaryText>
    with WidgetsBindingObserver {
  bool? _phoneAllows;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    bool? allows;
    try {
      allows = await ref.read(systemNotificationPermissionProvider)();
      if (allows == false &&
          await ref.read(notificationPermissionNeverAskedProvider)()) {
        allows = null;
      }
    } catch (_) {
      // No answer is no claim: keep the what-it-holds line.
      allows = null;
    }
    if (mounted) setState(() => _phoneAllows = allows);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final masterOn = ref.watch(
      notificationSettingsProvider.select((n) => n.masterEnabled),
    );
    final text = _phoneAllows == false
        ? s.settingsNotifPhoneOff
        : !masterOn
            ? s.settingsNotifOff
            : s.settingsNotifSummary;
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: widget.style,
    );
  }
}

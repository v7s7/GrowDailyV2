import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

/// Thin wrapper around [SharePlus.instance.share] that always supplies a
/// real, non-zero [ShareParams.sharePositionOrigin].
///
/// That field has always been how iPad anchors the share popover, but
/// leaving it unset used to just mean "iPhone doesn't need it, iPad falls
/// back to centered" — harmless. As of iOS 26, share_plus's platform
/// channel throws instead: `PlatformException(error, sharePositionOrigin:
/// argument must be set, {{0, 0}, {0, 0}} must be non-zero...)`, on every
/// device, iPad or not — no share sheet ever appears, on any share call
/// that doesn't set this. Confirmed upstream, not fixed as of share_plus
/// 11.1.0 (this app's pinned version): fluttercommunity/plus_plugins#3685.
///
/// Every `Share.share`/`SharePlus.instance.share` call in this app should
/// go through here instead of calling the plugin directly, so this fix
/// only ever has to happen once, and so it's still correct if a future
/// share_plus version starts requiring this on other platforms too.
class ShareService {
  ShareService._();

  /// Shares plain text (every share action in this app today — an invite
  /// message, a monthly recap summary — see RoomDetailScreen/
  /// CreateRoomSheet/MonthlyStoryScreen). [context] only needs to still be
  /// mounted at call time, which every real button-press call site already
  /// guarantees.
  static Future<void> shareText(BuildContext context, String text) {
    return SharePlus.instance.share(ShareParams(
      text: text,
      sharePositionOrigin: _originFor(context),
    ));
  }

  /// The tapped control's own on-screen rect where possible - the correct
  /// iPad popover anchor, and incidentally also satisfies iOS 26's new
  /// non-zero requirement everywhere else. Falls back to a small non-zero
  /// rect at the window's origin on the rare call where the context's
  /// render object isn't available yet - iOS only requires the rect to be
  /// non-zero and within the window, not pixel-perfect on any particular
  /// widget.
  static Rect _originFor(BuildContext context) {
    final box = context.findRenderObject();
    if (box is RenderBox && box.hasSize) {
      return box.localToGlobal(Offset.zero) & box.size;
    }
    return const Rect.fromLTWH(0, 0, 1, 1);
  }
}

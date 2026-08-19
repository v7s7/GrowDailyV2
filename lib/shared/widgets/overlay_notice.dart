import 'dart:async';

import 'package:flutter/material.dart';

/// A floating notice that is visible from ANYWHERE, including over modal
/// bottom sheets.
///
/// Exists because a SnackBar posted while a sheet is open draws on the
/// Scaffold BEHIND the sheet and is never seen. Three matrix widgets had
/// independently discovered this and grown their own inline notice slots;
/// five more call sites were still posting invisible SnackBars (a past
/// reminder time, notification permission denied, mic permission denied).
/// This is the one shared fix: an entry inserted into the ROOT overlay,
/// which stacks above every open route including modal sheets.
///
/// Deliberately not a SnackBar clone: top-anchored (sheets own the bottom
/// of the screen, and the thumb is usually there too), no action button,
/// auto-dismissing. For feedback that needs an action, use a real SnackBar
/// on a visible Scaffold instead.
void showOverlayNotice(
  BuildContext context,
  String message, {
  IconData icon = Icons.info_outline_rounded,
}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _OverlayNotice(
      message: message,
      icon: icon,
      onDone: () => entry.remove(),
    ),
  );
  overlay.insert(entry);
}

class _OverlayNotice extends StatefulWidget {
  final String message;
  final IconData icon;
  final VoidCallback onDone;
  const _OverlayNotice({
    required this.message,
    required this.icon,
    required this.onDone,
  });

  @override
  State<_OverlayNotice> createState() => _OverlayNoticeState();
}

class _OverlayNoticeState extends State<_OverlayNotice>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    _c.forward();
    _hide = Timer(const Duration(milliseconds: 3200), () async {
      await _c.reverse();
      widget.onDone();
    });
  }

  @override
  void dispose() {
    _hide?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Positioned(
      top: MediaQuery.of(context).padding.top + 10,
      left: 16,
      right: 16,
      child: FadeTransition(
        opacity: CurvedAnimation(parent: _c, curve: Curves.easeOut),
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, -0.3),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic)),
          // Material, not a bare Container: this lives in the root overlay
          // with no Scaffold ancestor, and Text without Material renders
          // with the yellow-underline fallback.
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: dark ? const Color(0xFF232B33) : const Color(0xFF2C3540),
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x59000000),
                    blurRadius: 18,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(widget.icon, size: 17, color: const Color(0xFFE8C468)),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      widget.message,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFF2F5F7),
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

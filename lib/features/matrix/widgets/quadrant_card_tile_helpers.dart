part of 'quadrant_card.dart';


/// A real, generously-sized tap target for one of row 2's icon buttons
/// (favorite/drag-handle/info) — a filled 34x34 circle (matching
/// ActionRow's precedent elsewhere in the app) instead of a bare glyph, so
/// the visible boundary and the actual hit box are the same size and a
/// thumb doesn't have to land pixel-perfectly on a 16px icon to register.
class _TileIconButton extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;

  /// What this button does, in words.
  ///
  /// Three glyphs sat on every task row with nothing naming any of them: a
  /// VoiceOver user heard "button, button, button", and a sighted new user
  /// had to guess. Given as a Semantics label AND a long-press tooltip, so
  /// the same string answers both "what is this?" questions.
  final String label;

  const _TileIconButton({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.onTap,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Semantics(
      container: true,
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
      // Center fills whatever width its parent gives it (a whole 1/3 or
      // 1/4 of the row when wrapped in Expanded — see _TaskTile.build())
      // and, since the GestureDetector above is opaque, that entire
      // filled area is tappable — not just the small 34x34 circle drawn
      // in the middle of it, which stays fixed-size purely for a compact,
      // uncluttered look.
          child: Center(
            child: Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: gp.textTert.withOpacity(0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 17, color: iconColor),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Voice note indicator ──────────────────────────────────────────────────

/// Compact row-2 icon for this task's recordings — a real play/pause
/// button (the exact same look-and-feel as each row's button inside
/// TaskDetailSheet's recordings list — see VoiceNoteRow in
/// voice_note_player.dart), not just a status glyph, so hearing a quick
/// recap never requires opening the details sheet first. Tapping surfaces
/// the same floating global player every other play button in the app
/// does (VoiceNoteService.play → GlobalVoiceNotePlayerOverlay) — nothing
/// extra to wire up here.
///
/// Only unambiguous when there's exactly one recording, so that's the only
/// time a tap plays anything directly. With more than one (see the count
/// badge), there's no single note a tap here could mean — so it opens
/// TaskDetailSheet's full list instead, same destination as the info icon
/// next to it, where each one has its own play button.
class _VoiceNoteIndicator extends StatelessWidget {
  final List<VoiceNote> notes;
  final Color color;
  final VoidCallback onOpenDetails;

  const _VoiceNoteIndicator({
    required this.notes,
    required this.color,
    required this.onOpenDetails,
  });

  @override
  Widget build(BuildContext context) {
    final first = notes.first;
    final s = S.of(context);
    final displayName =
        first.name.isNotEmpty ? first.name : s.voiceNoteDefaultName(1);
    final svc = VoiceNoteService.instance;
    return AnimatedBuilder(
      animation: Listenable.merge([svc.nowPlaying, svc.isPlaying]),
      builder: (context, _) {
        final nowPlayingId = svc.nowPlaying.value?.noteId;
        final active =
            nowPlayingId != null && notes.any((n) => n.id == nowPlayingId);
        final playing = active && svc.isPlaying.value;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticFeedback.selectionClick();
            if (notes.length > 1) {
              onOpenDetails();
              return;
            }
            svc.togglePlayback(
              first.id,
              first.path,
              title: displayName,
              color: color,
              durationSeconds: first.durationSeconds,
              audioBase64: first.audioBase64,
            );
          },
          // Same fill-the-cell-but-draw-a-small-circle treatment as
          // _TileIconButton (its neighbors in row 2) — Center expands to
          // whatever width Expanded gives this in _TaskTile.build(), so
          // the whole cell is tappable, not just the 34x34 circle.
          child: Center(
            child: Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withOpacity(playing ? 0.2 : 0.12),
                shape: BoxShape.circle,
              ),
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: 16,
                    color: color,
                  ),
                  if (notes.length > 1)
                    Positioned(
                      top: -7,
                      right: -11,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
                        ),
                        child: Text(
                          '${notes.length}',
                          style: const TextStyle(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w800,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─── Action sheet row ─────────────────────────────────────────────────────────

/// One tappable row in a task action sheet — either the "Delete" action
/// (an icon in a tinted circle) or a "move to quadrant" option (a small
/// colored dot standing in for that quadrant's chip color). Both share the
/// same tinted-card treatment so the sheet reads as a set of modern,
/// generously-spaced options instead of a cramped classic menu. Public so
/// TaskDetailSheet can reuse it for its own Delete/Move rows instead of
/// duplicating this styling.
class ActionRow extends StatelessWidget {
  final IconData? icon;
  final Color? iconColor;
  final Color? dotColor;
  final String label;
  final String? subtitle;
  final Color? labelColor;
  final VoidCallback onTap;

  const ActionRow({
    this.icon,
    this.iconColor,
    this.dotColor,
    required this.label,
    this.subtitle,
    this.labelColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final tint = iconColor ?? dotColor ?? GameColors.gold;
    return Material(
      color: tint.withOpacity(0.07),
      borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tint.withOpacity(0.16),
                  shape: BoxShape.circle,
                ),
                child: icon != null
                    ? Icon(icon, size: 17, color: iconColor)
                    : Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                            color: dotColor, shape: BoxShape.circle),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: labelColor ?? gp.textPrimary)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!,
                          style: TextStyle(fontSize: 11.5, color: gp.textSec)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

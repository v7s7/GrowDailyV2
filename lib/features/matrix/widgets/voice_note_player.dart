import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/services/voice_note_service.dart';
import '../../../core/theme/game_theme.dart';
import '../models/matrix_task.dart';

/// The app's one global "now playing" bar — a Spotify-style playback bar
/// (draggable scrubber, elapsed/remaining time, ±5s skip, play/pause, a
/// 1x/1.5x/2x speed pill) plus a title and a close button, floated near
/// the bottom of the screen by [GlobalVoiceNotePlayerOverlay] (mounted
/// once in main.dart's MaterialApp.builder — see its doc comment) so it
/// stays visible everywhere: every tab, any modal sheet, any pushed
/// screen — not just the task it came from.
///
/// Only ever built for the note VoiceNoteService.nowPlaying already points
/// at ([GlobalVoiceNotePlayerOverlay] only mounts this widget when that's
/// non-null), so every control below can assume it's acting on the loaded
/// note rather than needing to load one first.
///
/// Forced into LTR regardless of the app's locale: a playback timeline
/// reads as a universal left-to-right time axis (elapsed left, remaining
/// right) the same way WhatsApp/iMessage voice notes do even inside an
/// Arabic RTL layout, rather than mirroring with the rest of the screen.
class VoiceNotePlayer extends StatefulWidget {
  final String noteId;
  final String path;
  final String title;
  final int durationSeconds;
  final Color color;
  final VoidCallback onClose;
  // Threaded straight through to every svc.play() call below (see
  // _togglePlayPause/_skip/_seekToFraction) so a reload triggered from
  // *this* widget — e.g. resuming right as the previous note's onComplete
  // cleared VoiceNoteService.nowPlaying out from under it — can still fall
  // back to synced bytes on a device that never recorded this note.
  final String? audioBase64;

  const VoiceNotePlayer({
    super.key,
    required this.noteId,
    required this.path,
    required this.title,
    required this.durationSeconds,
    required this.color,
    required this.onClose,
    this.audioBase64,
  });

  @override
  State<VoiceNotePlayer> createState() => _VoiceNotePlayerState();
}

class _VoiceNotePlayerState extends State<VoiceNotePlayer> {
  bool _dragging = false;
  double _dragFraction = 0;

  bool get _active =>
      VoiceNoteService.instance.nowPlaying.value?.noteId == widget.noteId;

  Duration get _knownDuration => Duration(seconds: widget.durationSeconds);

  /// The live decoded duration once VoiceNoteService has it for *this*
  /// note; otherwise the estimate taken at record time, so the total-time
  /// label never has to show 0:00.
  Duration get _liveDuration {
    final d = VoiceNoteService.instance.duration.value;
    return (_active && d > Duration.zero) ? d : _knownDuration;
  }

  Duration get _livePosition =>
      _active ? VoiceNoteService.instance.position.value : Duration.zero;

  Future<void> _togglePlayPause() async {
    HapticFeedback.selectionClick();
    final svc = VoiceNoteService.instance;
    if (_active && svc.isPlaying.value) {
      await svc.pause();
    } else {
      await svc.play(widget.noteId, widget.path,
          title: widget.title,
          color: widget.color,
          durationSeconds: widget.durationSeconds,
          audioBase64: widget.audioBase64);
    }
  }

  Future<void> _skip(int seconds) async {
    HapticFeedback.lightImpact();
    final svc = VoiceNoteService.instance;
    if (!_active) {
      await svc.play(widget.noteId, widget.path,
          title: widget.title,
          color: widget.color,
          durationSeconds: widget.durationSeconds,
          audioBase64: widget.audioBase64);
    }
    await svc.seekBy(Duration(seconds: seconds));
  }

  Future<void> _cycleSpeed() async {
    HapticFeedback.lightImpact();
    await VoiceNoteService.instance.cycleSpeed();
  }

  /// Shared by both "tap the track to jump there" and "release the
  /// dragged thumb" — loads this note first if it isn't already the
  /// active one, then seeks.
  Future<void> _seekToFraction(double fraction) async {
    final total = _liveDuration;
    final target =
        Duration(milliseconds: (fraction * total.inMilliseconds).round());
    HapticFeedback.selectionClick();
    final svc = VoiceNoteService.instance;
    if (!_active) {
      await svc.play(widget.noteId, widget.path,
          title: widget.title,
          color: widget.color,
          durationSeconds: widget.durationSeconds,
          audioBase64: widget.audioBase64);
    }
    await svc.seek(target);
  }

  double _fractionForDx(double dx, double width) {
    if (width <= 0) return 0;
    return (dx / width).clamp(0.0, 1.0);
  }

  void _onDragStart(DragStartDetails d, double width) {
    HapticFeedback.selectionClick();
    setState(() {
      _dragging = true;
      _dragFraction = _fractionForDx(d.localPosition.dx, width);
    });
  }

  void _onDragUpdate(DragUpdateDetails d, double width) {
    setState(() {
      _dragFraction = _fractionForDx(d.localPosition.dx, width);
    });
  }

  Future<void> _onDragEnd() async {
    final fraction = _dragFraction;
    setState(() => _dragging = false);
    await _seekToFraction(fraction);
  }

  String _fmt(Duration d) {
    final clamped = d.isNegative ? Duration.zero : d;
    final m = clamped.inMinutes.toString().padLeft(2, '0');
    final s = (clamped.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final svc = VoiceNoteService.instance;
    return Directionality(
      textDirection: TextDirection.ltr,
      // Wrapped in a transparent Material so descendant Text widgets get a
      // real DefaultTextStyle to inherit from. This player now mounts
      // directly inside MaterialApp.builder's Stack (see
      // GlobalVoiceNotePlayerOverlay), outside any Scaffold/Material —
      // without this, every Text here falls back to Flutter's "no Material
      // ancestor" debug style: an ugly yellow, double-underlined look
      // (debug builds only, but a real bug to leave unfixed).
      // `transparency` means this adds no color/elevation/shadow of its
      // own — the Container below still fully owns this card's look.
      child: Material(
        type: MaterialType.transparency,
        child: AnimatedBuilder(
          animation: Listenable.merge([
            svc.nowPlaying,
            svc.isPlaying,
            svc.position,
            svc.duration,
            svc.speed,
          ]),
        builder: (context, _) {
          final playing = _active && svc.isPlaying.value;
          final total = _liveDuration;
          final displayPosition = _dragging
              ? Duration(
                  milliseconds:
                      (_dragFraction * total.inMilliseconds).round())
              : _livePosition;
          final remaining = total - displayPosition;
          final fraction = total.inMilliseconds <= 0
              ? 0.0
              : (displayPosition.inMilliseconds / total.inMilliseconds)
                  .clamp(0.0, 1.0);

          return Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
            decoration: BoxDecoration(
              // Opaque-ish rather than the tinted-translucent look this
              // used inline in TaskDetailSheet — it now floats over
              // whatever's on screen behind it (Dashboard/Grid/Focus/
              // Matrix/Profile all show it), so it needs its own solid
              // backing instead of relying on a sheet's surface underneath.
              color: gp.surfaceHigh,
              borderRadius: BorderRadius.circular(18),
              border:
                  Border.all(color: widget.color.withOpacity(0.28), width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.18),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(Icons.graphic_eq_rounded,
                        size: 14, color: widget.color),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: gp.textPrimary,
                        ),
                      ),
                    ),
                    Semantics(
                      button: true,
                      label: s.voiceNoteClosePlayer,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          HapticFeedback.lightImpact();
                          widget.onClose();
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(Icons.close_rounded,
                              size: 16, color: gp.textTert),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // A plain Row, not Stack+Positioned — that earlier attempt
                // pinned the speed pill to the right edge independently of
                // the centered Row next to it, so on a narrower card the
                // two could actually overlap (the pill painting over the
                // skip-forward button instead of past it). A Row's children
                // are always laid out in sequence, left to right, so
                // overlap like that is structurally impossible here. The
                // invisible twin of the speed pill on the left reserves the
                // exact same width there as the real one takes on the
                // right, which is what makes the Expanded center Row
                // land in the true middle of the *card* — centering it
                // without that twin would only center it within whatever
                // space happens to be left over after the real pill, which
                // visibly drifts off-center depending on the pill's label
                // width (1x vs 1.5x vs 2x).
                SizedBox(
                  height: 44,
                  child: Row(
                    children: [
                      Visibility(
                        visible: false,
                        maintainSize: true,
                        maintainAnimation: true,
                        maintainState: true,
                        child: _SpeedPill(
                          speed: svc.speed.value,
                          color: widget.color,
                          semanticLabelBuilder: s.voiceNoteSpeedLabel,
                          onTap: _cycleSpeed,
                        ),
                      ),
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _RoundIconButton(
                              icon: Icons.replay_5_rounded,
                              color: widget.color,
                              semanticLabel: s.voiceNoteSkipBack,
                              onTap: () => _skip(-5),
                            ),
                            const SizedBox(width: 10),
                            _PlayPauseButton(
                              playing: playing,
                              color: widget.color,
                              playLabel: s.voiceNotePlay,
                              pauseLabel: s.voiceNotePause,
                              onTap: _togglePlayPause,
                            ),
                            const SizedBox(width: 10),
                            _RoundIconButton(
                              icon: Icons.forward_5_rounded,
                              color: widget.color,
                              semanticLabel: s.voiceNoteSkipForward,
                              onTap: () => _skip(5),
                            ),
                          ],
                        ),
                      ),
                      _SpeedPill(
                        speed: svc.speed.value,
                        color: widget.color,
                        semanticLabelBuilder: s.voiceNoteSpeedLabel,
                        onTap: _cycleSpeed,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    final maxLeft = width > 14.0 ? width - 14.0 : 0.0;
                    final thumbLeft =
                        (width * fraction - 7).clamp(0.0, maxLeft);
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragStart: (d) => _onDragStart(d, width),
                      onHorizontalDragUpdate: (d) => _onDragUpdate(d, width),
                      onHorizontalDragEnd: (_) => _onDragEnd(),
                      onTapUp: (d) => _seekToFraction(
                          _fractionForDx(d.localPosition.dx, width)),
                      child: SizedBox(
                        height: 24,
                        width: double.infinity,
                        child: Stack(
                          clipBehavior: Clip.none,
                          alignment: Alignment.centerLeft,
                          children: [
                            Container(
                              height: 4,
                              width: width,
                              decoration: BoxDecoration(
                                color: gp.border,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            AnimatedContainer(
                              duration: _dragging
                                  ? Duration.zero
                                  : const Duration(milliseconds: 180),
                              height: 4,
                              width: width * fraction,
                              decoration: BoxDecoration(
                                color: widget.color,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            AnimatedPositioned(
                              duration: _dragging
                                  ? Duration.zero
                                  : const Duration(milliseconds: 180),
                              curve: Curves.easeOut,
                              left: thumbLeft,
                              top: 5,
                              child: AnimatedScale(
                                scale: _dragging ? 1.3 : 1.0,
                                duration: const Duration(milliseconds: 140),
                                curve: Curves.easeOut,
                                child: Container(
                                  width: 14,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: widget.color,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: gp.surfaceHigh, width: 2),
                                    boxShadow: _dragging
                                        ? [
                                            BoxShadow(
                                              color: widget.color
                                                  .withOpacity(0.35),
                                              blurRadius: 8,
                                              spreadRadius: 1,
                                            ),
                                          ]
                                        : const [],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      _fmt(displayPosition),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: gp.textTert,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '-${_fmt(remaining)}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: gp.textTert,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 220.ms)
        .slideY(begin: 0.06, duration: 240.ms, curve: Curves.easeOutCubic);
  }
}

// ─── Global overlay ─────────────────────────────────────────────────────────

/// Mounted once, above *everything* — see main.dart's MaterialApp.builder —
/// rather than inside GameNavBar the way this used to work. A modal bottom
/// sheet (TaskDetailSheet, AddTaskSheet) or a pushed full-screen route
/// (QuadrantExpandedScreen, Focus, Premium, ...) each add their own layer to
/// the *same* Navigator GameNavBar's screen already lives in, and that new
/// layer paints over the entire previous screen — nav bar included. So a
/// player docked inside GameNavBar would go dark the moment any of those
/// opened, even though VoiceNoteService kept right on playing underneath —
/// exactly what it's not supposed to do. Sitting in MaterialApp.builder
/// instead means this is the topmost layer of the whole app, full stop:
/// nothing pushed or shown modally can ever paint over it again.
///
/// [Align] rather than [Positioned] deliberately — this is a direct,
/// non-Positioned child of builder's root Stack (see main.dart), and Align
/// only ever hit-tests the area its child actually paints, so the rest of
/// the screen stays fully tappable through the empty space around the
/// player, exactly like it did when this was zero-cost dead space inside
/// GameNavBar's own Column.
///
/// The extra fixed clearance in the bottom padding is a stand-in for
/// GameNavBar's own height, which this widget has no way to know exactly —
/// it's mounted above the Navigator, not inside whichever screen happens to
/// be showing. On the three tab screens that actually have a nav bar
/// (Grid/Profile/Matrix) this keeps the player sitting just above it, same
/// as before; everywhere else it just leaves a little breathing room above
/// the bottom edge instead of gluing itself to it, which reads as
/// intentional rather than like a mistake.
class GlobalVoiceNotePlayerOverlay extends StatelessWidget {
  const GlobalVoiceNotePlayerOverlay({super.key});

  static const double _navBarClearance = 74;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<NowPlayingVoiceNote?>(
      valueListenable: VoiceNoteService.instance.nowPlaying,
      builder: (context, nowPlaying, _) {
        if (nowPlaying == null) return const SizedBox.shrink();
        return Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  12, 0, 12, 8 + _navBarClearance),
              child: VoiceNotePlayer(
                key: ValueKey(nowPlaying.noteId),
                noteId: nowPlaying.noteId,
                path: nowPlaying.path,
                title: nowPlaying.title,
                durationSeconds: nowPlaying.durationSeconds,
                color: nowPlaying.color,
                audioBase64: nowPlaying.audioBase64,
                onClose: () => VoiceNoteService.instance.stopPlayback(),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─── Small building blocks ─────────────────────────────────────────────────

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String semanticLabel;
  final VoidCallback onTap;

  const _RoundIconButton({
    required this.icon,
    required this.color,
    required this.semanticLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  final bool playing;
  final Color color;
  final String playLabel;
  final String pauseLabel;
  final VoidCallback onTap;

  const _PlayPauseButton({
    required this.playing,
    required this.color,
    required this.playLabel,
    required this.pauseLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: playing ? pauseLabel : playLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            transitionBuilder: (child, anim) =>
                ScaleTransition(scale: anim, child: child),
            child: Icon(
              playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              key: ValueKey<bool>(playing),
              size: 22,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _SpeedPill extends StatelessWidget {
  final double speed;
  final Color color;
  final String Function(String rate) semanticLabelBuilder;
  final VoidCallback onTap;

  const _SpeedPill({
    required this.speed,
    required this.color,
    required this.semanticLabelBuilder,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final label =
        speed == speed.roundToDouble() ? '${speed.toInt()}x' : '${speed}x';
    return Semantics(
      button: true,
      label: semanticLabelBuilder(label),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(100),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── One recording's row ───────────────────────────────────────────────────

class VoiceNoteRow extends StatelessWidget {
  final VoiceNote note;
  final String displayName;
  final Color color;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const VoiceNoteRow({
    required this.note,
    required this.displayName,
    required this.color,
    required this.onRename,
    required this.onDelete,
  });

  String _fmt(int totalSeconds) {
    final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final sec = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$sec';
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final svc = VoiceNoteService.instance;
    return AnimatedBuilder(
      animation: Listenable.merge([svc.nowPlaying, svc.isPlaying]),
      builder: (context, _) {
        final active = svc.nowPlaying.value?.noteId == note.id;
        final playing = active && svc.isPlaying.value;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: active ? color.withOpacity(0.08) : gp.surfaceHL,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: active ? color.withOpacity(0.35) : gp.border,
              width: active ? 1 : 0.5,
            ),
          ),
          child: Row(
            children: [
              Semantics(
                button: true,
                label: playing ? s.voiceNotePause : s.voiceNotePlay,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    svc.togglePlayback(
                      note.id,
                      note.path,
                      title: displayName,
                      color: color,
                      durationSeconds: note.durationSeconds,
                      audioBase64: note.audioBase64,
                    );
                  },
                  child: Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.14),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      playing
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      size: 17,
                      color: color,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onRename,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: gp.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _fmt(note.durationSeconds),
                        style: TextStyle(fontSize: 11, color: gp.textTert),
                      ),
                    ],
                  ),
                ),
              ),
              Semantics(
                button: true,
                label: s.voiceNoteRenameTitle,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onRename,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(Icons.edit_rounded,
                        size: 15, color: gp.textTert),
                  ),
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onDelete,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child:
                      Icon(Icons.close_rounded, size: 16, color: gp.textTert),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Rename sheet ───────────────────────────────────────────────────────────

/// Small bottom sheet for naming/renaming one voice note — same chrome as
/// profile's edit-name sheet (surfaceHigh card, drag handle, centered
/// title) minus its avatar/async-submit machinery, since renaming a note
/// is instant and purely local.
void showRenameVoiceNoteSheet(
  BuildContext context, {
  required String currentName,
  required ValueChanged<String> onSave,
}) {
  HapticFeedback.selectionClick();
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) =>
        _RenameVoiceNoteSheet(currentName: currentName, onSave: onSave),
  );
}

class _RenameVoiceNoteSheet extends StatefulWidget {
  final String currentName;
  final ValueChanged<String> onSave;

  const _RenameVoiceNoteSheet({
    required this.currentName,
    required this.onSave,
  });

  @override
  State<_RenameVoiceNoteSheet> createState() => _RenameVoiceNoteSheetState();
}

class _RenameVoiceNoteSheetState extends State<_RenameVoiceNoteSheet> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.currentName);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    widget.onSave(name);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        decoration: BoxDecoration(
          color: gp.surfaceHigh,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: gp.border, width: 0.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: gp.border,
                  borderRadius: BorderRadius.circular(100),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              s.voiceNoteRenameTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: gp.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              onSubmitted: (_) => _save(),
              decoration: InputDecoration(
                hintText: s.voiceNoteRenameHint,
                filled: true,
                fillColor: gp.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: gp.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: gp.border),
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check_rounded, size: 18),
              label: Text(s.voiceNoteRenameSave),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/datetime_ext.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/services/voice_note_service.dart';
import '../../../core/theme/game_theme.dart';
import '../../../shared/widgets/history_demo_gate.dart';
import '../../auth/notifiers/auth_notifier.dart' show authStateProvider;
import '../../matrix/models/matrix_task.dart' show VoiceNote;
import '../../premium/notifiers/premium_notifier.dart'
    show canBrowseHistoryMonth, premiumAccessProvider;
import '../notifiers/square_voice_notes.dart';
import '../notifiers/weekly_grid_notifier.dart' show WeeklyGridState;

/// One way a written note looks, everywhere it appears.
///
/// It had four. A bare unbounded `Text` in the journal, an unlabelled
/// secondary subtitle in the heatmap day sheet, a bordered block in the
/// Progress hub, and the editor's field. The heatmap's version in particular
/// was styled exactly like metadata, so nothing on screen told the user that
/// line was a thing they wrote.
///
/// The Progress hub's form wins because it is the only one that already reads
/// as an object rather than a caption, plus a 2pt leading rule so it reads as
/// quoted material in both text directions.
///
/// THE PAYWALL LIVES IN HERE, and that is structural rather than tidy. The
/// heatmap day sheet rendered notes with no premium check at all; it was
/// legal only by the accident that `MonthlyHeatmapScreen._freeMonthsToShow`
/// happens to equal [kFreeHistoryMonths]. Two independent constants, one leak
/// waiting for someone to change one of them. After this, no call site can
/// render a note without the check, because there is no other way to render
/// one.
class HabitNoteBlock extends ConsumerWidget {
  final String note;

  /// The day the note was written on, which is what the free-history window
  /// is measured against.
  final DateTime day;

  /// Shown above the block on surfaces that carry no other label for it.
  /// The journal and the Progress hub are already unambiguous, so they pass
  /// nothing rather than repeating themselves.
  final String? label;

  const HabitNoteBlock({
    super.key,
    required this.note,
    required this.day,
    this.label,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = note.trim();
    if (text.isEmpty) return const SizedBox.shrink();
    final gp = context.gp;

    final walled = WeeklyGridState.noteIsWalled(
      note: text,
      day: day,
      now: DateTime.now().effectiveDay,
      isPremium: ref.watch(premiumAccessProvider),
    );

    final body = walled
        ? const _LockCard()
        : Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: gp.surfaceHigh,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: gp.border, width: 0.5),
            ),
            // A start-side rule, so the block reads as quoted material and
            // lands on the correct side in Arabic and in English without a
            // second widget.
            child: Container(
              padding: const EdgeInsetsDirectional.only(start: 8),
              decoration: BoxDecoration(
                border: BorderDirectional(
                  start: BorderSide(color: gp.border, width: 2),
                ),
              ),
              // No maxLines on purpose. These are the user's own words on
              // surfaces they opened in order to read them, and truncating
              // them to tidy a list is the wrong trade.
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 13,
                  color: gp.textSec,
                  height: 1.45,
                ),
              ),
            ),
          );

    if (label == null) return body;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label!,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: gp.textTert,
          ),
        ),
        const SizedBox(height: 4),
        body,
      ],
    );
  }
}

/// A square's voice notes where its written note is read back (the journal
/// card, under [HabitNoteBlock]); see square_voice_notes.dart.
///
/// Folded to one line until tapped, because a square's recordings are a
/// read of their own and a month of entries should not cost a read per
/// entry just to scroll past. Playback only: naming and deleting stay in
/// the square's editor, where the recording was made.
///
/// Walled beyond the free history exactly as the written note is, with the
/// same card, and for the same reason the paywall lives in this file.
class SquareVoiceBlock extends ConsumerStatefulWidget {
  final String habitId;
  final DateTime day;
  final int count;

  const SquareVoiceBlock({
    super.key,
    required this.habitId,
    required this.day,
    required this.count,
  });

  @override
  ConsumerState<SquareVoiceBlock> createState() => _SquareVoiceBlockState();
}

class _SquareVoiceBlockState extends ConsumerState<SquareVoiceBlock> {
  List<VoiceNote>? _notes;
  bool _loading = false;

  Future<void> _open() async {
    if (_loading) return;
    HapticFeedback.selectionClick();
    setState(() => _loading = true);
    final uid = ref.read(authStateProvider).asData?.value?.uid;
    try {
      final notes = await ref
          .read(squareVoiceStoreProvider)
          .load(uid, squareVoiceKey(widget.habitId, widget.day));
      if (!mounted) return;
      setState(() {
        _notes = notes;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final walled = !canBrowseHistoryMonth(
      monthStart: DateTime(widget.day.year, widget.day.month),
      now: DateTime.now().effectiveDay,
      isPremium: ref.watch(premiumAccessProvider),
    );
    if (walled) return const _LockCard();

    final notes = _notes;
    if (notes == null) {
      return InkWell(
        // The web build has no audio player to hand these to (the voice
        // service works on files), so there the line says they exist and
        // stops there, rather than offering a play that cannot happen.
        onTap: kIsWeb ? null : _open,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: gp.surfaceHigh,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: gp.border, width: 0.5),
          ),
          child: Row(
            children: [
              Icon(Icons.mic_rounded, size: 16, color: gp.goldInk),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  s.voiceNotesTitle,
                  style: TextStyle(fontSize: 13, color: gp.textSec),
                ),
              ),
              if (_loading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 1.8),
                )
              else
                Text(
                  '${widget.count}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: gp.goldInk,
                  ),
                ),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < notes.length; i++) ...[
          if (i > 0) const SizedBox(height: 6),
          _VoicePlayRow(
            note: notes[i],
            name: notes[i].name.trim().isNotEmpty
                ? notes[i].name.trim()
                : s.voiceNoteDefaultName(i + 1),
          ),
        ],
      ],
    );
  }
}

/// One recording, play and pause only.
class _VoicePlayRow extends StatelessWidget {
  final VoiceNote note;
  final String name;

  const _VoicePlayRow({required this.note, required this.name});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final svc = VoiceNoteService.instance;
    final color = gp.goldInk;
    final seconds = note.durationSeconds;
    final length = '${(seconds ~/ 60).toString().padLeft(2, '0')}:'
        '${(seconds % 60).toString().padLeft(2, '0')}';
    return AnimatedBuilder(
      animation: Listenable.merge([svc.nowPlaying, svc.isPlaying]),
      builder: (context, _) {
        final playing =
            svc.nowPlaying.value?.noteId == note.id && svc.isPlaying.value;
        return Semantics(
          button: true,
          label: '${playing ? s.voiceNotePause : s.voiceNotePlay}, $name',
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              HapticFeedback.selectionClick();
              svc.togglePlayback(
                note.id,
                note.path,
                title: name,
                color: color,
                durationSeconds: note.durationSeconds,
                audioBase64: note.audioBase64,
              );
            },
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: gp.surfaceHigh,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: gp.border, width: 0.5),
              ),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      size: 16,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: gp.textPrimary),
                    ),
                  ),
                  Text(
                    length,
                    style: TextStyle(fontSize: 11, color: gp.textTert),
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

/// The editor's own lock card, so a withheld note looks the same wherever it
/// is withheld.
class _LockCard extends StatelessWidget {
  const _LockCard();

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    return InkWell(
        onTap: () => showHistoryDemoGate(context),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: GameColors.gold.withOpacity(gp.dark ? 0.10 : 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: GameColors.gold.withOpacity(0.35)),
          ),
          child: Row(
            children: [
              Icon(Icons.lock_rounded, size: 16, color: context.gp.goldInk),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  s.gridNoteLocked,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: gp.textSec,
                    height: 1.35,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: context.gp.goldInk,
              ),
            ],
          ),
        ),
      );
  }
}

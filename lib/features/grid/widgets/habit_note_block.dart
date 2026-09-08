import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/datetime_ext.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../../shared/widgets/history_demo_gate.dart';
import '../../premium/notifiers/premium_notifier.dart' show premiumAccessProvider;
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

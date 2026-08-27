import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../../shared/widgets/choice_chip_grid.dart';
import '../../auth/notifiers/auth_notifier.dart';
import '../notifiers/room_moderation.dart';
import '../../../shared/widgets/app_snackbar.dart';

/// The member-options sheet: report, and block.
///
/// One sheet rather than two entry points because the two actions belong
/// to the same moment — someone opens this because another member's row
/// bothered them, and which of the two they want is a detail. Reporting
/// offers blocking on the way out for the same reason.
///
/// Opened from the small overflow button on another member's leaderboard
/// row. Deliberately NOT a long-press on the row: the row's body is
/// already a tap target that opens the calendar, and a hidden gesture is
/// not a moderation affordance a reviewer (or an upset user) can find.
Future<void> showMemberOptions(
  BuildContext context, {
  required WidgetRef ref,
  required String roomCode,
  required String memberUid,
  required String memberName,
}) {
  HapticFeedback.selectionClick();
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _MemberOptionsSheet(
      parentRef: ref,
      roomCode: roomCode,
      memberUid: memberUid,
      memberName: memberName,
    ),
  );
}

class _MemberOptionsSheet extends ConsumerWidget {
  final WidgetRef parentRef;
  final String roomCode;
  final String memberUid;
  final String memberName;

  const _MemberOptionsSheet({
    required this.parentRef,
    required this.roomCode,
    required this.memberUid,
    required this.memberName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final blocked = ref.watch(blockedMembersProvider).contains(memberUid);

    return _SheetShell(
      title: s.roomMemberActions,
      children: [
        _ActionRow(
          icon: Icons.flag_outlined,
          label: s.roomReportAction,
          onTap: () async {
            Navigator.pop(context);
            await _showReportSheet(
              context,
              ref: parentRef,
              roomCode: roomCode,
              memberUid: memberUid,
              memberName: memberName,
            );
          },
        ),
        Divider(color: gp.divider, height: 1),
        _ActionRow(
          icon: blocked ? Icons.visibility_rounded : Icons.block_rounded,
          label: blocked ? s.roomUnblockAction : s.roomBlockAction,
          subtitle: blocked ? null : s.roomBlockExplain,
          destructive: !blocked,
          onTap: () async {
            final notifier = ref.read(blockedMembersProvider.notifier);
            if (blocked) {
              await notifier.unblock(memberUid);
            } else {
              await notifier.block(memberUid);
            }
            if (!context.mounted) return;
            Navigator.pop(context);
            _toast(
              context,
              blocked
                  ? s.roomUnblockedConfirm(memberName)
                  : s.roomBlockedConfirm(memberName),
            );
          },
        ),
      ],
    );
  }
}

Future<void> _showReportSheet(
  BuildContext context, {
  required WidgetRef ref,
  required String roomCode,
  required String memberUid,
  required String memberName,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ReportSheet(
      parentRef: ref,
      roomCode: roomCode,
      memberUid: memberUid,
      memberName: memberName,
    ),
  );
}

class _ReportSheet extends StatefulWidget {
  final WidgetRef parentRef;
  final String roomCode;
  final String memberUid;
  final String memberName;

  const _ReportSheet({
    required this.parentRef,
    required this.roomCode,
    required this.memberUid,
    required this.memberName,
  });

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  ReportReason _reason = ReportReason.inappropriateName;
  final _note = TextEditingController();
  bool _alsoBlock = true;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  String _label(S s, ReportReason r) => switch (r) {
        ReportReason.inappropriateName => s.roomReportReasonName,
        ReportReason.harassment => s.roomReportReasonHarassment,
        ReportReason.spam => s.roomReportReasonSpam,
        ReportReason.other => s.roomReportReasonOther,
      };

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);

    return _SheetShell(
      title: s.roomReportTitle(widget.memberName),
      subtitle: s.roomReportSubtitle,
      children: [
        // ChoiceChipGrid, the same control Add Habit and the reminder
        // picker use, rather than RadioListTile: two columns because the
        // reason labels are short phrases, and it keeps this sheet looking
        // like the rest of the app instead of like a settings screen.
        ChoiceChipGrid(
          columns: 2,
          items: [
            for (final r in ReportReason.values)
              PlainChoiceChip(
                selected: _reason == r,
                label: _label(s, r),
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _reason = r);
                },
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _note,
          maxLines: 3,
          maxLength: 500,
          style: TextStyle(fontSize: 13, color: gp.textPrimary),
          decoration: InputDecoration(
            hintText: s.roomReportNoteHint,
            hintStyle: TextStyle(fontSize: 13, color: gp.textTert),
            filled: true,
            fillColor: gp.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(GameSpacing.buttonRadius),
              borderSide: BorderSide(color: gp.border),
            ),
          ),
        ),
        CheckboxListTile(
          value: _alsoBlock,
          onChanged: (v) => setState(() => _alsoBlock = v ?? false),
          activeColor: GameColors.gold,
          contentPadding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(
            s.roomReportAlsoBlock,
            style: TextStyle(fontSize: 13, color: gp.textSec),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () async {
              // Confirmed to the reporter immediately rather than after the
              // write lands — see submitRoomReport's doc comment for why a
              // network failure must not read as a refusal.
              final messenger = ScaffoldMessenger.of(context);
              final text = s.roomReportThanks;
              Navigator.pop(context);
              if (_alsoBlock) {
                await widget.parentRef
                    .read(blockedMembersProvider.notifier)
                    .block(widget.memberUid);
              }
              await submitRoomReport(
                reporterUid: widget.parentRef
                        .read(authStateProvider)
                        .asData
                        ?.value
                        ?.uid ??
                    '',
                roomCode: widget.roomCode,
                reportedUid: widget.memberUid,
                reportedName: widget.memberName,
                reason: _reason,
                note: _note.text,
              );
              messenger.showOne(SnackBar(content: Text(text)));
            },
            child: Text(s.roomReportSubmit),
          ),
        ),
      ],
    );
  }
}

void _toast(BuildContext context, String message) =>
    ScaffoldMessenger.of(context).showOne(
      SnackBar(content: Text(message)),
    );

/// The app's standard inset sheet chassis, shared by both sheets here so
/// they read as one flow rather than two lookalikes.
class _SheetShell extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;
  const _SheetShell({
    required this.title,
    required this.children,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        decoration: BoxDecoration(
          color: gp.surfaceHigh,
          borderRadius: BorderRadius.circular(22),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: gp.border,
                    borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
                  ),
                ),
              ),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: gp.textPrimary,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: gp.textSec, height: 1.4),
                ),
              ],
              const SizedBox(height: 12),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final bool destructive;
  final VoidCallback onTap;
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final tint = destructive ? GameColors.error : gp.textPrimary;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: tint),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: tint,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: gp.textSec,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

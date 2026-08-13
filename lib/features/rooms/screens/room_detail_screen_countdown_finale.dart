part of 'room_detail_screen.dart';


/// One digit box in [_ScheduledLobbyCard]'s countdown — a zero-padded
/// number that pops with a quick scale+fade whenever it changes (mostly
/// every second, on the seconds box) — the one deliberate bit of "fun"
/// motion on this otherwise-static screen.
class _CountdownBox extends StatelessWidget {
  final int value;
  final String label;
  const _CountdownBox({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final text = value.toString().padLeft(2, '0');
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 50,
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: GameColors.gold.withOpacity(gp.dark ? 0.16 : 0.12),
            borderRadius: BorderRadius.circular(GameSpacing.buttonRadius),
            border: Border.all(color: GameColors.gold.withOpacity(0.35)),
          ),
          child: AnimatedSwitcher(
            duration: GameMotion.standard,
            transitionBuilder: (child, anim) => ScaleTransition(
              scale: anim,
              child: FadeTransition(opacity: anim, child: child),
            ),
            child: Text(
              text,
              key: ValueKey(text),
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: GameColors.gold,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
              fontSize: 9.5, fontWeight: FontWeight.w700, color: gp.textTert),
        ),
      ],
    );
  }
}

/// "Today · 8:00 PM" / "Tomorrow · 8:00 PM" / "Tue, Jul 21 · 8:00 PM" — the
/// absolute-time caption under the countdown digits, so it always has a
/// concrete anchor next to it instead of making everyone do the math
/// themselves. Deliberately not a reuse of matrix/widgets/reminder_picker.
/// dart's formatReminderMoment (same three-tier shape) even though it's a
/// near-identical need — that helper is marked @visibleForTesting for
/// Matrix's own reminder copy specifically, and three duplicated lines
/// here keeps this screen free to word a room's start moment differently
/// later without touching an unrelated feature's test-pinned helper.
String _formatScheduledMoment(DateTime dt, bool isAr) {
  final now = DateTime.now();
  final locale = isAr ? 'ar' : 'en';
  final time = DateFormat('h:mm a', locale).format(dt);
  if (dt.isSameDayAs(now)) return isAr ? 'اليوم · $time' : 'Today · $time';
  if (dt.isSameDayAs(now.add(const Duration(days: 1)))) {
    return isAr ? 'غدًا · $time' : 'Tomorrow · $time';
  }
  final date = DateFormat('EEE, MMM d', locale).format(dt);
  return '$date · $time';
}

/// Leader-only sheet for picking — or re-picking — this lobby's start
/// moment. Offered from both _EmptyLobbyCard's first-ever pick and
/// _ScheduledLobbyCard's "Change time", so there's exactly one place this
/// decision gets made. Shape mirrors _ExtendRoomSheet further down (quick
/// chips + one custom escape hatch) on purpose — same kind of leader-only,
/// lobby-adjacent scheduling decision, so it should feel like the same
/// control, not a new one to learn. Pops the picked moment, or null if
/// dismissed without picking (swiped away, or backed out of the custom
/// date/time dialogs) — _LobbyCardState._openScheduleSheet already treats
/// null as "nothing changed."
class _ScheduleStartSheet extends StatelessWidget {
  const _ScheduleStartSheet();

  static DateTime _tomorrowAt(int hour) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day + 1, hour);
  }

  Future<void> _pickCustom(BuildContext context) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
    );
    if (date == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
        child: child!,
      ),
    );
    if (time == null || !context.mounted) return;
    final picked =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (!picked.isAfter(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.of(context).roomScheduleNotFuture)),
      );
      return;
    }
    if (context.mounted) Navigator.pop(context, picked);
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        decoration: BoxDecoration(
          color: gp.surfaceHigh,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
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
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: gp.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(s.roomScheduleTitle,
                style: TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w800, color: gp.textPrimary)),
            const SizedBox(height: 6),
            Text(s.roomScheduleBody,
                style: TextStyle(fontSize: 12.5, color: gp.textSec, height: 1.35)),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ExtendOptionChip(
                  label: s.roomScheduleQuick1Hour,
                  onTap: () => Navigator.pop(
                      context, DateTime.now().add(const Duration(hours: 1))),
                ),
                _ExtendOptionChip(
                  label: s.roomScheduleTomorrowMorning,
                  onTap: () => Navigator.pop(context, _tomorrowAt(8)),
                ),
                _ExtendOptionChip(
                  label: s.roomScheduleTomorrowEvening,
                  onTap: () => Navigator.pop(context, _tomorrowAt(20)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => _pickCustom(context),
              icon: const Icon(Icons.calendar_month_rounded, size: 16),
              label: Text(s.roomScheduleCustomAction),
              style:
                  OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Between Start and the first counted day: one gold line of anticipation,
/// including the 2x promise so tomorrow starts with intent.
class _CountdownCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: GameColors.gold.withOpacity(gp.dark ? 0.10 : 0.08),
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        border: Border.all(color: GameColors.gold.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.hourglass_top_rounded,
              size: 20, color: GameColors.gold),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              s.roomStartsTomorrowBanner,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: gp.textPrimary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The ending the room deserves: a real podium for the top three (center
/// column tallest, crown on first), one confetti burst on first build, and
/// a warm closing line. Ties and small rooms degrade gracefully — with 2
/// members there are 2 podium spots, with 1 there's just the winner.
class _FinaleCard extends ConsumerStatefulWidget {
  final List<RoomParticipant> sorted;
  final RoomModel room;
  final RoomParticipant? mine;
  const _FinaleCard({
    required this.sorted,
    required this.room,
    required this.mine,
  });

  @override
  ConsumerState<_FinaleCard> createState() => _FinaleCardState();
}

class _FinaleCardState extends ConsumerState<_FinaleCard> {
  bool _claiming = false;
  @override
  void initState() {
    super.initState();
    // One burst per screen open — a finale, not a fireworks loop.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final size = MediaQuery.of(context).size;
      showVictoryBurst(context, Offset(size.width / 2, size.height * 0.3));
    });
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final top = widget.sorted.take(3).toList();
    // Visual order: 2nd, 1st, 3rd — the classic podium silhouette. RTL
    // flips the Row automatically, which keeps 1st in the middle either way.
    final order = [
      if (top.length > 1) (top[1], 2),
      if (top.isNotEmpty) (top[0], 1),
      if (top.length > 2) (top[2], 3),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        border: Border.all(color: GameColors.gold.withOpacity(0.45)),
      ),
      child: Column(
        children: [
          Text(
            s.roomEndedTitle,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: gp.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            s.roomEndedBody,
            style: TextStyle(fontSize: 12, color: gp.textSec),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final (p, rank) in order)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: _PodiumColumn(
                    participant: p,
                    rank: rank,
                    room: widget.room,
                  ),
                ),
            ],
          ),
          ..._prizeSection(context),
        ],
      ),
    );
  }

  /// The viewer's own prize, if they finished on the podium and haven't
  /// taken it yet. Nothing at all for everyone else — which is the point of
  /// a podium.
  List<Widget> _prizeSection(BuildContext context) {
    final mine = widget.mine;
    if (mine == null) return const [];
    final rank =
        widget.sorted.indexWhere((p) => p.uid == mine.uid) + 1; // 0 -> not found
    if (rank < 1) return const [];
    final prize = RoomsController.podiumPrizeFor(rank);
    if (prize == null) return const [];

    final s = S.of(context);
    final gp = context.gp;
    if (mine.podiumBonusClaimed) {
      return [
        const SizedBox(height: 14),
        Text(
          s.roomPrizeClaimed,
          style: TextStyle(fontSize: 12.5, color: gp.textSec),
        ),
      ];
    }
    return [
      const SizedBox(height: 14),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          // Locked out the instant it's tapped. The write and the stream
          // round-trip both take a moment, and this button hands out real
          // currency — see RoomsController.claimPodiumBonus, whose
          // transaction is the actual guarantee; this is just so the button
          // doesn't look tappable while that resolves.
          onPressed: _claiming
              ? null
              : () async {
                  HapticFeedback.mediumImpact();
                  setState(() => _claiming = true);
                  await ref
                      .read(roomsControllerProvider)
                      .claimPodiumBonus(widget.room, mine, rank: rank);
                  if (mounted) setState(() => _claiming = false);
                },
          icon: const Icon(Icons.card_giftcard_rounded, size: 18),
          label: Text(s.roomClaimPrize(prize.xp, prize.gold)),
          style: FilledButton.styleFrom(
            backgroundColor: GameColors.gold,
            foregroundColor: GameColors.onGold,
            minimumSize: const Size.fromHeight(46),
          ),
        ),
      ),
    ];
  }
}

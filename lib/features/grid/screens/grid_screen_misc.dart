part of 'grid_screen.dart';

// ─── Loading skeleton ─────────────────────────────────────────────────────────

class _GridSkeleton extends StatelessWidget {
  const _GridSkeleton();

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Container(
      height: 220,
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        border: Border.all(color: gp.border, width: 0.5),
      ),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: GameColors.emerald),
        ),
      ),
    );
  }
}

/// The board while its week is still on its way from the server.
///
/// It draws the squares this device last saw (WeeklyGridState.preview), so a
/// cold start shows the person's week at once instead of a spinner. It takes
/// no taps until the real week lands: a square's tap works out its next
/// colour, its XP and its streak from the square as the store has it, and
/// the device's copy can be behind (a square marked on the web a minute
/// ago). A tap in that moment says so, in the words the board already uses
/// for a tap that arrives before the account's numbers, rather than doing
/// nothing. Scrolling is untouched; only taps and long presses are held.
class _BoardUntilLoaded extends StatelessWidget {
  final bool loading;
  final Widget child;
  const _BoardUntilLoaded({required this.loading, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!loading) return child;
    void notYet() {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 2),
            content: Text(S.of(context).squareNotReadyYet),
          ),
        );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: notYet,
      onLongPress: notYet,
      child: AbsorbPointer(child: child),
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

/// The one line habits paused on an earlier day get on this screen — a
/// quiet count plus a chevron, opening the Add Habit hub whose paused
/// section holds the actual resume/delete rows. Kept in the paused
/// section's own tertiary voice (it is a record, not a demand), and a row
/// rather than a board section because these habits deliberately have no
/// squares to show here.
class _PausedElsewhereRow extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  const _PausedElsewhereRow({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: gp.border, width: 0.5),
          ),
          child: Row(
            children: [
              Icon(Icons.pause_circle_outline_rounded,
                  size: 16, color: gp.textTert),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  s.pausedElsewhereRow(count),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: gp.textSec,
                  ),
                ),
              ),
              // s.isAr, not Directionality: intl is imported by this
              // library and its TextDirection shadows dart:ui's (same
              // collision insights_screen.dart documents).
              Icon(
                s.isAr
                    ? Icons.chevron_left_rounded
                    : Icons.chevron_right_rounded,
                size: 18,
                color: gp.textTert,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Quiet label row above each of the Grid's two boards (build vs quit) —
/// small icon, uppercase-style label, and a count chip, deliberately far
/// lighter than a card header so the boards themselves stay the loudest
/// thing on screen. Only rendered when both boards exist; see the build
/// method's split comment.
class _GridSectionHeader extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final int count;

  const _GridSectionHeader({
    required this.icon,
    required this.color,
    required this.label,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    // Letter-spacing zeroed for Arabic, same as HabitCard's pills — spaced
    // Arabic glyphs read broken, not emphasized.
    final isAr = S.of(context).isAr;
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 8, start: 2),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: isAr ? 0 : 0.6,
              color: gp.textSec,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Container(height: 0.5, color: gp.border)),
        ],
      ),
    );
  }
}

class _GridEmptyState extends ConsumerWidget {
  // Only set by GridScreen when App Guide's "Add a habit" lesson is active
  // and the board is empty (no FAB to circle in that state — see
  // GridScreen's own floatingActionButton, which is null until a habit
  // exists) — the same GlobalKey the FAB would otherwise carry, so
  // CoachMarkOverlay always has exactly one live target regardless of
  // which of the two mutually-exclusive "add a habit" buttons is mounted.
  final GlobalKey? addButtonKey;
  const _GridEmptyState({this.addButtonKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The sprout with its pencil, where an icon in a circle used to
            // be. This is the first real screen a brand-new account lands
            // on, which makes it the one place a character earns the most.
            // Decorative to screen readers: the title below says it all.
            const Sprout(pose: SproutPose.pencil, height: 170),
            const SizedBox(height: 20),
            Text(
              s.gridEmptyTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: gp.textPrimary,
              ),
            ).animate(delay: 150.ms).fadeIn().slideY(begin: 0.2),
            const SizedBox(height: 8),
            Text(
              s.gridEmptyDesc,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: gp.textSec, height: 1.4),
            ).animate(delay: 220.ms).fadeIn(),
            const SizedBox(height: 28),
            SizedBox(
              key: addButtonKey,
              width: 260,
              child: FilledButton.icon(
                onPressed: () =>
                    showAddHabitHub(context, ref, initialTab: HubTab.addGoal),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(s.addHabit),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ).animate(delay: 300.ms).fadeIn().slideY(begin: 0.2),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: () =>
                  showAddHabitHub(context, ref, initialTab: HubTab.plans),
              icon: const Icon(Icons.auto_awesome_rounded, size: 16),
              label: Text(s.browsePlans),
            ).animate(delay: 380.ms).fadeIn(),
          ],
        ),
      ),
    );
  }
}

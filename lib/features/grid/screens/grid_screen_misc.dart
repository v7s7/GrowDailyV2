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

// ─── Empty state ──────────────────────────────────────────────────────────────

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
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: GameColors.emerald.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.grid_view_rounded,
                  size: 36, color: GameColors.emerald),
            )
                .animate()
                .scale(curve: Curves.elasticOut, duration: 700.ms)
                .fadeIn(duration: 300.ms),
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

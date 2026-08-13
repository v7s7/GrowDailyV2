part of 'quadrant_card.dart';


// ─── Expanded (near-fullscreen) quadrant view ──────────────────────────────

/// Pushed when a quadrant's header — or its new expand icon — is tapped
/// (see MatrixScreen._openQuadrantExpanded). The same task-list rendering
/// [_AnimatedTaskStack]/[_EmptyQuadrantBody] already do, just given the
/// whole screen instead of one cell of a cramped 2x2 grid: titles that
/// would truncate or wrap awkwardly at half-width get real room, and every
/// row's tap targets end up noticeably larger — directly the "read
/// clearly, see the buttons clearly" ask this screen exists for.
///
/// A ConsumerWidget that watches [matrixProvider] itself, rather than
/// receiving a fixed task list via constructor the way [QuadrantCard]
/// does — completing a task, adding one, or moving one out of this
/// quadrant while this screen is open all show up immediately instead of
/// leaving it stuck on a stale snapshot from the moment it was opened.
///
/// Deliberately doesn't support multi-select: MatrixScreen's selection
/// state lives on the previous, now-offstage route with no live link back
/// to this one, so trying to reflect it here would mean a selection UI
/// that can silently drift out of sync. Selecting/bulk-deleting stays a
/// compact-grid-only action; this screen is about reading clearly and
/// acting on one task at a time.
class QuadrantExpandedScreen extends ConsumerWidget {
  final MatrixQuadrant quadrant;
  // Same Today/Fav/All + carried-over lens MatrixScreen's own body is
  // currently showing (see MatrixScreen._isVisibleUnderFilter) — captured
  // once at the moment this screen is opened. It can't go stale the way a
  // task *list* snapshot could: the toggle that would change it lives on
  // the covered route, entirely unreachable while this one is on top, so
  // there's no way for it to change out from under this screen.
  final bool Function(MatrixTask task) isVisible;
  final void Function(String id) onToggle;
  final void Function(String id) onDelete;
  final void Function(String id, MatrixQuadrant q) onMove;
  final void Function(String id, MatrixQuadrant q, String? beforeId)
      onReorder;
  final void Function(String id) onToggleFav;
  final VoidCallback onAddTapped;
  final void Function(MatrixTask task) onOpenDetails;

  const QuadrantExpandedScreen({
    super.key,
    required this.quadrant,
    required this.isVisible,
    required this.onToggle,
    required this.onDelete,
    required this.onMove,
    required this.onReorder,
    required this.onToggleFav,
    required this.onAddTapped,
    required this.onOpenDetails,
  });

  // Unlike QuadrantCard (a plain StatelessWidget that receives title/color
  // as resolved props from its parent), this screen is already a
  // ConsumerWidget — so it watches matrixProvider directly instead (see
  // build() below: `matrixState.colorFor`/`titleFor`). That matters here
  // specifically: the Edit Quadrant sheet is reachable from this exact
  // screen's own header (long-press, wired below), and a static
  // constructor prop wouldn't pick up a just-saved rename/recolor without
  // leaving and reopening this screen. ref.watch makes that update show
  // immediately, same frame the sheet closes.

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final isAr = s.isAr;
    final matrixState = ref.watch(matrixProvider);
    final color = matrixState.colorFor(quadrant);
    final title = matrixState.titleFor(quadrant, isAr);
    // Same active-first-then-done split QuadrantCard.build() uses (see its
    // `ordered` local) — sorting the combined list by `order` alone would
    // let a done task's old (often lower) order value put it above a
    // still-pending one, so the two views could show this same quadrant in
    // two different sequences.
    final quadrantTasks =
        matrixState.tasks.where((t) => t.quadrant == quadrant && isVisible(t));
    final active = quadrantTasks.where((t) => !t.isDone).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    final done = quadrantTasks.where((t) => t.isDone).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    final tasks = [...active, ...done];

    // Long-press on the title below still works exactly as before — this
    // closure also backs the new pen icon in the header, so this
    // popped-up/maximized page has a second, more discoverable way to
    // reach the same rename+recolor sheet without removing the long-press.
    void openEditSheet() => showEditQuadrantSheet(
          context,
          ref,
          quadrant: quadrant,
          currentTitle: title,
          currentColorHex: matrixState.quadrantColors[quadrant.name],
        );

    return Scaffold(
      backgroundColor: gp.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(4, 6, 16, 6),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: gp.textSec),
                    tooltip: s.matrixCollapseQuadrant,
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      Navigator.pop(context);
                    },
                  ),
                  Container(
                    width: 9,
                    height: 9,
                    margin: const EdgeInsetsDirectional.only(end: 8),
                    decoration:
                        BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  Expanded(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(GameSpacing.chipRadius),
                        // Long-press to rename/recolor — same gesture as
                        // the compact card's header (see QuadrantCard).
                        // The pen icon in this header (below) opens the
                        // same sheet on a plain tap, for discoverability.
                        onLongPress: openEditSheet,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                title,
                                style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                    color: gp.textPrimary,
                                    letterSpacing: isAr ? 0 : -0.2),
                              ),
                              Text(
                                quadrant.localSubtitle(isAr),
                                style: TextStyle(
                                    fontSize: 11.5, color: gp.textSec),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Only shown here on the expanded/maximized page — the
                  // compact grid card keeps long-press as its sole entry
                  // point, unchanged. This is purely an added, more
                  // discoverable shortcut to the exact same sheet.
                  IconButton(
                    icon: Icon(Icons.edit_rounded, color: gp.textSec),
                    tooltip: s.matrixEditQuadrantTitle,
                    onPressed: openEditSheet,
                  ),
                  Material(
                    color: color.withOpacity(0.14),
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: onAddTapped,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child:
                            Icon(Icons.add_rounded, size: 20, color: color),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: tasks.isEmpty
                    ? _EmptyQuadrantBody(color: color, onTap: onAddTapped)
                    : _AnimatedTaskStack(
                        quadrant: quadrant,
                        tasks: tasks,
                        accentColor: color,
                        onToggle: onToggle,
                        onDelete: onDelete,
                        selectionMode: false,
                        selectedIds: const {},
                        onSelectionToggle: (_) {},
                        onSelectionStart: (_) {},
                        onMove: onMove,
                        onReorder: onReorder,
                        onToggleFav: onToggleFav,
                        onAddTapped: onAddTapped,
                        onOpenDetails: onOpenDetails,
                        expanded: true,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

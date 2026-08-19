part of 'quadrant_card.dart';


// ─── Empty quadrant body ──────────────────────────────────────────────────────

/// The whole square is the tap target — not just the tiny + icon in the
/// header — so a blank quadrant never means hunting for a small icon.
class _EmptyQuadrantBody extends StatelessWidget {
  final Color color;
  final VoidCallback onTap;

  const _EmptyQuadrantBody({
    super.key,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.add_rounded, size: 16, color: color),
              )
                  .animate(onPlay: (c) => c.repeat(reverse: true))
                  .scaleXY(
                      begin: 0.9,
                      end: 1.06,
                      duration: 1100.ms,
                      curve: Curves.easeInOut),
              const SizedBox(height: 4),
              Text(s.matrixTapToAdd,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 10,
                      color: gp.textTert,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Add-another row (populated quadrants) ────────────────────────────────────

/// A persistent, generously-sized "add" affordance at the end of a
/// populated quadrant's list, so adding a second or third goal never means
/// hunting for the small + icon back up in the header.
class _AddAnotherRow extends StatelessWidget {
  final Color color;
  final VoidCallback onTap;
  const _AddAnotherRow({required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Text(
            s.matrixAddAnother,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: color),
          ),
        ),
      ),
    );
  }
}

// ─── Task Tile ───────────────────────────────────────────────────────────────

class _TaskTile extends StatefulWidget {
  final MatrixTask task;
  // True only inside QuadrantExpandedScreen — swaps the title to
  // _expandedTitleStyle (bigger, bolder) instead of the compact grid's
  // small inline style. See _AnimatedTaskStack.expanded's doc comment.
  final bool expanded;
  final Color accentColor;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onSelectionToggle;
  final VoidCallback onSelectionStart;
  final void Function(MatrixQuadrant) onMove;
  final VoidCallback onToggleFav;
  // Bubble a drag's start/end up to the enclosing list, which uses them to
  // collapse this row out of the way while it's the one being dragged
  // (see _AnimatedTaskStackState._draggingId).
  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;
  // Pencil icon — opens TaskDetailSheet for this row's task.
  final VoidCallback onOpenDetails;

  const _TaskTile({
    super.key,
    required this.task,
    required this.expanded,
    required this.accentColor,
    required this.onToggle,
    required this.onDelete,
    required this.selectionMode,
    required this.selected,
    required this.onSelectionToggle,
    required this.onSelectionStart,
    required this.onMove,
    required this.onToggleFav,
    this.onDragStart,
    this.onDragEnd,
    required this.onOpenDetails,
  });

  @override
  State<_TaskTile> createState() => _TaskTileState();
}

class _TaskTileState extends State<_TaskTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spring;
  late final Animation<double> _scale;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _spring = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 380));
    _scale = TweenSequence<double>([
      TweenSequenceItem(
          tween: Tween(begin: 1.0, end: 1.35)
              .chain(CurveTween(curve: Curves.easeOut)),
          weight: 30),
      TweenSequenceItem(
          tween: Tween(begin: 1.35, end: 0.88)
              .chain(CurveTween(curve: Curves.easeIn)),
          weight: 20),
      TweenSequenceItem(
          tween: Tween(begin: 0.88, end: 1.0)
              .chain(CurveTween(curve: Curves.elasticOut)),
          weight: 50),
    ]).animate(_spring);
  }

  @override
  void dispose() {
    _spring.dispose();
    // Playback is intentionally NOT stopped here anymore — the floating
    // global player (docked above GameNavBar) is designed to survive
    // exactly this: a tile going away, a quadrant re-filtering, the whole
    // Matrix screen being left. See VoiceNoteService.stopPlayback's doc
    // comment.
    super.dispose();
  }

  void _handleTap() {
    if (widget.selectionMode) {
      widget.onSelectionToggle();
      return;
    }
    _spring.forward(from: 0.0);
    // The reward is paid exactly once per task (MatrixTask.rewarded), so
    // announce it exactly once too — recompleting a toggled-off task shows
    // nothing, matching what the economy actually does.
    if (!widget.task.isDone && !widget.task.rewarded) {
      showTaskRewardFloat(context);
    }
    widget.onToggle();
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    return Dismissible(
      key: ValueKey('dismiss-${widget.task.id}'),
      direction: widget.selectionMode ? DismissDirection.none : DismissDirection.endToStart,
      onDismissed: (_) => widget.onDelete(),
      // Directional, not physical: endToStart reveals the START side of
      // the background in RTL, so an icon pinned at physical right stayed
      // hidden under the sliding tile and Arabic users swiped over an
      // anonymous red strip. centerEnd renders identically in LTR.
      background: Container(
        alignment: AlignmentDirectional.centerEnd,
        padding: const EdgeInsetsDirectional.only(end: 14),
        decoration: BoxDecoration(
          color: GameColors.error.withOpacity(0.12),
          borderRadius: BorderRadius.circular(GameSpacing.chipRadius),
        ),
        child: const Icon(Icons.delete_outline_rounded,
            color: GameColors.error, size: 16),
      ),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) {
          setState(() => _pressed = false);
          _handleTap();
        },
        onTapCancel: () => setState(() => _pressed = false),
        onLongPress: () {
          HapticFeedback.mediumImpact();
          widget.onSelectionStart();
        },
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          color: _pressed ? gp.surfaceHL.withOpacity(0.7) : Colors.transparent,
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  AnimatedBuilder(
                    animation: _scale,
                    builder: (_, __) => Transform.scale(
                      scale: _spring.isAnimating ? _scale.value : 1.0,
                      child: AnimatedContainer(
                        duration: GameMotion.standard,
                        curve: Curves.easeOutCubic,
                        width: 17,
                        height: 17,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: widget.selectionMode
                              ? (widget.selected
                                  ? GameColors.gold
                                  : Colors.transparent)
                              : widget.task.isDone
                                  ? widget.accentColor
                                  : Colors.transparent,
                          border: Border.all(
                            color: widget.selectionMode
                                ? (widget.selected
                                    ? GameColors.gold
                                    : gp.border)
                                : widget.task.isDone
                                    ? widget.accentColor
                                    : gp.border,
                            width: 1.5,
                          ),
                          boxShadow: widget.selected || widget.task.isDone
                              ? [
                                  BoxShadow(
                                    color: (widget.selected
                                            ? GameColors.gold
                                            : widget.accentColor)
                                        .withOpacity(0.35),
                                    blurRadius: 6,
                                  )
                                ]
                              : null,
                        ),
                        child: widget.selectionMode
                            ? (widget.selected
                                ? const Icon(Icons.check_rounded,
                                    size: 10, color: Colors.black)
                                : null)
                            : widget.task.isDone
                                ? const Icon(Icons.check_rounded,
                                    size: 10, color: Colors.black)
                                : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: AnimatedDefaultTextStyle(
                      duration: GameMotion.standard,
                      style: (widget.expanded
                              ? _expandedTitleStyle
                              : const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  height: 1.35,
                                ))
                          .copyWith(
                        color:
                            widget.task.isDone ? gp.textTert : gp.textPrimary,
                        decoration: widget.task.isDone
                            ? TextDecoration.lineThrough
                            : TextDecoration.none,
                        decorationColor: gp.textTert,
                      ),
                      // No maxLines/overflow cap — the title wraps to as
                      // many lines as it needs (see _rowHeightFor, which
                      // reserves exactly that much space) instead of being
                      // clipped with an ellipsis.
                      child: Text(widget.task.title),
                    ),
                  ),
                ],
              ),
              // Row 2: everything that isn't the title gets its own strip
              // underneath instead of squeezing into the title's row.
              // Cramming checkbox+title+4-icons into one Row caused two
              // problems: the title's Expanded routinely had under ~40px
              // of real width left on a narrow, two-column quadrant card
              // (forcing an unreadable mid-word wrap), and each icon's tap
              // target was squeezed to a ~32x26 box — small enough that a
              // slightly-off tap missed it and fell through to the row's
              // own tap-to-complete instead. Giving the title a whole row
              // to itself fixes the first; giving these icons their own
              // row — with room for a real 34x34 tap circle each, matching
              // ActionRow's precedent elsewhere in the app — fixes the
              // second. Kept in sync with
              // _AnimatedTaskStackState._rowHeightFor, which reserves
              // exactly this much extra height whenever this row renders.
              if (!widget.selectionMode) ...[
                const SizedBox(height: 4),
                // Every icon gets an equal Expanded share of the row's
                // *full* width (33% each for 3, 25% each for 4 with a
                // voice note) instead of a fixed-width circle clustered to
                // one side — the tap target is the whole cell, not just
                // the small circle drawn in its middle, so there's far
                // more margin for error than before and the row actually
                // uses the space it was given instead of leaving most of
                // it empty.
                Row(
                  children: [
                    if (widget.task.voiceNotes.isNotEmpty) ...[
                      Expanded(
                        child: _VoiceNoteIndicator(
                          notes: widget.task.voiceNotes,
                          color: widget.accentColor,
                          onOpenDetails: widget.onOpenDetails,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    // Order is details → star → move, and it is deliberate.
                    // Laid out in a Row, so it mirrors with the language: the
                    // move control lands on the RIGHT in English and on the
                    // LEFT in Arabic, which is the conventional side for a
                    // reorder affordance in each. It used to be star → move →
                    // details, burying the one control nobody could guess in
                    // the middle of two they could.
                    Expanded(
                      child: _TileIconButton(
                        onTap: widget.onOpenDetails,
                        icon: Icons.info_outline_rounded,
                        iconColor: gp.textTert,
                        label: s.taskDetailsAction,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Flags this task as a favorite — a plain, sticky
                    // bool, not a due date, so it's one tap and never
                    // opens a picker, and it never expires on its own.
                    Expanded(
                      child: _TileIconButton(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          widget.onToggleFav();
                        },
                        icon: widget.task.isFav
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        iconColor: widget.task.isFav
                            ? GameColors.gold
                            : gp.textTert,
                        label: widget.task.isFav
                            ? s.taskUnfavAction
                            : s.taskFavAction,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Dragging is scoped to this small handle rather than
                    // the whole tile so it never fights the row's own
                    // long-press (which starts multi-select) or its
                    // swipe-to-delete.
                    Expanded(
                      child: LongPressDraggable<String>(
                        data: widget.task.id,
                        // Default long-press-to-drag takes 500ms, which
                        // reads as sluggish for something you want to
                        // reorder quickly and often — a third of that is
                        // still deliberate enough to not fire on an
                        // ordinary tap.
                        delay: const Duration(milliseconds: 150),
                        onDragStarted: () {
                          HapticFeedback.mediumImpact();
                          widget.onDragStart?.call();
                        },
                        onDragEnd: (_) => widget.onDragEnd?.call(),
                        feedback: Material(
                          color: Colors.transparent,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 220),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: gp.surfaceHigh,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: widget.accentColor, width: 1.5),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.18),
                                    blurRadius: 16,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Text(widget.task.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: gp.textPrimary)),
                            ),
                          ),
                        ),
                        childWhenDragging: Center(
                          child: Icon(Icons.drag_indicator_rounded,
                              size: 18,
                              color: gp.textTert.withOpacity(0.25)),
                        ),
                        // Two ways in, on purpose. Long-press starts the
                        // drag (above); a plain tap opens the move sheet.
                        //
                        // This tap used to be an empty closure — it existed
                        // only to absorb the touch, because without a
                        // recognizer of its own it fell through to the row's
                        // tap-to-complete and grazing the handle silently
                        // checked the task off. That left the handle visible,
                        // obviously pressable, and doing nothing: people
                        // found it, tapped it, and concluded the quadrants
                        // simply weren't connected. Press-and-hold-then-drag
                        // was advertised by nothing at all.
                        // open_with, not drag_indicator. The six dots are a
                        // grab handle and say exactly one thing: "hold and
                        // drag me". That is the gesture a new user does not
                        // discover — and it hid the fact that a plain TAP
                        // opens the move sheet, which is the easy way to do
                        // the same job. Four arrows read as "move this",
                        // which is true of both gestures rather than only the
                        // hard one. The name in the tooltip finishes the job.
                        child: _TileIconButton(
                          onTap: () => showMoveTaskSheet(
                            context,
                            widget.task,
                            widget.onMove,
                          ),
                          icon: Icons.open_with_rounded,
                          iconColor: gp.textTert,
                          label: s.taskMoveAction,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // Delete/Move-to-quadrant used to live in a "..." menu opened from here
  // (_showTaskActions) — now part of TaskDetailSheet instead, opened via
  // the pencil icon above, so this row only ever carries one icon for
  // "more about this task" instead of two.
}

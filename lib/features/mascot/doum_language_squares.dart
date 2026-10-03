part of 'doum_language_look.dart';

/// How the language squares' two Doums first appear.
enum DoumSquaresArrival {
  /// Not yet: the launch curtain is still over the screen, or flying its
  /// Doum here. The squares are drawn without him.
  waiting,

  /// Both pop up, each saying hello in his own language.
  pop,

  /// The curtain's Doum has landed in the square of the app's language as
  /// the everyday Doum: a breath, and he turns round into that language's
  /// look. The other square's Doum pops up beside him meanwhile.
  landed,
}

/// The language choice as two squares side by side, English on the left
/// and العربية on the right, each with Doum dressed for it: the suit and the
/// thobe (Aziz, 2026-10-02: "two squares, the arabic and english, right and
/// left ... so the poses appear").
///
/// Both looks are always on screen. The single Doum who turned round from
/// one look into the other (DoumLanguageLook's turn) showed one at a time,
/// and the Settings sheet closed itself as soon as he had turned, so the
/// look just left was never seen beside the one just picked.
///
/// Picking a square lights it at once and changes the language behind a
/// short fade of the screen's words (the controller's
/// [DoumLookController.wordsVisible], the same fade the turn used, so the
/// layout's flip between right-to-left and left-to-right is never seen),
/// and that square's Doum hops onto his greeting: a hand on his chest in the
/// thobe, a wave in the suit, with his «هلا» or "Hi". Picking the square
/// already chosen only greets. Nothing closes: the squares stay as they are.
///
/// The pair keeps one physical order whatever the app's language, English
/// left and Arabic right, for the reason the old switch gave: it is a fixed
/// pair of objects, not a sentence, and a pair that mirrors itself the
/// moment it is tapped jumps under the finger. Each name is written in its
/// own script with its own direction, never a flag and never the word for
/// the other language, so someone who opened the app in a language they
/// cannot read can still find theirs.
class DoumLanguageSquares extends ConsumerStatefulWidget {
  const DoumLanguageSquares({
    super.key,
    required this.height,
    required this.doumHeight,
    this.controller,
    this.enabled = true,
    this.arrival = DoumSquaresArrival.pop,
    this.standKey,
    this.gap = 12,
    this.maxSquareWidth = 168,
  });

  /// Each square's height. The width shares what is left with the other
  /// square, up to [maxSquareWidth].
  final double height;

  /// Doum's reference height in each square (DoumLanguageLook.height).
  final double doumHeight;

  /// The screen's: its words fade out and back in around the change.
  final DoumLookController? controller;

  /// False while the screen is busy (a sign-in in flight): the squares take
  /// no tap, and the one not chosen dims to say so.
  final bool enabled;

  final DoumSquaresArrival arrival;

  /// Put on Doum's box in the square of the language live when the squares
  /// were first built, for the launch curtain to fly its Doum onto
  /// (LaunchDoumHandoff). That square never moves, so neither does the key.
  final GlobalKey? standKey;

  final double gap;
  final double maxSquareWidth;

  @override
  ConsumerState<DoumLanguageSquares> createState() =>
      _DoumLanguageSquaresState();
}

class _DoumLanguageSquaresState extends ConsumerState<DoumLanguageSquares> {
  /// How long the words take to fade out before the language changes: the
  /// fade's own duration on the screens that use it (120 ms), and a frame.
  static const _changeAfter = Duration(milliseconds: 140);

  final _suit = DoumLookController();
  final _thobe = DoumLookController();

  /// The language live when first built: the square the curtain's Doum
  /// lands in.
  late final String _standCode;

  /// The square tapped, until the language has changed to it.
  String? _pending;

  /// The language a tap is changing to, until it is committed.
  String? _toCommit;
  Timer? _change;
  Timer? _dress;
  Timer? _giveUp;
  ProviderContainer? _container;
  Future<void> Function(ProviderContainer, Locale)? _commitFn;

  DoumLookController _doumFor(String code) => code == 'ar' ? _thobe : _suit;

  @override
  void initState() {
    super.initState();
    _standCode = ref.read(localeProvider).languageCode;
    if (widget.arrival == DoumSquaresArrival.landed) _dressSoon();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _container = ProviderScope.containerOf(context, listen: false);
    _commitFn = ref.read(doumLocaleCommitProvider);
  }

  @override
  void didUpdateWidget(covariant DoumLanguageSquares old) {
    super.didUpdateWidget(old);
    if (old.arrival != DoumSquaresArrival.landed &&
        widget.arrival == DoumSquaresArrival.landed) {
      _dressSoon();
    }
  }

  /// The landed Doum stands a breath as the everyday Doum, in the very spot
  /// the curtain's was last drawn, then turns round into his look.
  void _dressSoon() {
    _dress?.cancel();
    _dress = Timer(const Duration(milliseconds: 300), () {
      if (mounted) _doumFor(_standCode).arriveDressed();
    });
  }

  void _pick(String code) {
    if (!widget.enabled) return;
    final live = ref.read(localeProvider).languageCode;
    if (code == (_pending ?? live)) {
      HapticFeedback.selectionClick();
      _doumFor(code).greet();
      return;
    }
    // One change at a time: a second square mid-change is spent.
    if (_pending != null) return;
    HapticFeedback.selectionClick();
    setState(() => _pending = code);
    widget.controller?._setPending(code);
    widget.controller?._words(false);
    _toCommit = code;
    _change = Timer(_changeAfter, _commit);
    // Should the language never arrive (a commit that failed), the screen's
    // words must not stay faded out.
    _giveUp = Timer(const Duration(seconds: 2), _settle);
  }

  void _commit() {
    final code = _toCommit;
    _toCommit = null;
    if (code == null) return;
    final container = _container;
    final commit = _commitFn;
    if (container != null && commit != null) {
      unawaited(commit(container, Locale(code)));
    }
  }

  /// The language has arrived (or never will): the words come back, in the
  /// new language, and the chosen Doum greets.
  void _settle() {
    _giveUp?.cancel();
    final code = _pending;
    widget.controller?._setPending(null);
    widget.controller?._words(true);
    if (!mounted || code == null) return;
    setState(() => _pending = null);
    if (ref.read(localeProvider).languageCode == code) _doumFor(code).greet();
  }

  @override
  void dispose() {
    // Gone before the change was made (the sheet swiped away inside the
    // fade): the language still changes, the person asked for it. Just after
    // this frame, as DoumLanguageLook does it: a provider the app's widgets
    // watch cannot change while the tree is being finalised.
    final code = _toCommit;
    final container = _container;
    final commit = _commitFn;
    if (code != null && container != null && commit != null) {
      scheduleMicrotask(() {
        try {
          unawaited(commit(container, Locale(code)).catchError((Object _) {}));
        } catch (_) {}
      });
    }
    _change?.cancel();
    _dress?.cancel();
    _giveUp?.cancel();
    final c = widget.controller;
    if (c != null) {
      c._words(true, notify: false);
      c._setPending(null, notify: false);
    }
    _suit.dispose();
    _thobe.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<Locale>(localeProvider, (_, next) {
      if (_pending != null && next.languageCode == _pending) _settle();
    });
    final live = ref.watch(localeProvider).languageCode;
    final chosen = _pending ?? live;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(
          (constraints.maxWidth - widget.gap) / 2,
          widget.maxSquareWidth,
        );
        return Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _square(
                code: 'en',
                look: DoumLook.suit,
                name: 'English',
                direction: TextDirection.ltr,
                width: width,
                chosen: chosen,
              ),
              SizedBox(width: widget.gap),
              _square(
                code: 'ar',
                look: DoumLook.thobe,
                name: 'العربية',
                direction: TextDirection.rtl,
                width: width,
                chosen: chosen,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _square({
    required String code,
    required DoumLook look,
    required String name,
    required TextDirection direction,
    required double width,
    required String chosen,
  }) {
    final gp = context.gp;
    final selected = chosen == code;
    final compact = widget.height < 140;
    // The name's band under his feet. Text scaling is capped inside it: the
    // squares are sized to a measured budget (the sign-in screen's head),
    // and a name that grew past its band would push Doum out of his square.
    final band = compact ? 22.0 : 30.0;
    final box = DoumLanguageLook.sizeOf(widget.doumHeight);
    final landedHere =
        widget.arrival == DoumSquaresArrival.landed && code == _standCode;
    return Semantics(
      button: true,
      selected: selected,
      enabled: widget.enabled,
      label: name,
      excludeSemantics: true,
      child: AnimatedOpacity(
        opacity: widget.enabled || selected ? 1 : .5,
        duration: GameMotion.standard,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.enabled ? () => _pick(code) : null,
          child: AnimatedContainer(
            duration: GameMotion.relaxed,
            curve: Curves.easeOut,
            width: width,
            height: widget.height,
            decoration: BoxDecoration(
              // Gold as a tint and an edge only, never as ink: raw gold
              // measures 1.86:1 on the cream background.
              color: selected ? gp.goldEdge.withOpacity(0.14) : gp.surface,
              borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
              border: Border.all(
                color: selected ? gp.goldEdge : gp.border,
                width: selected ? 1.4 : 0.5,
              ),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: band,
                  child: Center(
                    child: SizedBox(
                      width: box.width,
                      height: box.height,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          if (code == _standCode && widget.standKey != null)
                            Positioned.fill(
                              child: SizedBox(key: widget.standKey),
                            ),
                          if (widget.arrival != DoumSquaresArrival.waiting)
                            DoumLanguageLook(
                              key: ValueKey('doum-square-$code'),
                              height: widget.doumHeight,
                              look: look,
                              controller: _doumFor(code),
                              helloAbove: true,
                              startPlain: landedHere,
                              entrance: landedHere
                                  ? SproutEntrance.none
                                  : SproutEntrance.pop,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 6,
                  right: 6,
                  bottom: compact ? 4 : 7,
                  child: Directionality(
                    textDirection: direction,
                    child: Text(
                      name,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textScaler: MediaQuery.textScalerOf(context)
                          .clamp(maxScaleFactor: 1.15),
                      style: TextStyle(
                        fontSize: compact ? 13 : 15,
                        height: 1.2,
                        fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                        color: selected ? gp.textPrimary : gp.textSec,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: compact ? 6 : 8,
                  right: compact ? 6 : 8,
                  child: AnimatedOpacity(
                    opacity: selected ? 1 : 0,
                    duration: GameMotion.standard,
                    child: Icon(
                      Icons.check_circle_rounded,
                      size: compact ? 16 : 18,
                      color: gp.goldInk,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

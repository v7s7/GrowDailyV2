import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../achievements/models/achievement_model.dart';
import '../../dashboard/notifiers/dashboard_notifier.dart';
import '../models/accessory.dart';
import '../models/character_option.dart';
import '../notifiers/character_notifier.dart';
import '../widgets/accessory_detail_sheet.dart';
import '../widgets/accessory_shop_tile.dart';
import '../widgets/character_avatar.dart';
import '../widgets/character_locked_sheet.dart';
import '../widgets/gold_coin.dart';

/// The closet, rebuilt around five things instead of twelve.
///
/// What it used to be: a preview card, a CHARACTER header, a horizontally
/// clipped character row, a streak-freeze card, and then six category
/// headers each followed by its own SliverGrid. Four of those six
/// categories hold exactly one accessory, and the grid delegate derives
/// its column count from available width rather than from the child count,
/// so each singleton rendered one 82.75pt tile in a 361pt row: 77% of the
/// row empty, under its own header, four times in a row.
///
/// What it is now, top to bottom:
///   1. the balance, as a struck coin in a pouch
///   2. the character on a lit stage, wearing what you picked
///   3. all six characters, none of them off screen
///   4. every accessory in one two-column grid, grouped into three bands
///   5. the one consumable
///
/// The six category headers are gone entirely. They were advertising six
/// "slots" that do not exist anyway: [CharacterState] wears at most one
/// accessory at a time, whatever its category.
class CharacterClosetScreen extends ConsumerWidget {
  const CharacterClosetScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final charState = ref.watch(characterProvider);
    final dash = ref.watch(dashboardProvider);

    bool met(Accessory a) =>
        a.unlock == null ||
        a.unlock!.isMetBy(
          level: dash.level,
          streak: dash.streak,
          completedDays: dash.totalCompletions,
        );

    // GROUPED BY ITEM TYPE, not by state.
    //
    // The bands used to be لديك / بمتناولك / بالتقدّم, which answered
    // "what can I get next" by scrolling. Grouping by type answers "what
    // kinds of thing are there" instead, which is the question once the
    // catalogue is big enough to have real families in it.
    //
    // Categories are ordered by how many pieces they hold, so the full
    // rows come first and the one-item families cluster at the bottom
    // where a half-empty row is least jarring. Four categories still hold
    // a single piece; that gap is the honest cost of this grouping and it
    // closes on its own as the catalogue fills out.
    final byCategory = <AccessoryCategory, List<Accessory>>{};
    for (final a in AccessoryCatalog.all) {
      byCategory.putIfAbsent(a.category, () => []).add(a);
    }
    int byLadder(Accessory a, Accessory b) {
      final r = a.rarity.index.compareTo(b.rarity.index);
      return r != 0 ? r : a.goldCost.compareTo(b.goldCost);
    }

    for (final list in byCategory.values) {
      list.sort(byLadder);
    }
    final categories = byCategory.keys.toList()
      ..sort((a, b) {
        final n = byCategory[b]!.length.compareTo(byCategory[a]!.length);
        return n != 0 ? n : a.index.compareTo(b.index);
      });

    return Scaffold(
      backgroundColor: gp.bg,
      appBar: AppBar(
        backgroundColor: gp.bg,
        surfaceTintColor: Colors.transparent,
        title: Text(
          s.closetTitle,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: gp.textPrimary,
          ),
        ),
        actions: [
          // EdgeInsetsDirectional: this was `EdgeInsets.only(right: 16)`, a
          // physical edge, which in an RTL-first app put the gap on the
          // wrong side and left the balance flush against the screen.
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 16),
            child: Center(child: GoldPurse(gold: dash.gold)),
          ),
        ],
      ),
      body: charState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: _Stage(state: charState)
                      .animate()
                      .fadeIn(duration: GameMotion.relaxed),
                ),
                SliverToBoxAdapter(child: _CharacterRow(state: charState)),
                for (final category in categories)
                  ..._band(context, ref, category.label(s.isAr),
                      byCategory[category]!, charState, dash, met),
                if (dash.streak >= 3)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 26, 20, 0),
                      child: _StreakFreezeShopCard(state: dash),
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 34)),
              ],
            ),
    );
  }

  /// A titled band plus its two-column grid. Bands replaced a row of
  /// filter chips: chips made the user operate the screen to find out what
  /// they had, whereas three titles answer it by scrolling.
  List<Widget> _band(
    BuildContext context,
    WidgetRef ref,
    String title,
    List<Accessory> items,
    CharacterState charState,
    DashboardState dash,
    bool Function(Accessory) met,
  ) {
    final gp = context.gp;
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 26, 20, 12),
          child: Row(
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: gp.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${items.length}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: gp.textTert,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: Container(height: 0.5, color: gp.divider)),
            ],
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        sliver: SliverGrid(
          // Three, not two. Two columns made the art large enough to
          // enjoy but turned ten accessories into five screens of
          // scrolling, and a 174pt card for one misbah reads as a
          // product page, not a shelf. 9 + 58 art + 7 + 30 name + 7 +
          // 24 chip + 10 = 145.
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 11,
            mainAxisSpacing: 11,
            mainAxisExtent: 148,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, i) {
              final a = items[i];
              return AccessoryShopTile(
                accessory: a,
                owned: charState.owns(a.id),
                equipped: charState.equippedAccessoryId == a.id,
                affordable: dash.gold >= a.goldCost,
                requirementMet: met(a),
                onTap: () {
                  HapticFeedback.selectionClick();
                  showAccessoryDetailSheet(context, a);
                },
              )
                  .animate(delay: (i * 34).ms)
                  .fadeIn(duration: GameMotion.standard)
                  .slideY(begin: 0.06, curve: Curves.easeOutCubic);
            },
            childCount: items.length,
          ),
        ),
      ),
    ];
  }
}

// ─── The stage ───────────────────────────────────────────────────────────────

/// The character, lit. An aura tinted by whatever accessory is worn and a
/// soft floor shadow under the feet: two cheap touches that are most of
/// the difference between "a shop" and "a settings page with a picture".
class _Stage extends StatelessWidget {
  final CharacterState state;
  const _Stage({required this.state});

  Color _auraColor(BuildContext context) {
    final worn = state.equippedAccessory;
    if (worn == null) return context.gp.border;
    return switch (worn.rarity) {
      AchievementRarity.common => GameColors.rarityCommon,
      AchievementRarity.uncommon => GameColors.rarityUncommon,
      AchievementRarity.rare => GameColors.rarityRare,
      AchievementRarity.epic => GameColors.rarityEpic,
      AchievementRarity.legendary => GameColors.rarityLegendary,
    };
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final worn = state.equippedAccessory;
    final aura = _auraColor(context);

    return SizedBox(
      height: 268,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Positioned(
            top: 6,
            child: AnimatedContainer(
              duration: GameMotion.slow,
              width: 272,
              height: 272,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [aura.withOpacity(0.22), aura.withOpacity(0)],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 42,
            child: Container(
              width: 148,
              height: 22,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
                gradient: RadialGradient(
                  colors: [
                    Colors.black.withOpacity(gp.bg.computeLuminance() > 0.5
                        ? 0.14
                        : 0.55),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 34,
            child: CharacterAvatar(
              character: state.character,
              accessory: worn,
              height: 206,
            ),
          ),
          Positioned(
            bottom: 4,
            child: Column(
              children: [
                Text(
                  worn?.name(s.isAr) ?? s.closetNoAccessory,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: gp.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                // The payoff nobody was ever told about: room leaderboards
                // already render every member's equipped accessory.
                Text(
                  s.closetSeenByRooms,
                  style: TextStyle(fontSize: 11, color: gp.textTert),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Characters ──────────────────────────────────────────────────────────────

/// All six, as circles, in one row that fits.
///
/// The old picker was a horizontal ListView of 78pt cards: 6 x 78 + 5 x 10
/// + 32 = 550pt of content in a ~393pt viewport, with no scrollbar, no
/// fade and no count, so two characters were permanently off screen with
/// nothing to suggest they existed. Every character is free from the start
/// ([CharacterCatalog]'s own doc says so), so there was never a reason to
/// hide any of them.
class _CharacterRow extends ConsumerStatefulWidget {
  final CharacterState state;
  const _CharacterRow({required this.state});

  /// SQUARE, because the art is square: every character PNG is 512x512.
  /// A portrait cell fits the figure to its width and then leaves the
  /// remaining height empty, so a 58x82 cell rendered a 58px figure and
  /// made the characters *smaller* than the circles it replaced. The cell
  /// width alone decides how big a character looks.
  static const double _cell = 76;

  /// One hairline between characters, so a longer catalog still reads as
  /// separate people rather than a strip.
  static const double _gap = 13;

  @override
  ConsumerState<_CharacterRow> createState() => _CharacterRowState();
}

class _CharacterRowState extends ConsumerState<_CharacterRow> {
  final _controller = ScrollController();

  /// Whether the row has been scrolled away from its start edge. Drives
  /// the leading fade, which must not be painted at rest: dimming the
  /// first character when there is nothing hidden behind it would be a
  /// lie about the content.
  final _scrolled = ValueNotifier<bool>(false);

  /// Which dot is lit: where the row is SCROLLED TO, not which character
  /// is equipped. The indicator answers "where am I in this list", the
  /// gold ring on a cell answers "which one am I wearing", and those are
  /// two different questions that were sharing one signal.
  final _visible = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
    // Six characters already overflow, and the catalog is expected to
    // grow, so the one you are actually wearing must not start off screen.
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelected());
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    final p = _controller.position;

    final scrolled = p.pixels > 4;
    if (scrolled != _scrolled.value) _scrolled.value = scrolled;

    // Scroll fraction mapped across the dot range, rather than "whichever
    // character is nearest the middle". With four cells visible out of
    // six, a nearest-to-centre rule can never reach the first or last dot,
    // so a third of the indicator would be decorative. This way offset 0
    // lights the first dot, the end lights the last, and it moves
    // monotonically in between.
    final max = p.maxScrollExtent;
    final count = CharacterCatalog.all.length;
    final fraction = max <= 0 ? 0.0 : (p.pixels / max).clamp(0.0, 1.0);
    final i = (fraction * (count - 1)).round();
    if (i != _visible.value) _visible.value = i;
  }

  void _revealSelected() {
    if (!mounted || !_controller.hasClients) return;
    final i = CharacterCatalog.all
        .indexWhere((c) => c.id == widget.state.characterId);
    if (i < 0) return;
    const step = _CharacterRow._cell + _CharacterRow._gap;
    final viewport = _controller.position.viewportDimension;
    final target = (i * step) - (viewport / 2) + (_CharacterRow._cell / 2);
    _controller.jumpTo(
      target.clamp(0.0, _controller.position.maxScrollExtent),
    );
    _onScroll();
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    _scrolled.dispose();
    _visible.dispose();
    super.dispose();
  }

  Widget _fade(Color bg, {required bool leading}) => IgnorePointer(
        child: Container(
          width: 30,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: AlignmentDirectional.centerStart,
              end: AlignmentDirectional.centerEnd,
              colors: leading
                  ? [bg, bg.withOpacity(0)]
                  : [bg.withOpacity(0), bg],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final all = CharacterCatalog.all;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: _CharacterRow._cell + 4,
          child: _strip(all),
        ),
        const SizedBox(height: 11),
        ValueListenableBuilder<int>(
          valueListenable: _visible,
          builder: (_, i, __) =>
              _CharacterDots(count: all.length, index: i),
        ),
      ],
    );
  }

  Widget _strip(List<CharacterOption> all) {
    final gp = context.gp;
    return SizedBox(
      height: _CharacterRow._cell + 4,
      child: Stack(
        children: [
          ListView.separated(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: all.length,
            separatorBuilder: (_, __) => Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: (_CharacterRow._gap - 1) / 2,
              ),
              child: Center(
                child: Container(width: 1, height: 44, color: gp.divider),
              ),
            ),
            itemBuilder: (context, i) {
              final option = all[i];
              final selected = option.id == widget.state.characterId;
              final dash = ref.watch(dashboardProvider);
              // canWear owns the whole rule now: free, already earned, or
              // worn before. That last clause is what stops raising a gate
              // from confiscating a look somebody already had.
              final locked = !widget.state.canWear(
                option,
                level: dash.level,
                streak: dash.streak,
                completedDays: dash.totalCompletions,
              );
              return Semantics(
                label: option.name(S.of(context).isAr),
                selected: selected,
                button: true,
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    if (locked) {
                      // Show the look, big, with how far off it is. A
                      // snackbar could only refuse; this can sell it.
                      showCharacterLockedSheet(context, option);
                      return;
                    }
                    ref
                        .read(characterProvider.notifier)
                        .selectCharacter(option.id);
                  },
                  child: AnimatedContainer(
                    duration: GameMotion.quick,
                    width: _CharacterRow._cell,
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: selected
                          ? GameColors.gold.withOpacity(0.10)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: selected ? GameColors.gold : Colors.transparent,
                        width: 1.4,
                      ),
                    ),
                    // contain, never cover, and no ClipOval: the whole
                    // figure or nothing. The outfit is the thing being
                    // chosen and most of it is below the neck.
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Opacity(
                            opacity: locked ? 0.32 : 1,
                            child: Image.asset(option.assetPath,
                                fit: BoxFit.contain),
                          ),
                        ),
                        if (locked)
                          Positioned.fill(
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: GameColors.rarityEpic
                                      .withOpacity(0.16),
                                  borderRadius: BorderRadius.circular(
                                      GameSpacing.pillRadius),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.lock_rounded,
                                        size: 8,
                                        color: GameColors.rarityEpic),
                                    const SizedBox(width: 3),
                                    Text(
                                      '${option.unlock!.amount}',
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w700,
                                        color: GameColors.rarityEpic,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          // The affordance the old picker never had: a figure is always
          // half-dissolved at whichever edge has more behind it, saying
          // "more this way", instead of being cut off mid-body.
          PositionedDirectional(
            end: 0,
            top: 0,
            bottom: 0,
            child: _fade(gp.bg, leading: false),
          ),
          PositionedDirectional(
            start: 0,
            top: 0,
            bottom: 0,
            child: ValueListenableBuilder<bool>(
              valueListenable: _scrolled,
              builder: (_, scrolled, child) => AnimatedOpacity(
                opacity: scrolled ? 1 : 0,
                duration: GameMotion.quick,
                child: child,
              ),
              child: _fade(gp.bg, leading: true),
            ),
          ),
        ],
      ),
    );
  }
}

/// Where you are in the character row, as a dot strip.
///
/// Modelled on the indicator under an Instagram carousel, and the part of
/// that design worth copying is not the dots, it is the CAP: past a
/// threshold the strip stops growing and slides instead, tapering the
/// outermost dots so "there are more beyond this edge" is visible without
/// the row ever getting wider. A naive one-dot-per-item strip is fine at
/// six characters and unreadable at thirty.
///
/// Below [_maxVisible] every dot is drawn full size, because the strip
/// also answers "how many are there" and a windowed strip cannot be
/// counted. The window only engages once counting was hopeless anyway.
///
/// [index] is a SCROLL position, not a selection. Which character is
/// equipped is said by the gold ring on its cell; making the dots say it
/// too left them frozen while the row moved under the user's thumb.
class _CharacterDots extends StatelessWidget {
  final int count;
  final int index;

  const _CharacterDots({required this.count, required this.index});

  static const int _maxVisible = 8;
  static const double _dot = 6;
  static const double _gap = 5;

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    if (count <= 1) return const SizedBox.shrink();

    final active = index < 0 ? 0 : index;
    final windowed = count > _maxVisible;

    // Centre the active dot in the window, then clamp so the strip never
    // runs off either end of the list.
    final first = !windowed
        ? 0
        : (active - _maxVisible ~/ 2).clamp(0, count - _maxVisible);
    final last = !windowed ? count - 1 : first + _maxVisible - 1;

    return Semantics(
      label: S.of(context).closetProgress(active + 1, count),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = first; i <= last; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: _gap / 2),
              child: AnimatedContainer(
                duration: GameMotion.quick,
                curve: Curves.easeOut,
                width: _dot * _scaleFor(i, first, last),
                height: _dot * _scaleFor(i, first, last),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i == active
                      ? GameColors.gold
                      : gp.textTert.withOpacity(0.45),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Full size, unless this dot sits at an edge of the window that still
  /// has items hidden beyond it. Two steps of taper reads as a fade rather
  /// than as two odd little dots.
  double _scaleFor(int i, int first, int last) {
    if (count <= _maxVisible) return 1;
    if (i == first && first > 0) return 0.45;
    if (i == last && last < count - 1) return 0.45;
    if (i == first + 1 && first > 0) return 0.72;
    if (i == last - 1 && last < count - 1) return 0.72;
    return 1;
  }
}

// ─── Streak Freeze shop card ────────────────────────────────────────────────

/// Relocated here from the old Dashboard/Progress page — this is a
/// gold-spending purchase, so it belongs in the shop with everything else
/// gold buys, not on a page whose whole job is now "look back at your
/// progress". Same 3-day-streak gate as before: every account starts with
/// one free freeze already banked (see DashboardNotifier's `?? 1`
/// default), so surfacing this before there's a real streak worth
/// protecting was pitching insurance before there was anything to insure.
class _StreakFreezeShopCard extends ConsumerWidget {
  final DashboardState state;
  const _StreakFreezeShopCard({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final canBuy = state.gold >= DashboardNotifier.streakFreezeCost &&
        state.streakFreezes < DashboardNotifier.maxStreakFreezes;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: gp.border, width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: GameColors.iconXp.withOpacity(0.13),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(Icons.ac_unit_rounded, color: GameColors.iconXp, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.streakFreeze,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: gp.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  s.streakFreezeStatus(
                      state.streakFreezes, DashboardNotifier.maxStreakFreezes),
                  style: TextStyle(fontSize: 11.5, color: gp.textSec),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: canBuy
                ? () async {
                    HapticFeedback.mediumImpact();
                    final ok = await ref
                        .read(dashboardProvider.notifier)
                        .buyStreakFreeze();
                    if (context.mounted) {
                      final s2 = S.of(context);
                      // `canBuy` already gated this on having enough gold
                      // and a free slot, so a `false` here means the
                      // purchase failed to save, not that funds were short.
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(ok ? s2.streakFreeze : s2.errGeneric),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  }
                : null,
            child: GoldPrice(
              amount: DashboardNotifier.streakFreezeCost,
              affordable: canBuy,
            ),
          ),
        ],
      ),
    );
  }
}

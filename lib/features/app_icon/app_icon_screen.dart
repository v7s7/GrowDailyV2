import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/day_clock_provider.dart';
import '../../core/providers/theme_provider.dart';
import '../../core/theme/game_theme.dart';
import '../../core/theme/theme_preset.dart';
import '../premium/notifiers/premium_notifier.dart';
import '../premium/screens/premium_screen.dart';
import 'app_icon_art.dart';
import 'app_icon_catalog.dart';
import 'app_icon_providers.dart';

/// Settings › التخصيص › أيقونة التطبيق: the Home Screen icon, as a SHAPE and
/// a COLOUR picked separately (see app_icon_catalog.dart).
///
/// A page rather than a sheet like its neighbours, because it holds two
/// choices, a switch and a preview, and a sheet that tall scrolls under a
/// finger. Nothing reaches the phone until «استخدم هذه الأيقونة»: iOS answers
/// every icon change with an alert of its own, and a shape tap and a colour
/// tap applied as they happen would raise two.
///
/// «مع المظهر» makes the icon take each theme's colour as it is picked (the
/// custom theme takes the nearest of the sixteen). It is off unless turned
/// on, and picking a colour by hand turns it off again: the two are one
/// choice, made either way.
///
/// «موسمية» holds the Ramadan icon, a whole icon rather than a shape or a
/// colour: picking it sets the shape and colour aside, and picking either
/// of those again leaves it. All year it sits at the end, locked, saying
/// when it opens; in Ramadan it moves up under the preview, open to all.
class AppIconScreen extends ConsumerStatefulWidget {
  const AppIconScreen({super.key});

  @override
  ConsumerState<AppIconScreen> createState() => _AppIconScreenState();
}

class _AppIconScreenState extends ConsumerState<AppIconScreen> {
  // Seeded once from what the phone shows and this device's preference,
  // then owned by the page until «استخدم».
  bool _seeded = false;
  PlantShape _shape = PlantShape.sprout;
  String _colourId = 'emerald_gold';
  bool _follow = false;
  bool _ramadan = false;
  bool _applying = false;

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final current = ref.watch(appIconProvider);
    final prefs = ref.watch(appIconPrefsProvider);
    final premium = ref.watch(premiumAccessProvider);
    final fullDays = ref.watch(plantFullDaysProvider).valueOrNull;
    final earned = earnedShape(ref.watch(plantGrowthProvider), fullDays);
    final presetId = ref.watch(themePresetProvider);
    final matched = iconColourById(
      iconColourForTheme(presetId, ThemePresets.customAccent),
    );
    // The day clock re-reads itself at midnight, so a page left open across
    // Ramadan's first night opens the tile without being reopened.
    final today = ref.watch(dayClockProvider);
    final ramadan = RamadanIconWindow.at(today);
    final ramadanOpen = ramadan?.isOpenAt(today) ?? false;

    if (!_seeded && current != null && prefs.loaded) {
      _seeded = true;
      _ramadan = current.isRamadan;
      _shape = current.shape;
      _colourId =
          current.isRamadan ? AppIconChoice.shipped.colourId : current.colourId;
      _follow = prefs.followTheme && !current.isRamadan;
    }

    final followAllowed = !matched.needsPremium || premium;
    final follow = _follow && followAllowed && !_ramadan;
    final plain = AppIconChoice(_shape, follow ? matched.id : _colourId);
    final choice = _ramadan ? AppIconChoice.ramadan : plain;
    final dirty =
        current != null && (choice != current || follow != prefs.followTheme);

    final seasonal = <Widget>[
      _SectionTitle(s.appIconSeasonSection),
      const SizedBox(height: 12),
      _RamadanRow(
        selected: _ramadan,
        open: ramadanOpen,
        note: ramadanOpen
            ? s.appIconRamadanNote
            : s.appIconRamadanSoon(ramadan?.daysUntilOpen(today) ?? 0),
        onTap: () {
          if (!ramadanOpen) {
            HapticFeedback.lightImpact();
            return;
          }
          HapticFeedback.selectionClick();
          setState(() {
            _ramadan = true;
            _follow = false;
          });
        },
      ),
    ];

    return Scaffold(
      backgroundColor: gp.bg,
      appBar: AppBar(
        backgroundColor: gp.bg,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        title: Text(
          s.appIconTitle,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: gp.textPrimary,
          ),
        ),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        children: [
          _Preview(choice: choice, live: !dirty),
          if (ramadanOpen) ...[const SizedBox(height: 24), ...seasonal],
          const SizedBox(height: 24),
          _SectionTitle(s.appIconShapeSection),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final shape in PlantShape.values)
                Expanded(
                  child: _IconTile(
                    choice: AppIconChoice(shape, plain.colourId),
                    label: shape.label(s),
                    caption: shape.index > earned.index && fullDays != null
                        ? s.appIconFullDaysLeft(shape.daysNeeded - fullDays)
                        : null,
                    selected: !_ramadan && shape == _shape,
                    locked: shape.index > earned.index,
                    onTap: () {
                      if (shape.index > earned.index) {
                        HapticFeedback.lightImpact();
                        return;
                      }
                      HapticFeedback.selectionClick();
                      setState(() {
                        _shape = shape;
                        _ramadan = false;
                      });
                    },
                  ),
                ),
            ],
          ),
          if (fullDays != null) ...[
            const SizedBox(height: 12),
            Text(
              _progressLine(s, fullDays, earned),
              style: TextStyle(fontSize: 12, height: 1.5, color: gp.textSec),
            ),
          ],
          SizedBox(height: fullDays != null ? 4 : 12),
          Text(
            s.appIconFullDayRule,
            style: TextStyle(fontSize: 11.5, height: 1.5, color: gp.textTert),
          ),
          const SizedBox(height: 24),
          _SectionTitle(s.appIconColourSection),
          const SizedBox(height: 12),
          _FollowCard(
            value: follow,
            onChanged: followAllowed
                ? (on) {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _follow = on;
                      if (on) _ramadan = false;
                    });
                  }
                : null,
          ),
          for (final tier in IconColourTier.values) ...[
            const SizedBox(height: 18),
            _SubLabel(
              switch (tier) {
                IconColourTier.free => s.themeSectionFree,
                IconColourTier.premium => s.themeSectionPremium,
                IconColourTier.more => s.appIconMoreColours,
              },
            ),
            const SizedBox(height: 10),
            _ColourGrid(
              colours: [
                for (final c in kIconColours)
                  if (c.tier == tier) c,
              ],
              shape: _shape,
              selectedId: _ramadan ? null : plain.colourId,
              premium: premium,
              onPick: (c) {
                if (c.needsPremium && !premium) {
                  _openPaywall(context);
                  return;
                }
                HapticFeedback.selectionClick();
                setState(() {
                  _colourId = c.id;
                  _follow = false;
                  _ramadan = false;
                });
              },
            ),
          ],
          if (!ramadanOpen && ramadan != null) ...[
            const SizedBox(height: 28),
            ...seasonal,
          ],
        ],
      ),
      bottomNavigationBar: _ApplyBar(
        dirty: dirty,
        busy: _applying,
        // A lapsed account whose phone still shows a Premium colour keeps
        // it (like a paid theme), but a new icon in that colour is an edit,
        // and edits are Premium's: the button goes to the paywall instead.
        onApply: choice.needsPremium && !premium
            ? () => _openPaywall(context)
            : () => _apply(choice, follow),
      ),
    );
  }

  /// «عندك 12 يومًا كاملًا. النبتة الكبيرة بعد 18 يومًا كاملًا.» The next
  /// shape is the one after [earned], not after today's count: a shape
  /// already opened stays open whatever the count says (see [PlantGrowth]).
  String _progressLine(S s, int fullDays, PlantShape earned) {
    final ahead =
        PlantShape.values.where((p) => p.index > earned.index).toList();
    final next = ahead.isEmpty ? null : ahead.first;
    final tail = next == null
        ? s.appIconAllShapes
        : s.appIconNextShape(
            next.labelInSentence(s),
            next.daysNeeded - fullDays,
          );
    return '${s.appIconFullDaysSoFar(fullDays)} $tail';
  }

  void _openPaywall(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const PremiumScreen(
          reason: PremiumReason.appearance,
          source: 'app_icon',
        ),
      ),
    );
  }

  Future<void> _apply(AppIconChoice choice, bool follow) async {
    if (_applying) return;
    setState(() => _applying = true);
    final messenger = ScaffoldMessenger.of(context);
    final s = S.of(context);
    final ok = await ref.read(appIconProvider.notifier).apply(choice);
    if (ok) {
      await ref.read(appIconPrefsProvider.notifier).setFollowTheme(follow);
    }
    if (!mounted) return;
    setState(() => _applying = false);
    if (!ok) {
      messenger.showSnackBar(SnackBar(content: Text(s.appIconFailed)));
    }
  }
}

/// The icon as it will look, with what it is and whether it is already on
/// the phone.
class _Preview extends StatelessWidget {
  const _Preview({required this.choice, required this.live});

  final AppIconChoice choice;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 18),
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: gp.border, width: 0.5),
      ),
      child: Column(
        children: [
          AppIconArt(choice: choice, size: 96),
          const SizedBox(height: 12),
          Text.rich(
            TextSpan(
              // The Ramadan icon is one icon, not a shape in a colour.
              text: choice.isRamadan ? s.appIconRamadan : choice.shape.label(s),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: gp.textPrimary,
              ),
              children: [
                if (!choice.isRamadan)
                  TextSpan(
                    text: ' · ${choice.colour.label(s)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: gp.textSec,
                    ),
                  ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            live ? s.appIconNow : s.appIconPreviewing,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: live ? gp.goldInk : gp.textSec,
            ),
          ),
        ],
      ),
    );
  }
}

/// Same recipe as the Settings screen's group titles, so this page reads
/// as the next step of that one.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: context.gp.textSec,
        letterSpacing: 1.5,
      ),
    );
  }
}

/// Same recipe as the theme sheet's مجاني / مميّز labels.
class _SubLabel extends StatelessWidget {
  const _SubLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 2),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
          color: context.gp.textTert,
        ),
      ),
    );
  }
}

/// An icon with the picker's two marks: a ring when chosen, a lock when not
/// yet open to this person. The ring stands 3pt off the icon so the icon's
/// own edge never merges into it.
class _MarkedIcon extends StatelessWidget {
  const _MarkedIcon({
    required this.choice,
    required this.size,
    required this.selected,
    required this.locked,
  });

  final AppIconChoice choice;
  final double size;
  final bool selected;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    const gap = 3.0;
    const ring = 2.0;
    final outer = size + (gap + ring) * 2;
    return SizedBox.square(
      dimension: outer,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          if (selected)
            Positioned.fill(
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  shape: RoundedSuperellipseBorder(
                    borderRadius: BorderRadius.circular(
                      outer * kAppIconCornerShare,
                    ),
                    side: BorderSide(color: gp.goldInk, width: ring),
                  ),
                ),
              ),
            ),
          AppIconArt(choice: choice, size: size),
          if (locked || selected)
            PositionedDirectional(
              end: 0,
              bottom: 0,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: gp.bg,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  locked ? Icons.lock_rounded : Icons.check_circle_rounded,
                  size: locked ? 13 : 19,
                  color: locked ? gp.textSec : gp.goldInk,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A shape, or the Ramadan icon: the icon with its marks, a name, and a
/// line under it when there is something to say (how far off, when open).
class _IconTile extends StatelessWidget {
  const _IconTile({
    required this.choice,
    required this.label,
    required this.caption,
    required this.selected,
    required this.locked,
    required this.onTap,
  });

  final AppIconChoice choice;
  final String label;
  final String? caption;
  final bool selected;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final caption = this.caption;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      hint: caption,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              _MarkedIcon(
                choice: choice,
                size: 64,
                selected: selected,
                locked: locked,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: locked ? gp.textSec : gp.textPrimary,
                ),
              ),
              if (caption != null)
                // Two lines: «باقي 18 يومًا كاملًا» and its English run
                // past a quarter of an iPhone SE's width.
                Text(
                  caption,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.35,
                    color: gp.textSec,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The Ramadan tile, a quarter of the width like a shape's, with what it is
/// beside it: when it opens, or that it is open to everyone.
class _RamadanRow extends StatelessWidget {
  const _RamadanRow({
    required this.selected,
    required this.open,
    required this.note,
    required this.onTap,
  });

  final bool selected;
  final bool open;
  final String note;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    return Row(
      children: [
        Expanded(
          child: _IconTile(
            choice: AppIconChoice.ramadan,
            label: s.appIconRamadan,
            caption: open ? s.appIconRamadanOpen : s.appIconRamadanLocked,
            selected: selected,
            locked: !open,
            onTap: onTap,
          ),
        ),
        Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: 12),
            child: Text(
              note,
              style: TextStyle(fontSize: 12, height: 1.5, color: gp.textSec),
            ),
          ),
        ),
      ],
    );
  }
}

class _FollowCard extends StatelessWidget {
  const _FollowCard({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    return Material(
      color: gp.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        side: BorderSide(color: gp.border, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              Icon(Icons.palette_rounded, size: 20, color: gp.textSec),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.appIconFollowTitle,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: gp.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      s.appIconFollowBody,
                      style: TextStyle(fontSize: 12, color: gp.textSec),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: value,
                activeTrackColor: GameColors.emerald,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: onChanged,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ColourGrid extends StatelessWidget {
  const _ColourGrid({
    required this.colours,
    required this.shape,
    required this.selectedId,
    required this.premium,
    required this.onPick,
  });

  final List<IconColour> colours;
  final PlantShape shape;

  /// Null while the Ramadan icon is picked, which is no colour of these.
  final String? selectedId;
  final bool premium;
  final ValueChanged<IconColour> onPick;

  static const _columns = 5;
  static const _gap = 10.0;

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        final width = (box.maxWidth - _gap * (_columns - 1)) / _columns;
        return Wrap(
          spacing: _gap,
          runSpacing: 12,
          children: [
            for (final c in colours)
              SizedBox(
                width: width,
                child: Semantics(
                  button: true,
                  selected: c.id == selectedId,
                  label: c.label(s),
                  excludeSemantics: true,
                  child: InkWell(
                    onTap: () => onPick(c),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        children: [
                          _MarkedIcon(
                            choice: AppIconChoice(shape, c.id),
                            size: 52,
                            selected: c.id == selectedId,
                            locked: c.needsPremium && !premium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            c.label(s),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: c.id == selectedId
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: c.needsPremium && !premium
                                  ? gp.textSec
                                  : gp.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// «استخدم هذه الأيقونة», or a quiet «هذه أيقونتك الحين» when there is
/// nothing to change.
class _ApplyBar extends StatelessWidget {
  const _ApplyBar({
    required this.dirty,
    required this.busy,
    required this.onApply,
  });

  final bool dirty;
  final bool busy;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    return Container(
      decoration: BoxDecoration(
        color: gp.bg,
        border: Border(top: BorderSide(color: gp.divider, width: 0.5)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 50,
          child: dirty
              ? FilledButton(
                  onPressed: busy ? null : onApply,
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: Text(s.appIconUse),
                )
              : DecoratedBox(
                  decoration: BoxDecoration(
                    color: gp.surfaceHL,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_rounded, size: 18, color: gp.textSec),
                      const SizedBox(width: 8),
                      Text(
                        s.appIconInUse,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: gp.textSec,
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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/app_guide_provider.dart';
import '../../core/providers/day_clock_provider.dart';
import '../../core/providers/theme_provider.dart';
import '../../core/theme/game_theme.dart';
import '../../core/theme/theme_preset.dart';
import '../premium/notifiers/premium_notifier.dart';
import 'app_icon_art.dart';
import 'app_icon_catalog.dart';
import 'app_icon_providers.dart';
import 'app_icon_service.dart';

// The moments the icon speaks up on its own: right after a theme is picked,
// when the plant grows, and once each Ramadan. All of them only ever OFFER;
// the icon changes on the person's tap, because iOS answers every change
// with an alert.

// ─── After a theme is picked ────────────────────────────────────────────────

/// Called by every place a theme is picked for good (the theme sheet, the
/// theme preview's apply, the custom theme sheet as it closes).
///
/// Takes the container and messenger rather than a context because every
/// caller has just popped the sheet it lived in: capture both first, then
/// pop, then call this.
///
/// With «مع المظهر» on, the icon simply takes the new colour (that is what
/// the switch was turned on to do). Otherwise, when the icon does not match,
/// a small card offers it, with a box to make it automatic from now on.
/// «مو الحين» twice ends the offer for good ([kAppIconOfferDeclineLimit]).
Future<void> offerIconForTheme(
  ProviderContainer container,
  ScaffoldMessengerState? messenger,
) async {
  if (!AppIconService.onThisPlatform) return;
  if (!await container.read(appIconsAvailableProvider.future)) return;
  final prefsNotifier = container.read(appIconPrefsProvider.notifier);
  await prefsNotifier.ready;
  final current = await container.read(appIconProvider.notifier).refresh();
  final presetId = container.read(themePresetProvider);
  final colour = iconColourById(
    iconColourForTheme(presetId, ThemePresets.customAccent),
  );
  if (current.colourId == colour.id) return;
  if (colour.needsPremium && !container.read(premiumAccessProvider)) return;
  final target = current.withColour(colour.id);
  final prefs = container.read(appIconPrefsProvider);
  if (prefs.followTheme) {
    await container.read(appIconProvider.notifier).apply(target);
    return;
  }
  if (prefs.offerDeclines >= kAppIconOfferDeclineLimit || messenger == null) {
    return;
  }
  final host = messenger.context;
  if (!host.mounted) return;
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    _offerSnackBar(
      host,
      target: target,
      custom: presetId == ThemePresets.customId,
      onYes: (always) {
        messenger.hideCurrentSnackBar();
        if (always) unawaited(prefsNotifier.setFollowTheme(true));
        unawaited(container.read(appIconProvider.notifier).apply(target));
      },
      onNo: () {
        messenger.hideCurrentSnackBar();
        unawaited(prefsNotifier.noteOfferDeclined());
      },
    ),
  );
}

SnackBar _offerSnackBar(
  BuildContext context, {
  required AppIconChoice target,
  required bool custom,
  required void Function(bool always) onYes,
  required VoidCallback onNo,
}) {
  final gp = context.gp;
  return SnackBar(
    behavior: SnackBarBehavior.floating,
    backgroundColor: gp.surfaceHigh,
    elevation: 8,
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 6, 12),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: BorderSide(color: gp.border, width: 0.5),
    ),
    // Long enough to read and decide; letting it slide away is not a
    // «مو الحين» and is not counted as one.
    duration: const Duration(seconds: 12),
    content: _IconOfferCard(
      target: target,
      custom: custom,
      onYes: onYes,
      onNo: onNo,
    ),
  );
}

class _IconOfferCard extends StatefulWidget {
  const _IconOfferCard({
    required this.target,
    required this.custom,
    required this.onYes,
    required this.onNo,
  });

  final AppIconChoice target;
  final bool custom;
  final void Function(bool always) onYes;
  final VoidCallback onNo;

  @override
  State<_IconOfferCard> createState() => _IconOfferCardState();
}

class _IconOfferCardState extends State<_IconOfferCard> {
  bool _always = false;

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final colour = widget.target.colour;
    final body = widget.custom
        ? s.appIconOfferBodyCustom
        : colour.id == 'emerald_gold'
            ? s.appIconOfferBodyOriginal
            : s.appIconOfferBody(colour.label(s));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppIconArt(choice: widget.target, size: 48),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.appIconOfferTitle,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: gp.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      body,
                      style: TextStyle(fontSize: 12, color: gp.textSec),
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              onPressed: widget.onNo,
              icon: Icon(Icons.close_rounded, size: 18, color: gp.textSec),
            ),
          ],
        ),
        InkWell(
          onTap: () => setState(() => _always = !_always),
          borderRadius: BorderRadius.circular(10),
          child: Row(
            children: [
              Checkbox(
                value: _always,
                activeColor: gp.goldInk,
                onChanged: (v) => setState(() => _always = v ?? false),
              ),
              Expanded(
                child: Text(
                  s.appIconOfferAlways,
                  style: TextStyle(fontSize: 13, color: gp.textPrimary),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsetsDirectional.only(end: 8),
          child: Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    widget.onYes(_always);
                  },
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(s.appIconOfferYes),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.onNo,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                    foregroundColor: gp.textSec,
                    side: BorderSide(color: gp.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(s.appIconOfferNo),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── The cards: the plant grew, Ramadan is here ─────────────────────────────

/// One card at a time. Every call joins the end of this line and looks again
/// when its turn comes, so two calls at launch can never stack two cards,
/// and a call from a HomeShell that has since been rebuilt finds its context
/// gone and leaves the card to the call from the new one.
///
/// Null when nothing is waiting. Back to null as soon as the line empties,
/// rather than holding a finished future: a finished future answers a late
/// listener through the zone it was made in, and in a widget test that zone
/// is gone by the next test, which then waits forever.
Future<void>? _iconCardQueue;

/// Shows the icon's own cards: «رمضان مبارك» once each Ramadan, and
/// «نبتتك كبرت» once per newly opened shape. HomeShell calls it after its
/// first frame, whenever the full-day count moves, and on resume;
/// [dayJustFull] when the count has just gone up, which is the moment a day
/// reached its 80% and has its own «يوم كامل!» on screen.
///
/// One card a call. Ramadan's goes first, because it is gone after Eid and
/// a grown shape keeps; the plant's then waits for the next call (a resume,
/// the next full day) rather than opening straight after the first closes.
///
/// Waits rather than interrupts: nothing is shown over another route (a
/// completion's own celebration, a sheet, a pushed screen) or during an
/// App Guide lesson; the next call tries again.
///
/// A card counts as seen once it has actually OPENED (its first build),
/// never before. Marking it on the way in lost it for good on the simulator
/// on 2026-09-25: launch rebuilt HomeShell between the mark and the sheet,
/// so the sheet never opened while the record said it had.
///
/// Someone who already has 30 or 90 full days when this ships sees the plant
/// card once for the furthest shape they have, which is also how they find
/// the feature.
Future<void> maybeShowIconCard(
  BuildContext context,
  WidgetRef ref, {
  bool dayJustFull = false,
}) async {
  if (!AppIconService.onThisPlatform) return;
  // Asked at launch whatever happens below, so the Settings row and its
  // little icon are ready by the time anyone opens Settings, rather than
  // popping in a moment after the screen appears.
  ref.read(appIconsAvailableProvider);
  ref.read(appIconProvider);
  final previous = _iconCardQueue;
  final done = Completer<void>();
  final mine = done.future;
  _iconCardQueue = mine;
  try {
    if (previous != null) await previous;
    if (!context.mounted) return;
    // A beat first: the completion that made a day full has its own moment
    // on screen (points, a level, «يوم كامل!»), and launch has the rooms
    // prompt. Whatever claimed the screen in that beat wins, and this tries
    // again on the next count change or resume.
    final beat = dayJustFull ? _kIconCardBeatAfterFullDay : _kIconCardBeat;
    if (await _ramadanCardTurn(context, ref, beat: beat)) return;
    if (!context.mounted) return;
    await _plantCardTurn(context, ref, beat: beat);
  } catch (e) {
    debugPrint('[AppIcon] icon card: $e');
  } finally {
    done.complete();
    if (identical(_iconCardQueue, mine)) _iconCardQueue = null;
  }
}

/// How long a card waits before it looks at the screen. At launch, a beat.
/// Right after a day has become full, long enough for that day's own
/// «يوم كامل!» (a burst and a three-second bar, reaction_overlays.dart) to
/// be read first, so the two moments do not land on top of each other.
const Duration _kIconCardBeat = Duration(milliseconds: 700);
const Duration _kIconCardBeatAfterFullDay = Duration(milliseconds: 3500);

/// Whether the screen is free for a card after [beat]: still mounted, not
/// under another route, no App Guide lesson running.
Future<bool> _screenFreeAfter(
  BuildContext context,
  WidgetRef ref,
  Duration beat,
) async {
  await Future<void>.delayed(beat);
  if (!context.mounted) return false;
  if (ModalRoute.of(context)?.isCurrent == false) return false;
  return ref.read(activeAppGuideLessonProvider) == null;
}

/// «رمضان مبارك»: the Ramadan icon, offered once each Ramadan, from its
/// first day until Eid, because a seasonal icon kept in Settings is one
/// nobody finds in time (Aziz, 2026-09-25). True when it showed.
///
/// Not on the eve, which the picker opens for the icon's sake: a greeting
/// before the moon is sighted is a day early for most people. Never to a
/// phone already showing the icon, which has nothing to be told.
Future<bool> _ramadanCardTurn(
  BuildContext context,
  WidgetRef ref, {
  required Duration beat,
}) async {
  final today = ref.read(dayClockProvider);
  final dates = RamadanIconWindow.at(today)?.dates;
  if (dates == null ||
      today.isBefore(dates.start) ||
      !today.isBefore(dates.eid)) {
    return false;
  }
  final year = dates.hijriYear;
  final prefs = ref.read(appIconPrefsProvider.notifier);
  await prefs.ready;
  if (!context.mounted) return false;
  if (ref.read(appIconPrefsProvider).ramadanCardYear >= year) return false;
  if (!await ref.read(appIconsAvailableProvider.future)) return false;
  if (!context.mounted) return false;
  final current = await ref.read(appIconProvider.notifier).refresh();
  if (!context.mounted) return false;
  if (current.isRamadan) {
    await prefs.noteRamadanCardShown(year);
    return false;
  }
  if (!await _screenFreeAfter(context, ref, beat) || !context.mounted) {
    return false;
  }
  if (ref.read(appIconPrefsProvider).ramadanCardYear >= year) return false;
  final s = S.of(context);
  debugPrint('[AppIcon] Ramadan card: $year');
  await _showIconCard(
    context,
    _IconCardSheet(
      choice: AppIconChoice.ramadan,
      title: s.ramadanCardTitle,
      body: s.ramadanCardBody,
      // The Ramadan icon is a pick of its own, like one made on the page: a
      // theme picked later must not take it off the phone.
      leavesTheme: true,
      onShown: () => prefs.noteRamadanCardShown(year),
    ),
  );
  return true;
}

Future<void> _plantCardTurn(
  BuildContext context,
  WidgetRef ref, {
  required Duration beat,
}) async {
  final days = await ref.read(plantFullDaysProvider.future);
  if (days == null || !context.mounted) return;
  final growth = ref.read(plantGrowthProvider.notifier);
  await growth.ready;
  await growth.observe(days);
  if (!context.mounted) return;
  final seen = ref.read(plantGrowthProvider);
  if (seen.earned.index <= seen.celebrated.index) return;
  if (!await ref.read(appIconsAvailableProvider.future)) return;
  if (!context.mounted) return;
  if (!await _screenFreeAfter(context, ref, beat)) return;
  final shape = ref.read(plantGrowthProvider).earned;
  if (shape.index <= ref.read(plantGrowthProvider).celebrated.index) return;
  final current = await ref.read(appIconProvider.notifier).refresh();
  if (!context.mounted) return;
  final s = S.of(context);
  final ahead = PlantShape.values.where((p) => p.index > shape.index);
  final next = ahead.isEmpty ? null : ahead.first;
  debugPrint('[AppIcon] plant card: ${shape.name} at $days full days');
  // The new shape in the colour the phone already shows (the original
  // colours when that is the Ramadan icon, see AppIconChoice.withShape).
  // Unless that colour is Premium's and Premium has ended: the phone keeps
  // the colour it has, like a paid theme, but a new icon in it is an edit,
  // which the icon page sends to the paywall. This card applied it with no
  // question. A grown plant is everyone's, so it comes in the original
  // colours instead, which is what the card then shows.
  final kept = current.withShape(shape);
  final choice = kept.needsPremium && !ref.read(premiumAccessProvider)
      ? AppIconChoice(shape, AppIconChoice.shipped.colourId)
      : kept;
  await _showIconCard(
    context,
    _IconCardSheet(
      choice: choice,
      title: shape == PlantShape.bloom ? s.plantBloomedTitle : s.plantGrewTitle,
      body: s.plantGrewBody(days),
      footnote: next == null
          ? null
          : s.appIconNextShape(next.labelInSentence(s), next.daysNeeded - days),
      onShown: () => growth.markCelebrated(shape),
    ),
  );
}

Future<void> _showIconCard(BuildContext context, _IconCardSheet card) =>
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      // Sized by its content, not the default 9/16 cap, which cut the card's
      // buttons off on a short phone (an iPhone SE's 667pt gives 375).
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => card,
    );

/// Both cards: the icon, what happened, «استخدمها» and «بعدين».
class _IconCardSheet extends ConsumerStatefulWidget {
  const _IconCardSheet({
    required this.choice,
    required this.title,
    required this.body,
    this.footnote,
    this.leavesTheme = false,
    required this.onShown,
  });

  /// What «استخدمها» puts on the phone.
  final AppIconChoice choice;
  final String title;
  final String body;

  /// A smaller line under [body]: what is next, when something is.
  final String? footnote;

  /// Whether «استخدمها» also turns «مع المظهر» off.
  final bool leavesTheme;

  /// Records the card as seen; see [maybeShowIconCard] for why this waits
  /// for the card to exist.
  final Future<void> Function() onShown;

  @override
  ConsumerState<_IconCardSheet> createState() => _IconCardSheetState();
}

class _IconCardSheetState extends ConsumerState<_IconCardSheet> {
  @override
  void initState() {
    super.initState();
    // After the first frame: the card is on screen by then, and a provider
    // may not change while the tree is still building.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => unawaited(widget.onShown()));
  }

  void _use() {
    HapticFeedback.selectionClick();
    // Both read now: this sheet, and its ref with it, is gone once it pops.
    final icons = ref.read(appIconProvider.notifier);
    final prefs = ref.read(appIconPrefsProvider.notifier);
    Navigator.of(context).pop();
    unawaited(() async {
      final ok = await icons.apply(widget.choice);
      if (ok && widget.leavesTheme) await prefs.setFollowTheme(false);
    }());
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final footnote = widget.footnote;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: 24 + MediaQuery.of(context).padding.bottom,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.82,
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 18),
          decoration: BoxDecoration(
            color: gp.surfaceHigh,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: gp.border, width: 0.5),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: gp.border,
                    borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
                  ),
                ),
                const SizedBox(height: 24),
                AppIconArt(choice: widget.choice, size: 104),
                const SizedBox(height: 18),
                Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: gp.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.body,
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(fontSize: 14, height: 1.55, color: gp.textSec),
                ),
                if (footnote != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    footnote,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: gp.textSec),
                  ),
                ],
                const SizedBox(height: 22),
                FilledButton(
                  onPressed: _use,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: Text(s.plantGrewUse),
                ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                    foregroundColor: gp.textSec,
                  ),
                  child: Text(s.plantGrewLater),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

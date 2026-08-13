part of 'profile_screen.dart';


class _LanguageSheet extends ConsumerWidget {
  const _LanguageSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final isAr = ref.watch(localeProvider).languageCode == 'ar';
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        decoration: BoxDecoration(
          color: gp.surfaceHigh,
          borderRadius: BorderRadius.circular(22),
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
                decoration: BoxDecoration(
                  color: gp.border,
                  borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              s.language,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: gp.textPrimary,
              ),
            ),
            const SizedBox(height: 18),
            LanguageOptionCard(
              nativeName: 'English',
              selected: !isAr,
              onTap: () {
                Navigator.pop(context);
                setLocale(ref, const Locale('en'));
              },
            ),
            const SizedBox(height: 10),
            LanguageOptionCard(
              nativeName: 'العربية',
              selected: isAr,
              textDirection: TextDirection.rtl,
              onTap: () {
                Navigator.pop(context);
                setLocale(ref, const Locale('ar'));
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens the app-wide theme preset picker from Settings.
void _showThemePresetSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    // The preset list no longer fits every screen size unscrolled now that
    // there are 7 presets instead of the original 4 — isScrollControlled
    // lets the sheet grow past the default ~half-screen cap, and the
    // Flexible+ScrollView below handles the case where it still doesn't
    // fit (small phones, split-screen, a future 8th/9th preset).
    isScrollControlled: true,
    // See _showLanguageSheet above for why every bottom sheet here sets
    // this — without it the sheet ignores the home-indicator inset.
    useSafeArea: true,
    builder: (ctx) => const _ThemePresetSheet(),
  );
}

class _ThemePresetSheet extends ConsumerWidget {
  const _ThemePresetSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final isAr = s.isAr;
    final selectedId = ref.watch(themePresetProvider);
    final isPremium = ref.watch(premiumProvider);

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.82,
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          decoration: BoxDecoration(
            color: gp.surfaceHigh,
            borderRadius: BorderRadius.circular(22),
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
                  decoration: BoxDecoration(
                    color: gp.border,
                    borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                s.appearanceSheetTitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: gp.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                s.appearancePremiumHint,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: gp.textSec),
              ),
              const SizedBox(height: 18),
              Flexible(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ...ThemePresets.all.map((preset) {
                        final selected = preset.id == selectedId;
                        final locked = preset.isPremium && !isPremium;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _ThemePresetTile(
                            preset: preset,
                            selected: selected,
                            locked: locked,
                            label: isAr ? preset.nameAr : preset.nameEn,
                            onTap: () {
                              if (locked) {
                                Navigator.pop(context);
                                Navigator.pushNamed(context, '/premium');
                                return;
                              }
                              HapticFeedback.selectionClick();
                              ref
                                  .read(themePresetProvider.notifier)
                                  .set(preset.id);
                              Navigator.pop(context);
                            },
                            // Preview works even for locked/premium presets —
                            // trying the look on the real screens is not the
                            // same as unlocking it, so it doesn't need the
                            // premium gate onTap above uses.
                            onPreview: () {
                              HapticFeedback.selectionClick();
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      ThemePreviewScreen(preset: preset),
                                ),
                              );
                            },
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemePresetTile extends StatelessWidget {
  final ThemePreset preset;
  final bool selected;
  final bool locked;
  final String label;
  final VoidCallback onTap;
  final VoidCallback onPreview;

  const _ThemePresetTile({
    required this.preset,
    required this.selected,
    required this.locked,
    required this.label,
    required this.onTap,
    required this.onPreview,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? preset.gold.withOpacity(0.08) : gp.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? preset.gold.withOpacity(0.5) : gp.border,
            width: selected ? 1.2 : 0.5,
          ),
        ),
        child: Row(
          children: [
            // Just the two real hues a preset is built from — xpBlue/
            // streakOrange are only tint/shade "touches" of gold now, so
            // showing them as separate dots would just repeat this one.
            _PresetDot(color: preset.gold, size: 18),
            const SizedBox(width: 5),
            _PresetDot(color: preset.emerald, size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: gp.textPrimary,
                ),
              ),
            ),
            // Nothing to preview for the preset already applied — for
            // every other tile (locked or not) this is a second tap target
            // nested inside the row's own tap target, which Flutter's
            // gesture arena resolves fine as long as this one claims the
            // hit first (HitTestBehavior.opaque).
            if (!selected) ...[
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onPreview,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.visibility_outlined,
                          size: 15, color: gp.textSec),
                      const SizedBox(width: 4),
                      Text(
                        s.preview,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: gp.textSec,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4),
            ],
            if (locked)
              Icon(Icons.lock_rounded, size: 16, color: gp.textTert)
            else if (selected)
              Icon(Icons.check_circle_rounded, size: 18, color: preset.gold),
          ],
        ),
      ),
    );
  }
}

class _PresetDot extends StatelessWidget {
  final Color color;
  final double size;
  const _PresetDot({required this.color, this.size = 12});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// Opens the app-wide font picker from Settings.
void _showFontSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    // See _showLanguageSheet above for why every bottom sheet here sets
    // this — without it the sheet ignores the home-indicator inset.
    useSafeArea: true,
    builder: (ctx) => const _FontSheet(),
  );
}

class _FontSheet extends ConsumerWidget {
  const _FontSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final selected = ref.watch(appFontProvider);

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        decoration: BoxDecoration(
          color: gp.surfaceHigh,
          borderRadius: BorderRadius.circular(22),
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
                decoration: BoxDecoration(
                  color: gp.border,
                  borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              s.appFontSheetTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: gp.textPrimary,
              ),
            ),
            const SizedBox(height: 18),
            ...AppFont.values.map((font) {
              final isSelected = font == selected;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _FontTile(
                  font: font,
                  selected: isSelected,
                  onTap: () {
                    if (isSelected) {
                      Navigator.pop(context);
                      return;
                    }
                    HapticFeedback.selectionClick();
                    ref.read(appFontProvider.notifier).set(font);
                    Navigator.pop(context);
                  },
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _FontTile extends StatelessWidget {
  final AppFont font;
  final bool selected;
  final VoidCallback onTap;

  const _FontTile({
    required this.font,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    // Rendered in the candidate font itself — regardless of which one is
    // currently active — so the tile doubles as a live preview, the same
    // idea as the comparison shown in chat before this got wired up.
    final sampleStyle = GoogleFonts.getFont(
      font.googleFontsFamily,
      fontSize: 17,
      fontWeight: FontWeight.w700,
      color: gp.textPrimary,
      height: 1.4,
    );
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? GameColors.gold.withOpacity(0.08) : gp.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? GameColors.gold.withOpacity(0.5) : gp.border,
            width: selected ? 1.2 : 0.5,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(font.label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: gp.textSec,
                      )),
                  const SizedBox(height: 6),
                  Text('المشي 10 دقائق',
                      textDirection: TextDirection.rtl, style: sampleStyle),
                  const SizedBox(height: 2),
                  Text('Walk 10 minutes', style: sampleStyle.copyWith(fontSize: 14)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (selected)
              Icon(Icons.check_circle_rounded, size: 18, color: GameColors.gold),
          ],
        ),
      ),
    );
  }
}

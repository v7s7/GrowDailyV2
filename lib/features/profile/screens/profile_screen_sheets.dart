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
    final isPremium = ref.watch(premiumAccessProvider);

    // One tile builder for both sections, so free and premium rows are
    // provably the same control rather than two copies that drift.
    Widget buildPresetTile(ThemePreset preset) {
      final locked = preset.isPremium && !isPremium;
      return _ThemePresetTile(
        preset: preset,
        selected: preset.id == selectedId,
        locked: locked,
        label: isAr ? preset.nameAr : preset.nameEn,
        onTap: () {
          if (locked) {
            Navigator.pop(context);
            _openPremiumForAppearance(context);
            return;
          }
          HapticFeedback.selectionClick();
          ref.read(themePresetProvider.notifier).set(preset.id);
          Navigator.pop(context);
        },
        // Preview works even for locked presets — trying a look on the real
        // screens is not the same as unlocking it, so it doesn't need the
        // premium gate onTap uses. It is also the best argument for paying.
        onPreview: () {
          HapticFeedback.selectionClick();
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ThemePreviewScreen(preset: preset),
            ),
          );
        },
      );
    }

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
                      // Free first. A free user should meet what they
                      // already have before what they cannot have, and with
                      // only two of them nobody has to scroll to find one.
                      _ThemeSectionLabel(s.themeSectionFree),
                      const SizedBox(height: 10),
                      ...ThemePresets.free.map(
                        (preset) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: buildPresetTile(preset),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // The custom theme sits between the two groups rather
                      // than at the end of a list of twelve: it is the only
                      // entry that is not a look but a LOOK-MAKER, and buried
                      // as item twelve nobody would ever find it.
                      _CustomThemeCard(
                        locked: !isPremium,
                        selected: selectedId == ThemePresets.customId,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          Navigator.pop(context);
                          if (!isPremium) {
                            _openPremiumForAppearance(context);
                            return;
                          }
                          showCustomThemeSheet(context);
                        },
                      ),
                      const SizedBox(height: 18),
                      _ThemeSectionLabel(s.themeSectionPremium),
                      const SizedBox(height: 10),
                      ...ThemePresets.premium.map(
                        (preset) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: buildPresetTile(preset),
                        ),
                      ),
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



/// Opens the paywall knowing the user came from a colour, so it leads with
/// the colour benefit instead of habit limits.
void _openPremiumForAppearance(BuildContext context) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => const PremiumScreen(
        reason: PremiumReason.appearance,
        source: 'theme_picker',
      ),
    ),
  );
}

// ─── Custom theme: the user's own two colours ────────────────────────────────

void showCustomThemeSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _CustomThemeSheet(),
  );
}

class _CustomThemeSheet extends ConsumerStatefulWidget {
  const _CustomThemeSheet();

  @override
  ConsumerState<_CustomThemeSheet> createState() => _CustomThemeSheetState();
}

class _CustomThemeSheetState extends ConsumerState<_CustomThemeSheet> {
  late Color _accent = ThemePresets.customAccent;
  late Color _grid = ThemePresets.customGrid;

  /// Which of the two roles every control below is currently setting.
  int _role = 0;

  /// False shows the 48 curated swatches, true the free hue/shade picker.
  ///
  /// Starts on the palette on purpose. It is the faster path, it is the one
  /// that was already here, and a user who only wants "a nice green" should
  /// never have to meet a saturation gradient to get one.
  bool _freePicker = false;

  /// HSV of the colour the picker is currently on, kept as three doubles
  /// rather than derived from [_roleColour] on every build: a colour that
  /// has been through the readability guard no longer round-trips (that is
  /// the entire point of the guard), so reading the thumb position back off
  /// the stored colour would make the thumb jump out from under the finger
  /// the moment a drag crossed the band edge.
  late double _hue;
  late double _sat;
  late double _val;

  late final TextEditingController _hexCtrl;
  late final FocusNode _hexFocus;

  /// Set to true only while this class is writing the hex field itself, so
  /// [_onHexChanged] can tell a programmatic write from a keystroke.
  bool _writingHex = false;

  @override
  void initState() {
    super.initState();
    final hsv = argbToHsv(_roleColour.value);
    _hue = hsv.$1;
    _sat = hsv.$2;
    _val = hsv.$3;
    _hexCtrl = TextEditingController(text: _hexOf(_roleColour));
    _hexFocus = FocusNode()..addListener(_onHexFocusChange);
  }

  @override
  void dispose() {
    _hexFocus.removeListener(_onHexFocusChange);
    _hexFocus.dispose();
    _hexCtrl.dispose();
    super.dispose();
  }

  Color get _roleColour => _role == 0 ? _accent : _grid;

  static String _hexOf(Color c) =>
      c.value.toRadixString(16).substring(2).toUpperCase();

  /// Applies [raw] to the active role, after the readability guard has had
  /// its say.
  ///
  /// [typed] exists for one reason: the hex field must not have its text
  /// replaced while somebody is typing into it. Rewriting it moves the
  /// caret, and a caret that jumps on the sixth character makes the field
  /// unusable. Everything else about a typed colour behaves normally, the
  /// picker's thumb included, so what the user sees is their own six
  /// characters over a picker and an app that have both already moved to
  /// the colour those characters produced.
  void _apply(Color raw, {bool typed = false, bool persist = true}) {
    final fitted = _role == 0 ? fitAccentColour(raw) : fitGridColour(raw);
    setState(() {
      if (_role == 0) {
        _accent = fitted;
      } else {
        _grid = fitted;
      }
      _seedHsvFrom(fitted);
      if (!typed) _syncHexField(fitted);
    });
    final notifier = ref.read(themePresetProvider.notifier);
    if (persist) {
      notifier.setCustom(accent: _accent, grid: _grid);
    } else {
      notifier.previewCustom(accent: _accent, grid: _grid);
    }
  }

  /// Writes down whatever the last preview left in place. Called when a drag
  /// ends, which is the moment the pair stops being a guess.
  void _commit() {
    ref
        .read(themePresetProvider.notifier)
        .setCustom(accent: _accent, grid: _grid);
  }

  /// Moves the picker's three doubles onto [c].
  ///
  /// Hue is held back when [c] has no saturation worth speaking of. A grey
  /// carries no hue, [argbToHsv] reports one anyway, and taking that reading
  /// literally throws away the hue the user chose the instant a drag reaches
  /// the grey edge of the saturation field, which they are usually about to
  /// drag straight back out of.
  ///
  /// The threshold is 0.04 rather than something near zero because of where
  /// the number comes from. On a near-grey the channels sit a COUNT or two
  /// apart out of 255, so the hue computed from them is quantisation noise
  /// with a number attached: 0xFF757676 reports saturation 0.008 and a hue
  /// nowhere near the blue it was dragged from, which on the device showed
  /// up as the hue bar jumping from blue to cyan on its own. 0.04 is about
  /// ten counts of spread, which is the point where a hue reading starts
  /// meaning something.
  void _seedHsvFrom(Color c) {
    final hsv = argbToHsv(c.value);
    if (hsv.$2 > 0.04) _hue = hsv.$1;
    _sat = hsv.$2;
    _val = hsv.$3;
  }

  void _syncHexField(Color c) {
    final text = _hexOf(c);
    if (_hexCtrl.text == text) return;
    _writingHex = true;
    _hexCtrl.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _writingHex = false;
  }

  void _onHexChanged(String text) {
    if (_writingHex) return;
    final cleaned = text.replaceAll('#', '').trim();
    if (cleaned.length != 6) return;
    final parsed = int.tryParse(cleaned, radix: 16);
    if (parsed == null) return;
    HapticFeedback.selectionClick();
    _apply(Color(0xFF000000 | parsed), typed: true);
  }

  /// Selects the whole code on focus, and catches the field up to what is
  /// actually stored on blur.
  ///
  /// The select-on-focus half is not a nicety. This field is never empty:
  /// it always shows the colour currently in use, which is always exactly
  /// six characters, which is also its maxLength. So without selecting,
  /// every keystroke a user types is REJECTED until they have manually
  /// deleted six characters first, and the field simply appears not to work.
  /// Selecting on focus makes the first keystroke replace the lot, which is
  /// what a hex field is expected to do anyway.
  ///
  /// The blur half is the reconciliation described in [_apply]: until focus
  /// leaves, the field shows what they asked for and the note explains what
  /// is being used instead.
  void _onHexFocusChange() {
    if (_hexFocus.hasFocus) {
      _hexCtrl.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _hexCtrl.text.length,
      );
      return;
    }
    setState(() {
      _syncHexField(_roleColour);
      _seedHsvFrom(_roleColour);
    });
  }

  void _setRole(int role) {
    if (role == _role) return;
    HapticFeedback.selectionClick();
    setState(() {
      _role = role;
      _seedHsvFrom(_roleColour);
      _syncHexField(_roleColour);
    });
  }

  /// The finger's position is read fresh every event and never fed back from
  /// the thumb, so the wall described in [_apply] cannot turn into a feedback
  /// loop: the thumb always shows fitted(finger), and the finger is free to
  /// keep travelling past the edge without dragging the thumb further with it.
  void _onSatValDrag(Offset local, Size size) {
    final sat = (local.dx / size.width).clamp(0.0, 1.0);
    final val = (1 - local.dy / size.height).clamp(0.0, 1.0);
    _apply(
      fitPickerColour(hue: _hue, sat: sat, val: val, accent: _role == 0),
      persist: false,
    );
  }

  void _onHueDrag(double dx, double width) {
    final hue = (dx / width).clamp(0.0, 1.0) * 360;
    _apply(
      fitPickerColour(hue: hue, sat: _sat, val: _val, accent: _role == 0),
      persist: false,
    );
  }


  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final saved = ref.watch(savedThemeColoursProvider);
    final active = _roleColour;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: 24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 22),
          decoration: BoxDecoration(
            color: gp.surfaceHigh,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: gp.border, width: 0.5),
          ),
          child: SingleChildScrollView(
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
                      borderRadius:
                          BorderRadius.circular(GameSpacing.pillRadius),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  s.themeCustomTitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: gp.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  s.themeCustomHint,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: gp.textSec),
                ),
                const SizedBox(height: 14),
                // The single most important addition. The whole feature is
                // "pick two colours and twenty-six more are derived from
                // them", and until this strip existed none of that
                // derivation was visible: the sheet covers the screen it
                // claims to be previewing, so "the app behind it is the
                // preview" was true only for the strip of it still showing.
                _ThemePreviewStrip(accent: _accent, grid: _grid),
                const SizedBox(height: 14),
                _RoleTabs(
                  labels: [s.themeCustomAccent, s.themeCustomGrid],
                  colors: [_accent, _grid],
                  selected: _role,
                  onChanged: _setRole,
                ),
                const SizedBox(height: 8),
                Text(
                  _role == 0 ? s.themeCustomAccentHint : s.themeCustomGridHint,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11.5, color: gp.textTert),
                ),
                const SizedBox(height: 14),
                _SavedColourRow(
                  saved: saved,
                  active: active,
                  onPick: (c) {
                    HapticFeedback.selectionClick();
                    _apply(c);
                  },
                  onSave: () {
                    HapticFeedback.mediumImpact();
                    ref
                        .read(savedThemeColoursProvider.notifier)
                        .add(active, asAccent: _role == 0);
                  },
                  onRemove: (c) {
                    HapticFeedback.mediumImpact();
                    ref.read(savedThemeColoursProvider.notifier).remove(c);
                  },
                ),
                const SizedBox(height: 14),
                _ModeTabs(
                  labels: [s.themeCustomTabPalette, s.themeCustomTabPicker],
                  selected: _freePicker ? 1 : 0,
                  onChanged: (i) {
                    HapticFeedback.selectionClick();
                    setState(() => _freePicker = i == 1);
                  },
                ),
                const SizedBox(height: 14),
                if (_freePicker)
                  _HsvPicker(
                    hue: _hue,
                    sat: _sat,
                    val: _val,
                    onSatVal: _onSatValDrag,
                    onHue: _onHueDrag,
                    onRelease: _commit,
                  )
                else
                  _PaletteGrid(
                    active: active,
                    onPick: (c) {
                      HapticFeedback.selectionClick();
                      _apply(c);
                    },
                  ),
                const SizedBox(height: 14),
                _HexField(
                  controller: _hexCtrl,
                  focusNode: _hexFocus,
                  swatch: active,
                  onChanged: _onHexChanged,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(s.themeCustomDone),
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

/// A live sample of the theme the two chosen colours actually produce.
///
/// Builds a real [ThemePreset.custom] rather than approximating one, so this
/// cannot drift from what the app will look like: every colour drawn here is
/// read off the same object [GameColors.applyPreset] is handed. That is also
/// why it shows STRUCTURE (a background, a card on it, body text) and not
/// just two circles. The two colours a user picks are the only two they
/// choose; the eighteen structural neutrals derived from them are the ones
/// that decide whether the app is pleasant to look at, and they were
/// previously invisible until after the sheet closed.
class _ThemePreviewStrip extends StatelessWidget {
  final Color accent;
  final Color grid;

  const _ThemePreviewStrip({required this.accent, required this.grid});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final p = ThemePreset.custom(
      id: 'preview',
      nameEn: 'preview',
      nameAr: 'preview',
      accent: accent,
      grid: grid,
    );

    final bg = dark ? p.darkBg : p.lightBg;
    final surface = dark ? p.darkSurface : p.lightSurface;
    final border = dark ? p.darkBorder : p.lightBorder;
    final empty = dark ? p.darkSurfaceHighlight : p.lightSurfaceHL;
    final textPrimary = dark ? p.darkTextPrimary : p.lightTextPrimary;
    final textSec = dark ? p.darkTextSecondary : p.lightTextSecondary;
    // Exactly what game_theme.dart's filledButtonTheme does: the label on an
    // accent fill is dark in BOTH themes. Reproducing that rule here rather
    // than picking something readable is the whole point, because this strip
    // is what tells a user their button label is about to disappear.
    final onAccent = dark ? p.darkBg : p.lightTextPrimary;

    return AnimatedContainer(
      duration: GameMotion.quick,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border, width: 0.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          s.themeCustomPreview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: textPrimary,
                          ),
                        ),
                      ),
                      for (var i = 0; i < 5; i++) ...[
                        if (i > 0) const SizedBox(width: 3),
                        Container(
                          width: 11,
                          height: 11,
                          decoration: BoxDecoration(
                            color: i < 3 ? grid : empty,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(
                    s.themeCustomPreviewHabit,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 9.5, color: textSec),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              s.themeCustomPreviewAction,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: onAccent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The user's own shortlist, with the button that fills it.
///
/// The add button leads rather than trails, so its position never moves as
/// colours accumulate: it is the only control here that is always in the
/// same place, and a row that can scroll would otherwise be able to push it
/// out of reach. Removal is a long press, because a visible delete affordance
/// on ten swatches is more chrome than the whole row is worth.
class _SavedColourRow extends StatelessWidget {
  final List<Color> saved;
  final Color active;
  final ValueChanged<Color> onPick;
  final VoidCallback onSave;
  final ValueChanged<Color> onRemove;

  const _SavedColourRow({
    required this.saved,
    required this.active,
    required this.onPick,
    required this.onSave,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final alreadySaved = saved.any((c) => c.value == active.value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              s.themeCustomSaved.toUpperCase(),
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
                color: gp.textTert,
              ),
            ),
            const Spacer(),
            Text(
              saved.isEmpty
                  ? s.themeCustomSavedEmpty
                  : (saved.length >= kMaxSavedColours
                      ? s.themeCustomSavedFull
                      : s.themeCustomSavedTapHint),
              style: TextStyle(fontSize: 10.5, color: gp.textTert),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 38,
          child: ListView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            children: [
              Semantics(
                button: true,
                label: s.themeCustomSaveTooltip,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: alreadySaved ? null : onSave,
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: gp.surface,
                      borderRadius:
                          BorderRadius.circular(GameSpacing.buttonRadius),
                      border: Border.all(color: gp.border, width: 1),
                    ),
                    child: Icon(
                      Icons.add_rounded,
                      size: 19,
                      // Dimmed rather than hidden when the active colour is
                      // already on the list: the button vanishing under the
                      // finger as you move through the palette would be far
                      // more confusing than a button that quietly does
                      // nothing.
                      color: alreadySaved ? gp.textTert : gp.textSec,
                    ),
                  ),
                ),
              ),
              for (final c in saved) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onPick(c),
                  onLongPress: () => onRemove(c),
                  child: AnimatedContainer(
                    duration: GameMotion.quick,
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: c,
                      borderRadius:
                          BorderRadius.circular(GameSpacing.buttonRadius),
                      border: Border.all(
                        color: c.value == active.value
                            ? gp.textPrimary
                            : gp.border,
                        width: c.value == active.value ? 2.4 : 0.5,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Plain two-segment switch for palette versus free picker.
///
/// Separate from [_RoleTabs] rather than a flag on it: that one's segments
/// each carry a colour swatch, which is load-bearing there (it is the only
/// place the OTHER role's colour is visible) and meaningless here.
class _ModeTabs extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;

  const _ModeTabs({
    required this.labels,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: gp.surfaceHL,
        borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
        border: Border.all(color: gp.border, width: 0.5),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: i == selected ? null : () => onChanged(i),
                child: AnimatedContainer(
                  duration: GameMotion.relaxed,
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  decoration: BoxDecoration(
                    color: i == selected
                        ? gp.surfaceHigh
                        : Colors.transparent,
                    borderRadius:
                        BorderRadius.circular(GameSpacing.pillRadius),
                  ),
                  child: Text(
                    labels[i],
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          i == selected ? FontWeight.w800 : FontWeight.w600,
                      color: i == selected ? gp.textPrimary : gp.textSec,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The 27 curated swatches, nine hues across and three tones down.
///
/// The tap target fills its whole grid cell and the visible square is inset
/// inside it, rather than the square itself being the target. That is worth
/// stating because the arithmetic does not allow the usual answer: a 44pt
/// target across nine columns needs 396pt of content width and this sheet
/// has 330, so no honest layout reaches the guideline here. Taking the
/// whole cell gets the target to about 36pt instead of the 29pt the painted
/// square would give, and the two paths that are NOT a dense grid, the
/// saved-colour row at 38pt and the free picker's drag surface, are both
/// deliberately larger.
class _PaletteGrid extends StatelessWidget {
  final Color active;
  final ValueChanged<Color> onPick;

  const _PaletteGrid({required this.active, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var tone = 0; tone < kCustomSwatches.length; tone++)
          Row(
            children: [
              for (var i = 0; i < kCustomSwatches[tone].length; i++)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onPick(kCustomSwatches[tone][i]),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: _HueSwatch(
                        color: kCustomSwatches[tone][i],
                        selected:
                            kCustomSwatches[tone][i].value == active.value,
                      ),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

/// Hue bar plus a saturation/brightness field, the same two controls (and
/// the same maths) the habit icon picker already uses. Imported rather than
/// re-derived: hsvToArgb/argbToHsv are the one part of colour picking this
/// app had already solved, and a second copy of them would be a second copy
/// to get subtly wrong.
///
/// Everything positional in here is deliberately NON-directional
/// (Alignment.centerLeft, Positioned.left) while the rest of this file is
/// carefully directional. A gradient is not text: red does not belong on the
/// right in Arabic. More concretely, the drag handlers read
/// `localPosition.dx`, which is measured from the physical left edge whatever
/// the text direction is, so mirroring only the PAINT would leave the thumb
/// on the opposite side of the field from the finger that is dragging it.
class _HsvPicker extends StatelessWidget {
  final double hue;
  final double sat;
  final double val;
  final void Function(Offset local, Size size) onSatVal;
  final void Function(double dx, double width) onHue;

  /// Fired when a drag finishes, so the sheet can persist once instead of
  /// once per frame. Both cancel and end route here: a drag interrupted by
  /// an incoming call still leaves the colour it landed on applied, and that
  /// colour has to survive the app being killed while that call is answered.
  final VoidCallback onRelease;

  const _HsvPicker({
    required this.hue,
    required this.sat,
    required this.val,
    required this.onSatVal,
    required this.onHue,
    required this.onRelease,
  });

  @override
  Widget build(BuildContext context) {
    final current = Color(hsvToArgb(hue, sat, val));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(constraints.maxWidth, 156);
              return GestureDetector(
                onPanDown: (d) => onSatVal(d.localPosition, size),
                onPanUpdate: (d) => onSatVal(d.localPosition, size),
                onPanEnd: (_) => onRelease(),
                onPanCancel: onRelease,
                child: SizedBox(
                  width: size.width,
                  height: size.height,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            // Non-directional on purpose: see the class doc.
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              Colors.white,
                              Color(hsvToArgb(hue, 1, 1)),
                            ],
                          ),
                        ),
                      ),
                      Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.black],
                          ),
                        ),
                      ),
                      Positioned(
                        left: (sat * size.width) - 9,
                        top: ((1 - val) * size.height) - 9,
                        child: _PickerThumb(color: current),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 13),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return GestureDetector(
              onPanDown: (d) => onHue(d.localPosition.dx, width),
              onPanUpdate: (d) => onHue(d.localPosition.dx, width),
              onPanEnd: (_) => onRelease(),
              onPanCancel: onRelease,
              child: SizedBox(
                width: width,
                height: 26,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      height: 14,
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(7),
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            for (var i = 0; i <= 360; i += 60)
                              Color(hsvToArgb(i.toDouble(), 1, 1)),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: (hue / 360 * width) - 9,
                      top: -2,
                      child: _PickerThumb(color: Color(hsvToArgb(hue, 1, 1))),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _PickerThumb extends StatelessWidget {
  final Color color;
  const _PickerThumb({required this.color});

  @override
  Widget build(BuildContext context) => Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2.5),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 4),
          ],
        ),
      );
}

/// The hex field, which is both the input and the readout.
///
/// Always visible, in both modes, because it is the only control in the
/// sheet that names the colour rather than gesturing at it: a user who
/// tapped a swatch and now wants to write that colour down needs it as much
/// as the one who came here to type one in.
class _HexField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final Color swatch;
  final ValueChanged<String> onChanged;

  const _HexField({
    required this.controller,
    required this.focusNode,
    required this.swatch,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(GameSpacing.buttonRadius),
        border: Border.all(color: gp.border, width: 0.5),
      ),
      child: Row(
        children: [
          AnimatedContainer(
            duration: GameMotion.quick,
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: swatch,
              borderRadius: BorderRadius.circular(GameSpacing.chipRadius),
              border: Border.all(color: gp.border, width: 0.5),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '#',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: gp.textTert,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              onChanged: onChanged,
              textCapitalization: TextCapitalization.characters,
              maxLength: 6,
              // Always LTR: a hex code is not text in either language, and
              // in an Arabic build an RTL field renders "E4B45F" with its
              // caret and its characters running the wrong way.
              textDirection: TextDirection.ltr,
              // ...but the field still has to sit against the "#" that
              // labels it, and in Arabic the "#" is on the RIGHT. Left
              // alignment there strands the code at the far side of the row
              // with a hand's width of nothing between it and its own
              // prefix. So the CHARACTERS stay LTR and only the BLOCK of
              // them follows the sheet's direction.
              textAlign: Directionality.of(context) == TextDirection.rtl
                  ? TextAlign.right
                  : TextAlign.left,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F]')),
                // Upper-cased as it is typed. textCapitalization is only a
                // hint to the on-screen keyboard: it does nothing to a
                // hardware keystroke, a paste, or the lower-case half of a
                // code somebody half-typed, so without this the field
                // happily displays "8b5A2B". It is a readout as much as an
                // input, and a readout should not be shouting and whispering
                // in the same six characters. Upper-casing cannot change the
                // length, so the caret and any selection survive it.
                TextInputFormatter.withFunction(
                  (_, next) => next.copyWith(text: next.text.toUpperCase()),
                ),
              ],
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
                color: gp.textPrimary,
              ),
              decoration: InputDecoration(
                counterText: '',
                isDense: true,
                isCollapsed: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: s.hexCode,
                hintStyle: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0,
                  color: gp.textTert,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Two segments, each showing the colour it currently holds.
///
/// Styled to match [SegmentedTabs] rather than reusing it, because that one
/// takes plain labels and the whole point here is that a segment carries a
/// swatch: without it there is nowhere to see what the OTHER role is set to
/// while you are editing this one.
class _RoleTabs extends StatelessWidget {
  final List<String> labels;
  final List<Color> colors;
  final int selected;
  final ValueChanged<int> onChanged;

  const _RoleTabs({
    required this.labels,
    required this.colors,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: gp.surfaceHL,
        borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
        border: Border.all(color: gp.border, width: 0.5),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: i == selected ? null : () => onChanged(i),
                child: AnimatedContainer(
                  duration: GameMotion.relaxed,
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: i == selected
                        ? colors[i].withOpacity(0.18)
                        : Colors.transparent,
                    borderRadius:
                        BorderRadius.circular(GameSpacing.pillRadius),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: colors[i],
                          shape: BoxShape.circle,
                          border: Border.all(color: gp.border, width: 0.5),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          labels[i],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: i == selected
                                ? FontWeight.w800
                                : FontWeight.w600,
                            color:
                                i == selected ? gp.textPrimary : gp.textSec,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One square in the palette. Purely visual: the tap is owned by
/// [_PaletteGrid], which wraps this in a target that fills the whole grid
/// cell rather than only the part of it that is painted.
class _HueSwatch extends StatelessWidget {
  final Color color;
  final bool selected;

  const _HueSwatch({required this.color, required this.selected});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return AspectRatio(
      aspectRatio: 1,
      child: AnimatedContainer(
        duration: GameMotion.quick,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(GameSpacing.buttonRadius),
          // The ring is the surface colour and the tick sits inside it, so
          // selection reads on a swatch of any hue without having to know
          // whether that hue is light or dark.
          border: Border.all(
            color: selected ? gp.textPrimary : gp.border,
            width: selected ? 2.4 : 0.5,
          ),
        ),
        child: selected
            ? Center(
                child:
                    Icon(Icons.check_rounded, size: 17, color: gp.surfaceHigh),
              )
            : null,
      ),
    );
  }
}

/// A quiet group heading. Two of these turn a flat list of twelve into "what
/// you have" and "what you could have", which is the whole reason the sheet
/// felt long rather than the number of rows in it.
class _ThemeSectionLabel extends StatelessWidget {
  final String text;
  const _ThemeSectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 2),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
          color: gp.textTert,
        ),
      ),
    );
  }
}

/// The custom theme, presented as an offer rather than a list item.
///
/// It shows the actual palette rather than describing it: a strip of real
/// swatches from [kCustomSwatches] is the only honest way to say "any two of
/// these", and it is a far better advert than a lock icon and a name.
///
/// The strip ends in a dashed "#" tile, which is the entire change this card
/// needed once a hex field existed: these 48, plus anything. The card used to
/// close on a combination count (48 squared, spelled out), and that number
/// was exactly right until the moment a user could type a colour that is not
/// in the table. A precise wrong number in a paid pitch is worse than no
/// number, so it was replaced rather than recalculated: the honest new figure
/// runs to fifteen digits and says nothing to anybody.
class _CustomThemeCard extends StatelessWidget {
  final bool locked;
  final bool selected;
  final VoidCallback onTap;

  const _CustomThemeCard({
    required this.locked,
    required this.selected,
    required this.onTap,
  });

  /// One representative swatch per hue, taken from the middle row, so the
  /// strip reads as "all the colours" at a glance. The middle row rather
  /// than the last one because the last is now the palest of the three, and
  /// a row of tints is a weak advert for a paid feature.
  static List<Color> get _strip => kCustomSwatches[1];

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    // Arabic-Indic when the rest of the card is: "٤٨ لونًا" beside a Western
    // "48" in the same card is the kind of mix that reads as a bug.
    final count = kCustomSwatchesFlat.length;
    final readyMade = s.isAr ? arabicDigits(count) : '$count';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        decoration: BoxDecoration(
          color: selected
              ? GameColors.gold.withOpacity(0.10)
              : gp.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: GameColors.gold.withOpacity(selected ? 0.55 : 0.30),
            width: selected ? 1.2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.palette_rounded, size: 17, color: GameColors.gold),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    s.themeCustomTitle,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: gp.textPrimary,
                    ),
                  ),
                ),
                if (locked)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: GameColors.gold.withOpacity(0.16),
                      borderRadius:
                          BorderRadius.circular(GameSpacing.pillRadius),
                    ),
                    child: Text(
                      'Premium',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: GameColors.gold,
                      ),
                    ),
                  )
                else if (selected)
                  Icon(Icons.check_circle_rounded,
                      size: 18, color: GameColors.gold),
              ],
            ),
            const SizedBox(height: 9),
            Text(
              s.themeCustomPitch,
              style: TextStyle(fontSize: 12, color: gp.textSec, height: 1.35),
            ),
            const SizedBox(height: 12),
            // The palette itself, not a description of it, and then the
            // one tile that is not a colour: everything the table does not
            // contain, which is now most of what the feature offers.
            Row(
              children: [
                for (var i = 0; i < _strip.length; i++) ...[
                  if (i > 0) const SizedBox(width: 5),
                  Expanded(
                    child: Container(
                      height: 22,
                      decoration: BoxDecoration(
                        color: _strip[i],
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 5),
                Expanded(
                  child: Container(
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: gp.border, width: 1),
                    ),
                    child: Text(
                      '#',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: gp.textSec,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  s.themeCustomReadyMade(readyMade),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: GameColors.gold,
                  ),
                ),
                const Spacer(),
                Icon(
                  // chevron_RIGHT, matching the other nineteen trailing
                  // "go" chevrons in this app. It carries
                  // matchTextDirection, so it renders > at the row's end in
                  // English and < at the row's end in Arabic: pointing
                  // outward, away from the label, in both. chevron_left was
                  // pointing back INTO its own text, in both languages.
                  locked ? Icons.lock_rounded : Icons.chevron_right_rounded,
                  size: 15,
                  color: gp.textTert,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

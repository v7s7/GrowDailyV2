import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../widgets/language_option_card.dart';

/// First-launch language picker. Shown once per device (see `_LanguageGate`
/// in main.dart) before the auth/grid flow, so it deliberately doesn't use
/// [S] — the locale hasn't been chosen yet — and shows both supported
/// languages' own copy side by side instead.
class LanguagePickerScreen extends ConsumerStatefulWidget {
  const LanguagePickerScreen({super.key});

  @override
  ConsumerState<LanguagePickerScreen> createState() =>
      _LanguagePickerScreenState();
}

class _LanguagePickerScreenState extends ConsumerState<LanguagePickerScreen> {
  String? _selecting;

  Future<void> _choose(String code) async {
    if (_selecting != null) return;
    HapticFeedback.selectionClick();
    setState(() => _selecting = code);
    await Future.delayed(const Duration(milliseconds: 420));
    if (!mounted) return;
    await setLocale(ref, Locale(code));
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Scaffold(
      backgroundColor: gp.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.translate_rounded,
                        size: 52, color: GameColors.gold)
                    .animate()
                    .fadeIn(duration: 500.ms)
                    .scale(
                      begin: const Offset(0.7, 0.7),
                      end: const Offset(1, 1),
                      curve: Curves.easeOutBack,
                      duration: 500.ms,
                    ),
                const SizedBox(height: 24),
                Text(
                  'Choose your language',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: gp.textPrimary,
                  ),
                ).animate(delay: 150.ms).fadeIn(duration: 450.ms).slideY(
                    begin: 0.2, end: 0, curve: Curves.easeOut),
                const SizedBox(height: 6),
                Directionality(
                  textDirection: TextDirection.rtl,
                  child: Text(
                    'اختر لغتك',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: gp.textSec,
                    ),
                  ),
                ).animate(delay: 230.ms).fadeIn(duration: 450.ms).slideY(
                    begin: 0.2, end: 0, curve: Curves.easeOut),
                const SizedBox(height: 44),
                LanguageOptionCard(
                  nativeName: 'English',
                  selected: _selecting == 'en',
                  dimmed: _selecting != null && _selecting != 'en',
                  onTap: () => _choose('en'),
                ).animate(delay: 340.ms).fadeIn(duration: 450.ms).slideY(
                    begin: 0.15, end: 0, curve: Curves.easeOut),
                const SizedBox(height: 14),
                LanguageOptionCard(
                  nativeName: 'العربية',
                  selected: _selecting == 'ar',
                  dimmed: _selecting != null && _selecting != 'ar',
                  textDirection: TextDirection.rtl,
                  onTap: () => _choose('ar'),
                ).animate(delay: 420.ms).fadeIn(duration: 450.ms).slideY(
                    begin: 0.15, end: 0, curve: Curves.easeOut),
                const SizedBox(height: 28),
                Text(
                  'You can change this later in Settings\nيمكنك تغييره لاحقًا من الإعدادات',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.6,
                    color: gp.textTert,
                  ),
                ).animate(delay: 600.ms).fadeIn(duration: 450.ms),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

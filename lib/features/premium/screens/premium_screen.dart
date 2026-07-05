import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/services/analytics_service.dart';
import '../../../core/theme/game_theme.dart';
import '../notifiers/premium_notifier.dart';

/// The GrowDaily Premium paywall.
///
/// Purchase flow: this screen is intentionally store-agnostic. When the
/// in_app_purchase (or RevenueCat) SDK is wired, replace [_startPurchase]
/// with the real flow and call `premiumProvider.notifier.activate()` on a
/// verified transaction. Until then the CTA is honest about availability
/// and tracks intent so launch pricing can be data-informed.
class PremiumScreen extends ConsumerStatefulWidget {
  const PremiumScreen({super.key});

  @override
  ConsumerState<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends ConsumerState<PremiumScreen> {
  bool _yearly = true;

  void _startPurchase() {
    HapticFeedback.mediumImpact();
    AnalyticsService.instance.track('premium_purchase_intent', props: {
      'plan': _yearly ? 'yearly' : 'monthly',
    });
    // TODO(store): launch the platform purchase flow here and call
    // ref.read(premiumProvider.notifier).activate() once verified.
    final s = S.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(s.premiumComingSoon),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final isPremium = ref.watch(premiumProvider);

    return Scaffold(
      backgroundColor: gp.bg,
      appBar: AppBar(title: Text(s.premiumTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Hero
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      GameColors.gold.withOpacity(gp.dark ? 0.20 : 0.16),
                      gp.surface,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
                  border:
                      Border.all(color: GameColors.gold.withOpacity(0.4)),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: GameColors.gold.withOpacity(0.16),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.workspace_premium_rounded,
                          size: 32, color: GameColors.gold),
                    )
                        .animate()
                        .scale(curve: Curves.elasticOut, duration: 700.ms)
                        .fadeIn(duration: 300.ms),
                    const SizedBox(height: 14),
                    Text(
                      s.premiumHeadline,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: gp.textPrimary,
                        letterSpacing: -0.4,
                        height: 1.2,
                      ),
                    ).animate(delay: 120.ms).fadeIn().slideY(begin: 0.15),
                    const SizedBox(height: 6),
                    Text(
                      s.premiumSubhead,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 13, color: gp.textSec, height: 1.4),
                    ).animate(delay: 180.ms).fadeIn(),
                  ],
                ),
              ),
              const SizedBox(height: 22),

              // Benefits
              ..._benefits(s).asMap().entries.map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _BenefitRow(
                        icon: e.value.$1,
                        title: e.value.$2,
                        desc: e.value.$3,
                      )
                          .animate(delay: (200 + e.key * 70).ms)
                          .fadeIn(duration: 350.ms)
                          .slideX(begin: 0.05),
                    ),
                  ),
              const SizedBox(height: 12),

              if (isPremium)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: GameColors.emerald.withOpacity(0.12),
                    borderRadius:
                        BorderRadius.circular(GameSpacing.cardRadius),
                    border: Border.all(
                        color: GameColors.emerald.withOpacity(0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.verified_rounded,
                          color: GameColors.emerald),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          s.premiumActive,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: GameColors.emerald,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else ...[
                // Plan picker
                Row(
                  children: [
                    Expanded(
                      child: _PlanCard(
                        label: s.premiumMonthly,
                        price: r'$2.99',
                        period: s.premiumPerMonth,
                        selected: !_yearly,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _yearly = false);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _PlanCard(
                        label: s.premiumYearly,
                        price: r'$19.99',
                        period: s.premiumPerYear,
                        badge: s.premiumSave('44%'),
                        selected: _yearly,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _yearly = true);
                        },
                      ),
                    ),
                  ],
                ).animate(delay: 500.ms).fadeIn().slideY(begin: 0.1),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: _startPurchase,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 54),
                  ),
                  child: Text(s.premiumCta),
                ).animate(delay: 580.ms).fadeIn().slideY(begin: 0.2),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    AnalyticsService.instance.track('premium_restore_intent');
                    // TODO(store): restore purchases via the store SDK.
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(s.premiumComingSoon),
                        behavior: SnackBarBehavior.floating,
                        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      ),
                    );
                  },
                  child: Text(s.premiumRestore),
                ),
                const SizedBox(height: 4),
                Text(
                  s.premiumFinePrint,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: gp.textTert),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<(IconData, String, String)> _benefits(S s) => [
        (
          Icons.grid_on_rounded,
          s.premiumBenefitHabitsTitle,
          s.premiumBenefitHabitsDesc,
        ),
        (
          Icons.insights_rounded,
          s.premiumBenefitHistoryTitle,
          s.premiumBenefitHistoryDesc,
        ),
        (
          Icons.family_restroom_rounded,
          s.premiumBenefitFamilyTitle,
          s.premiumBenefitFamilyDesc,
        ),
        (
          Icons.favorite_rounded,
          s.premiumBenefitSupportTitle,
          s.premiumBenefitSupportDesc,
        ),
      ];
}

class _BenefitRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String desc;
  const _BenefitRow(
      {required this.icon, required this.title, required this.desc});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: GameColors.gold.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 20, color: GameColors.gold),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: gp.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style:
                    TextStyle(fontSize: 12.5, color: gp.textSec, height: 1.35),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  final String label;
  final String price;
  final String period;
  final String? badge;
  final bool selected;
  final VoidCallback onTap;

  const _PlanCard({
    required this.label,
    required this.price,
    required this.period,
    this.badge,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? GameColors.gold.withOpacity(0.10) : gp.surface,
          borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
          border: Border.all(
            color: selected ? GameColors.gold : gp.border,
            width: selected ? 1.6 : 0.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: selected ? GameColors.gold : gp.textSec,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: GameColors.emerald.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      badge!,
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: GameColors.emerald,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              price,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: gp.textPrimary,
                letterSpacing: -0.8,
                height: 1,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              period,
              style: TextStyle(fontSize: 11, color: gp.textTert),
            ),
          ],
        ),
      ),
    );
  }
}

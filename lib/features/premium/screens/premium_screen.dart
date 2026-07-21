import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart' show Offering, Package;
import 'package:url_launcher/url_launcher.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/services/analytics_service.dart';
import '../../../core/services/purchase_service.dart';
import '../../../core/theme/game_theme.dart';
import '../notifiers/premium_notifier.dart';

/// Which plan card is selected — monthly (auto-renewing subscription) or
/// lifetime (one-time, non-consumable purchase). Both map to the same
/// RevenueCat entitlement (see PurchaseService.entitlementId), so nothing
/// past this screen ever needs to know which one someone bought.
enum _PlanKind { monthly, lifetime }

/// Apple's standard EULA - used as-is since GrowDaily hasn't set a custom
/// License Agreement in App Store Connect (App Information -> License
/// Agreement). Required reading here regardless: App Store Guideline
/// 3.1.2 requires a functional Terms of Use link on any subscription
/// purchase screen, and if you're relying on the standard EULA, Apple
/// requires this exact link in your App Description too.
const String _termsOfUseUrl =
    'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/';

/// GrowDaily's actual Privacy Policy - published Google Doc. Guideline
/// 3.1.2 requires this alongside the Terms link above. If this ever moves
/// to a custom domain, this is the only line that needs to change.
const String _privacyPolicyUrl =
    'https://docs.google.com/document/d/e/2PACX-1vT1weIyykC2Bdbz6aVMBae9PNtCXoFNdfUnpFZ1Po9A87pseQFOfogWPV4CLytHwolFhVKcaLrw-4aD/pub';

/// The GrowDaily Premium paywall.
///
/// Real purchase flow, backed by RevenueCat (see PurchaseService): this
/// screen fetches the live Offering (real, store-localized prices — never
/// hardcoded strings, since Apple requires the displayed price to match
/// what StoreKit will actually charge), and PremiumScreen itself never
/// decides whether someone is Premium — a successful purchase/restore just
/// updates PurchaseService's CustomerInfo stream, which premiumProvider
/// (and therefore every gate in the app) reacts to on its own. If
/// PurchaseService.isConfigured is still false (see its doc comment for
/// the one-time RevenueCat/App Store Connect setup that only a human with
/// those accounts can do), or the Offering has no usable packages yet,
/// this honestly shows "not available yet" instead of a broken paywall.
class PremiumScreen extends ConsumerStatefulWidget {
  const PremiumScreen({super.key});

  @override
  ConsumerState<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends ConsumerState<PremiumScreen> {
  _PlanKind _selected = _PlanKind.monthly;
  bool _loadingOffering = true;
  Offering? _offering;
  bool _isPurchasing = false;
  bool _isRestoring = false;
  bool _isOpeningCustomerCenter = false;

  @override
  void initState() {
    super.initState();
    _loadOffering();
  }

  Future<void> _loadOffering() async {
    final offering = await PurchaseService.instance.getCurrentOffering();
    if (!mounted) return;
    setState(() {
      _offering = offering;
      _loadingOffering = false;
      // Default to whichever plan actually exists, in case only one of
      // the two was configured — see [_selectedPackage].
      if (offering?.monthly == null && offering?.lifetime != null) {
        _selected = _PlanKind.lifetime;
      }
    });
  }

  Package? get _selectedPackage {
    final offering = _offering;
    if (offering == null) return null;
    return _selected == _PlanKind.monthly ? offering.monthly : offering.lifetime;
  }

  Future<void> _startPurchase() async {
    final package = _selectedPackage;
    if (package == null || _isPurchasing) return;
    HapticFeedback.mediumImpact();
    AnalyticsService.instance.track('premium_purchase_intent', props: {
      'plan': _selected == _PlanKind.monthly ? 'monthly' : 'lifetime',
    });
    setState(() => _isPurchasing = true);
    final outcome = await PurchaseService.instance.purchase(package);
    if (!mounted) return;
    setState(() => _isPurchasing = false);
    if (outcome.cancelled) return; // Silent — the user just backed out.
    if (outcome.success) {
      HapticFeedback.mediumImpact();
      // Flip premiumProvider right now with the CustomerInfo this call
      // already has, instead of waiting on the separate update stream —
      // see PremiumNotifier.applyCustomerInfo's doc comment. This is what
      // makes "Premium is active" appear the instant the purchase clears,
      // with no gap where someone who just paid still sees the paywall.
      ref.read(premiumProvider.notifier).applyCustomerInfo(outcome.customerInfo!);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(S.of(context).premiumPurchaseError),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
    );
  }

  Future<void> _restore() async {
    if (_isRestoring) return;
    HapticFeedback.lightImpact();
    AnalyticsService.instance.track('premium_restore_intent');
    setState(() => _isRestoring = true);
    final outcome = await PurchaseService.instance.restore();
    if (!mounted) return;
    setState(() => _isRestoring = false);
    final s = S.of(context);
    final info = outcome.customerInfo;
    // Same reasoning as _startPurchase: apply now rather than waiting on
    // the separate update stream, so a successful restore is reflected
    // immediately instead of on whatever the listener's timing happens to be.
    if (info != null) {
      ref.read(premiumProvider.notifier).applyCustomerInfo(info);
    }
    final message = !outcome.success
        ? s.premiumPurchaseError
        : (info != null && PurchaseService.instance.isEntitled(info))
            ? s.premiumRestoreSuccess
            : s.premiumRestoreNothingFound;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
    );
  }

  /// Opens RevenueCat's hosted Customer Center (see
  /// PurchaseService.presentCustomerCenter) so an existing Premium member
  /// can view their renewal date, cancel, or switch plans without leaving
  /// the app — Apple requires this kind of self-serve management to be
  /// reachable from inside the app, not just via the OS Settings app.
  Future<void> _manageSubscription() async {
    if (_isOpeningCustomerCenter) return;
    HapticFeedback.lightImpact();
    AnalyticsService.instance.track('premium_manage_subscription_tap');
    setState(() => _isOpeningCustomerCenter = true);
    final opened = await PurchaseService.instance.presentCustomerCenter();
    if (!mounted) return;
    setState(() => _isOpeningCustomerCenter = false);
    if (opened) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(S.of(context).premiumPurchaseError),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
    );
  }

  /// Opens a legal link (Terms of Use / Privacy Policy) in the system
  /// browser. Both are plain https URLs so this never needs the
  /// LSApplicationQueriesSchemes entry url_launcher's README calls out —
  /// that's only required for scheme checks like tel:/sms:, not a plain
  /// launchUrl on http(s).
  Future<void> _openLink(String url) async {
    bool ok;
    try {
      ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
    if (ok || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(S.of(context).premiumLinkOpenError),
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
    final monthly = _offering?.monthly;
    final lifetime = _offering?.lifetime;
    final hasPlans = monthly != null || lifetime != null;

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
                      child: Icon(Icons.workspace_premium_rounded,
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

              if (isPremium) ...[
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
                      Icon(Icons.verified_rounded,
                          color: GameColors.emerald),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          s.premiumActive,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: GameColors.emerald,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed:
                      _isOpeningCustomerCenter ? null : _manageSubscription,
                  child: _isOpeningCustomerCenter
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        )
                      : Text(s.premiumManageSubscription),
                ),
              ] else if (_loadingOffering) ...[
                const SizedBox(height: 32),
                const Center(child: CircularProgressIndicator()),
                const SizedBox(height: 32),
              ] else if (!hasPlans) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: gp.surface,
                    borderRadius:
                        BorderRadius.circular(GameSpacing.cardRadius),
                    border: Border.all(color: gp.border),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 18, color: gp.textTert),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(s.premiumComingSoon,
                            style: TextStyle(fontSize: 12.5, color: gp.textSec)),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                // Plan picker
                Row(
                  children: [
                    if (monthly != null)
                      Expanded(
                        child: _PlanCard(
                          label: s.premiumMonthly,
                          price: monthly.storeProduct.priceString,
                          period: s.premiumPerMonth,
                          selected: _selected == _PlanKind.monthly,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _selected = _PlanKind.monthly);
                          },
                        ),
                      ),
                    if (monthly != null && lifetime != null)
                      const SizedBox(width: 12),
                    if (lifetime != null)
                      Expanded(
                        child: _PlanCard(
                          label: s.premiumLifetime,
                          price: lifetime.storeProduct.priceString,
                          period: s.premiumOneTime,
                          badge: s.premiumBestValueBadge,
                          selected: _selected == _PlanKind.lifetime,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _selected = _PlanKind.lifetime);
                          },
                        ),
                      ),
                  ],
                ).animate(delay: 500.ms).fadeIn().slideY(begin: 0.1),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed:
                      _isPurchasing || _selectedPackage == null ? null : _startPurchase,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 54),
                  ),
                  child: _isPurchasing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        )
                      : Text(s.premiumCta),
                ).animate(delay: 580.ms).fadeIn().slideY(begin: 0.2),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: _isRestoring ? null : _restore,
                  child: _isRestoring
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        )
                      : Text(s.premiumRestore),
                ),
                const SizedBox(height: 4),
                Text(
                  s.premiumFinePrint,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: gp.textTert),
                ),
                const SizedBox(height: 6),
                // Required alongside the subscription itself, not just
                // somewhere in Settings — see App Store Guideline 3.1.2 and
                // _termsOfUseUrl/_privacyPolicyUrl's doc comments above.
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: () => _openLink(_termsOfUseUrl),
                      child: Text(
                        s.premiumTermsOfUse,
                        style: TextStyle(
                          fontSize: 11,
                          color: gp.textSec,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                    Text('  ·  ',
                        style: TextStyle(fontSize: 11, color: gp.textTert)),
                    GestureDetector(
                      onTap: () => _openLink(_privacyPolicyUrl),
                      child: Text(
                        s.premiumPrivacyPolicy,
                        style: TextStyle(
                          fontSize: 11,
                          color: gp.textSec,
                          decoration: TextDecoration.underline,
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

  // Every bullet still maps to a real, currently-enforced gate — see each
  // string's doc comment in app_strings.dart for exactly which file/check
  // backs it. Copy was rewritten shorter and warmer per user feedback
  // (previous two-clause descriptions read as "a lot of details"). The
  // appearance bullet (was "themes") now also carries a brief, honestly
  // future-tense mention of premium-exclusive character looks — folded
  // into this bullet rather than given its own, per user direction. Still
  // deliberately doesn't include a "Family grids" bullet: that one has no
  // user-directed exception and remains unbuilt with no mention anywhere.
  List<(IconData, String, String)> _benefits(S s) => [
        (
          Icons.grid_on_rounded,
          s.premiumBenefitHabitsTitle,
          s.premiumBenefitHabitsDesc,
        ),
        (
          Icons.history_rounded,
          s.premiumBenefitHistoryTitle,
          s.premiumBenefitHistoryDesc,
        ),
        (
          Icons.insights_rounded,
          s.premiumBenefitInsightsTitle,
          s.premiumBenefitInsightsDesc,
        ),
        (
          Icons.palette_rounded,
          s.premiumBenefitAppearanceTitle,
          s.premiumBenefitAppearanceDesc,
        ),
        (
          Icons.mic_rounded,
          s.premiumBenefitVoiceTitle,
          s.premiumBenefitVoiceDesc,
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
                      style: TextStyle(
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

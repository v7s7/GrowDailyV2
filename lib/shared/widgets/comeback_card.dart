import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/game_theme.dart';
import '../../features/dashboard/notifiers/dashboard_notifier.dart';

/// The "you're back" moment: shown once after a gap, offering either a
/// streak restore (if a freeze is banked) or a clean restart, and making the
/// point that nothing was erased.
///
/// This used to live inside the Today screen — which was reachable only by
/// tapping a notification, and by no route inside the app at all. So the one
/// screen that welcomed someone back was the one screen they could not
/// navigate to. It lives on the Grid now, the app's real home, which is where
/// a returning person actually lands.
///
/// ── What this card is allowed to say ────────────────────────────────────
/// One bonus, stated once. The previous version put "+50 XP" on the card
/// twice, in two tenses that contradicted each other: a pill reading "+50 XP
/// comeback bonus when you continue" sat directly above a button offering
/// "Claim +50 XP comeback" right now. A reader had to guess whether the 50
/// was a reward for continuing or a thing to collect, and the answer was
/// worse than either guess, because only the button actually paid: finishing
/// today's habits cleared the offer and granted nothing (see
/// DashboardNotifier.completeHabit's clearsPendingComeback, where the bonus
/// is now added). Both routes pay it now, so the card states the amount once
/// and says plainly that it arrives either way.
///
/// Renders nothing unless [DashboardState.showComebackBonus] is true, so
/// callers can drop it in unconditionally.
class ComebackCard extends ConsumerWidget {
  final DashboardState state;
  const ComebackCard({super.key, required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!state.showComebackBonus) return const SizedBox.shrink();
    final gp = context.gp;
    final s = S.of(context);
    final user = FirebaseAuth.instance.currentUser;
    // Localized fallback, not a literal 'Warrior': every guest session hits
    // this, and an English word spliced into the Arabic welcome line is exactly
    // the kind of seam this card exists to avoid.
    final name = user?.email?.split('@').first ?? s.comebackGuestName;
    // A banked freeze turns this from "here is a consolation bonus" into a
    // real choice, so the two layouts differ in more than a button.
    final canRestore = state.streakFreezes > 0 && state.previousStreak > 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          // A dawn tint rather than a flat surface: this is the one card in
          // the app that exists to feel like a warm welcome, and it sits
          // directly above the blue stat card that already establishes the
          // gradient idiom here.
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.alphaBlend(GameColors.iconXp.withOpacity(0.10), gp.surface),
              gp.surface,
            ],
          ),
          borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
          border:
              Border.all(color: GameColors.iconXp.withOpacity(0.30), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(name: name),
            const SizedBox(height: 16),
            _BonusRow(xp: DashboardNotifier.comebackBonusXp),
            const SizedBox(height: 16),
            if (canRestore) ...[
              Text(
                s.restoreStreakOffer(state.previousStreak),
                style: TextStyle(fontSize: 12.5, color: gp.textSec, height: 1.4),
              ),
              const SizedBox(height: 12),
              _PrimaryAction(
                icon: Icons.ac_unit_rounded,
                label: s.restoreStreakCta(state.streakFreezes),
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  ref.read(dashboardProvider.notifier).useStreakFreeze();
                },
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    ref.read(dashboardProvider.notifier).acknowledgeComeback();
                  },
                  child: Text(s.freshStreakInstead),
                ),
              ),
            ] else ...[
              _PrimaryAction(
                label: s.claimComeback,
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  ref.read(dashboardProvider.notifier).acknowledgeComeback();
                },
              ),
              const SizedBox(height: 10),
              // The line that makes the card safe to walk past. Without it
              // the button reads as the only way to get the bonus, which is
              // exactly the misunderstanding that made someone tap it
              // instead of going and doing the habit.
              Text(
                s.comebackEitherWay,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, color: gp.textTert, height: 1.35),
              ).animate().fadeIn(delay: 520.ms, duration: 400.ms),
            ],
          ],
        ),
      )
          .animate()
          .fadeIn(duration: 400.ms)
          .slideY(begin: 0.10, curve: Curves.easeOutCubic, duration: 450.ms)
          .scaleXY(begin: 0.98, end: 1, curve: Curves.easeOutCubic, duration: 450.ms),
    );
  }
}

/// Sunrise mark, name, and the one reassurance the card exists to give.
class _Header extends StatelessWidget {
  final String name;
  const _Header({required this.name});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    return Row(
      children: [
        // The halo breathes rather than shimmers: a shimmer sweep on a
        // circle this small reads as a loading skeleton, which is the one
        // impression a welcome card must not give.
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: GameColors.iconXp.withOpacity(0.16),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: GameColors.iconXp.withOpacity(0.28),
                blurRadius: 16,
                spreadRadius: 1,
              ),
            ],
          ),
          child: const Icon(Icons.wb_twilight_rounded,
              color: GameColors.iconXp, size: 23),
        )
            .animate()
            .scaleXY(
                begin: 0.4, end: 1, duration: 620.ms, curve: Curves.elasticOut)
            .fadeIn(duration: 260.ms)
            // No delay on this one: inside a repeat, a delay is replayed at
            // the top of every cycle, so the breath would hitch each time
            // instead of running continuously. It composes harmlessly with
            // the elastic entrance above, which is scaling the same widget
            // for the first 620ms.
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .scaleXY(
                begin: 1, end: 1.06, duration: 1600.ms, curve: Curves.easeInOut),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.welcomeBack(name),
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: gp.textPrimary,
                      letterSpacing: -0.2)),
              const SizedBox(height: 3),
              Text(s.comebackNoErase,
                  style: TextStyle(
                      fontSize: 12.5, color: gp.textSec, height: 1.3)),
            ],
          ),
        ),
      ],
    ).animate().fadeIn(delay: 120.ms, duration: 350.ms).slideX(
        begin: 0.05, delay: 120.ms, duration: 350.ms, curve: Curves.easeOut);
  }
}

/// The bonus, named on one side and counted on the other. One statement of
/// the amount, on its own line, so it cannot disagree with the button.
class _BonusRow extends StatelessWidget {
  final int xp;
  const _BonusRow({required this.xp});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: GameColors.iconXp.withOpacity(0.10),
        borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
        border: Border.all(color: GameColors.iconXp.withOpacity(0.20)),
      ),
      child: Row(
        children: [
          const Icon(Icons.bolt_rounded, size: 16, color: GameColors.iconXp),
          const SizedBox(width: 8),
          Expanded(
            child: Text(s.comebackBonusLabel,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: gp.textSec)),
          ),
          // Forced LTR: "+50 XP" is a signed number followed by a Latin
          // unit, and letting the RTL paragraph direction lay it out moves
          // the plus to the wrong end of the digits.
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              s.comebackBonusAmount(xp),
              style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: GameColors.iconXp,
                  letterSpacing: -0.3),
            ),
          )
              .animate()
              .fadeIn(delay: 380.ms, duration: 300.ms)
              .scaleXY(
                  begin: 0.6,
                  end: 1,
                  delay: 380.ms,
                  duration: 520.ms,
                  curve: Curves.elasticOut),
        ],
      ),
    )
        .animate()
        .fadeIn(delay: 260.ms, duration: 350.ms)
        .slideY(begin: 0.25, delay: 260.ms, duration: 380.ms, curve: Curves.easeOut);
  }
}

/// Full-width primary button with a single shimmer sweep on arrival, which
/// is what draws the eye down to it after the card has settled.
class _PrimaryAction extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onPressed;
  const _PrimaryAction({
    required this.label,
    required this.onPressed,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final button = icon == null
        ? FilledButton(onPressed: onPressed, child: Text(label))
        : FilledButton.icon(
            onPressed: onPressed,
            icon: Icon(icon, size: 16),
            label: Text(label),
            style: FilledButton.styleFrom(
                backgroundColor: GameColors.iconXp,
                foregroundColor: Colors.white),
          );
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: button,
    )
        .animate()
        .fadeIn(delay: 420.ms, duration: 320.ms)
        .slideY(begin: 0.2, delay: 420.ms, duration: 340.ms, curve: Curves.easeOut)
        .shimmer(
            delay: 820.ms, duration: 1100.ms, color: Colors.white.withOpacity(0.35));
  }
}

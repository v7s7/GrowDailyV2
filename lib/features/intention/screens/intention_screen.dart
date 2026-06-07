import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/game_theme.dart';
import '../../../features/dashboard/notifiers/dashboard_notifier.dart';

class IntentionScreen extends ConsumerStatefulWidget {
  const IntentionScreen({super.key});

  @override
  ConsumerState<IntentionScreen> createState() => _IntentionScreenState();
}

class _IntentionScreenState extends ConsumerState<IntentionScreen> {
  final _p1 = TextEditingController();
  final _p2 = TextEditingController();
  final _p3 = TextEditingController();
  final _anchor = TextEditingController();
  final _action = TextEditingController();

  @override
  void dispose() {
    _p1.dispose();
    _p2.dispose();
    _p3.dispose();
    _anchor.dispose();
    _action.dispose();
    super.dispose();
  }

  void _finish() {
    HapticFeedback.mediumImpact();
    final priorities = [_p1.text.trim(), _p2.text.trim(), _p3.text.trim()]
        .where((p) => p.isNotEmpty)
        .toList();
    ref.read(dashboardProvider.notifier).setIntentionsDone(
          priorities: priorities,
          anchor: _anchor.text.trim(),
          intention: _action.text.trim(),
        );
    Navigator.of(context).pop();
  }

  void _skip() {
    HapticFeedback.lightImpact();
    ref.read(dashboardProvider.notifier).setIntentionsDone(
          priorities: const [],
          anchor: '',
          intention: '',
        );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Scaffold(
      backgroundColor: gp.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: GameColors.gold.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.wb_sunny_rounded,
                        color: GameColors.gold, size: 22),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _skip,
                    child: Text('Skip',
                        style: TextStyle(
                            color: gp.textTert, fontWeight: FontWeight.w600)),
                  ),
                ],
              ).animate().fadeIn(duration: 400.ms),
              const SizedBox(height: 24),
              Text(
                'Set your intention',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: gp.textPrimary,
                  letterSpacing: -0.6,
                  height: 1.15,
                ),
              ).animate(delay: 80.ms).fadeIn().slideY(begin: 0.15, curve: Curves.easeOut),
              const SizedBox(height: 8),
              Text(
                'Twenty seconds now saves your whole day. What matters most today?',
                style: TextStyle(fontSize: 14, color: gp.textSec, height: 1.4),
              ).animate(delay: 140.ms).fadeIn(),
              const SizedBox(height: 28),
              Text(
                'TOP 3 PRIORITIES',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: gp.textSec,
                    letterSpacing: 2),
              ).animate(delay: 180.ms).fadeIn(),
              const SizedBox(height: 12),
              _PriorityField(controller: _p1, number: 1, hint: 'e.g. Finish the report')
                  .animate(delay: 220.ms)
                  .fadeIn()
                  .slideX(begin: 0.06, curve: Curves.easeOut),
              const SizedBox(height: 10),
              _PriorityField(controller: _p2, number: 2, hint: 'e.g. Call my parents')
                  .animate(delay: 260.ms)
                  .fadeIn()
                  .slideX(begin: 0.06, curve: Curves.easeOut),
              const SizedBox(height: 10),
              _PriorityField(controller: _p3, number: 3, hint: 'e.g. 30-minute walk')
                  .animate(delay: 300.ms)
                  .fadeIn()
                  .slideX(begin: 0.06, curve: Curves.easeOut),
              const SizedBox(height: 32),
              Text(
                'IMPLEMENTATION INTENTION',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: gp.textSec,
                    letterSpacing: 2),
              ).animate(delay: 340.ms).fadeIn(),
              const SizedBox(height: 6),
              Text(
                'Linking a habit to a daily moment makes it far more likely to stick.',
                style: TextStyle(fontSize: 12.5, color: gp.textTert, height: 1.4),
              ).animate(delay: 360.ms).fadeIn(),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: gp.surface,
                  borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
                  border: Border.all(color: gp.border, width: 0.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('After...',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: gp.textSec)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _anchor,
                      style: TextStyle(fontSize: 15, color: gp.textPrimary),
                      decoration: const InputDecoration(
                        hintText: 'Fajr prayer / my morning coffee...',
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('I will...',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: gp.textSec)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _action,
                      style: TextStyle(fontSize: 15, color: gp.textPrimary),
                      decoration: const InputDecoration(
                        hintText: 'read one page of Quran...',
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ).animate(delay: 400.ms).fadeIn().slideY(begin: 0.08, curve: Curves.easeOut),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _finish,
                  child: const Text('START MY DAY'),
                ),
              ).animate(delay: 460.ms).fadeIn().slideY(begin: 0.15, curve: Curves.easeOut),
            ],
          ),
        ),
      ),
    );
  }
}

class _PriorityField extends StatelessWidget {
  final TextEditingController controller;
  final int number;
  final String hint;
  const _PriorityField({required this.controller, required this.number, required this.hint});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(GameSpacing.buttonRadius),
        border: Border.all(color: gp.border, width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: GameColors.gold.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Text('$number',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: GameColors.gold)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
              style: TextStyle(fontSize: 15, color: gp.textPrimary),
              decoration: InputDecoration(
                hintText: hint,
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

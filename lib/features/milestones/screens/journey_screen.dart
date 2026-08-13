import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../dashboard/notifiers/dashboard_notifier.dart';
import '../models/milestone_event.dart';
import '../notifiers/milestone_notifier.dart';

/// The narrative counterpart to ProgressHubScreen's numbers: instead of
/// totals and bar charts, a scrollable story of the dated moments that
/// actually mattered — level-ups, streak thresholds, perfect days/weeks,
/// achievement unlocks — newest first, grouped by month, ending (at the very
/// bottom, oldest) in the day the account itself began. Reads entirely from
/// [milestoneEventsProvider] (the shared MilestoneEvent log — see that
/// model's doc comment) plus [DashboardState.accountCreatedAt] for the
/// synthetic origin card; this screen adds no detection logic of its own,
/// only presentation.
///
/// Pushed from Profile's links section, next to Dashboard/Closet/Rooms.
class JourneyScreen extends ConsumerWidget {
  const JourneyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final eventsAsync = ref.watch(milestoneEventsProvider);
    final accountCreatedAt = ref.watch(dashboardProvider).accountCreatedAt;

    return Scaffold(
      backgroundColor: gp.bg,
      appBar: AppBar(
        backgroundColor: gp.bg,
        surfaceTintColor: Colors.transparent,
        title: Text(s.journeyTitle,
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: gp.textPrimary)),
      ),
      body: eventsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _JourneyBody(
          events: const [],
          accountCreatedAt: accountCreatedAt,
        ),
        data: (events) => _JourneyBody(
          events: events,
          accountCreatedAt: accountCreatedAt,
        ),
      ),
    );
  }
}

class _JourneyBody extends StatelessWidget {
  final List<MilestoneEvent> events;
  final DateTime? accountCreatedAt;

  const _JourneyBody({required this.events, required this.accountCreatedAt});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isAr = s.isAr;
    final locale = Localizations.localeOf(context).languageCode;

    if (events.isEmpty && accountCreatedAt == null) {
      return const _EmptyJourney();
    }

    final grouped = groupMilestonesByMonth(events);

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        _JourneyHeaderCard(
          totalMilestones: events.length,
          accountCreatedAt: accountCreatedAt,
          isAr: isAr,
          locale: locale,
        ),
        const SizedBox(height: 24),
        for (final entry in grouped.entries) ...[
          _MonthHeader(month: entry.key, locale: locale),
          const SizedBox(height: 10),
          for (var i = 0; i < entry.value.length; i++) ...[
            if (i != 0) const SizedBox(height: 8),
            _MilestoneRow(event: entry.value[i], isAr: isAr, locale: locale),
          ],
          const SizedBox(height: 22),
        ],
        if (accountCreatedAt != null)
          _MilestoneRow(
            event: MilestoneEvent(
              id: 'joined',
              type: MilestoneType.joined,
              occurredAt: accountCreatedAt!,
            ),
            isAr: isAr,
            locale: locale,
            isOrigin: true,
          ),
      ],
    );
  }
}

class _EmptyJourney extends StatelessWidget {
  const _EmptyJourney();

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.route_rounded, size: 44, color: gp.textTert),
            const SizedBox(height: 14),
            Text(
              s.journeyEmptyTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w800, color: gp.textPrimary),
            ),
            const SizedBox(height: 6),
            Text(
              s.journeyEmptyBody,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: gp.textSec, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _JourneyHeaderCard extends StatelessWidget {
  final int totalMilestones;
  final DateTime? accountCreatedAt;
  final bool isAr;
  final String locale;

  const _JourneyHeaderCard({
    required this.totalMilestones,
    required this.accountCreatedAt,
    required this.isAr,
    required this.locale,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final createdAt = accountCreatedAt;
    final daysSince =
        createdAt == null ? null : DateTime.now().difference(createdAt).inDays;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        border: Border.all(color: gp.border, width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: GameColors.gold.withOpacity(0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.auto_awesome_rounded, color: GameColors.gold),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.journeyMilestoneCount(totalMilestones),
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: gp.textPrimary),
                ),
                if (createdAt != null && daysSince != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    s.journeyMemberSince(
                      DateFormat('MMMM yyyy', locale).format(createdAt),
                      daysSince,
                    ),
                    style: TextStyle(fontSize: 12, color: gp.textSec),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthHeader extends StatelessWidget {
  final DateTime month;
  final String locale;
  const _MonthHeader({required this.month, required this.locale});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Text(
      DateFormat('MMMM yyyy', locale).format(month).toUpperCase(),
      style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: gp.textSec,
          letterSpacing: 1.5),
    );
  }
}

/// One row of the story — icon, headline sentence, and date. [isOrigin]
/// styles the trailing "day one" card slightly differently (emerald, no
/// trailing divider feel) so it visually reads as the start of the thread
/// rather than just another entry, without needing its own widget.
class _MilestoneRow extends StatelessWidget {
  final MilestoneEvent event;
  final bool isAr;
  final String locale;
  final bool isOrigin;

  const _MilestoneRow({
    required this.event,
    required this.isAr,
    required this.locale,
    this.isOrigin = false,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final color = event.type.color;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isOrigin ? color.withOpacity(0.06) : gp.surface,
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        border: Border.all(
          color: isOrigin ? color.withOpacity(0.3) : gp.border,
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withOpacity(0.14),
              borderRadius: BorderRadius.circular(GameSpacing.buttonRadius),
            ),
            child: Icon(event.type.icon, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  milestoneHeadline(event, isAr),
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: gp.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  DateFormat('EEEE, MMMM d', locale).format(event.occurredAt),
                  style: TextStyle(fontSize: 11.5, color: gp.textTert),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

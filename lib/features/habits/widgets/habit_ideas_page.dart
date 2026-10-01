import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../core/constants/game_constants.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../../shared/widgets/category_icon.dart';
import '../../grid/screens/grid_screen.dart' show categoryVisual;
import '../../mascot/sprout.dart';
import '../catalog/habit_ideas.dart';
import '../models/habit_cue.dart';
import '../models/habit_model.dart';

/// What the ideas page hands back to Add Habit.
sealed class IdeasPick {
  const IdeasPick();
}

/// One idea: added at once ([addNow]), or filled into the form to change
/// before adding. With an [IdeaAdder] the page adds ideas itself and only
/// hands back the one to change before adding.
class IdeaPicked extends IdeasPick {
  const IdeaPicked(this.idea, {required this.addNow});
  final HabitIdea idea;
  final bool addNow;
}

/// A ready-made plan, opened on the hub's Plans tab.
class PlanPicked extends IdeasPick {
  const PlanPicked(this.planId);
  final String planId;
}

/// Saves [idea] as one of the person's habits, as suggested, and says
/// whether it did (false: a limit or a refusal stopped it, and said why).
typedef IdeaAdder = Future<bool> Function(HabitIdea idea);

/// «أفكار لعاداتك»: a page of its own over Add Habit (the "Habit ideas
/// page" canvas, Aziz 2026-10-01: "that is perfect"). Two sections, each
/// saying what it is, so a whole plan is never mistaken for one habit:
/// «خطط جاهزة», a set of habits started together, as wide cards you swipe;
/// then «عادات بمفردها», one habit each, with a simple category filter.
/// Every idea card says in one line why it is worth doing, and a tap opens
/// it in full: the text behind it, the easy ways to start, and the way to
/// add it (Aziz, 2026-10-01: "remove the + mark so user click on it ... so
/// the pop up must always appear of the habit").
///
/// [goalType] picks the side: a quit habit gets ideas to quit or cut down,
/// and no plans (a plan is a set of habits to build). [withPlans] is false
/// outside the Add Habit hub, which is where the Plans tab lives.
///
/// With [onAdd] the popup's «أضفها لعاداتي» adds the habit there and then:
/// it says so, the card is marked «مضافة», and the person goes back to the
/// list for another ("when he add he can see that its added he can click
/// back and choose another one"). Each idea added is put in [added] by id,
/// which is how the caller knows, once the page is closed. Without [onAdd]
/// (a room's habit picker, which links the one habit its sheet returns) the
/// button hands the idea back to the form as before. [haveNames] are the
/// person's habits' names, lower case: an idea by one of them is shown as
/// added already.
Future<IdeasPick?> showHabitIdeasPage(
  BuildContext context, {
  required GoalType goalType,
  required bool withPlans,
  IdeaAdder? onAdd,
  Set<String>? added,
  Set<String> haveNames = const {},
}) {
  HapticFeedback.selectionClick();
  return showModalBottomSheet<IdeasPick>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => HabitIdeasPage(
      goalType: goalType,
      withPlans: withPlans,
      onAdd: onAdd,
      added: added,
      haveNames: haveNames,
    ),
  );
}

class HabitIdeasPage extends StatefulWidget {
  const HabitIdeasPage({
    super.key,
    required this.goalType,
    required this.withPlans,
    this.onAdd,
    this.added,
    this.haveNames = const {},
  });

  final GoalType goalType;
  final bool withPlans;
  final IdeaAdder? onAdd;
  final Set<String>? added;
  final Set<String> haveNames;

  @override
  State<HabitIdeasPage> createState() => _HabitIdeasPageState();
}

/// The habit list's filter: «الكل», or one category. A «مختارة لك» pill
/// sat first until Aziz asked how it chose (2026-10-01: "if its not smart
/// enough lets remove it"): it was the admin's fixed star, the same for
/// everyone. The star now puts an idea first in whatever list is shown.
const String _all = 'all';

class _HabitIdeasPageState extends State<HabitIdeasPage> {
  late final Future<List<ShownIdea>> _ideas = loadShownIdeas();
  final _search = TextEditingController();
  String? _filter;

  static const _categoryOrder = [
    HabitCategory.faith,
    HabitCategory.health,
    HabitCategory.learning,
    HabitCategory.focus,
    HabitCategory.sleep,
    HabitCategory.money,
    HabitCategory.mind,
    HabitCategory.social,
    HabitCategory.custom,
  ];

  bool get _quit => widget.goalType == GoalType.quit;

  /// Added from this page, or already one of the person's habits by name.
  bool _isAdded(HabitIdea idea) =>
      (widget.added?.contains(idea.id) ?? false) ||
      widget.haveNames.contains(idea.nameAr.trim().toLowerCase()) ||
      widget.haveNames.contains(idea.nameEn.trim().toLowerCase());

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final height = MediaQuery.of(context).size.height;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        height: height * 0.94 - bottom,
        decoration: BoxDecoration(
          color: gp.surfaceHigh,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: gp.border, width: 0.5),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: gp.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.chevron_left_rounded,
                        size: 28, color: gp.textPrimary),
                  ),
                  Expanded(
                    child: Text(
                      _quit ? s.ideasPageTitleQuit : s.ideasPageTitle,
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: gp.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<ShownIdea>>(
                future: _ideas,
                builder: (context, snap) {
                  final all = snap.data;
                  if (all == null) {
                    return const Center(
                      child: CircularProgressIndicator.adaptive(),
                    );
                  }
                  return _body(s, all);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(S s, List<ShownIdea> all) {
    final gp = context.gp;
    final side = [
      for (final i in all)
        if (i.idea.type == widget.goalType) i,
    ];
    final query = _search.text.trim().toLowerCase();
    final searching = query.isNotEmpty;
    final filter = _filter ?? _all;
    final categories = [
      for (final c in _categoryOrder)
        if (side.any((i) => i.idea.category == c)) c,
    ];
    final matching = [
      for (final i in side)
        if (searching
            ? _matches(i.idea, query)
            : filter == _all || i.idea.category.name == filter)
          i,
    ];
    // The admin's starred ideas first, each part in the admin's order.
    final shown = [
      for (final i in matching)
        if (i.featured) i,
      for (final i in matching)
        if (!i.featured) i,
    ];
    final plans = widget.withPlans && !_quit && !searching ? shownPlans() : const <ShownPlan>[];

    return ListView(
      padding: EdgeInsets.fromLTRB(
        0,
        4,
        0,
        24 + MediaQuery.of(context).padding.bottom,
      ),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  s.ideasPageIntro,
                  style: TextStyle(fontSize: 13.5, color: gp.textSec, height: 1.55),
                ),
              ),
              const SizedBox(width: 10),
              Sprout(
                pose: _quit ? SproutPose.determined : SproutPose.idea,
                height: 64,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: TextField(
            selectionWidthStyle: GameTextStyles.selectionWidthStyle,
            controller: _search,
            textInputAction: TextInputAction.search,
            style: TextStyle(fontSize: 15, color: gp.textPrimary),
            decoration: InputDecoration(
              hintText: s.ideasSearchHint,
              isDense: true,
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: searching
                  ? IconButton(
                      tooltip: MaterialLocalizations.of(context)
                          .deleteButtonTooltip,
                      onPressed: _search.clear,
                      icon: const Icon(Icons.close_rounded, size: 18),
                    )
                  : null,
            ),
          ),
        ),
        if (plans.isNotEmpty) ...[
          const SizedBox(height: 22),
          _sectionHeader(s.ideasPlansTitle, s.ideasPlansNote),
          const SizedBox(height: 10),
          SizedBox(
            height: 196,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: plans.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) => _PlanCard(
                plan: plans[i],
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.pop(context, PlanPicked(plans[i].plan.id));
                },
              ),
            ),
          ).animate().fadeIn(duration: 260.ms),
        ],
        const SizedBox(height: 22),
        _sectionHeader(
          _quit ? s.ideasHabitsTitleQuit : s.ideasHabitsTitle,
          s.ideasHabitsNote,
        ),
        if (!searching) ...[
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                _FilterPill(
                  label: s.ideasFilterAll,
                  selected: filter == _all,
                  onTap: () => _setFilter(_all),
                ),
                for (final c in categories) ...[
                  const SizedBox(width: 6),
                  _FilterPill(
                    label: c.localizedName(s.isAr),
                    selected: filter == c.name,
                    onTap: () => _setFilter(c.name),
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Text(
              s.ideasNoResults,
              style: TextStyle(fontSize: 13.5, color: gp.textTert, height: 1.5),
            ),
          ),
        for (final i in shown)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: _IdeaCard(
              key: ValueKey(i.idea.id),
              idea: i.idea,
              added: _isAdded(i.idea),
              onOpen: () => _openIdea(i.idea),
            ),
          ),
      ],
    );
  }

  void _setFilter(String value) {
    HapticFeedback.selectionClick();
    setState(() => _filter = value);
  }

  bool _matches(HabitIdea idea, String query) =>
      idea.nameAr.toLowerCase().contains(query) ||
      idea.nameEn.toLowerCase().contains(query) ||
      idea.shortAr.toLowerCase().contains(query) ||
      idea.shortEn.toLowerCase().contains(query);

  /// The popup, always. With [HabitIdeasPage.onAdd] adding happens in
  /// it, and back here the card says «مضافة»; only «عدّلها قبل الإضافة»
  /// leaves the page, for the form.
  Future<void> _openIdea(HabitIdea idea) async {
    HapticFeedback.selectionClick();
    final onAdd = widget.onAdd;
    final addNow = await showIdeaDetail(
      context,
      idea,
      onAdd: onAdd == null
          ? null
          : (idea) async {
              final ok = await onAdd(idea);
              if (ok) {
                widget.added?.add(idea.id);
                if (mounted) setState(() {});
              }
              return ok;
            },
      alreadyAdded: _isAdded(idea),
    );
    if (addNow == null || !mounted) return;
    Navigator.pop(context, IdeaPicked(idea, addNow: addNow));
  }

  Widget _sectionHeader(String title, String note) {
    final gp = context.gp;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16.5,
              fontWeight: FontWeight.w800,
              color: gp.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(note, style: TextStyle(fontSize: 12.5, color: gp.textTert)),
        ],
      ),
    );
  }
}

/// How often an idea suggests, in words: «كل يوم», «3 مرات بالأسبوع», or
/// the set days' names.
String ideaOftenLabel(BuildContext context, HabitIdea idea) {
  final s = S.of(context);
  final often = idea.often;
  if (often.isDaily) {
    return idea.timesPerDay > 1
        ? '${s.oftenEveryDay} · ${s.timesPerDayPhrase(idea.timesPerDay)}'
        : s.oftenEveryDay;
  }
  if (!often.isSetDays) return s.timesAWeekPhrase(often.target);
  final locale = Localizations.localeOf(context).languageCode;
  // 2024-01-01 was a Monday, so day d of that week is weekday d.
  return [
    for (final d in often.weekdays)
      DateFormat.EEEE(locale).format(DateTime(2024, 1, d)),
  ].join(s.isAr ? ' و' : ' and ');
}

/// The suggested reminder in words, or null for none.
String? ideaReminderLabel(S s, HabitIdea idea) {
  if (idea.reminderPrayer case final String prayer) {
    return s.ideasWithPrayer(HabitCue.preset(prayer).labelForLocale(s.isAr));
  }
  if (idea.reminderHour case final int hour) {
    return s.ideasReminderAt(
      HabitCue.time(hour, idea.reminderMinute ?? 0).labelForLocale(s.isAr),
    );
  }
  return null;
}

/// A quit idea's style in words: quit fully, or its daily limit.
String ideaQuitLabel(S s, HabitIdea idea) => idea.limitAmount == null
    ? s.ideasQuitFully
    : s.ideasDailyLimit(
        idea.limitAmount!,
        s.limitUnitLabel(idea.limitUnit!.name),
      );

int _xpFor(HabitIdea idea) =>
    GameConstants.categoryXpRewards[idea.category.name] ?? 10;

/// The category's icon in its own colour, on a tinted tile.
Widget _categoryTile(BuildContext context, HabitCategory category, double size) {
  final (_, color) = categoryVisual(context, category);
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color.withOpacity(0.16),
      borderRadius: BorderRadius.circular(size * 0.3),
    ),
    child: Center(
      child: CategoryIcon(
        category: category,
        size: size * 0.48,
        color: context.gp.ink(color),
      ),
    ),
  );
}

/// One ready-made plan: wide, in the plan's colour, with a row of its
/// habits' icons and how many there are, which is what says "a set of
/// habits" at a glance beside the one-habit cards below.
class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.onTap});
  final ShownPlan plan;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final c = plan.plan.color;
    final ink = gp.ink(c);
    final habits = plan.plan.habits;
    final xp = habits.fold<int>(0, (sum, h) => sum + h.xpReward);
    final radius = BorderRadius.circular(20);
    return Semantics(
      button: true,
      child: Material(
        type: MaterialType.transparency,
        child: Ink(
          width: 244,
          decoration: BoxDecoration(
            color: c.withOpacity(0.10),
            borderRadius: radius,
            border: Border.all(color: c.withOpacity(0.32)),
          ),
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: c.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(plan.plan.icon, size: 22, color: ink),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 3),
                        decoration: BoxDecoration(
                          color: c.withOpacity(0.18),
                          borderRadius:
                              BorderRadius.circular(GameSpacing.pillRadius),
                        ),
                        child: Text(
                          '+$xp XP',
                          textDirection: TextDirection.ltr,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    plan.name(s.isAr),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: gp.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    plan.desc(s.isAr),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: gp.textSec,
                      height: 1.45,
                    ),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      for (final h in habits.take(4)) ...[
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: c.withOpacity(0.16),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Center(
                            child: CategoryIcon(
                              category: h.category,
                              size: 13,
                              color: ink,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                      const SizedBox(width: 4),
                      Text(
                        s.ideasPlanHabitCount(habits.length),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: gp.textSec,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One habit idea: its icon, its name, the one line on why, and how often
/// it is suggested. The whole card opens the idea in full, where it is
/// added; once it is one of the person's habits the card says «مضافة».
class _IdeaCard extends StatelessWidget {
  const _IdeaCard({
    super.key,
    required this.idea,
    required this.added,
    required this.onOpen,
  });
  final HabitIdea idea;
  final bool added;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final quit = idea.type == GoalType.quit;
    final radius = BorderRadius.circular(18);
    return Material(
      type: MaterialType.transparency,
      child: Ink(
        decoration: BoxDecoration(
          color: gp.surface,
          borderRadius: radius,
          border: Border.all(color: gp.border, width: 0.5),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 10, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _categoryTile(context, idea.category, 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        idea.name(s.isAr),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: gp.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text.rich(
                        TextSpan(
                          children: [
                            if (quit)
                              TextSpan(
                                text: '${s.ideasWhy} ',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: gp.goldInk,
                                ),
                              ),
                            TextSpan(text: idea.short(s.isAr)),
                          ],
                        ),
                        style: TextStyle(
                          fontSize: 12.5,
                          color: gp.textSec,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _MetaChip(
                            quit
                                ? ideaQuitLabel(s, idea)
                                : ideaOftenLabel(context, idea),
                          ),
                          Text(
                            '+${_xpFor(idea)} XP',
                            textDirection: TextDirection.ltr,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: gp.goldInk,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: added
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: GameColors.gold.withOpacity(0.14),
                            borderRadius:
                                BorderRadius.circular(GameSpacing.pillRadius),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_rounded,
                                  size: 14, color: gp.goldInk),
                              const SizedBox(width: 4),
                              Text(
                                s.ideasAddedChip,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                  color: gp.goldInk,
                                ),
                              ),
                            ],
                          ),
                        )
                      : Icon(
                          Directionality.of(context) == TextDirection.rtl
                              ? Icons.chevron_left_rounded
                              : Icons.chevron_right_rounded,
                          size: 22,
                          color: gp.textTert,
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

class _MetaChip extends StatelessWidget {
  const _MetaChip(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
      decoration: BoxDecoration(
        color: gp.surfaceHL,
        borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
      ),
      child: Text(label, style: TextStyle(fontSize: 11.5, color: gp.textSec)),
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final radius = BorderRadius.circular(GameSpacing.pillRadius);
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: AnimatedContainer(
          duration: GameMotion.quick,
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: selected ? GameColors.gold.withOpacity(0.14) : gp.surface,
            borderRadius: radius,
            border: Border.all(
              color: selected ? GameColors.gold.withOpacity(0.55) : gp.border,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              color: selected ? gp.goldInk : gp.textSec,
            ),
          ),
        ),
      ),
    );
  }
}

/// One idea in full: the text behind it (a hadith in a quote with its
/// source, or plain words), the easy ways to start, what is suggested, and
/// the two ways on: false for «عدّلها قبل الإضافة», null when closed.
///
/// «أضفها لعاداتي» adds it with [onAdd] and the popup stays, saying so,
/// with «اختر فكرة ثانية» to go back to the list; one already added
/// ([alreadyAdded]) opens that way. Without [onAdd] the button returns
/// true, for the form to add it.
Future<bool?> showIdeaDetail(
  BuildContext context,
  HabitIdea idea, {
  IdeaAdder? onAdd,
  bool alreadyAdded = false,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _IdeaDetail(
      idea: idea,
      onAdd: onAdd,
      alreadyAdded: alreadyAdded,
    ),
  );
}

class _IdeaDetail extends StatefulWidget {
  const _IdeaDetail({
    required this.idea,
    required this.onAdd,
    required this.alreadyAdded,
  });
  final HabitIdea idea;
  final IdeaAdder? onAdd;
  final bool alreadyAdded;

  @override
  State<_IdeaDetail> createState() => _IdeaDetailState();
}

class _IdeaDetailState extends State<_IdeaDetail> {
  /// Added while this popup is open.
  bool _added = false;
  bool _adding = false;

  HabitIdea get idea => widget.idea;

  Future<void> _add() async {
    final onAdd = widget.onAdd;
    if (onAdd == null) {
      HapticFeedback.mediumImpact();
      Navigator.pop(context, true);
      return;
    }
    if (_adding) return;
    setState(() => _adding = true);
    final ok = await onAdd(idea);
    if (!mounted) return;
    if (ok) HapticFeedback.mediumImpact();
    setState(() {
      _adding = false;
      _added = ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final quit = idea.type == GoalType.quit;
    final source = idea.source(s.isAr);
    final (_, color) = categoryVisual(context, idea.category);
    final reminder = ideaReminderLabel(s, idea);
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: BoxDecoration(
        color: gp.surfaceHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: gp.border, width: 0.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: gp.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      _categoryTile(context, idea.category, 58),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              idea.name(s.isAr),
                              style: TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.w800,
                                color: gp.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: color.withOpacity(0.16),
                                    borderRadius: BorderRadius.circular(
                                        GameSpacing.pillRadius),
                                  ),
                                  child: Text(
                                    idea.category.localizedName(s.isAr),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: gp.ink(color),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '+${_xpFor(idea)} XP',
                                  textDirection: TextDirection.ltr,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: gp.goldInk,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  // A hadith or ayah in a quote with its source; plain
                  // words as a plain card.
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: color.withOpacity(0.25)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (source != null) ...[
                          Icon(Icons.format_quote_rounded,
                              size: 26, color: gp.ink(color)),
                          const SizedBox(height: 4),
                        ] else if (quit) ...[
                          Text(
                            s.ideasWhy,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: gp.goldInk,
                            ),
                          ),
                          const SizedBox(height: 4),
                        ],
                        Text(
                          idea.benefit(s.isAr),
                          style: TextStyle(
                            fontSize: 15.5,
                            height: 1.85,
                            fontWeight: FontWeight.w500,
                            color: gp.textPrimary,
                          ),
                        ),
                        if (source != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            source,
                            style: TextStyle(fontSize: 12.5, color: gp.textTert),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    s.ideasEasyWays,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: gp.textSec,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final way in idea.ways(s.isAr))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 22,
                            height: 22,
                            margin: const EdgeInsets.only(top: 2),
                            decoration: BoxDecoration(
                              color: GameColors.gold.withOpacity(0.14),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.check_rounded,
                                size: 14, color: gp.goldInk),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              way,
                              style: TextStyle(
                                fontSize: 14.5,
                                height: 1.6,
                                color: gp.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 10),
                  Text(
                    s.ideasSuggested,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: gp.textSec,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _SuggestChip(
                        icon: Icons.repeat_rounded,
                        label: ideaOftenLabel(context, idea),
                      ),
                      if (quit)
                        _SuggestChip(
                          icon: Icons.do_not_disturb_on_outlined,
                          label: ideaQuitLabel(s, idea),
                        ),
                      if (reminder != null)
                        _SuggestChip(
                          icon: Icons.notifications_none_rounded,
                          label: reminder,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              10,
              20,
              16 + MediaQuery.of(context).padding.bottom,
            ),
            child: AnimatedSwitcher(
              duration: GameMotion.standard,
              child: _added || widget.alreadyAdded
                  ? _addedFooter(s)
                  : Column(
                      key: const ValueKey('add'),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FilledButton.icon(
                          onPressed: _adding ? null : _add,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(double.infinity, 52),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: _adding
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.add_rounded),
                          label: Text(s.ideasAddNow),
                        ),
                        const SizedBox(height: 4),
                        TextButton(
                          onPressed: _adding
                              ? null
                              : () {
                                  HapticFeedback.selectionClick();
                                  Navigator.pop(context, false);
                                },
                          style: TextButton.styleFrom(
                            minimumSize: const Size(double.infinity, 44),
                          ),
                          child: Text(s.ideasEditFirst),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

extension on _IdeaDetailState {
  /// Once added: it says so where the button was, and the way back to the
  /// list for another idea.
  Widget _addedFooter(S s) {
    final gp = context.gp;
    return Column(
      key: const ValueKey('added'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          liveRegion: true,
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              color: GameColors.gold.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: GameColors.gold.withOpacity(0.45)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_rounded, size: 20, color: gp.goldInk),
                const SizedBox(width: 8),
                Text(
                  _added ? s.ideasAddedDone : s.ideasAlreadyHave,
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    color: gp.goldInk,
                  ),
                ),
              ],
            ),
          )
              .animate(key: ValueKey(_added))
              .scale(
                begin: const Offset(0.96, 0.96),
                duration: 220.ms,
                curve: Curves.easeOutBack,
              ),
        ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: () {
            HapticFeedback.selectionClick();
            Navigator.pop(context);
          },
          style: TextButton.styleFrom(
            minimumSize: const Size(double.infinity, 44),
          ),
          child: Text(s.ideasPickAnother),
        ),
      ],
    );
  }
}

class _SuggestChip extends StatelessWidget {
  const _SuggestChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: gp.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: gp.goldInk),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: gp.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

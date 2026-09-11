import '../../premium/notifiers/premium_notifier.dart';

/// What a tap on one of Add Habit's reminder chips did.
///
/// The reason this is a value and not a bool: the same tap means four
/// different things depending on the tier and on what the habit already
/// holds, and each one owes the user a different answer on screen — nothing,
/// a notice, or the paywall.
enum HabitOffsetTap {
  /// The shift was already set and has been taken off.
  removed,

  /// Free tier, at its one reminder: the tap MOVED that reminder rather than
  /// adding a second. This is the case that makes the whole thing safe to
  /// ship — a free user must still be able to change the reminder they have,
  /// and a paywall here would take away something they already had.
  replaced,

  /// The shift was added to the stack.
  added,

  /// The only remaining shift was tapped. A habit's shift IS its reminder, so
  /// clearing the last one would mean "never remind me", which Add Habit says
  /// by choosing a custom-text cue, not by emptying a grid.
  refusedLast,

  /// The habit already holds [kMaxHabitReminders]. A ceiling Premium shares,
  /// so this is a limit to explain, never an upsell.
  refusedFull,

  /// Free tier, already carrying a stack it kept through a lapsed
  /// subscription. Adding another is what Premium is for.
  locked,
}

/// Which side of its anchor a habit's reminders sit on. See
/// [HabitReminderStack.side].
///
/// [both] is reachable only with a stack (Premium, or one kept through a
/// lapsed subscription): 10 before Fajr and 30 after it on the same habit.
enum HabitReminderSide { none, before, after, both }

/// A habit's reminder shifts: one primary plus the stack around it.
///
/// Mirrors how they are stored (IslamicHabitTemplate.reminderOffsetMinutes
/// and .extraReminderOffsets) rather than flattening them into one set,
/// because the primary is not interchangeable with the rest: it is what
/// notification slot 0 means, and slot 0 is an id the OS is already holding.
class HabitReminderStack {
  /// Signed minutes: negative before the anchor, positive after, 0 on the dot.
  final int primary;

  /// The rest, never containing [primary].
  final Set<int> extras;

  const HabitReminderStack({required this.primary, this.extras = const {}});

  /// Every shift, earliest first. Never empty.
  List<int> get all => ({primary, ...extras}.toList()..sort());

  int get length => all.length;

  bool contains(int signed) => primary == signed || extras.contains(signed);

  /// The side of the anchor the shifts sit on, read off their signs.
  ///
  /// This is the only direction a habit reminder has anywhere: the scheduler
  /// reads nothing but the signed minutes (NotificationService), so Add
  /// Habit's «قبل | بعد» chips light from this rather than keeping a second
  /// answer of their own that could disagree with the reminders under them.
  /// An on-time reminder belongs to neither side, so 0 alone is [none] and
  /// 0 beside -15 is [HabitReminderSide.before].
  HabitReminderSide get side {
    final before = all.any((o) => o < 0);
    final after = all.any((o) => o > 0);
    if (before && after) return HabitReminderSide.both;
    if (before) return HabitReminderSide.before;
    if (after) return HabitReminderSide.after;
    return HabitReminderSide.none;
  }

  /// Every shift moved to the other side of the anchor by the same amount:
  /// 15 before becomes 15 after, and on time stays on time.
  ///
  /// What tapping the other chip on the main step does. Negation cannot make
  /// two different shifts equal, so the count never changes and the primary
  /// stays the primary: notification slot 0 keeps its id and keeps meaning
  /// the same reminder. Mirroring twice gives the stack back.
  HabitReminderStack mirrored() => HabitReminderStack(
        primary: -primary,
        extras: {for (final e in extras) -e},
      );

  /// The result of tapping the chip for [signed].
  ///
  /// Pure, so the rule can be read and tested on its own — the widget only
  /// has to render what comes back and say the matching thing out loud.
  ({HabitReminderStack stack, HabitOffsetTap outcome}) toggle(
    int signed, {
    required bool isPremium,
  }) {
    if (contains(signed)) {
      if (length == 1) {
        return (stack: this, outcome: HabitOffsetTap.refusedLast);
      }
      if (signed != primary) {
        return (
          stack: HabitReminderStack(
            primary: primary,
            extras: {...extras}..remove(signed),
          ),
          outcome: HabitOffsetTap.removed,
        );
      }
      // Removing the primary promotes the earliest survivor into its place,
      // rather than renumbering the whole stack around a hole.
      final rest = extras.toList()..sort();
      return (
        stack: HabitReminderStack(
          primary: rest.first,
          extras: {...rest.skip(1)},
        ),
        outcome: HabitOffsetTap.removed,
      );
    }

    if (!isPremium && length <= kFreeHabitReminders) {
      return (
        stack: HabitReminderStack(primary: signed),
        outcome: HabitOffsetTap.replaced,
      );
    }

    final gate = canAddHabitReminder(current: length, isPremium: isPremium);
    if (gate.locked) return (stack: this, outcome: HabitOffsetTap.locked);
    if (!gate.allowed) {
      return (stack: this, outcome: HabitOffsetTap.refusedFull);
    }
    return (
      stack: HabitReminderStack(primary: primary, extras: {...extras, signed}),
      outcome: HabitOffsetTap.added,
    );
  }

  /// A shift typed into the custom sheet.
  ///
  /// The one thing that makes it different from a chip tap: a value the habit
  /// already holds stays put instead of being toggled off. Nobody types 45
  /// into a field and presses Add meaning "remove my 45-minute reminder".
  /// One reminder edited into another: [old] leaves and [signed] takes its
  /// place, which is what tapping a reminder row and picking a different
  /// value means. The count never changes, so no tier rule applies. Roles
  /// carry over: editing the primary makes [signed] the primary. A value
  /// the habit already carries is not doubled, the edit then only drops
  /// [old]; and editing a reminder to what it already is changes nothing.
  HabitReminderStack replace(int old, int signed) {
    if (old == signed || !contains(old)) return this;
    if (contains(signed)) {
      if (old != primary) {
        return HabitReminderStack(
          primary: primary,
          extras: {...extras}..remove(old),
        );
      }
      final rest = extras.toList()..sort();
      return HabitReminderStack(primary: rest.first, extras: {...rest.skip(1)});
    }
    if (old == primary) {
      return HabitReminderStack(primary: signed, extras: extras);
    }
    return HabitReminderStack(
      primary: primary,
      extras: {...extras}
        ..remove(old)
        ..add(signed),
    );
  }

  ({HabitReminderStack stack, HabitOffsetTap outcome}) addTyped(
    int signed, {
    required bool isPremium,
  }) =>
      contains(signed)
          ? (stack: this, outcome: HabitOffsetTap.added)
          : toggle(signed, isPremium: isPremium);
}

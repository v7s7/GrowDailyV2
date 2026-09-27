import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which shared-plan slot a room's strips are drawn for, per room code; null
/// draws the whole plan, as the board always has.
///
/// Aziz, 2026-09-27: "add a filter like user can click on a habit to see the
/// room grid showing the grid of that choosen habit". Picked by tapping a
/// habit tile on the plan card, cleared by tapping it again or the ✕ on the
/// bar above the rows. See room_habit_strip.dart for what a filtered strip
/// draws, and why it can never reach the ranking.
///
/// autoDispose and in memory: a way of looking at one visit to the room, so
/// leaving the screen puts the board back to the whole plan and nobody comes
/// back to a filtered board they forgot about.
final roomHabitFilterProvider =
    StateProvider.autoDispose.family<int?, String>((ref, code) => null);

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The id of the habit that was just created, so the Grid can scroll its
/// row into view and glow it once.
///
/// Creating a habit used to end with no visible change at all: the sheet
/// closed, the new row appended BELOW THE FOLD, and the board looked
/// exactly as it did before — on a first run that reads as "it didn't
/// work". Set by AddHabitSheet's create path the moment the habit exists,
/// consumed by _GridTable's row (which announces itself via
/// Scrollable.ensureVisible and a one-shot glow), and cleared by that same
/// row when the glow finishes, so the highlight can never replay on a
/// later rebuild.
///
/// Deliberately NOT set by the Plans path: a plan activates several habits
/// at once, and picking one of them to glow would be arbitrary.
final newlyAddedHabitIdProvider = StateProvider<String?>((ref) => null);

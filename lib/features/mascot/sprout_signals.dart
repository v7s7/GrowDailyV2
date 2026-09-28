import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../character/models/character_option.dart';
import '../character/notifiers/character_notifier.dart';
import 'sprout_praise.dart';

/// Bumped once each time the day earns its streak point (80% of its habits),
/// by the same listener that fires the heavy haptic, the burst and «يومك
/// انحسب في سلسلتك!» for it (registerDashboardReactions). The day card's
/// sprout celebrates on each bump.
///
/// A counter, not the dashboard's own perfectDayCelebration flag read on
/// rebuild: that flag is true for exactly one state, and two state changes
/// inside one frame would hide it from anything that only looks at the
/// latest state. The reactions listener sees every change as it happens, so
/// the moment is taken from there. It also keeps the sprout clear of the
/// dashboard, whose notifier cannot be built inside a widget test.
final sproutStreakPointProvider = StateProvider<int>((ref) => 0);

/// How the sprout addresses the reader (PraiseForm): from the skin the
/// account wears (Aziz, 2026-09-28: "take it from the skin chosen", no
/// question asked). That is what apps in Arabic do, the masculine as the
/// everyday default and the feminine once they know, and the skin is how
/// this one knows:
///   - a woman's skin: a woman («عليج»);
///   - any man's skin, the one every account starts in included: a man
///     («عليك»), the app's usual second person;
///   - a skin not loaded yet, an id the catalog does not know, or anything
///     that cannot be read: unknown, and the sprout says only the lines that
///     fit anyone.
PraiseForm praiseFormFor(CharacterState character) {
  if (character.isLoading) return PraiseForm.unknown;
  final option = CharacterCatalog.findById(character.characterId);
  if (option == null) return PraiseForm.unknown;
  return option.gender == CharacterGender.female
      ? PraiseForm.woman
      : PraiseForm.man;
}

/// [praiseFormFor] the account's character, watched so a change in the
/// closet is heard at once.
final sproutAddressProvider = Provider<PraiseForm>((ref) {
  try {
    return praiseFormFor(ref.watch(characterProvider));
  } catch (_) {
    return PraiseForm.unknown;
  }
});

/// A square that just turned green on the board: which habit, and when. Set
/// by WeeklyGridNotifier.setSquare for the open day's squares; the day card's
/// sprout looks the habit up to pick praise that fits it.
class SproutDone {
  const SproutDone(this.habitId, this.at);
  final String habitId;
  final DateTime at;
}

/// The last square turned green on the board ([SproutDone]), read by the day
/// card's sprout when the day's numbers rise, to pick praise that fits the
/// habit. A rise with no fresh event (a widget tap, a notification action,
/// another screen) gets the general lines.
final sproutDoneProvider = StateProvider<SproutDone?>((ref) => null);

/// The one picker for the app, so what was said lately is remembered across
/// every card and screen (see PraisePicker).
final sproutPraisePickerProvider =
    Provider<PraisePicker>((ref) => PraisePicker());

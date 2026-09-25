// Test doubles for the Home Screen icon: a phone that records what it is
// asked to show, and the two preference notifiers kept in memory so no test
// body ever writes to Hive (see LandingHarness on why that hangs).
import 'package:grow_daily_v2/features/app_icon/app_icon_catalog.dart';
import 'package:grow_daily_v2/features/app_icon/app_icon_providers.dart';
import 'package:grow_daily_v2/features/app_icon/app_icon_service.dart';

class FakeIconPhone extends AppIconService {
  FakeIconPhone([this.showing = AppIconChoice.shipped]);

  AppIconChoice showing;
  final List<AppIconChoice> sets = [];

  @override
  Future<bool> supported() async => true;

  @override
  Future<AppIconChoice> current() async => showing;

  @override
  Future<bool> set(AppIconChoice choice) async {
    sets.add(choice);
    showing = choice;
    return true;
  }
}

class MemIconPrefs extends AppIconPrefsNotifier {
  MemIconPrefs([AppIconPrefs prefs = const AppIconPrefs(loaded: true)])
      : super(initial: prefs);

  @override
  Future<void> setFollowTheme(bool on) async {
    state = state.copyWith(followTheme: on);
  }

  @override
  Future<void> noteOfferDeclined() async {
    state = state.copyWith(offerDeclines: state.offerDeclines + 1);
  }

  @override
  Future<void> noteRamadanCardShown(int year) async {
    if (year > state.ramadanCardYear) {
      state = state.copyWith(ramadanCardYear: year);
    }
  }
}

/// A full-day count that answers from a list, one call at a time, and
/// remembers who it was asked for.
class FakeFullDayCounter extends FullDayCounter {
  FakeFullDayCounter(this.answers);

  final List<int?> answers;
  final List<String?> askedFor = [];

  @override
  Future<int?> count(String? uid) async {
    askedFor.add(uid);
    return answers.isEmpty ? null : answers.removeAt(0);
  }
}

class MemPlantGrowth extends PlantGrowthNotifier {
  MemPlantGrowth([PlantGrowth growth = const PlantGrowth(loaded: true)])
      : super('test', initial: growth);

  @override
  Future<void> observe(int fullDays) async {
    final reached = grownShapeFor(fullDays);
    if (reached.index <= state.earned.index) return;
    state = PlantGrowth(
      loaded: true,
      earned: reached,
      celebrated: state.celebrated,
    );
  }

  @override
  Future<void> markCelebrated(PlantShape shape) async {
    if (shape.index <= state.celebrated.index) return;
    state = PlantGrowth(loaded: true, earned: state.earned, celebrated: shape);
  }
}

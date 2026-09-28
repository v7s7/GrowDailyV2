import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bumped once each time the day earns its streak point (80% of its habits),
/// by the same listener that fires the heavy haptic, the burst and «يوم كامل!
/// يومك انحسب في سلسلتك.» for it (registerDashboardReactions). The day card's
/// sprout celebrates on each bump.
///
/// A counter, not the dashboard's own perfectDayCelebration flag read on
/// rebuild: that flag is true for exactly one state, and two state changes
/// inside one frame would hide it from anything that only looks at the
/// latest state. The reactions listener sees every change as it happens, so
/// the moment is taken from there. It also keeps the sprout clear of the
/// dashboard, whose notifier cannot be built inside a widget test.
final sproutStreakPointProvider = StateProvider<int>((ref) => 0);

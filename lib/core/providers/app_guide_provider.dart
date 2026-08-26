import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/local_store_service.dart';

/// The four on-demand, replayable lessons AppGuideScreen offers. Each one
/// spotlights a real, always-present piece of UI on the relevant tab with
/// [CoachMarkOverlay] - never a copy, never simulated - so "learn it" and
/// "do it" are the same tap. Order matches the natural order someone
/// touches these systems in: build a habit, mark a day, plan a task, find
/// people.
enum AppGuideLesson { addHabit, colorSquare, addTask, discoverRooms }

/// Which lesson (if any) should currently be spotlighted, and on which
/// screen — set by AppGuideScreen when a lesson row is tapped (alongside
/// requestedHomeTabProvider, to also jump to the right tab), read by
/// whichever of GridScreen/MatrixScreen/ProfileScreen owns that lesson's
/// target, cleared by that same screen once its CoachMarkOverlay is
/// dismissed.
///
/// Nothing here is "seen" - the same lesson can be set any number of times.
/// That's the point of living in Settings as something to revisit any time,
/// rather than a one-shot tour you either catch on day one or never see.
final activeAppGuideLessonProvider =
    StateProvider<AppGuideLesson?>((ref) => null);

// There used to be an `autoShowAppGuideProvider` here: a one-shot flag
// OnboardingScreen set on finish, which made main.dart push this whole
// screen on top of the Grid half a second after a new user first reached it.
// It's gone. A first-time user now meets exactly one teacher — the Get
// Started checklist on the Grid — and finds this guide through the "new" dot
// on its Settings row whenever they want it. Everything below still works
// identically when they do; only the uninvited entrance was removed.

/// The guide row's own title and one-line "why" — kept here beside the
/// coach-mark copy rather than inline in AppGuideScreen, because the Grid's
/// guide card renders the same steps and the two must never word them
/// differently.
String appGuideLessonTitle(AppGuideLesson lesson, bool isAr) =>
    switch (lesson) {
      AppGuideLesson.addHabit => isAr ? 'أضف عادة' : 'Add a habit',
      // "Color", not "Colour" — this string renders on the Grid directly
      // beside "Color your life, one square at a time." and "Tap to color",
      // so the one British spelling in the app was visibly inconsistent with
      // its own neighbours on the first screen a new user sees.
      AppGuideLesson.colorSquare => isAr ? 'لوّن مربّع اليوم' : "Color today's square",
      AppGuideLesson.addTask => isAr ? 'أضف مهمة' : 'Add a task',
      AppGuideLesson.discoverRooms => isAr ? 'انضم لغرفة' : 'Join a Room',
    };

String appGuideLessonSubtitle(AppGuideLesson lesson, bool isAr) =>
    switch (lesson) {
      AppGuideLesson.addHabit =>
        isAr ? 'ابدأ بشيء تبي تبنيه' : 'Start something you want to build',
      // The core loop, and the reason the app exists — worded as the promise
      // rather than the mechanic.
      AppGuideLesson.colorSquare =>
        isAr ? 'هذي هي اللعبة كلها' : 'This is the whole thing',
      AppGuideLesson.addTask =>
        isAr ? 'رتّب يومك في أربع خانات' : 'Sort your day into four boxes',
      AppGuideLesson.discoverRooms =>
        isAr ? 'تحدَّ أهلك وربعك' : 'Team up with friends',
    };

/// Short, imperative copy for the coach-mark card itself — centralized here
/// rather than written separately inside each of the three screens that
/// render one, so the wording can't quietly drift between, say, what
/// AppGuideScreen's list row promises and what the coach-mark on Grid
/// actually says once you get there.
// Switch expressions (matching categoryVisual's style in grid_screen.dart)
// rather than switch statements — the compiler enforces every AppGuideLesson
// value is covered, so adding a 5th lesson later without updating these two
// functions is a build error here, not a silent missing-copy bug at runtime.
String appGuideLessonCoachTitle(AppGuideLesson lesson, bool isAr) =>
    switch (lesson) {
      AppGuideLesson.addHabit =>
        isAr ? 'اضغط هنا لإضافة عادتك' : 'Tap here to add your habit',
      AppGuideLesson.colorSquare =>
        isAr ? 'اضغط على مربع لتلوّنه' : 'Tap a square to color it in',
      AppGuideLesson.addTask =>
        isAr ? 'اضغط + لإضافة مهمتك' : 'Tap + to add your task',
      AppGuideLesson.discoverRooms => isAr
          ? 'اضغط هنا للانضمام لغرفة أو إنشائها'
          : 'Tap here to join or create a room',
    };

String appGuideLessonCoachBody(AppGuideLesson lesson, bool isAr) =>
    switch (lesson) {
      AppGuideLesson.addHabit => isAr
          ? 'هذا هو الزر الحقيقي. جرّبه بنفسك.'
          : "This is the real button. Give it a try.",
      // One tap means done — the cycle stopped passing through yellow (see
      // SquareState.next), so promising a yellow step here taught the very
      // first thing a new person tries about the board incorrectly.
      AppGuideLesson.colorSquare => isAr
          ? 'ضغطة وحدة تخلّص العادة. اضغط مطولاً لخيارات أكثر.'
          : 'One tap marks it done. Long-press for more options.',
      AppGuideLesson.addTask => isAr
          ? 'رتّب مهامك حسب الأهمية والإلحاح.'
          : "Sort tasks by how important and how urgent they are.",
      AppGuideLesson.discoverRooms => isAr
          ? 'تحدَّ أصدقاءك وحافظوا على عاداتكم معاً.'
          : 'Challenge friends and keep habits together.',
    };

// ─── "Discover Rooms" completion ───────────────────────────────────────────
//
// The other three lessons derive "done" from real data that already exists
// (habitListProvider non-empty, dashboardProvider's cumulativeXp > 0,
// matrixProvider's tasks non-empty — see AppGuideScreen). Rooms has no
// equivalent: guests can't join or create a room at all (RoomsHubScreen's
// own _GuestGate covers that), and a signed-in person might visit without
// ever joining one, so "is in a room" would never fire for a guest and
// might never fire for a curious signed-in person either. This just
// remembers "AppGuideScreen sent them to see where Rooms lives" — discovery
// is the actual teaching goal here, not participation.

const _kAppGuideRoomsSeenKey = 'app_guide_rooms_seen_v1';

final appGuideRoomsSeenProvider = StateProvider<bool>((ref) => false);

Future<void> markAppGuideRoomsSeen(WidgetRef ref) async {
  ref.read(appGuideRoomsSeenProvider.notifier).state = true;
  final box = await LocalStoreService.settingsBox();
  await box.put(_kAppGuideRoomsSeenKey, true);
}

/// Reads the persisted flag, if any. Called once at boot (see main.dart) to
/// seed [appGuideRoomsSeenProvider] before the first frame.
Future<bool> loadPersistedAppGuideRoomsSeen() async {
  final box = await LocalStoreService.settingsBox();
  return box.get(_kAppGuideRoomsSeenKey) as bool? ?? false;
}

// ─── "New" badge on the Settings entry point ───────────────────────────────
//
// A small dot on the App Guide row until it's been opened once — the same
// "new feature" convention most settings screens already use, and simpler
// than trying to time a nudge off the Get Started checklist's own
// completion moment. Opening the screen once is enough to earn it forever.
//
// This dot is now the ONLY way a new user is pointed at the guide, since
// finishing onboarding no longer pushes the screen at them — which makes it
// the whole discovery story rather than a supporting one: present, quiet,
// and waiting until someone is curious instead of shouting on day one.

const _kAppGuideBadgeSeenKey = 'app_guide_badge_seen_v1';

final appGuideBadgeSeenProvider = StateProvider<bool>((ref) => false);

Future<void> markAppGuideBadgeSeen(WidgetRef ref) async {
  ref.read(appGuideBadgeSeenProvider.notifier).state = true;
  final box = await LocalStoreService.settingsBox();
  await box.put(_kAppGuideBadgeSeenKey, true);
}

/// Reads the persisted flag, if any. Called once at boot (see main.dart) to
/// seed [appGuideBadgeSeenProvider] before the first frame.
Future<bool> loadPersistedAppGuideBadgeSeen() async {
  final box = await LocalStoreService.settingsBox();
  return box.get(_kAppGuideBadgeSeenKey) as bool? ?? false;
}

/// One stable [GlobalKey] per lesson target that a *stateless* ConsumerWidget
/// needs to point a coach-mark at, cached for the life of the app via
/// Riverpod's plain `Provider` rather than recreated on every rebuild.
///
/// Grid's and Matrix's targets live on `State` objects
/// (`_GridScreenState`/`_MatrixScreenState`) that already persist across
/// rebuilds, so their keys are just ordinary `final` fields there — no
/// provider needed. Profile's Rooms row has no such object (`
/// _ProfileLinksSection` is a plain `ConsumerWidget`, rebuilt fresh each
/// time), so a `GlobalKey` field would be a *new* key every rebuild and
/// silently break any coach-mark already pointed at the old one. This
/// provider is the fix: constructed once, read from anywhere.
final roomsRowKeyProvider = Provider<GlobalKey>((ref) => GlobalKey());

/// Same fix, same reasoning, for RoomsHubScreen's own Create/Join button
/// row (also a plain `ConsumerWidget`) — the second half of the
/// discoverRooms lesson. Tapping through Profile's Rooms row (above)
/// deliberately leaves [activeAppGuideLessonProvider] set to
/// [AppGuideLesson.discoverRooms] rather than clearing it, precisely so
/// RoomsHubScreen can pick the same lesson back up and circle *these*
/// buttons next — one lesson, two screens, two coach-marks in sequence,
/// so the person is shown both "where Rooms lives" and "what to actually
/// do once you're there" instead of being dropped at the door.
final roomsActionButtonsKeyProvider = Provider<GlobalKey>((ref) => GlobalKey());

# Build/Release Lessons

Running log of real build failures hit while getting GrowDaily to TestFlight,
and the rule each one taught. Read this before making non-trivial edits to
`main.dart`, `pubspec.yaml`, or anything native (`ios/`) — most of these are
the kind of mistake that's easy to repeat because it only shows up at
compile/build time, not on a plain code read.

**Context for whoever's fixing things (including future-me):** this repo is
usually edited without a Flutter/Dart SDK available to compile or run
against. Manual code review catches logic bugs but not the errors below —
those only surface when the user actually runs `flutter analyze` or
`flutter build`. Treat any fix made without a real compiler run as
provisional until the user confirms it, and proactively ask for
`flutter analyze` output after any change that touches widget constructors,
package APIs, or `const` expressions.

## Working convention: new features get researched first, automatically

When the ask is a genuinely new feature (not a bug fix or a tweak to
something that already exists), research it properly before proposing
anything or writing code: how competitors handle it, what the real
technical options are (packages, native APIs, their actual capabilities and
limits — verified against docs/source, not assumed from memory), and how it
fits what's already in this codebase. Then come back with a concrete
recommendation plus the specific questions that are genuinely the user's
call to make (scope, premium vs free, which tradeoff to take) — not a
request for permission to go do the research in the first place.

This is the default. Do it without being asked each time.

## 1. Private widget constructors need `super.key` if ever used with an explicit key

**What broke:** `AnimatedSwitcher`'s children need distinct keys so it can
tell old/new apart. `_LanguageGate` passed
`const _AuthGate(key: ValueKey('auth-gate'))`, but `_AuthGate`'s constructor
was `const _AuthGate();` — no `key` parameter accepted.

```
lib/main.dart:163:29: Error: No named parameter with the name 'key'.
```

**Rule:** any time a widget is constructed with `key: ...`, its constructor
must declare `{super.key}` (or `{Key? key}` + `super(key: key)` for older
style). This applies even to small private (`_Foo`) widgets — check the
constructor, don't assume.

## 2. Bundle ID must be set in Xcode *before* running `flutterfire configure`

**What broke:** `flutter create --platforms=ios .` scaffolds the default
placeholder bundle ID (`com.example.growDailyV2`). Running
`flutterfire configure` before changing it in Xcode registered a brand-new,
wrong Firebase iOS app under that placeholder ID and overwrote
`firebase_options.dart` / `GoogleService-Info.plist` with it. This then
caused an App Store Connect upload rejection ("no matching app records
found") because the real archive's bundle ID never matched anything
registered.

**Rule:** set the real bundle ID in Xcode (Signing & Capabilities) *first*,
confirm it's correct, *then* run `flutterfire configure`.

## 3. `flutter_launcher_icons` crashes entirely if `android: true` with no `android/` folder

**What broke:** with only `ios/` scaffolded (no `android/`), `dart run
flutter_launcher_icons` hit a `PathNotFoundException` on
`android/app/src/main/AndroidManifest.xml` and **aborted the whole run** —
it never got to generating the iOS icons that come after Android in its
pipeline. (`flutter_native_splash`, by contrast, skips Android gracefully
when the folder is missing — it's specifically `flutter_launcher_icons`
that hard-fails.)

**Rule:** set `android: false` in `pubspec.yaml`'s `flutter_launcher_icons:`
block until the `android/` platform folder actually exists. Flip back to
`true` once `flutter create --platforms=android .` has been run.

## 4. Package version pinned in `pubspec.yaml` may not compile against the installed Flutter SDK

**What broke:** `google_fonts: ^6.2.1` failed at the Dart kernel-snapshot
step of a *release* build (not `flutter analyze` — this one only showed up
in `flutter build ipa`):
```
Error: Constant evaluation error:
The key 'FontWeight {value: 100}' does not have a primitive operator '=='.
```
A known 6.x incompatibility with newer Flutter SDKs, fixed in google_fonts
7.x+.

**Rule:** a clean `flutter analyze` does not guarantee a clean release
build — some errors (const-evaluation issues in third-party packages
especially) only appear during the actual Dart-to-native compile step of
`flutter build`. If a build fails inside a `.pub-cache/hosted/...` path
rather than `lib/...`, suspect a package/SDK version mismatch first, check
`flutter pub outdated`, and try bumping that package.

## 5. `const` expressions can't depend on runtime values

**What broke:** `const Duration(days: 7 * (weeksToShow - 1))` where
`weeksToShow` was a local variable computed from `isPremium ? a : b` at
runtime — not a compile-time constant, so the `const` was invalid.
```
error • Invalid constant value • lib/features/grid/screens/monthly_heatmap_screen.dart:51:45
```

**Rule:** don't reflexively add `const` to every `Duration`/collection
literal — check whether every value inside actually is a compile-time
constant first.

## 6. Converting a `static const` color to a mutable `static` field breaks every `const` call site that touches it

**What changed:** `GameColors.gold`/`.xpBlue`/`.streakOrange` (+ Dim variants)
needed to become mutable (`static Color`, not `static const Color`) so the
new theme-preset system could swap them at runtime. The moment they stopped
being compile-time constants, every `const Icon(...)`, `const TextStyle(...)`,
`const BorderSide(...)`, etc. that referenced them anywhere in the app broke
— Dart requires every value inside a `const` expression to itself be a
compile-time constant.

**Rule:** before making a previously-const value mutable, grep the whole
`lib/` tree for `const ` near that identifier — not just in the file that
declares it. A single-line grep misses multi-line `const Icon(Icons.x,\n
color: GameColors.gold)` calls; use a multiline pattern (e.g. `const
(Icon|TextStyle|BorderSide)\([\s\S]{0,150}?GameColors\.gold`) and check every
hit by hand, since plenty will be false positives where `const` and the
color just happen to be near each other but aren't in the same expression.
This one touched ~35 call sites across 20+ files.

## 7. `flutter create .` overwrites some files without asking

**What happened (not a break, but a gotcha):** running `flutter create
--platforms=ios .` on an existing project regenerated `test/widget_test.dart`
(harmless boilerplate, deleted) and touched `web/index.html`, `.metadata`,
and `pubspec.lock`. It did **not** touch the real hand-written test suite in
`test/`, but check `git status`/`git diff` right after running `flutter
create` on an existing repo, don't assume it only added new files.

## 8. Not every named constructor on a "simple data" class is `const`

**What broke:** `NotificationService.init()` built its Darwin (iOS) settings
as one `const` tree:
```dart
const iosInit = DarwinInitializationSettings(
  ...
  notificationCategories: [
    DarwinNotificationCategory(_habitCategoryId, actions: [
      DarwinNotificationAction.plain(actionMarkDone, 'Mark Done', ...),
```
`DarwinNotificationCategory(...)` itself is const-constructible, but its
named constructor `DarwinNotificationAction.plain(...)` is not — so the
outer `const` failed:
```
error • Const variables must be initialized with a constant value •
  notification_service.dart:100:13 • const_initialized_with_non_constant_value
error • The constructor being called isn't a const constructor •
  notification_service.dart:100:13 • const_with_non_const
```
This is the kind of thing that reads as obviously-fine on a plain code
review — `DarwinInitializationSettings` and `DarwinNotificationCategory`
both look like the same sort of small immutable config object — but a
factory-style named constructor (`.plain`, `.fromX`, etc.) on an otherwise
const-friendly class is not guaranteed to be `const` itself, and there's no
way to tell without either the source or a real analyzer run.

**Rule:** don't assume every named/factory constructor on a class is const
just because the class's default constructor is, especially for
plugin-provided types (`flutter_local_notifications`, and likely others).
If a `const` tree fails like this, the fix is almost always to drop `const`
from the outermost declaration that contains the offending call (here,
`iosInit` became `final`, and the one call site building
`InitializationSettings(...)` from it lost its own `const` too) rather than
hunting for a workaround to keep it const — the object is only built once
per `init()` call, so the runtime-vs-compile-time construction cost is
irrelevant here.

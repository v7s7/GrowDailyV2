# Grow Daily wording inventory

An Excel inventory of every piece of wording a person can read in Grow Daily, in Arabic and English. Each row gives the text in both languages, the reason the developers wrote down for it (the comments above it in the source), where it is defined (file and line, and where each language's text sits when that is elsewhere) and where it shows (the screens and the lines that use it).

## What is in this folder

| Path | What it is |
| --- | --- |
| `GrowDaily-Wording.xlsx` | The workbook. Open the "Read me" sheet first. |
| `README.md` | This file. |
| `generator/pubspec.yaml`, `generator/analysis_options.yaml` | A standalone Dart package (not part of the app) that pins `analyzer` 10.0.2. |
| `generator/bin/extract_dart.dart` | Parses every `.dart` file under `lib/` and writes one row per Arabic and English wording, plus a report of what it skipped. |
| `generator/bin/verify_usage.dart` | Resolves `lib/` with the Dart analyzer and lists every reference to every member, and where each referenced value, string literal and parameter goes next (returned, stored in a field, passed on, shown, written to storage, or dropped). `map_usage.py` runs it. |
| `generator/extract_native.py` | Reads `ios/` (Info.plist, InfoPlist.strings, Swift), `android/`, `functions/` (room push copy), `public/` and `web/`. |
| `generator/map_usage.py` | Finds where each wording is used and names the screen: a text search for the `S` members of `app_strings.dart` and the top-level copy of `reminder_copy.dart` and `daily_quotes.dart`, and, for everything else, the text itself followed along the analyzer's flows to the widgets that draw it. |
| `generator/build_workbook.py` | Joins the JSON into the workbook, then reopens the file and checks it. |
| `generator/bin/gen_wording_edits.dart` | Not part of the workbook: builds the layer that lets the app's wording be edited without a release. See "Editing the wording without a release" below. |
| `generator/.cache/` | Intermediate JSON. Ignored by git, safe to delete. |

## The workbook

| Sheet | Contents |
| --- | --- |
| Read me | What the file is, when it was generated, the git commit and whether the tree was dirty, how to regenerate it, what every column and flag means, and known gaps. |
| Summary | Rows per source group (with Arabic, with English, with a developer reason, with generator notes, with a usage, flagged, unused), the 40 screens with the most strings, and rows per flag (also split by group). `Many screens, through X` is not a screen: it is left out of the ranking and of the distinct-screen count and named apart with its number of strings. |
| All wording | Every row, sorted by group, then rows with a usage before rows with none, then screen, file and line. |
| One sheet per group | App strings (app_strings.dart), Notification and reminder copy, Daily quotes, In-screen strings (other Dart), Help and Support FAQ, iOS system strings, Android system strings, Push notifications (server), Web pages. |
| Flags | Only the rows that carry at least one flag. |

Columns on every data sheet: ID, Group, Screen / where it shows, Section, Key, Arabic, English, Reason (why it is worded this way), Defined in (file:line), Used in (file:line), Placeholders, Flags, Kind, Generator notes. Every data sheet has a frozen header row and an autofilter. Arabic cells are right aligned with right-to-left reading order, except a cell that holds source code after `[dynamic]`, which is left aligned so the code is not reordered.

How the columns are filled:

- **Arabic / English**: the text as written, interpolations as `{name}`, or as the code that computes the value when it is not a plain name (`{daysCount(counted)}`, `{quoted.join('، ')}`). When a side reads differently under different conditions, each reading sits on its own line after the source's own condition: `n == 1: ...`, `n <= 10: ...`, `otherwise: ...`; a reading that is an empty string shows as `(empty)`. A local that builds a piece of a sentence (`final noun = ...`) is written under that sentence as `noun =` with its readings, instead of standing alone as a half-row. That includes a local that is a language test of its own (`final done = isAr ? arabicDigits(weekDone) : '$weekDone'` is `done = {arabicDigits(weekDone)}` under the Arabic sentences that use it and `done = {weekDone}` under the English ones) and a joining word both sentences open with (`_oneQuitSentence`'s `and =` with `lead: (empty)` and `otherwise: و`). A language test with no letter on either side (only placeholders, digits and punctuation) is not a row when both sides are the same (`isAr ? '"$n"' : '"$n"'`) or when it is only a piece of a member whose other rows are wording (the `arabicDigits(minutes)` fallback of `reminderOffsetLabel`); a member whose whole result is one (`formatOffsetMagnitude`) keeps its row. A conditional inside an interpolation is written out the same way, one reading per branch: `appVersion == null: App: Grow Daily` and `otherwise: App: Grow Daily {appVersion}`. When both sides line up case by case (an enum's names, a list of suggestions), each case is its own row, for example `PrayerCalcMethod.label[jordan]`, and a language `?:` inside one arm of a switch is named by that arm's case, for example `HabitCue._presetLabel[fajr]`. When the Arabic has more plural forms than the English (1, 2, 3 to 10, 11 and up against one and many), the Arabic forms that one English form covers share that English form's row. An em dash in live copy shows as `[em dash]`.
- **Reason**: the developers' comments only. The declaration's doc comment comes first, then the comments that sit with the text:
  - above the lines that hold it, and trailing them;
  - inside the language test itself, between `isAr` and `?` or between `?` and the text (`onboardingTasksBody`);
  - above the statement, switch arm, widget or call that holds the text: `// Late...` above `final stamp = ...` for the two rows inside it, the comment above `_SettingsRow(` for its `label:`, the comment above `throw FirebaseAuthException(` for its message. A comment above an `if` counts for every row inside it. The walk stops at the innermost call's statement, at a closure and at the member, so a comment above a whole widget tree does not spread to every text in it;
  - for a statement with no comment of its own, the comment that heads its run of statements when no blank line separates them (`// Zero and the first day are sentences...` above `if (won == 0)` also covers `if (counted == 1)` right under it);
  - the comments of a local written under a sentence.

  Decorative box-drawing rules are dropped, an em dash becomes a comma.
- **Generator notes**: anything the generator has to say, kept out of Reason: which other comment a Reason was taken from, how a web page's English and Arabic were paired, why a Latin-only text has no Arabic, which lines pass an Android channel name.
- **Defined in**: the first line of the declaration that holds the wording (after its doc comment and annotations; for Swift, the `func`, `var` or `struct` around the text). When the text itself sits on other lines or in another file, a second line gives each side's place: `ar: public/reset/index.html:167; en: public/reset/index.html:254`, or `en: ios/GrowDailyWidget/GrowDailyWidget.swift:471` under `GrowDailyWidget.swift:465`. For a row with a local written under it, that is the line of the sentence the cell starts with, not of the local, so `roomLinkedHabitPausedHint#1` and `#2` each point at their own sentence.
- **Screen / Used in**: for `S`, `reminder_copy` and `daily_quotes` members, the using files from `map_usage.py`. For every other Dart row, the places the text itself reaches, found by following it with the Dart analyzer:
  - A catalog entry (an `IslamicHabitTemplate`, `AchievementModel` or `CharacterOption` in a list or constant) is followed from the fields its constructor arguments fill, not from the list that holds it, so `AchievementCatalog.all.length` counts for nothing.
  - A value is followed when it is returned (to the members that call that one), stored in a field (to that field's reads) or passed to a parameter (to that parameter's reads, and back to the same call when the callee hands the parameter straight back, as `toWesternDigits` does). It shows where it is handed to a widget, a notification, the home widget or a thrown exception. It stops, with no screen, where it is written to Firestore or preferences or used for something that is not text (a comparison, a condition, a length, an id, a log line).
  - So an action or a write, such as `DashboardNotifier._resolveUnlocks` or `RoomsController._profileFields`, is never a screen of its own. The "Warrior" fallback in `_profileFields` shows on the Room page through `RoomParticipant.displayName`; the achievement names show on Achievements, the detail sheet, the unlock celebration, the Progress hub and Journey.
  - A method that returns nothing text can carry (void, bool), or whose text it shows itself (a thrown exception, a notification, a widget of its own file), is mapped to the places that call it. A member read on one enum constant (`MilestoneType.levelUp.localizedName`) counts only for that constant's row, and so does one read inside a switch case that has already narrowed its receiver (`case MilestoneType.levelUp:` then `e.type.localizedName(isAr)` in `milestoneHeadline`), so Journey is not named for the types whose arm returns its own sentence.
  - For `S`, `reminder_copy` and `daily_quotes`, a reference that only reads a list's size (`days % kDailyQuotes.length` in `_indexForDay`) is not a use of its text; `usage.json` keeps it apart under `internal_non_text_reads`.
  - `(via X > Y)` in Used in names the steps: a member, a field (`RoomParticipant.displayName`) or a parameter (`toWesternDigits(input)`). Used in has one line per `file:line`: when several chains reach the same line they share it, shortest first, `(via X; or via Y > Z)`, or `(directly; or via X)` when the text also reaches it with no step between. The 15-line cap counts places, not chains. A Riverpod provider, or a member that reaches more than 25 places, is not walked place by place: its line is kept with a note such as `(in IslamicHabitTemplate.localName, which reaches 63 places)`, and Screen names the screens behind it, or `Many screens, through X` past 12.
  - Text in a `build` method with no caller shows where it is written, so its screen is its own file's and Used in is empty. iOS permission prompts name the screens whose action opens them. Push rows list the `functions/index.js` lines that send them.
- **Generator notes** also say which fields a catalog entry was followed from, and list the write lines of text that only goes to stored data.

Flags:

- **em dash**: the Arabic or English wording contains an em dash. The workbook never contains that character itself, so live copy that has one shows the token `[em dash]`.
- **Arabic-Indic digits**: the Arabic wording, as written in the source, contains digits U+0660 to U+0669.
- **Arabic-Indic digits (runtime)**: the Arabic wording puts a number through `arabicDigits()`, so the reader sees Arabic-Indic digits although the source has none: in the placeholder itself, in a local it names (`final d = arabicDigits(done)`, then `{d}`), or in a function that does (`countedOffsetPhrase`, `_countedHabits`; `dart_report.json` lists them under `digit_functions`: only functions that return text, String or a record of strings such as `ReminderLine`, and keep the digits, so not a void scheduler that calls one and not `habitReminderSentence`, which turns them back with `toWesternDigits`).
- **Latin word in Arabic**: the Arabic wording contains Latin letters. The words are listed after the colon (for example `Latin word in Arabic: Premium`). Conditions and placeholders are not counted.
- **missing Arabic** / **missing English**: that side is empty.
- **fragment**: a one-sided piece of a sentence that could not be written under its sentence. Not flagged missing. (None in the current workbook.)
- **same text both languages**: both sides are identical, not counting brand names or text that is only numbers, symbols and placeholders.
- **unused**: no place in `lib/` shows it. For `S`, `reminder_copy` and `daily_quotes`: no usage directly or through another string that is used. For every other Dart row: following the text reached no widget, notification or other place that shows it, because nothing reads the member or field that holds it or its value only goes to comparisons, ids, logs or stored data. The 28 catalog habit descriptions are the largest set: `IslamicHabitTemplate.localDescription` has no caller, and `description` is only copied into other templates, `HabitModel` and Firestore.
- **dynamic**: one side is code that could not be written out as text, so the cell shows it after `[dynamic] `. (None in the current workbook.)

Every count in the workbook is a plain value computed when it was generated. There are no formulas: LibreOffice is not installed on the machine that builds it, so nothing could recalculate them. Regenerate the workbook to refresh the numbers.

## How to regenerate

Needs the Dart SDK (with `analyzer` 10.0.2 already in `~/.pub-cache`, so `pub get` works offline), Python 3 and `openpyxl`. `map_usage.py` also reads the app's `.dart_tool/package_config.json` to resolve `lib/`; if that file is missing, pass `--no-analyzer`.

```sh
cd /Users/aysha/Documents/GrowDailyV2/docs/wording/generator
dart pub get --offline
dart run bin/extract_dart.dart --out .cache/dart_rows.json --report .cache/dart_report.json
python3 extract_native.py
python3 map_usage.py --verify
python3 build_workbook.py
```

The same as one line:

```sh
cd /Users/aysha/Documents/GrowDailyV2/docs/wording/generator && dart pub get --offline && dart run bin/extract_dart.dart --out .cache/dart_rows.json --report .cache/dart_report.json && python3 extract_native.py && python3 map_usage.py --verify && python3 build_workbook.py
```

The order matters: `map_usage.py` reads `dart_rows.json` and `native_rows.json`, and `build_workbook.py` stops with an error when the usage map and the rows were taken from different versions of the sources.

What each step writes, and how long it took on the machine that built the current workbook:

| Step | Output (default) | Time | Other options |
| --- | --- | --- | --- |
| `extract_dart.dart` | `.cache/dart_rows.json` and `.cache/dart_report.json` | about 8 s | Without `--out` the rows go to stdout. `--root <repo>` reads another checkout. |
| `extract_native.py` | `.cache/native_rows.json` and `.cache/native_summary.json` | under 1 s | Pass an output path as the first argument. |
| `map_usage.py` | `.cache/usage.json` | about 50 s | It runs the Dart analyzer once either way; `--verify` reuses that run to check the text-based `S` usage map against it, so it adds almost nothing. `--no-analyzer` skips the analyzer (about 19 s), and then the rows outside `app_strings`, `reminder_copy` and `daily_quotes` only name their own file's screen. Pass an output path as the first argument. |
| `build_workbook.py` | `../GrowDaily-Wording.xlsx` and `.cache/workbook_summary.json` | about 4 s | `--inputs <dir>` reads the JSON from another folder, `--out <file>` writes elsewhere. |

`build_workbook.py` exits non-zero if its own check of the saved workbook fails. The check covers the row counts of every sheet, the headers, autofilters and frozen panes, every row's Arabic and English against the source rows, ids with no spaces or parentheses, formulas, cell alignment, and an em dash anywhere in the workbook or in any text file under `docs/wording` (the generator's code and its `.cache` JSON included).

## Editing the wording without a release

The workbook reads the wording. Since 2026-09-18 the app's own strings can also be changed without a build: Aziz edits them on the Wording page of the admin tool (`scripts/admin_lookup`, `npm start`, then the Wording button), and every open app shows the new text within seconds.

How it fits together:

- The built-in text stays where it is, in `lib/core/l10n/app_strings.dart` and `daily_quotes.dart`. An edit is laid over it, never copied into it.
- The edits live in one Firestore document, `wording/live`: `strings.ar` and `strings.en` (edited text by S member name) and `quotes` (the whole daily rotation, when one has been saved). Anyone can read it, no client can write it (`firestore.rules`); only the admin tool writes, through the Admin SDK. `wording_log` keeps every change for History and Undo, and `wording_admin/state` keeps the built-in text each edit replaced.
- The app reads it in `lib/core/l10n/wording_edits.dart`: this device's saved copy at boot, then a live listener. `S.of(context)` lays the edits over the built-in text, so every screen that shows a string repaints when one is saved.
- `generator/bin/gen_wording_edits.dart` writes `lib/core/l10n/app_strings_edited.g.dart`, a part of `app_strings.dart` that overrides every editable string by name, and the admin tool's catalog (`scripts/admin_lookup/wording/catalog.json`, gitignored, which the tool rebuilds itself when `app_strings.dart` changes).

Which strings can be edited: an S member whose whole body is `isAr ? '...' : '...'`, with any values it fills in written as `{parts}`, the same notation as this workbook. That is 1,251 of the 1,307 strings in S. The other 56 pick between several wordings in code (one day, two days, three days; a state; a case), so they stay built-in only rather than being flattened into one sentence. Text outside S (the in-screen strings of other files, reminders, the FAQ, iOS and Android system strings, the server's push copy) is not editable yet.

After adding, removing or renaming a string in S, or changing a method's parameters, rerun:

```sh
cd /Users/aysha/Documents/GrowDailyV2/docs/wording/generator && dart run bin/gen_wording_edits.dart
```

Until then a new string is simply not editable (and `test/core/wording_edits_test.dart` fails, naming it), while a removed, renamed or re-parameterised one stops the build at the stale line of `app_strings_edited.g.dart`. `--check` exits 1 when the generated part is out of date, without writing anything.

## Rules the tools keep

- They only read the app. Nothing under `lib/`, `test/`, `ios/`, `android/`, `functions/`, `public/` or `web/` is written, and nothing is built. The extractors read the working tree, so uncommitted edits are included; the Read me sheet records the commit and whether the tree was dirty.
- No em dash is written anywhere: not in the workbook, not in the JSON, not in this folder's files.
- Rows with no language branch are still rows. Latin-only text an Arabic reader sees as written (the "Grow Daily" wordmark, "PRO", "+{xp} XP" chips, AM and PM, the font names, the medal numerals I to IV, the "Warrior" fallback display name, the support mail's "App:", "Platform:" and "Language:" lines, exception messages that may reach the user) has ids ending in `.latin_only` and an empty Arabic side. `S` members that return one pattern for both languages, such as `comebackBonusAmount` (`+{xp} XP`), carry the pattern on both sides. The Android notification channel names and descriptions from `notification_service.dart` are rows in the Android system strings group.

## Known gaps

The Read me sheet lists them in full. In short: Arabic literals in `lib/` that are not wording (keyword matchers, the moderation blocklist, digit tables) have no row and are listed in `dart_report.json` under `uncovered_arabic_literals`; language conditionals that are not wording (join separators such as `isAr ? '، ' : ', '`, a lone «و» / "and" used as a join, pieces with no letter on either side, locale code pairs, a date format pattern, an internal theme id) have no row either and are listed under `skipped_conditionals` with their reason; text is not followed through stored data, so a value written to Firestore and read back by key elsewhere is not traced to that reader, and text that only reaches storage is flagged unused; all Swift text is English only because the widget extension has no `.lproj` folder; the usage maps scan only `lib/`, so a string used only by tests counts as unused, and a member called only through a supertype or a dynamic call has no resolved reference; a file that holds several surfaces has one screen name; and the Section column is the nearest banner comment, which is sometimes only loosely related.

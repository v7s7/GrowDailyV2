/// Wording edited from the admin tool after a build shipped.
///
/// ── Why this exists ─────────────────────────────────────────────────────
/// Aziz, 2026-09-18, on a daily quote he found unclear: "we need to store
/// them somewhere, where I have admin side, where I can edit them and they
/// auto change in all screens". Until now every sentence in the app lived in
/// code, so changing a word meant a build and an App Store review.
///
/// The built-in text stays exactly where it is (app_strings.dart,
/// daily_quotes.dart) and stays the source of every line. This is a thin
/// layer of EDITS laid over it, and everything here is built so that no edit
/// can make a screen worse than the built-in text would have been.
///
/// ── Where the edits live ────────────────────────────────────────────────
/// One Firestore document, [kWordingDocPath]:
///
///   strings  {ar: {key: text}, en: {key: text}}  one entry per edited S member
///   quotes   [{ar, en}, ...]                     the whole daily rotation, or absent
///   version  int                                 bumped by every save
///
/// Anyone may read it (guests have no Firebase account, and every word in it
/// ships inside the app anyway); nobody may write it from a client. The only
/// writer is the admin tool's Wording page (scripts/admin_lookup), through
/// the Admin SDK, which is the whole of "the admin side".
///
/// ── How an edit reaches a screen ────────────────────────────────────────
/// [WordingEditsStore.live] holds the edits in force. main() seeds it from
/// this device's own copy before the first frame, so an edit never flashes
/// the old text on launch, then [WordingEditsStore.listen] keeps it current.
/// The app root puts it in a [WordingScope], and `S.of(context)` reads that
/// scope, which is what registers every widget that shows a string to
/// rebuild when an edit lands: a save on the Mac repaints open screens
/// within a second or two, with no restart.
///
/// ── What an edit cannot do ──────────────────────────────────────────────
/// Blank a line: an empty or all-space edit is dropped here and the built-in
/// text shows. Show a raw `{name}`: an edit's `{parts}` are filled by the
/// app from a fixed list per string (see [fillWording]), and an edit that
/// names a part the app cannot fill is set aside for the built-in text. The
/// admin tool refuses such a part when it is saved, so this only happens
/// when the code has since renamed or dropped one. Reach a string the
/// generator did not mark editable: an edit under any other key is simply
/// never read.
library;

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:hive/hive.dart';

import '../services/local_store_service.dart';
import 'daily_quotes.dart';

/// The one document the admin tool writes and every device reads.
const String kWordingDocPath = 'wording/live';

/// The edits in force at one moment. Immutable: a change is a new instance,
/// which is what lets [WordingScope] tell listeners apart by identity.
@immutable
class WordingEdits {
  const WordingEdits({
    this.ar = const {},
    this.en = const {},
    this.quotes,
    this.version = 0,
  });

  /// No edits: every string and quote is the built-in one.
  static const empty = WordingEdits();

  /// Edited Arabic, by S member name.
  final Map<String, String> ar;

  /// Edited English, by S member name.
  final Map<String, String> en;

  /// The whole daily rotation when the admin saved one, null for the
  /// built-in [kDailyQuotes]. Never empty: an empty list would leave the
  /// Grid with no line at all, so it parses to null instead.
  final List<DailyQuote>? quotes;

  /// The admin tool's save counter. Informational only; nothing orders
  /// snapshots by it, because Firestore already delivers them in order.
  final int version;

  /// The edits for the language [S] renders [languageCode] in. S reads every
  /// language but Arabic as English, so this does too.
  Map<String, String> stringsFor(String languageCode) =>
      languageCode == 'ar' ? ar : en;

  bool get isEmpty => ar.isEmpty && en.isEmpty && quotes == null;

  /// The document as Firestore (or this device's cached copy) holds it.
  ///
  /// Parsed entry by entry, never trusted whole: a malformed entry costs
  /// that entry and nothing else, the same rule the account loader has
  /// followed since one malformed map field bricked a whole account.
  /// Anything unreadable parses to [empty].
  factory WordingEdits.fromData(Object? data) {
    if (data is! Map) return empty;
    final strings = data['strings'];
    final version = data['version'];
    return WordingEdits(
      ar: _stringMap(strings is Map ? strings['ar'] : null),
      en: _stringMap(strings is Map ? strings['en'] : null),
      quotes: _quoteList(data['quotes']),
      version: version is num ? version.toInt() : 0,
    );
  }

  static Map<String, String> _stringMap(Object? raw) {
    if (raw is! Map) return const {};
    final out = <String, String>{};
    raw.forEach((key, value) {
      if (key is String && value is String && value.trim().isNotEmpty) {
        out[key] = value;
      }
    });
    return Map.unmodifiable(out);
  }

  static List<DailyQuote>? _quoteList(Object? raw) {
    if (raw is! List) return null;
    final out = <DailyQuote>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final ar = entry['ar'];
      final en = entry['en'];
      if (ar is String &&
          en is String &&
          ar.trim().isNotEmpty &&
          en.trim().isNotEmpty) {
        out.add(DailyQuote(ar: ar.trim(), en: en.trim()));
      }
    }
    return out.isEmpty ? null : List.unmodifiable(out);
  }

  /// The shape [WordingEdits.fromData] reads back, for this device's cache.
  Map<String, Object?> toJson() => {
        'strings': {'ar': ar, 'en': en},
        if (quotes != null)
          'quotes': [
            for (final q in quotes!) {'ar': q.ar, 'en': q.en},
          ],
        'version': version,
      };
}

/// A `{part}` as the admin tool writes one: braces around anything that is
/// neither a brace nor a line break. The same pattern as partsIn in
/// scripts/admin_lookup/wording/rules.js, which refuses unknown parts at save.
final RegExp _wordingPart = RegExp(r'\{([^{}\n]+)\}');

/// Whether every `{part}` in [edit] is one of [known].
///
/// The admin tool will not save an edit that names a part the app cannot
/// fill, so a live edit that does was written for a sentence the code has
/// changed since (a value renamed, or dropped). Showing it would put a raw
/// `{name}` in front of every reader; the callers show the built-in text
/// instead, until the edit is fixed on the Wording page, where that string
/// is flagged as changed in code.
bool wordingPartsKnown(String edit, Iterable<String> known) {
  if (!edit.contains('{')) return true;
  for (final m in _wordingPart.allMatches(edit)) {
    if (!known.contains(m.group(1))) return false;
  }
  return true;
}

/// [edit] for a string that fills no values, or null when there is no edit
/// or it names a part (see [wordingPartsKnown]): the generated overrides use
/// the built-in text then.
String? plainWording(String? edit) =>
    edit == null || wordingPartsKnown(edit, const []) ? edit : null;

/// [template] with every `{token}` in it replaced by that token's value, or
/// null when it names a part that is not one of [tokens] (see
/// [wordingPartsKnown]), so the caller shows the built-in text.
///
/// The generated S overrides (app_strings_edited.g.dart) call this with the
/// tokens the built-in sentence interpolates, each computed by the same
/// expression the built-in sentence uses, so `{daysInSentence(days)}` in an
/// edit still reads «3 أيام» or «يومين» as the number requires.
///
/// One pass, left to right: a value that itself contains braces (a habit
/// someone named "{level}") is written as it is and never filled a second
/// time. Each value is computed only if its token actually appears.
String? fillWording(String template, Map<String, String Function()> tokens) {
  if (!template.contains('{')) return template;
  if (!wordingPartsKnown(template, tokens.keys)) return null;
  final out = StringBuffer();
  var i = 0;
  outer:
  while (i < template.length) {
    if (template.codeUnitAt(i) == 0x7B) {
      for (final entry in tokens.entries) {
        if (template.startsWith('{${entry.key}}', i)) {
          out.write(entry.value());
          i += entry.key.length + 2;
          continue outer;
        }
      }
    }
    out.writeCharCode(template.codeUnitAt(i));
    i++;
  }
  return out.toString();
}

/// Where the wording document is read from in a debug build started with
/// `--dart-define=WORDING_EMULATOR=127.0.0.1:8080`: a local Firestore
/// emulator, through a second Firebase app, so ONLY the wording listener
/// moves there and every account read and write stays on the real project.
///
/// This is how an edit can be tried on the simulator without touching what
/// real phones read: run the emulator (`firebase emulators:start --only
/// firestore`), run the admin tool against it (`FIRESTORE_EMULATOR_HOST=
/// 127.0.0.1:8080 PORT=4199 npm start`), and save on that tool's Wording
/// page. Null, the real project, in every other build: the define is empty
/// and a release build compiles this away entirely.
Future<FirebaseFirestore?> wordingEmulatorFirestore() async {
  const target = String.fromEnvironment('WORDING_EMULATOR');
  if (!kDebugMode || target.isEmpty) return null;
  final hostAndPort = target.split(':');
  final app = await Firebase.initializeApp(
    name: 'wording-emulator',
    options: Firebase.app().options,
  );
  final db = FirebaseFirestore.instanceFor(app: app)
    ..useFirestoreEmulator(
      hostAndPort.first,
      int.parse(hostAndPort.length > 1 ? hostAndPort[1] : '8080'),
    );
  debugPrint('[wording] reading edits from the emulator at $target');
  return db;
}

/// Holds the edits in force and keeps them current.
class WordingEditsStore {
  WordingEditsStore._();

  /// Where this device keeps its last copy, in the settings box. A JSON
  /// string rather than a nested map, so a Hive type quirk can never turn a
  /// read of it into an exception at boot.
  static const String cacheKey = 'wording_edits_v1';

  /// The edits in force. Built-in wording (empty) until [loadCached] or the
  /// listener says otherwise.
  static final ValueNotifier<WordingEdits> live =
      ValueNotifier(WordingEdits.empty);

  static WordingEdits get current => live.value;

  static StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  static AppLifecycleListener? _resumeRetry;
  static String _currentJson = jsonEncode(WordingEdits.empty.toJson());

  /// Seeds [live] from the copy this device saved when it last heard from
  /// the server. Called once in main() before runApp, so the first frame
  /// already carries the edits instead of flashing the built-in text and
  /// then swapping. Never throws: an unreadable copy means built-in text
  /// until the listener delivers.
  static Future<void> loadCached([Box<dynamic>? box]) async {
    try {
      final settings = box ?? await LocalStoreService.settingsBox();
      final raw = settings.get(cacheKey);
      if (raw is String) _publish(WordingEdits.fromData(jsonDecode(raw)));
    } catch (e) {
      debugPrint('[wording] cached edits unreadable, using built-in: $e');
    }
  }

  /// Follows [kWordingDocPath] for as long as the app runs. Safe to call
  /// again: it only attaches when no listener is running.
  ///
  /// A listener stops for good on its first error (Firestore closes the
  /// stream). The likeliest error is permission-denied, before the rule
  /// that opens this document is deployed or on a build older than it, and
  /// a phone that met it once should not need a restart to recover. So a
  /// stopped listener is re-attached the next time the app comes to the
  /// foreground ([retryOnResume]; off in tests, which have no app lifecycle).
  ///
  /// Costs one document read when it attaches and one per save, for every
  /// open app. There is one document, and it changes when Aziz edits.
  static void listen({
    FirebaseFirestore? firestore,
    Box<dynamic>? box,
    bool retryOnResume = true,
  }) {
    if (retryOnResume) {
      _resumeRetry ??= AppLifecycleListener(
        onResume: () => listen(firestore: firestore, box: box),
      );
    }
    if (_sub != null) return;
    final db = firestore ?? FirebaseFirestore.instance;
    _sub = db.doc(kWordingDocPath).snapshots().listen(
      (snap) {
        // "No such document" from Firestore's own cache only means this
        // device has not heard from the server yet. Taken at its word it
        // would wipe the copy loadCached just applied and flash the
        // built-in text until the server answered. Only the server can say
        // there are no edits; a cached document that EXISTS is the last
        // thing the server said, and is safe to apply.
        if (!snap.exists && snap.metadata.isFromCache) return;
        unawaited(
          _receive(
            snap.exists
                ? WordingEdits.fromData(snap.data())
                : WordingEdits.empty,
            box,
          ),
        );
      },
      onError: (Object e) {
        debugPrint('[wording] listener stopped, built-in or cached text '
            'stays: $e');
        _sub = null;
      },
    );
  }

  static Future<void> _receive(WordingEdits edits, Box<dynamic>? box) async {
    if (!_publish(edits)) return;
    try {
      final settings = box ?? await LocalStoreService.settingsBox();
      // The latest edits at the moment of writing, not the ones this call
      // was handed: two snapshots in quick succession then both write the
      // newer copy, and the cache can never end on the older one.
      if (live.value.isEmpty) {
        await settings.delete(cacheKey);
      } else {
        await settings.put(cacheKey, _currentJson);
      }
    } catch (e) {
      debugPrint('[wording] could not keep a copy of the edits: $e');
    }
  }

  /// Makes [edits] the ones in force. False when they are what is already
  /// in force, so an unchanged snapshot (the cache replaying, a reconnect)
  /// rebuilds nothing and writes nothing.
  static bool _publish(WordingEdits edits) {
    final json = jsonEncode(edits.toJson());
    if (json == _currentJson) return false;
    _currentJson = json;
    live.value = edits;
    return true;
  }

  /// Puts [edits] in force as if the listener had delivered them, without
  /// Firestore or the cache.
  @visibleForTesting
  static void debugPublish(WordingEdits edits) => _publish(edits);

  /// Stops listening and goes back to built-in wording.
  @visibleForTesting
  static Future<void> reset() async {
    await _sub?.cancel();
    _sub = null;
    _resumeRetry?.dispose();
    _resumeRetry = null;
    _publish(WordingEdits.empty);
  }
}

/// Makes the edits in force visible to everything below it.
///
/// `S.of(context)` and the Grid's daily quote read it through [of], which
/// registers them as dependents: when the edits change, exactly the widgets
/// that show wording rebuild, on every open route, dialog and sheet.
class WordingScope extends InheritedWidget {
  const WordingScope({super.key, required this.edits, required super.child});

  final WordingEdits edits;

  /// The edits in force for [context]. Outside any scope, which only
  /// happens in a test that pumps a bare widget, the store's own current
  /// edits, which in a test are empty unless it set some.
  static WordingEdits of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WordingScope>()?.edits ??
      WordingEditsStore.current;

  @override
  bool updateShouldNotify(WordingScope oldWidget) =>
      !identical(oldWidget.edits, edits);
}

/// A [WordingScope] that follows [WordingEditsStore.live]. Mounted once, at
/// the app root, around the Navigator.
class WordingEditsHost extends StatelessWidget {
  const WordingEditsHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<WordingEdits>(
        valueListenable: WordingEditsStore.live,
        builder: (context, edits, child) =>
            WordingScope(edits: edits, child: child!),
        child: child,
      );
}

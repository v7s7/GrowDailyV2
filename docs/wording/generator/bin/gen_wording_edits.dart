// Builds the editable-wording layer from the app's own strings.
//
// Aziz asked on 2026-09-18 for the wording to live somewhere he can edit it
// himself, with an edit reaching every screen without a release. The app
// side of that is lib/core/l10n/wording_edits.dart; this script writes the
// two files that tie it to the strings:
//
//   lib/core/l10n/app_strings_edited.g.dart
//     A part of app_strings.dart. A subclass of S that returns the admin's
//     edit for a string when there is one and the built-in text otherwise.
//     It overrides every editable string BY NAME, which is why it has to be
//     rebuilt when a string is added, removed or renamed, or a method's
//     parameters change. Until then the build stops at the stale line.
//
//   scripts/admin_lookup/wording/catalog.json
//     Everything the admin tool's Wording page lists: every S string with its
//     built-in Arabic and English, its section, the comments written above
//     it, the screens that show it, and whether it can be edited; plus the
//     built-in daily quotes. Gitignored: the admin tool reruns this script
//     with --catalog-only whenever app_strings.dart or daily_quotes.dart has
//     changed since the catalog it holds.
//
// Usage, from docs/wording/generator:
//   dart run bin/gen_wording_edits.dart                 write both files
//   dart run bin/gen_wording_edits.dart --check         write nothing, exit 1 if the part is out of date
//   dart run bin/gen_wording_edits.dart --catalog-only  write only the catalog
//   add --root <repo> to read another checkout
//
// Which strings can be edited: a public S member whose whole body is
// `isAr ? '...' : '...'`, two plain sentences, however many values they
// interpolate. That is 96% of S. The rest pick between several wordings in
// code (one day, two days, three days; a state; a switch), and an edit that
// replaced all of them with one sentence would break the plural or the
// state, so they are listed as built-in only rather than made editable
// badly.
//
// An interpolated value becomes a token named by its own source,
// `{daysInSentence(days)}`, the same notation the wording workbook uses. The
// generated override computes each token with the very expression the
// built-in sentence uses, so an edit that keeps `{daysInSentence(days)}`
// keeps the plural that comes with it.
//
// The usage map (screens) is read from .cache/usage.json when it exists,
// which the wording workbook's own pipeline writes (see ../README.md). The
// script works without it; the screens are then left empty.

import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

const _appStringsPath = 'lib/core/l10n/app_strings.dart';
const _quotesPath = 'lib/core/l10n/daily_quotes.dart';
const _partPath = 'lib/core/l10n/app_strings_edited.g.dart';
const _catalogPath = 'scripts/admin_lookup/wording/catalog.json';
const _usagePath = 'docs/wording/generator/.cache/usage.json';

/// Names the generated override uses for its own locals and fields. A
/// parameter with one of these names would be shadowed, so the script
/// refuses rather than emit code that quietly reads the wrong value.
const _reservedNames = {'wordingEdit', '_edits'};

const _builtInOnlyWhy =
    'Has more than one wording, picked in code (by a number, a state or a '
    'case), so it can only be reworded in the app\'s code.';
const _listWhy =
    'A list offered together (suggestions), so it can only be reworded in '
    'the app\'s code.';

void main(List<String> args) {
  final check = args.contains('--check');
  final catalogOnly = args.contains('--catalog-only');
  final root = _option(args, '--root') ?? _findRoot();
  if (root == null) {
    stderr.writeln('Could not find the repo: no $_appStringsPath above '
        '${Directory.current.path}. Pass --root <repo>.');
    exit(2);
  }

  final stringsSource = File('$root/$_appStringsPath').readAsStringSync();
  final quotesSource = File('$root/$_quotesPath').readAsStringSync();
  final members = _readMembers(stringsSource);
  final usage = _readUsage('$root/$_usagePath');

  // --check looks at the part only. The catalog is the admin tool's own
  // file: gitignored, and rebuilt by the tool itself (--catalog-only) when it
  // finds app_strings.dart has moved on, so it is never "out of date" in a
  // way anyone else has to act on.
  final outputs = <String, String>{
    if (!check)
      _catalogPath: _catalogJson(
        members: members,
        quotes: _readQuotes(quotesSource),
        stringsSource: stringsSource,
        quotesSource: quotesSource,
        usage: usage,
      ),
    if (!catalogOnly) _partPath: _partSource(members),
  };

  var stale = 0;
  for (final entry in outputs.entries) {
    final file = File('$root/${entry.key}');
    final current = file.existsSync() ? file.readAsStringSync() : null;
    if (current == entry.value) continue;
    stale++;
    if (check) {
      stderr.writeln('${entry.key} is out of date.');
    } else {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(entry.value);
      stdout.writeln('wrote ${entry.key}');
    }
  }

  final editable = members.where((m) => m.editable).length;
  stdout.writeln('${members.length} strings in S: $editable editable, '
      '${members.length - editable} built-in only.'
      '${usage == null ? ' No $_usagePath, so no screens.' : ''}');
  if (check && stale > 0) {
    stderr.writeln('Rerun: cd docs/wording/generator && '
        'dart run bin/gen_wording_edits.dart');
    exit(1);
  }
  if (check) stdout.writeln('Up to date.');
}

String? _option(List<String> args, String name) {
  final i = args.indexOf(name);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
}

/// The nearest directory at or above the working directory that holds the
/// app's strings, so the script runs the same from any folder in the repo.
String? _findRoot() {
  var dir = Directory.current.absolute;
  while (true) {
    if (File('${dir.path}/$_appStringsPath').existsSync()) return dir.path;
    final parent = dir.parent;
    if (parent.path == dir.path) return null;
    dir = parent;
  }
}

// ─── Reading S ──────────────────────────────────────────────────────────────

class _Member {
  _Member({
    required this.key,
    required this.kind,
    required this.line,
    required this.section,
    required this.notes,
    required this.editable,
    required this.params,
    required this.superArgs,
    required this.ar,
    required this.en,
    required this.tokensAr,
    required this.tokensEn,
  });

  final String key;

  /// 'getter', 'method', or 'list' (a List<String> member, never editable).
  final String kind;
  final int line;
  final String section;
  final String notes;
  final bool editable;

  /// The member's own parameter list, as written, for a method.
  final String params;

  /// The arguments that hand those parameters straight to `super`.
  final String superArgs;

  /// Built-in text with every interpolated value written as `{source}`. For a
  /// built-in-only member, every wording its body contains, one per line.
  final String ar;
  final String en;
  final List<String> tokensAr;
  final List<String> tokensEn;

  /// The code that computes each token, by token, for the generated
  /// override. Usually the token itself; a static member of S is qualified
  /// (`S._byAmount(amount)`), because a subclass cannot call its
  /// superclass's statics by their bare name.
  Map<String, String> tokenCode = const {};

  bool get hasTokens => tokensAr.isNotEmpty || tokensEn.isNotEmpty;
}

List<_Member> _readMembers(String source) {
  final unit = parseString(content: source, throwIfDiagnostics: false).unit;
  final s = unit.declarations
      .whereType<ClassDeclaration>()
      .firstWhere((c) => c.namePart.typeName.lexeme == 'S');
  final body = s.body as BlockClassBody;
  final lines = source.split('\n');
  final sections = _sectionBanners(lines);
  final info = unit.lineInfo;

  final statics = <String>{
    for (final m in body.members)
      if (m is MethodDeclaration && m.isStatic) m.name.lexeme
      else if (m is FieldDeclaration && m.isStatic)
        for (final v in m.fields.variables) v.name.lexeme,
  };

  final out = <_Member>[];
  var previousEndLine = info.getLocation(body.leftBracket.end).lineNumber;
  for (final m in body.members) {
    final endLine = info.getLocation(m.end).lineNumber;
    final notesFrom = previousEndLine + 1;
    previousEndLine = endLine;
    if (m is! MethodDeclaration) continue;
    final name = m.name.lexeme;
    if (m.isStatic || m.isSetter || m.isOperator || name.startsWith('_')) {
      continue;
    }
    final returnType = m.returnType?.toSource();
    if (returnType != 'String' && returnType != 'List<String>') continue;

    final line = info.getLocation(m.name.offset).lineNumber;
    final notes = _notes(lines, notesFrom, endLine);
    final section = _sectionAt(sections, line);
    final params = m.parameters;
    for (final p in params?.parameters ?? const <FormalParameter>[]) {
      if (_reservedNames.contains(p.name?.lexeme)) {
        throw StateError('S.$name has a parameter named ${p.name!.lexeme}, '
            'which the generated override uses itself. Rename one of them.');
      }
    }
    final superArgs = [
      for (final p in params?.parameters ?? const <FormalParameter>[])
        p.isNamed ? '${p.name!.lexeme}: ${p.name!.lexeme}' : p.name!.lexeme,
    ].join(', ');

    final literals = returnType == 'String' ? _plainConditional(m) : null;
    if (literals != null && m.typeParameters == null) {
      final shadowed = {
        for (final p in params?.parameters ?? const <FormalParameter>[])
          p.name!.lexeme,
      };
      final ar = _render(literals.$1, source, statics.difference(shadowed));
      final en = _render(literals.$2, source, statics.difference(shadowed));
      out.add(_Member(
        key: name,
        kind: m.isGetter ? 'getter' : 'method',
        line: line,
        section: section,
        notes: notes,
        editable: true,
        params: params?.toSource() ?? '',
        superArgs: superArgs,
        ar: ar.text,
        en: en.text,
        tokensAr: ar.tokens,
        tokensEn: en.tokens,
      )..tokenCode = {...ar.code, ...en.code});
    } else {
      final wordings = _wordingsIn(m.body);
      out.add(_Member(
        key: name,
        kind: returnType == 'String'
            ? (m.isGetter ? 'getter' : 'method')
            : 'list',
        line: line,
        section: section,
        notes: notes,
        editable: false,
        params: params?.toSource() ?? '',
        superArgs: superArgs,
        ar: wordings.where(_hasArabic).join('\n'),
        en: wordings.where((w) => !_hasArabic(w) && _hasLatin(w)).join('\n'),
        tokensAr: const [],
        tokensEn: const [],
      ));
    }
  }
  return out;
}

/// The two literals of a body that is exactly `isAr ? '...' : '...'`.
(StringLiteral, StringLiteral)? _plainConditional(MethodDeclaration m) {
  final body = m.body;
  if (body is! ExpressionFunctionBody) return null;
  var e = body.expression;
  while (e is ParenthesizedExpression) {
    e = e.expression;
  }
  if (e is! ConditionalExpression) return null;
  if (e.condition.toSource() != 'isAr') return null;
  final then = e.thenExpression;
  final otherwise = e.elseExpression;
  if (then is! StringLiteral || otherwise is! StringLiteral) return null;
  return (then, otherwise);
}

/// [literal]'s text with each interpolated value written as `{token}`, the
/// tokens in order, and the code that computes each one. [source] and
/// [statics] are only needed for the code: a token that calls one of S's
/// static members is qualified with `S.` there.
({String text, List<String> tokens, Map<String, String> code}) _render(
  StringLiteral literal, [
  String? source,
  Set<String> statics = const {},
]) {
  final text = StringBuffer();
  final tokens = <String>[];
  final code = <String, String>{};
  void walk(StringLiteral s) {
    if (s is SimpleStringLiteral) {
      text.write(s.value);
    } else if (s is AdjacentStrings) {
      for (final part in s.strings) {
        walk(part);
      }
    } else if (s is StringInterpolation) {
      for (final element in s.elements) {
        if (element is InterpolationString) {
          text.write(element.value);
        } else if (element is InterpolationExpression) {
          final token = element.expression.toSource();
          text.write('{$token}');
          if (!tokens.contains(token)) tokens.add(token);
          code[token] = source == null
              ? token
              : _qualifyStatics(element.expression, source, statics);
        }
      }
    }
  }

  walk(literal);
  return (text: text.toString(), tokens: tokens, code: code);
}

/// [e]'s own source text with `S.` in front of every bare reference to one
/// of [statics].
String _qualifyStatics(Expression e, String source, Set<String> statics) {
  final at = <int>[];
  e.accept(_StaticRefs(statics, at));
  var out = source.substring(e.offset, e.end);
  for (final offset in at.toSet().toList()..sort((a, b) => b - a)) {
    final i = offset - e.offset;
    out = '${out.substring(0, i)}S.${out.substring(i)}';
  }
  return out;
}

class _StaticRefs extends RecursiveAstVisitor<void> {
  _StaticRefs(this.statics, this.at);

  final Set<String> statics;
  final List<int> at;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final parent = node.parent;
    final qualified = (parent is PrefixedIdentifier &&
            identical(parent.identifier, node)) ||
        (parent is PropertyAccess && identical(parent.propertyName, node)) ||
        (parent is MethodInvocation &&
            identical(parent.methodName, node) &&
            parent.target != null) ||
        parent is Label;
    if (!qualified && statics.contains(node.name)) at.add(node.offset);
    super.visitSimpleIdentifier(node);
  }
}

/// Every wording a built-in-only member's body holds, in source order, so
/// the Wording page can still show it and a search can still find it.
List<String> _wordingsIn(FunctionBody body) {
  final found = <String>[];
  body.accept(_LiteralCollector((literal) {
    final text = _render(literal).text.trim();
    if (text.isNotEmpty && !found.contains(text)) found.add(text);
  }));
  return found;
}

class _LiteralCollector extends RecursiveAstVisitor<void> {
  _LiteralCollector(this.onLiteral);

  final void Function(StringLiteral) onLiteral;

  // Each outermost literal once: a literal's own pieces (the parts of an
  // AdjacentStrings, a literal inside an interpolation) are part of it.
  @override
  void visitAdjacentStrings(AdjacentStrings node) => onLiteral(node);

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) => onLiteral(node);

  @override
  void visitStringInterpolation(StringInterpolation node) => onLiteral(node);
}

// U+0600 to U+06FF, the Arabic block, built from code points: the first
// of them is an invisible format character, and typed into the source it
// would look like an empty range.
final _arabic = RegExp(
  '[${String.fromCharCode(0x0600)}-${String.fromCharCode(0x06FF)}]',
);
final _latin = RegExp(r'[A-Za-z]');
bool _hasArabic(String s) => _arabic.hasMatch(s);
bool _hasLatin(String s) => _latin.hasMatch(s);

/// `// ── Auth ───` style banners: (line number, section name).
List<(int, String)> _sectionBanners(List<String> lines) {
  final banner = RegExp(r'^\s*//+\s*─{2,}\s*(.+?)\s*─{2,}');
  return [
    for (var i = 0; i < lines.length; i++)
      if (banner.firstMatch(lines[i]) case final m?) (i + 1, m.group(1)!),
  ];
}

String _sectionAt(List<(int, String)> banners, int line) {
  var name = '';
  for (final (at, section) in banners) {
    if (at > line) break;
    name = section;
  }
  return name;
}

/// The whole-line comments from [from] to [to] (1-based, inclusive): the
/// doc comment and notes above a member plus any inside it. Banners are
/// dropped, a bare `//` line starts a new paragraph.
String _notes(List<String> lines, int from, int to) {
  final paragraphs = <String>[];
  var current = <String>[];
  void flush() {
    if (current.isNotEmpty) {
      paragraphs.add(current.join(' ').replaceAll(RegExp(r'\s+'), ' '));
    }
    current = [];
  }

  for (var i = from; i <= to && i <= lines.length; i++) {
    final line = lines[i - 1].trim();
    if (!line.startsWith('//')) continue;
    if (line.contains('──')) continue;
    final text = line.replaceFirst(RegExp(r'^///?\s?'), '').trimRight();
    if (text.isEmpty) {
      flush();
    } else {
      current.add(text);
    }
  }
  flush();
  return paragraphs.join('\n');
}

// ─── Reading the quotes ─────────────────────────────────────────────────────

List<Map<String, Object?>> _readQuotes(String source) {
  final unit = parseString(content: source, throwIfDiagnostics: false).unit;
  final lines = source.split('\n');
  final info = unit.lineInfo;
  final list = unit.declarations
      .whereType<TopLevelVariableDeclaration>()
      .expand((d) => d.variables.variables)
      .firstWhere((v) => v.name.lexeme == 'kDailyQuotes')
      .initializer as ListLiteral;

  final out = <Map<String, Object?>>[];
  var previousEnd = info.getLocation(list.leftBracket.end).lineNumber;
  for (final element in list.elements) {
    final start = info.getLocation(element.offset).lineNumber;
    final end = info.getLocation(element.end).lineNumber;
    String? source;
    for (var i = previousEnd + 1; i < start; i++) {
      final m = RegExp(r'^\s*//\s*Source:\s*(.+?)\.?(\s*Not shown on screen\.)?$')
          .firstMatch(lines[i - 1]);
      if (m != null) source = m.group(1);
    }
    previousEnd = end;
    final arguments = switch (element) {
      MethodInvocation(:final argumentList) => argumentList,
      InstanceCreationExpression(:final argumentList) => argumentList,
      _ => throw StateError('kDailyQuotes holds something that is not a '
          'DailyQuote(...) at line $start.'),
    };
    String named(String name) => _render(arguments.arguments
            .whereType<NamedExpression>()
            .firstWhere((a) => a.name.label.name == name)
            .expression as StringLiteral)
        .text;
    out.add({'ar': named('ar'), 'en': named('en'), 'source': source});
  }
  return out;
}

// ─── Usage (screens) ────────────────────────────────────────────────────────

Map<String, Object?>? _readUsage(String path) {
  final file = File(path);
  if (!file.existsSync()) return null;
  final json = jsonDecode(file.readAsStringSync());
  if (json is! Map || json['members'] is! Map) return null;
  return (json['members'] as Map).cast<String, Object?>();
}

// ─── The catalog ────────────────────────────────────────────────────────────

String _catalogJson({
  required List<_Member> members,
  required List<Map<String, Object?>> quotes,
  required String stringsSource,
  required String quotesSource,
  required Map<String, Object?>? usage,
}) {
  final catalog = {
    'about': 'Generated by docs/wording/generator/bin/gen_wording_edits.dart '
        'for the admin tool\'s Wording page. Do not edit by hand.',
    // A fingerprint of each source, so the admin tool can tell when the app's
    // wording moved on since this catalog was built. FNV-1a over the UTF-8
    // bytes: not a security hash, just cheap to compute the same way in Node.
    'sources': {
      'appStrings': {
        'path': _appStringsPath,
        'fnv1a': _fnv1a(utf8.encode(stringsSource)),
      },
      'dailyQuotes': {
        'path': _quotesPath,
        'fnv1a': _fnv1a(utf8.encode(quotesSource)),
      },
    },
    'screensFrom': usage == null ? null : _usagePath,
    'strings': [
      for (final m in members)
        {
          'key': m.key,
          'section': m.section,
          'line': m.line,
          'kind': m.kind,
          if (m.params.isNotEmpty) 'params': m.params,
          'editable': m.editable,
          if (!m.editable) 'why': m.kind == 'list' ? _listWhy : _builtInOnlyWhy,
          'ar': m.ar,
          'en': m.en,
          if (m.editable) 'tokensAr': m.tokensAr,
          if (m.editable) 'tokensEn': m.tokensEn,
          'notes': m.notes,
          'screens': _screens(usage, m.key),
          'unused': _unused(usage, m.key),
        },
    ],
    'quotes': quotes,
  };
  return '${const JsonEncoder.withIndent('  ').convert(catalog)}\n';
}

List<String> _screens(Map<String, Object?>? usage, String key) {
  final entry = usage?[key];
  if (entry is! Map || entry['screens'] is! List) return const [];
  return (entry['screens'] as List).whereType<String>().toList();
}

bool? _unused(Map<String, Object?>? usage, String key) {
  final entry = usage?[key];
  return entry is Map && entry['unused'] is bool
      ? entry['unused'] as bool
      : null;
}

/// FNV-1a, 32 bits, as eight hex digits. scripts/admin_lookup/lib/wording.js
/// computes the same thing to compare against.
String _fnv1a(List<int> bytes) {
  var hash = 0x811c9dc5;
  for (final b in bytes) {
    hash ^= b;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

// ─── The generated part ─────────────────────────────────────────────────────

String _partSource(List<_Member> members) {
  final out = StringBuffer()
    ..writeln('// GENERATED FILE. Do not edit by hand.')
    ..writeln('//')
    ..writeln('// Rebuilt from app_strings.dart by')
    ..writeln('//   cd docs/wording/generator && '
        'dart run bin/gen_wording_edits.dart')
    ..writeln('// Rerun it whenever a string in S is added, removed or '
        'renamed, or a')
    ..writeln("// method's parameters change. This file overrides every "
        'editable string')
    ..writeln('// by name, so until it is rerun the build stops here with '
        "an \"isn't a")
    ..writeln("// valid override\" or \"isn't defined\" error on the stale "
        'line.')
    ..writeln('//')
    ..writeln("// What it does: lays the admin's wording edits (see "
        'wording_edits.dart)')
    ..writeln('// over the built-in text. An editable string returns its edit '
        'when there')
    ..writeln('// is one and the built-in text otherwise. The {parts} of an '
        'edit are')
    ..writeln('// filled with the very values the built-in sentence uses, and '
        'an edit')
    ..writeln('// naming a part the string no longer has falls back to the '
        'built-in')
    ..writeln('// text (see wordingPartsKnown in wording_edits.dart).')
    ..writeln()
    ..writeln("part of 'app_strings.dart';")
    ..writeln()
    ..writeln('/// Every S string the admin tool can edit, in the order '
        'app_strings.dart')
    ..writeln('/// declares them.')
    ..writeln('const List<String> kEditableWordingKeys = [');
  for (final m in members.where((m) => m.editable)) {
    out.writeln("  '${m.key}',");
  }
  out
    ..writeln('];')
    ..writeln()
    ..writeln('/// Every other S string. Each picks between several '
        'wordings in code (a')
    ..writeln('/// number, a state, a case), so only a code change can '
        'reword it.')
    ..writeln('const List<String> kBuiltInOnlyWordingKeys = [');
  for (final m in members.where((m) => !m.editable)) {
    out.writeln("  '${m.key}',");
  }
  out
    ..writeln('];')
    ..writeln()
    ..writeln('/// [S] with the edits for its language laid over it. Built '
        'only by')
    ..writeln('/// [S.edited], and only when that language has at least '
        'one edit.')
    ..writeln('class _EditedS extends S {')
    ..writeln('  _EditedS(super.locale, this._edits);')
    ..writeln()
    ..writeln('  /// Edited text by S member name, for this language only.')
    ..writeln('  final Map<String, String> _edits;');

  for (final m in members.where((m) => m.editable)) {
    out.writeln();
    out.writeln('  @override');
    final superCall = m.kind == 'getter'
        ? 'super.${m.key}'
        : 'super.${m.key}(${m.superArgs})';
    final head = m.kind == 'getter'
        ? 'String get ${m.key}'
        : 'String ${m.key}${m.params}';
    if (!m.hasTokens) {
      out.writeln("  $head => plainWording(_edits['${m.key}']) ?? $superCall;");
      continue;
    }
    out
      ..writeln('  $head {')
      ..writeln("    final wordingEdit = _edits['${m.key}'];")
      ..writeln('    if (wordingEdit == null) return $superCall;')
      ..writeln('    return fillWording(')
      ..writeln('          wordingEdit,')
      ..writeln('          isAr')
      ..writeln('              ? ${_tokenMap(m.tokensAr, m.tokenCode)}')
      ..writeln('              : ${_tokenMap(m.tokensEn, m.tokenCode)},')
      ..writeln('        ) ??')
      ..writeln('        $superCall;')
      ..writeln('  }');
  }
  out.writeln('}');
  return out.toString();
}

String _tokenMap(List<String> tokens, Map<String, String> code) {
  if (tokens.isEmpty) return 'const <String, String Function()>{}';
  final out = StringBuffer('<String, String Function()>{\n');
  for (final token in tokens) {
    final expression = code[token] ?? token;
    final value = RegExp(r'^[A-Za-z_]\w*$').hasMatch(expression)
        ? "'\$$expression'"
        : "'\${$expression}'";
    out.writeln('                  ${_dartString(token)}: () => $value,');
  }
  out.write('                }');
  return out.toString();
}

/// [s] as a single-quoted Dart literal that means exactly [s].
String _dartString(String s) {
  final escaped = s
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll(r'$', r'\$')
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r');
  return "'$escaped'";
}

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
//     built-in daily quotes, and (since 2026-09-26, for the FAQ and Premium
//     pages) the built-in FAQ from help_support_screen.dart and the
//     paywall's built-in benefit list and icon names from
//     premium_benefits.dart. Gitignored: the admin tool reruns this script
//     with --catalog-only whenever one of those sources has changed since
//     the catalog it holds.
//
//     The FAQ and the benefit list are read leniently: if either cannot be
//     read (a file moved, an entry written in another form), the catalog
//     carries null and a sentence saying why, which the admin page shows,
//     and everything else is written as usual. A broken FAQ never stops the
//     strings from being editable.
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
const _faqPath = 'lib/features/profile/screens/help_support_screen.dart';
const _benefitsPath = 'lib/features/premium/premium_benefits.dart';
const _partPath = 'lib/core/l10n/app_strings_edited.g.dart';
const _catalogPath = 'scripts/admin_lookup/wording/catalog.json';
const _usagePath = 'docs/wording/generator/.cache/usage.json';

/// Names the generated override uses for its own locals and fields. A
/// parameter with one of these names would be shadowed, so the script
/// refuses rather than emit code that quietly reads the wrong value.
const _reservedNames = {'wordingEdit', '_edits'};

/// The start of every id the admin tool gives what it adds: a question
/// ('q-'), a group ('g-'), a benefit ('b-'). A built-in id never starts
/// with one, so the two can never collide.
const _addedIdPrefixes = ['q-', 'g-', 'b-'];

/// What the catalog's shape is. The admin tool rebuilds a catalog written
/// in an older shape, the same as one built from older sources.
const _catalogFormat = 2;

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
  final faqSource = _readIfThere('$root/$_faqPath');
  final benefitsSource = _readIfThere('$root/$_benefitsPath');
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
        faq: _leniently('FAQ', _faqPath,
            () => _readFaq(faqSource, stringsSource)),
        benefits: _leniently('benefit list', _benefitsPath,
            () => _readBenefits(benefitsSource, members)),
        stringsSource: stringsSource,
        quotesSource: quotesSource,
        faqSource: faqSource,
        benefitsSource: benefitsSource,
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

// ─── Reading the FAQ and the benefit list ───────────────────────────────────

String? _readIfThere(String path) {
  final file = File(path);
  return file.existsSync() ? file.readAsStringSync() : null;
}

/// [read]'s result, or its failure as a sentence for the admin page. Never
/// throws: see the header, a list that cannot be read costs that list only.
({Map<String, Object?>? data, String? error}) _leniently(
  String what,
  String path,
  Map<String, Object?> Function() read,
) {
  try {
    return (data: read(), error: null);
  } catch (e) {
    final said = e is StateError ? e.message : '$e';
    stderr.writeln('Could not read the $what from $path: $said');
    return (data: null, error: 'The $what could not be read from $path: $said');
  }
}

/// The value of [name] among [arguments], or null.
Expression? _named(ArgumentList arguments, String name) {
  for (final a in arguments.arguments) {
    if (a is NamedExpression && a.name.label.name == name) return a.expression;
  }
  return null;
}

String _stringArg(ArgumentList arguments, String name, String where) {
  final e = _named(arguments, name);
  if (e is! StringLiteral) {
    throw StateError('$where has no plain string for $name.');
  }
  // A value interpolated with $ cannot be shown by the admin tool as text;
  // a brace typed in the sentence itself is just a character.
  final rendered = _render(e);
  if (rendered.tokens.isNotEmpty) {
    throw StateError('$where interpolates a value into $name.');
  }
  return rendered.text;
}

ArgumentList _entryArguments(Expression element, String type, int line) =>
    switch (element) {
      MethodInvocation(:final methodName, :final argumentList)
          when methodName.name == type =>
        argumentList,
      InstanceCreationExpression(:final constructorName, :final argumentList)
          when constructorName.type.name.lexeme == type =>
        argumentList,
      _ => throw StateError('the list holds something that is not a '
          '$type(...) at line $line.'),
    };

ListLiteral _topLevelList(CompilationUnit unit, String name) {
  for (final d in unit.declarations.whereType<TopLevelVariableDeclaration>()) {
    for (final v in d.variables.variables) {
      if (v.name.lexeme != name) continue;
      final init = v.initializer;
      if (init is ListLiteral) return init;
      throw StateError('$name is not written as a list literal.');
    }
  }
  throw StateError('there is no top-level $name.');
}

void _checkIds(List<String> ids, String what) {
  final seen = <String>{};
  for (final id in ids) {
    if (!RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$').hasMatch(id)) {
      throw StateError('$what id "$id" is not lower case words joined by '
          'dashes.');
    }
    if (_addedIdPrefixes.any(id.startsWith)) {
      throw StateError('$what id "$id" starts like an id the admin tool '
          'gives its own additions (${_addedIdPrefixes.join(', ')}).');
    }
    if (!seen.add(id)) throw StateError('$what id "$id" is used twice.');
  }
}

/// The built-in FAQ: its groups (the FaqGroup enum's order, with each
/// group's heading from S.faqGroupTitle) and kFaqEntries in order.
Map<String, Object?> _readFaq(String? source, String stringsSource) {
  if (source == null) throw StateError('the file is not there.');
  final unit = parseString(content: source, throwIfDiagnostics: false).unit;
  final info = unit.lineInfo;

  final groupEnum = unit.declarations
      .whereType<EnumDeclaration>()
      .where((e) => e.namePart.typeName.lexeme == 'FaqGroup')
      .firstOrNull;
  if (groupEnum == null) throw StateError('there is no enum FaqGroup.');
  final groupIds = [
    for (final c in groupEnum.body.constants) c.name.lexeme,
  ];

  final titles = _faqGroupTitles(stringsSource);
  final groups = [
    for (final id in groupIds)
      {
        'id': id,
        'ar': (titles[id] ?? titles['_'])?.$1 ??
            (throw StateError('S.faqGroupTitle has no heading for $id.')),
        'en': (titles[id] ?? titles['_'])!.$2,
      },
  ];

  final items = <Map<String, Object?>>[];
  for (final element in _topLevelList(unit, 'kFaqEntries').elements) {
    final line = info.getLocation(element.offset).lineNumber;
    final args = _entryArguments(element as Expression, 'FaqEntry', line);
    final where = 'The FaqEntry at line $line';
    final group = _named(args, 'group');
    final groupId = switch (group) {
      PrefixedIdentifier(:final prefix, :final identifier)
          when prefix.name == 'FaqGroup' =>
        identifier.name,
      _ => throw StateError('$where has no FaqGroup.<name> group.'),
    };
    if (!groupIds.contains(groupId)) {
      throw StateError('$where names a group FaqGroup does not have.');
    }
    items.add({
      'id': _stringArg(args, 'id', where),
      'group': groupId,
      'qAr': _stringArg(args, 'questionAr', where),
      'qEn': _stringArg(args, 'questionEn', where),
      'aAr': _stringArg(args, 'answerAr', where),
      'aEn': _stringArg(args, 'answerEn', where),
    });
  }
  _checkIds([for (final i in items) i['id']! as String], 'A question');
  return {'groups': groups, 'items': items};
}

/// S.faqGroupTitle's headings by case: `'basics' => isAr ? '...' : '...'`,
/// with '_' for the default case.
Map<String, (String, String)> _faqGroupTitles(String stringsSource) {
  final unit =
      parseString(content: stringsSource, throwIfDiagnostics: false).unit;
  final s = unit.declarations
      .whereType<ClassDeclaration>()
      .firstWhere((c) => c.namePart.typeName.lexeme == 'S');
  final method = (s.body as BlockClassBody)
      .members
      .whereType<MethodDeclaration>()
      .where((m) => m.name.lexeme == 'faqGroupTitle')
      .firstOrNull;
  final body = method?.body;
  final e = body is ExpressionFunctionBody ? body.expression : null;
  if (e is! SwitchExpression) {
    throw StateError('S.faqGroupTitle is not a switch on the group.');
  }
  final out = <String, (String, String)>{};
  for (final c in e.cases) {
    final pattern = c.guardedPattern.pattern;
    final key = switch (pattern) {
      ConstantPattern(:final expression) when expression is StringLiteral =>
        _render(expression).text,
      WildcardPattern() => '_',
      _ => throw StateError('S.faqGroupTitle has a case that is neither a '
          'group name nor _.'),
    };
    final value = c.expression;
    if (value is! ConditionalExpression ||
        value.condition.toSource() != 'isAr' ||
        value.thenExpression is! StringLiteral ||
        value.elseExpression is! StringLiteral) {
      throw StateError('S.faqGroupTitle\'s $key case is not '
          'isAr ? \'...\' : \'...\'.');
    }
    out[key] = (
      _render(value.thenExpression as StringLiteral).text,
      _render(value.elseExpression as StringLiteral).text,
    );
  }
  return out;
}

/// The paywall's built-in benefits (kBuiltInPremiumBenefits, in order, each
/// with the S members of its title and description), the icon names a row
/// may wear (kBenefitIcons, in order) and the fallback icon.
Map<String, Object?> _readBenefits(String? source, List<_Member> members) {
  if (source == null) throw StateError('the file is not there.');
  final unit = parseString(content: source, throwIfDiagnostics: false).unit;
  final info = unit.lineInfo;
  final keys = {for (final m in members) m.key};

  String member(ArgumentList args, String name, String where) {
    final e = _named(args, name);
    final body = e is FunctionExpression ? e.body : null;
    final read = body is ExpressionFunctionBody ? body.expression : null;
    final key = switch (read) {
      PrefixedIdentifier(:final identifier) => identifier.name,
      PropertyAccess(:final propertyName) => propertyName.name,
      _ => throw StateError('$where\'s $name is not (s) => s.<member>.'),
    };
    if (!keys.contains(key)) {
      throw StateError('$where\'s $name reads S.$key, which S does not have.');
    }
    return key;
  }

  final icons = <String>[];
  for (final d in unit.declarations.whereType<TopLevelVariableDeclaration>()) {
    for (final v in d.variables.variables) {
      if (v.name.lexeme != 'kBenefitIcons') continue;
      final init = v.initializer;
      if (init is! SetOrMapLiteral) {
        throw StateError('kBenefitIcons is not written as a map literal.');
      }
      for (final element in init.elements) {
        if (element is MapLiteralEntry && element.key is StringLiteral) {
          icons.add(_render(element.key as StringLiteral).text);
        }
      }
    }
  }
  if (icons.isEmpty) throw StateError('there is no kBenefitIcons map.');

  String? fallback;
  for (final d in unit.declarations.whereType<TopLevelVariableDeclaration>()) {
    for (final v in d.variables.variables) {
      if (v.name.lexeme == 'kBenefitFallbackIcon' &&
          v.initializer is StringLiteral) {
        fallback = _render(v.initializer as StringLiteral).text;
      }
    }
  }
  if (fallback == null || !icons.contains(fallback)) {
    throw StateError('kBenefitFallbackIcon is missing or not in '
        'kBenefitIcons.');
  }

  final items = <Map<String, Object?>>[];
  for (final element in _topLevelList(unit, 'kBuiltInPremiumBenefits').elements) {
    final line = info.getLocation(element.offset).lineNumber;
    final args = _entryArguments(element as Expression, 'BuiltInBenefit', line);
    final where = 'The BuiltInBenefit at line $line';
    final icon = _stringArg(args, 'icon', where);
    if (!icons.contains(icon)) {
      throw StateError('$where wears "$icon", which kBenefitIcons does not '
          'have.');
    }
    items.add({
      'id': _stringArg(args, 'id', where),
      'icon': icon,
      'titleKey': member(args, 'title', where),
      'descKey': member(args, 'desc', where),
    });
  }
  _checkIds([for (final i in items) i['id']! as String], 'A benefit');
  return {'items': items, 'icons': icons, 'fallbackIcon': fallback};
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
  required ({Map<String, Object?>? data, String? error}) faq,
  required ({Map<String, Object?>? data, String? error}) benefits,
  required String stringsSource,
  required String quotesSource,
  required String? faqSource,
  required String? benefitsSource,
  required Map<String, Object?>? usage,
}) {
  final catalog = {
    'about': 'Generated by docs/wording/generator/bin/gen_wording_edits.dart '
        'for the admin tool\'s Wording, FAQ and Premium pages. Do not edit by '
        'hand.',
    'format': _catalogFormat,
    // A fingerprint of each source, so the admin tool can tell when the app's
    // wording moved on since this catalog was built. FNV-1a over the UTF-8
    // bytes: not a security hash, just cheap to compute the same way in Node.
    // A source that is not there is null, which the admin tool reads the
    // same way, so a missing file is not "changed" on every page load.
    'sources': {
      'appStrings': {
        'path': _appStringsPath,
        'fnv1a': _fnv1a(utf8.encode(stringsSource)),
      },
      'dailyQuotes': {
        'path': _quotesPath,
        'fnv1a': _fnv1a(utf8.encode(quotesSource)),
      },
      'faq': {
        'path': _faqPath,
        'fnv1a': faqSource == null ? null : _fnv1a(utf8.encode(faqSource)),
      },
      'benefits': {
        'path': _benefitsPath,
        'fnv1a': benefitsSource == null
            ? null
            : _fnv1a(utf8.encode(benefitsSource)),
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
    'faq': faq.data,
    if (faq.error != null) 'faqError': faq.error,
    'benefits': benefits.data,
    if (benefits.error != null) 'benefitsError': benefits.error,
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

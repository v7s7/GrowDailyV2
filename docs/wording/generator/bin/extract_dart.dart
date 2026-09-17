// Extracts every bilingual (Arabic and English) wording from the Grow Daily
// Dart sources under lib/ into JSON rows, one row per wording.
//
// Usage, from docs/wording/generator:
//   dart run bin/extract_dart.dart [--root <repo>] [--report <file.json>] > rows.json
//   dart run bin/extract_dart.dart --out .cache/dart_rows.json --report .cache/dart_report.json
// With --out the rows go to that file (parent folders are created) instead of
// stdout. .cache/ is gitignored and is where build_workbook.py looks by default.
//
// Parse only: nothing is resolved, so the extractor never needs the app's
// own packages and never builds anything. These shapes are recognised:
//
//   (a) A conditional expression on the reader's language:
//       isAr ? 'Arabic' : 'English', s.isAr ? ..., languageCode == 'ar' ? ...
//       When both sides are switches over the same value with the same cases
//       (an enum's localizedName), or lists of the same length, each case or
//       element is its own row: PrayerCalcMethod.label[jordan]. A side that
//       names a getter of the same class or enum (`: label`) is read through
//       that getter, so MatrixQuadrant.localLabel shows 'DO FIRST'. A local
//       that holds one (`final done = isAr ? arabicDigits(weekDone) :
//       '$weekDone'`) and is only read inside other rows' sentences is
//       written under each of them as `done = ...` instead of being a row.
//       One with no letter on either side is no row when both sides are the
//       same or when its member has other rows (skipped_conditionals).
//   (b) Named pairs in one call, map or record: nameAr / nameEn, questionAr /
//       questionEn, ar / en, name / nameAr (the bare name is the English side
//       when only the Arabic one carries a suffix). Positional constructor
//       arguments are mapped to parameter names when the class is declared
//       anywhere under lib/, which is how GoalSuggestion(type, cat, en, ar)
//       is read.
//   (c) An if statement or collection-if on the language:
//       if (!isAr) return 'English'; ... return 'Arabic';
//       The branch is one side, the else branch (or, when the branch always
//       returns, the statements after it) is the other side. Returns pair
//       one to one when both sides return the same number of times under the
//       same conditions. Otherwise the row lists every return with the
//       condition it sits under ("n == 1: ...", "otherwise: ..."). A local
//       that only feeds one side's sentence (final noun = ...) is written
//       under that sentence instead of becoming a row of its own, and so is
//       a joining word both sentences open with (`final and = lead ? '' :
//       'و'`), shown as `lead: (empty)` / `otherwise: و`.
//   (d) Parallel members or locals named by language: label / labelAr,
//       const ar = [...] / const en = [...]. Lists, records, maps and switch
//       expressions are paired element by element.
//   (e) A literal kept in one script beside the same call in the other
//       script (the language switch's own names).
//
// Two more kinds of rows have no language branch at all:
//   * Latin-only text a person can read in either language: a Text or label
//     argument ('+$xp XP'), a label getter's switch ('IBM Plex Sans Arabic'),
//     a capitalised fallback name (?? 'Warrior', return 'Warrior'), AM and PM
//     markers, and the "Label: value" lines of the support mail body. Their
//     ids end in .latin_only and the Arabic side is empty.
//   * Android notification channel names and descriptions, which Android
//     shows in the system settings. They go in "Android system strings".
//
// Line numbers: "line" is the first line of the declaration that holds the
// wording (after its doc comment and annotations), "text_line" the line of
// the first literal, and "ar_line" / "en_line" the line of each side (the
// sentence's own first literal, not a local written under it).
//
// Reason: the declaration's comments, then the comments on the lines that
// hold the text, inside the language test (before `?` and `:`), and above
// the statement, switch arm or call that holds it (see _addEnclosing).
//
// No U+2014 is written: in wording it becomes the token "[em dash]", in
// comments and section names a comma.
//
// Everything that is not wording (locale codes, text direction, sizes, date
// patterns, identifiers) is filtered out, and the --report file lists what
// was skipped plus every Arabic literal that no row covers, which is the
// check that nothing was missed.

import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

const _langNames = {'isAr', 'ar', 'isArabic', '_isAr', 'arabic'};

/// Flags such as `_actionsAreAr` or `localeIsAr` read the same way.
final _langNameRe = RegExp(r'(IsAr|AreAr|IsArabic)$');

bool _isLangName(String name) =>
    _langNames.contains(name) || _langNameRe.hasMatch(name);

/// A section banner: `// ── Title ──────`, possibly wrapped over up to three
/// comment lines of which the last ends in the rule.
final _bannerStartRe = RegExp(r'^//\s*─{2,}\s*(\S.*)$');
final _ruleEndRe = RegExp(r'─{2,}\s*$');
final _arabicRe = RegExp(r'[؀-ۿݐ-ݿﭐ-﷿ﹰ-﻿]');
final _letterRe = RegExp(r'[A-Za-z؀-ۿݐ-ݿﭐ-﷿ﹰ-﻿]');

const _emDash = '\u2014';
const _emToken = '[em dash]';

String _wordingText(String s) => s.replaceAll(_emDash, _emToken);

/// Developer comments and section names: an em dash becomes a comma, and
/// the box-drawing rules that decorate headings are dropped.
String _commentText(String s) {
  final out = <String>[];
  for (var line in s.split('\n')) {
    line = line.replaceAll(RegExp(r'\s*─{2,}\s*'), ' ').trim();
    line = line.replaceFirst(RegExp('^[ \\t]*$_emDash[ \\t]*'), '');
    line = line.replaceAll(RegExp('[ \\t]*$_emDash[ \\t]*'), ', ');
    out.add(line);
  }
  return out.join('\n');
}

/// Ids are stable keys: no spaces, parentheses or operators.
String _sanitizeId(String id) {
  // \u0001 marks a separator this function inserts, so a name's own
  // underscores (_cutoffClock) are never trimmed.
  const sep = '\u0001';
  var s = id
      .replaceAll(RegExp(r'\s*<=\s*'), '${sep}le$sep')
      .replaceAll(RegExp(r'\s*>=\s*'), '${sep}ge$sep')
      .replaceAll(RegExp(r'\s*==\s*'), '${sep}eq$sep')
      .replaceAll(RegExp(r'\s*!=\s*'), '${sep}ne$sep')
      .replaceAll(RegExp(r'\s*<\s*'), '${sep}lt$sep')
      .replaceAll(RegExp(r'\s*>\s*'), '${sep}gt$sep')
      .replaceAll(RegExp(r'\s*\|\|\s*'), '${sep}or$sep')
      .replaceAll(RegExp(r'\s*&&\s*'), '${sep}and$sep');
  s = s.replaceAll(RegExp('[^A-Za-z0-9_.#\\[\\]:\\-$sep]'), sep);
  s = s.replaceAll(RegExp('$sep+'), sep);
  s = s.replaceAll(RegExp('$sep(?=[\\[\\].#])|(?<=[\\[\\].#])$sep'), '');
  return s.replaceAll(sep, '_');
}

void main(List<String> args) {
  String? root;
  String? reportPath;
  String? outPath;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--root' && i + 1 < args.length) root = args[++i];
    if (args[i] == '--report' && i + 1 < args.length) reportPath = args[++i];
    if (args[i] == '--out' && i + 1 < args.length) outPath = args[++i];
  }
  root ??= _defaultRoot();
  final libDir = Directory('$root/lib');
  if (!libDir.existsSync()) {
    stderr.writeln('No lib/ under $root');
    exit(2);
  }

  final files = libDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  // First pass: parse everything and index constructor parameters, so a
  // positional call can be read by parameter name.
  final parsed = <_Parsed>[];
  final ctorIndex = <String, List<List<String>>>{};
  final fnBodies = <String, List<_FnInfo>>{};
  final textTypes = <String>{};
  for (final f in files) {
    final rel = f.path.substring(root.length + 1);
    final content = f.readAsStringSync();
    final result = parseString(
      content: content,
      path: f.path,
      throwIfDiagnostics: false,
    );
    parsed.add(_Parsed(rel, content, result.unit, result.lineInfo));
    result.unit.accept(_CtorIndexer(ctorIndex));
    result.unit.accept(_TextTypedefs(textTypes));
  }
  for (final p in parsed) {
    p.unit.accept(_FunctionBodies(fnBodies, textTypes));
  }
  final digitFns = _digitFunctions(fnBodies);

  final rows = <Map<String, Object?>>[];
  final report = <String, Object?>{};
  final fileStats = <Map<String, Object?>>[];
  final skipped = <Map<String, Object?>>[];
  final unpaired = <Map<String, Object?>>[];
  final latinUi = <Map<String, Object?>>[];

  for (final p in parsed) {
    final ex = _FileExtractor(p, ctorIndex, digitFns);
    ex.run();
    rows.addAll(ex.rows);
    skipped.addAll(ex.skipped);
    unpaired.addAll(ex.unpairedArabic());
    latinUi.addAll(ex.latinReport);
    final grepCount = 'isAr ?'.allMatches(p.content).length;
    if (ex.stats.values.any((v) => v > 0) || grepCount > 0) {
      fileStats.add({'file': p.rel, 'grep_isAr_q': grepCount, ...ex.stats});
    }
  }

  _assignIds(rows);
  rows.sort((a, b) {
    final c = (a['file'] as String).compareTo(b['file'] as String);
    if (c != 0) return c;
    final l = (a['line'] as int).compareTo(b['line'] as int);
    if (l != 0) return l;
    final t = (a['text_line'] as int).compareTo(b['text_line'] as int);
    if (t != 0) return t;
    return (a['id'] as String).compareTo(b['id'] as String);
  });

  final rowsJson = '${const JsonEncoder.withIndent('  ').convert(rows)}\n';
  if (rowsJson.contains(_emDash)) {
    stderr.writeln('extract_dart: an em dash survived into the rows');
    exit(3);
  }
  if (outPath != null) {
    File(outPath)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(rowsJson);
  } else {
    stdout.add(utf8.encode(rowsJson));
  }

  final byGroup = <String, int>{};
  final byShape = <String, int>{};
  for (final r in rows) {
    byGroup.update(r['source_group'] as String, (v) => v + 1, ifAbsent: () => 1);
    byShape.update(r['shape'] as String, (v) => v + 1, ifAbsent: () => 1);
  }
  report['rows'] = rows.length;
  report['by_group'] = byGroup;
  report['by_shape'] = byShape;
  report['files'] = fileStats;
  report['skipped_conditionals'] = skipped;
  report['uncovered_arabic_literals'] = unpaired;
  report['latin_only_literals'] = latinUi;
  report['digit_functions'] = (digitFns.toList()..sort());
  if (reportPath != null) {
    final text = const JsonEncoder.withIndent('  ')
        .convert(report)
        .replaceAll(_emDash, _emToken);
    File(reportPath)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(text);
  }
  if (outPath != null) stderr.writeln('wrote $outPath');
  stderr.writeln('rows: ${rows.length}');
  byGroup.forEach((k, v) => stderr.writeln('  $k: $v'));
  byShape.forEach((k, v) => stderr.writeln('  shape $k: $v'));
  stderr.writeln('skipped conditionals and pairs: ${skipped.length}');
  stderr.writeln('uncovered Arabic literals: ${unpaired.length}');
  stderr.writeln('Latin-only literals given a row: ${latinUi.length}');
}

String _defaultRoot() {
  // bin/extract_dart.dart -> generator -> wording -> docs -> repo
  var dir = File.fromUri(Platform.script).parent;
  for (var i = 0; i < 4; i++) {
    dir = dir.parent;
  }
  return dir.path;
}

/// Stable ids: basename.key, with #1..#n when one key yields several rows.
void _assignIds(List<Map<String, Object?>> rows) {
  final groups = <String, List<Map<String, Object?>>>{};
  for (final r in rows) {
    final suffix = r['latin_only'] == true ? '.latin_only' : '';
    final base = _sanitizeId('${_stem(r['file'] as String)}.${r['key']}$suffix');
    groups.putIfAbsent(base, () => []).add(r);
  }
  groups.forEach((base, list) {
    list.sort((a, b) {
      final l = (a['text_line'] as int).compareTo(b['text_line'] as int);
      if (l != 0) return l;
      return (a['_offset'] as int).compareTo(b['_offset'] as int);
    });
    if (list.length == 1) {
      list.first['id'] = base;
    } else {
      for (var i = 0; i < list.length; i++) {
        list[i]['id'] = '$base#${i + 1}';
      }
    }
  });
  for (final r in rows) {
    r.remove('_offset');
    // Put id first for readability.
    final copy = Map<String, Object?>.of(r);
    r
      ..clear()
      ..addAll({'id': copy.remove('id')})
      ..addAll(copy);
  }
}

/// Functions and methods whose returned text carries Arabic-Indic digits:
/// they return text (String, String? or a record of strings such as
/// ReminderLine) and call arabicDigits() or another such function outside a
/// toWesternDigits(...) that turns the digits back. A void or non-text member
/// that calls one (setReminders) is not listed, and neither is one that only
/// hands the result to toWesternDigits (habitReminderSentence). A name
/// declared more than once counts only when every declaration does.
Set<String> _digitFunctions(Map<String, List<_FnInfo>> fns) {
  final out = <String>{};
  var changed = true;
  while (changed) {
    changed = false;
    for (final e in fns.entries) {
      if (out.contains(e.key) || e.key == 'arabicDigits') continue;
      bool digits(_FnInfo f) {
        if (!f.returnsText) return false;
        var hit = false;
        f.body.accept(_CallFinder((MethodInvocation call) {
          final n = call.methodName.name;
          if (n != 'arabicDigits' && !out.contains(n)) return;
          for (AstNode? x = call.parent;
              x != null && !identical(x, f.body);
              x = x.parent) {
            if (x is MethodInvocation && x.methodName.name == 'toWesternDigits') {
              return;
            }
          }
          hit = true;
        }));
        return hit;
      }

      if (e.value.every(digits)) {
        out.add(e.key);
        changed = true;
      }
    }
  }
  return out;
}

class _FnInfo {
  _FnInfo(this.body, this.returnsText);
  final FunctionBody body;
  final bool returnsText;
}

class _FunctionBodies extends RecursiveAstVisitor<void> {
  _FunctionBodies(this.out, this.textTypes);
  final Map<String, List<_FnInfo>> out;

  /// Type names that stand for text: String, and typedefs of a record whose
  /// fields are strings (ReminderLine).
  final Set<String> textTypes;

  bool _text(TypeAnnotation? t) {
    if (t == null) return false;
    final src = t.toSource().replaceAll('?', '');
    return src == 'String' || textTypes.contains(src);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    out.putIfAbsent(node.name.lexeme, () => []).add(
        _FnInfo(node.functionExpression.body, _text(node.returnType)));
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    out
        .putIfAbsent(node.name.lexeme, () => [])
        .add(_FnInfo(node.body, !node.isSetter && _text(node.returnType)));
    super.visitMethodDeclaration(node);
  }
}

/// Typedef names whose type is a record of strings, `({String title, String
/// body})`.
class _TextTypedefs extends RecursiveAstVisitor<void> {
  _TextTypedefs(this.out);
  final Set<String> out;

  @override
  void visitGenericTypeAlias(GenericTypeAlias node) {
    final t = node.type;
    if (t is RecordTypeAnnotation) {
      final fields = [
        ...t.positionalFields.map((f) => f.type),
        ...?t.namedFields?.fields.map((f) => f.type),
      ];
      if (fields.isNotEmpty &&
          fields.every((f) => f.toSource().replaceAll('?', '') == 'String')) {
        out.add(node.name.lexeme);
      }
    }
    super.visitGenericTypeAlias(node);
  }
}

class _CallFinder extends RecursiveAstVisitor<void> {
  _CallFinder(this.found);
  final void Function(MethodInvocation call) found;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    found(node);
    super.visitMethodInvocation(node);
  }
}

String _stem(String rel) {
  final name = rel.split('/').last;
  return name.endsWith('.dart') ? name.substring(0, name.length - 5) : name;
}

class _Parsed {
  final String rel;
  final String content;
  final CompilationUnit unit;
  final LineInfo lineInfo;
  _Parsed(this.rel, this.content, this.unit, this.lineInfo);
}

/// className -> list of positional parameter name lists (one per constructor).
class _CtorIndexer extends RecursiveAstVisitor<void> {
  final Map<String, List<List<String>>> index;
  _CtorIndexer(this.index);

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    final cls = node.thisOrAncestorOfType<ClassDeclaration>();
    if (cls != null) {
      final className = cls.namePart.typeName.lexeme;
      final ctorName = node.name?.lexeme;
      final key = ctorName == null ? className : '$className.$ctorName';
      final names = <String>[];
      for (final p in node.parameters.parameters) {
        if (p.isPositional) names.add(p.name?.lexeme ?? '');
      }
      index.putIfAbsent(key, () => []).add(names);
    }
    super.visitConstructorDeclaration(node);
  }
}

class _Range {
  final int start;
  final int end;
  _Range(this.start, this.end);
  bool contains(int offset, [int? endOffset]) =>
      offset >= start && (endOffset ?? offset) <= end;
}

class _Member {
  final String key;
  final String kind;
  final AstNode? declNode; // AnnotatedNode whose comments are the reason
  final String? className;
  final String name;
  final String declKind; // getter, method, field, enum-constant, ...
  final CompilationUnitMember? topLevel;
  _Member(this.key, this.kind, this.declNode, this.className, this.name,
      this.declKind, this.topLevel);
}

class _Unit {
  final AstNode node;
  final bool isReturn;
  final String? name;
  final List<StringLiteral> lits;
  final String? cond;
  final bool orphan;
  _Unit(this.node, this.isReturn, this.name, this.lits, this.cond,
      {this.orphan = false});
  Expression get expr => node as Expression;
}

/// One way a side can read, and the condition it reads that way under
/// (null: always).
class _Alt {
  final String? cond;
  final String text;
  final List<String> ph;
  final String visible;
  final bool dynamic;
  _Alt(this.cond, this.text, this.ph, this.visible, {this.dynamic = false});
  _Alt withCond(String? c) => _Alt(c, text, ph, visible, dynamic: dynamic);
}

/// A side after pairing: its alternatives and the literals it came from.
class _Side {
  final List<_Alt> alts;
  final List<StringLiteral> lits;
  final List<AstNode> helperDecls;
  final List<(String, List<_Alt>)> where;
  AstNode? first;
  _Side(this.alts, this.lits, [this.first])
      : helperDecls = [],
        where = [];
  bool get isEmpty => alts.isEmpty;

  /// The literals of the sentence itself, not of a local written under it.
  List<StringLiteral> get leadLits => [
        for (final l in lits)
          if (!helperDecls.any((d) => l.offset >= d.offset && l.end <= d.end)) l
      ];

  /// The first literal of the sentence the cell leads with (a local written
  /// under it only when the side has nothing else).
  AstNode? get firstNode {
    final own = leadLits;
    final pool = own.isNotEmpty ? own : lits;
    return pool.isNotEmpty
        ? (pool.toList()..sort((a, b) => a.offset.compareTo(b.offset))).first
        : first;
  }
}

/// What a row was made from, kept while the file is processed so a later
/// pass can fold a local under the sentences it feeds.
class _RowInfo {
  _RowInfo(this.member, this.node, this.comments, this.ar, this.en,
      this.arTexts, this.enTexts);
  final _Member member;
  final AstNode node;
  final List<CommentToken> comments;
  final _Text ar;
  final _Text en;
  final List<AstNode> arTexts;
  final List<AstNode> enTexts;

  /// Locals written under this row: (declaration offset, name, Arabic side,
  /// the local's text on that side).
  final folds = <(int, String, bool, _Text)>[];
}

class _PairResult {
  final _Side ar;
  final _Side en;
  final bool leftover;
  _PairResult(this.ar, this.en, {this.leftover = false});
}

class _Text {
  final String text;
  final List<String> placeholders;
  final bool dynamic;
  final String visible;
  _Text(this.text, this.placeholders, this.dynamic, this.visible);
  static final empty = _Text('', const [], false, '');
}

String? _and(String? outer, String? inner) {
  if (inner == null) return outer;
  if (outer == null) return inner;
  if (outer == 'otherwise') return inner;
  if (inner == 'otherwise') return outer;
  return '$outer && $inner';
}

class _FileExtractor {
  final _Parsed p;
  final Map<String, List<List<String>>> ctorIndex;
  final Set<String> digitFns;
  final rows = <Map<String, Object?>>[];
  final skipped = <Map<String, Object?>>[];
  final latinReport = <Map<String, Object?>>[];
  final claimed = <_Range>[];
  final _info = Map<Map<String, Object?>, _RowInfo>.identity();
  final stats = <String, int>{
    'lang_conditionals': 0,
    'cond_rows': 0,
    'cond_case_rows': 0,
    'cond_skipped_no_literal': 0,
    'cond_skipped_locale_code': 0,
    'cond_skipped_date_pattern': 0,
    'cond_skipped_join_piece': 0,
    'cond_outer_of_nested': 0,
    'cond_dynamic_branch': 0,
    'named_pair_rows': 0,
    'if_splits': 0,
    'if_rows': 0,
    'if_folded_helpers': 0,
    'parallel_rows': 0,
    'cond_folded_locals': 0,
    'skipped_letterless': 0,
  };
  late final List<({int offset, int end, String text, CompilationUnitMember? top})>
      banners = _collectBanners();

  _FileExtractor(this.p, this.ctorIndex, this.digitFns);

  int line(int offset) => p.lineInfo.getLocation(offset).lineNumber;

  void run() {
    final conds = <ConditionalExpression>[];
    final ifs = <AstNode>[]; // IfStatement or IfElement
    final argLists = <ArgumentList>[];
    final maps = <SetOrMapLiteral>[];
    final records = <RecordLiteral>[];
    p.unit.accept(_Collector(conds, ifs, argLists, maps, records));

    _handleAndroidChannels(argLists);
    _handleConditionals(conds);
    for (final a in argLists) {
      _handleArgList(a);
    }
    for (final m in maps) {
      _handleMap(m);
    }
    for (final r in records) {
      _handleRecord(r);
    }
    _handleParallelMembers();
    _handleIfs(ifs);
    _handleSiblingPairs();
    _handleLatinOnly();
    _foldLocalConditionals();
    _skipLetterless();
  }

  // ── Pieces: locals written under their sentences, rows with no letters ──

  /// A local that holds a language conditional and only feeds other rows'
  /// sentences (`final done = isAr ? arabicDigits(weekDone) : '$weekDone'`)
  /// is written under each of those sentences as `done = ...`, on the side
  /// that reads it, instead of standing alone as a half-row. Only when every
  /// read of the local is inside another row's text.
  void _foldLocalConditionals() {
    final removed = Set<Map<String, Object?>>.identity();
    final cands = <(Map<String, Object?>, _RowInfo, VariableDeclaration)>[];
    for (final r in rows) {
      final info = _info[r];
      if (info == null || r['shape'] != 'conditional') continue;
      AstNode n = info.node;
      while (n.parent is ParenthesizedExpression) {
        n = n.parent!;
      }
      final decl = n.parent;
      if (decl is! VariableDeclaration || !identical(decl.initializer, n)) {
        continue;
      }
      if (decl.parent?.parent is! VariableDeclarationStatement) continue;
      cands.add((r, info, decl));
    }
    // Last local first, so a local that feeds another local ends up under
    // the sentence both feed.
    cands.sort((a, b) => b.$3.offset.compareTo(a.$3.offset));
    for (final (r, info, decl) in cands) {
      final name = decl.name.lexeme;
      final scope = decl.parent!.parent!.parent;
      if (scope == null) continue;
      final uses = <SimpleIdentifier>[];
      var assigned = false;
      scope.accept(_NameUses(name, (id) {
        if (id.offset <= decl.end) return;
        if (id.inSetterContext()) assigned = true;
        uses.add(id);
      }));
      if (uses.isEmpty || assigned) continue;
      final targets = <(Map<String, Object?>, _RowInfo, bool)>[];
      var ok = true;
      for (final u in uses) {
        var found = false;
        for (final other in rows) {
          if (identical(other, r) || removed.contains(other)) continue;
          final oi = _info[other];
          if (oi == null || other['latin_only'] == true) continue;
          bool inAny(List<AstNode> ns) =>
              ns.any((x) => u.offset >= x.offset && u.end <= x.end);
          if (inAny(oi.arTexts)) {
            targets.add((other, oi, true));
            found = true;
          }
          if (inAny(oi.enTexts)) {
            targets.add((other, oi, false));
            found = true;
          }
        }
        if (!found) {
          ok = false;
          break;
        }
      }
      if (!ok) continue;
      for (final (_, oi, isAr) in targets) {
        if (!oi.folds.any((f) => f.$1 == decl.offset && f.$3 == isAr)) {
          oi.folds.add((decl.offset, name, isAr, isAr ? info.ar : info.en));
          (isAr ? oi.arTexts : oi.enTexts)
              .addAll(isAr ? info.arTexts : info.enTexts);
        }
        for (final c in info.comments) {
          if (!oi.comments.any((o) => o.offset == c.offset)) oi.comments.add(c);
        }
        for (final f in info.folds) {
          if (f.$3 == isAr && !oi.folds.any((g) => g.$1 == f.$1 && g.$3 == isAr)) {
            oi.folds.add(f);
          }
        }
      }
      removed.add(r);
      stats['cond_folded_locals'] = stats['cond_folded_locals']! + 1;
    }
    for (final r in rows) {
      final oi = _info[r];
      if (oi == null || oi.folds.isEmpty || removed.contains(r)) continue;
      oi.folds.sort((a, b) => a.$1.compareTo(b.$1));
      final ph = [...(r['placeholders'] as List).cast<String>()];
      final arPh = <String>[...oi.ar.placeholders];
      var dyn = r['dynamic'] == true;
      for (final isAr in [true, false]) {
        final fs = oi.folds.where((f) => f.$3 == isAr).toList();
        if (fs.isEmpty) continue;
        final key = isAr ? 'arabic' : 'english';
        final visKey = '${key}_visible';
        final lines = <String>[r[key] as String];
        final vis = <String>[(r[visKey] ?? r[key]) as String];
        for (final (_, name, _, t) in fs) {
          final tx = _wordingText(t.text);
          if (!tx.contains('\n')) {
            lines.add('$name = ${_reading(tx)}');
          } else {
            lines.add('$name =');
            lines.addAll(tx.split('\n').map((l) => '  $l'));
          }
          if (t.visible.isNotEmpty) vis.add(_wordingText(t.visible));
          for (final x in t.placeholders) {
            if (!ph.contains(x)) ph.add(x);
            if (isAr && !arPh.contains(x)) arPh.add(x);
          }
          dyn = dyn || t.dynamic;
        }
        r[key] = lines.join('\n');
        r[visKey] = vis.join('\n');
      }
      r['placeholders'] = ph;
      r['dynamic'] = dyn;
      if (r['arabic_digits_runtime'] != true &&
          _runtimeDigits(_Text(r['arabic'] as String, arPh, dyn, ''), oi.member)) {
        r['arabic_digits_runtime'] = true;
      }
      r['reason'] = _reasonOf(oi.member, oi.comments);
    }
    rows.removeWhere(removed.contains);
  }

  static final _letters = RegExp(r'[A-Za-zء-يٮ-ۓۺ-ۿ]');

  /// A language conditional with no letter on either side (only
  /// placeholders, digits and punctuation) is not wording when both sides
  /// are the same (`isAr ? '"$n"' : '"$n"'`) or when it is only a piece of a
  /// member whose other rows are wording (`return isAr ? arabicDigits(m) :
  /// '$m'` after two worded returns). A member whose whole result is such a
  /// conditional (formatOffsetMagnitude) keeps its row: that is the member's
  /// output. The skipped ones are listed in skipped_conditionals.
  void _skipLetterless() {
    String vis(Map<String, Object?> r, String key) =>
        (r['${key}_visible'] ?? r[key]) as String;
    bool worded(Map<String, Object?> r) =>
        _letters.hasMatch(vis(r, 'arabic')) || _letters.hasMatch(vis(r, 'english'));
    final remove = Set<Map<String, Object?>>.identity();
    for (final r in rows) {
      final info = _info[r];
      if (info == null || r['latin_only'] == true) continue;
      if (r['shape'] == 'android-channel') continue;
      final ar = (r['arabic'] as String).trim();
      final en = (r['english'] as String).trim();
      if (ar.isEmpty || en.isEmpty || worded(r)) continue;
      final same = ar.split(RegExp(r'\s+')).join(' ') ==
          en.split(RegExp(r'\s+')).join(' ');
      final decl = info.member.declNode;
      final piece = decl != null &&
          rows.any((o) =>
              !identical(o, r) &&
              identical(_info[o]?.member.declNode, decl) &&
              worded(o));
      if (!same && !piece) continue;
      remove.add(r);
      skipped.add(_skipEntry(
          info.node,
          same
              ? 'the same on both sides and no letters (placeholders and '
                  'punctuation only), not wording'
              : 'no letters on either side (placeholders, digits and '
                  'punctuation only), a piece of a member whose other rows '
                  'are wording'));
      stats['skipped_letterless'] = stats['skipped_letterless']! + 1;
    }
    rows.removeWhere(remove.contains);
  }

  // ── Language tests ─────────────────────────────────────────────────────

  /// true: the test is "reader is Arabic"; false: "reader is English";
  /// null: not a language test.
  bool? langTest(Expression e) {
    e = e.unParenthesized;
    if (e is PrefixExpression && e.operator.type == TokenType.BANG) {
      final r = langTest(e.operand);
      return r == null ? null : !r;
    }
    if (e is SimpleIdentifier) return _isLangName(e.name) ? true : null;
    if (e is PrefixedIdentifier) {
      return _isLangName(e.identifier.name) ? true : null;
    }
    if (e is PropertyAccess) {
      return _isLangName(e.propertyName.name) ? true : null;
    }
    if (e is BinaryExpression &&
        (e.operator.type == TokenType.EQ_EQ ||
            e.operator.type == TokenType.BANG_EQ)) {
      String? code;
      Expression? other;
      if (e.rightOperand is SimpleStringLiteral) {
        code = (e.rightOperand as SimpleStringLiteral).value;
        other = e.leftOperand;
      } else if (e.leftOperand is SimpleStringLiteral) {
        code = (e.leftOperand as SimpleStringLiteral).value;
        other = e.rightOperand;
      }
      if (other == null || other is StringLiteral) return null;
      if (code != 'ar' && code != 'en') return null;
      var r = code == 'ar';
      if (e.operator.type == TokenType.BANG_EQ) r = !r;
      return r;
    }
    return null;
  }

  // ── Android notification channels ──────────────────────────────────────

  /// AndroidNotificationChannel(id, name, description: ...) and the
  /// AndroidNotificationDetails that repeat them. Android lists the name and
  /// description in the system settings, so they are wording even though the
  /// app never draws them. The arguments are constants of the same class.
  void _handleAndroidChannels(List<ArgumentList> argLists) {
    final fields = <String, VariableDeclaration>{};
    final uses = <String, List<int>>{};
    for (final list in argLists) {
      final call = list.parent;
      final callee = call == null ? null : _calleeName(call);
      if (callee != 'AndroidNotificationChannel' &&
          callee != 'AndroidNotificationDetails') {
        continue;
      }
      final exprs = <Expression>[];
      final args = list.arguments;
      final positional = args.where((a) => a is! NamedExpression).toList();
      if (positional.length > 1) exprs.add(positional[1]);
      for (final a in args) {
        if (a is NamedExpression &&
            (a.name.label.name == 'description' ||
                a.name.label.name == 'channelDescription')) {
          exprs.add(a.expression);
        }
      }
      final idents = <SimpleIdentifier>[];
      for (final e in exprs) {
        final u = e.unParenthesized;
        if (u is SimpleIdentifier) idents.add(u);
        if (u is ConditionalExpression) {
          for (final b in [u.thenExpression, u.elseExpression]) {
            final bb = b.unParenthesized;
            if (bb is SimpleIdentifier) idents.add(bb);
          }
        }
      }
      for (final id in idents) {
        final decl = _fieldDecl(id, id.name);
        if (decl == null || decl.initializer is! SimpleStringLiteral) continue;
        fields[id.name] = decl;
        uses.putIfAbsent(id.name, () => []).add(line(id.offset));
      }
    }
    fields.forEach((name, decl) {
      final lit = decl.initializer as SimpleStringLiteral;
      if (_isClaimed(lit)) return;
      claimed.add(_Range(lit.offset, lit.end));
      final m = member(lit);
      final lines = (uses[name]!.toSet().toList()..sort()).join(', ');
      rows.add(_row(
        shape: 'android-channel',
        member: m,
        key: m.key,
        kind: 'field',
        ar: _Text.empty,
        en: _textOf(lit, false),
        node: lit,
        enNode: lit,
        hitComments: [],
        group: 'Android system strings',
        section: 'Android notification channel (system Settings, Apps, '
            'Grow Daily, Notifications)',
        notes: [
          'English only. Android shows a notification channel\'s name and '
              'description in the system settings, whatever the app\'s '
              'language. Passed to AndroidNotificationChannel or '
              'AndroidNotificationDetails at lines $lines.',
        ],
      ));
    });
  }

  VariableDeclaration? _fieldDecl(AstNode from, String name) {
    final cls = _classLike(from);
    final scope = cls ?? p.unit;
    VariableDeclaration? found;
    scope.accept(_VarFinder(name, (v) {
      final holder = v.parent?.parent;
      if (holder is FieldDeclaration || holder is TopLevelVariableDeclaration) {
        found ??= v;
      }
    }));
    return found;
  }

  AstNode? _classLike(AstNode from) => from.thisOrAncestorMatching((n) =>
      n is ClassDeclaration ||
      n is EnumDeclaration ||
      n is MixinDeclaration ||
      n is ExtensionDeclaration ||
      n is ExtensionTypeDeclaration);

  // ── (a) conditionals ───────────────────────────────────────────────────

  void _handleConditionals(List<ConditionalExpression> conds) {
    final lang = conds.where((c) => langTest(c.condition) != null).toList();
    stats['lang_conditionals'] = lang.length;
    for (final c in lang) {
      // Every language conditional is claimed, emitted or not, so the
      // if-split pass never counts its literals a second time.
      claimed.add(_Range(c.offset, c.end));
    }
    for (final c in lang) {
      final isAr = langTest(c.condition)!;
      final arE = isAr ? c.thenExpression : c.elseExpression;
      final enE = isAr ? c.elseExpression : c.thenExpression;
      final nested = lang.where((o) =>
          !identical(o, c) && o.offset >= c.offset && o.end <= c.end).toList();
      final arLits = _topLiterals(arE, excludeWithin: nested)
          .where(_isWordingLiteral)
          .toList();
      final enLits = _topLiterals(enE, excludeWithin: nested)
          .where(_isWordingLiteral)
          .toList();
      final a = arE.unParenthesized, b = enE.unParenthesized;
      if (a is SimpleStringLiteral &&
          b is SimpleStringLiteral &&
          _isLocaleCode(a.value) &&
          _isLocaleCode(b.value)) {
        stats['cond_skipped_locale_code'] =
            stats['cond_skipped_locale_code']! + 1;
        skipped.add(_skipEntry(c, 'locale code pair'));
        continue;
      }
      if (_isDatePatternArg(c, a, b)) {
        stats['cond_skipped_date_pattern'] =
            stats['cond_skipped_date_pattern']! + 1;
        skipped.add(_skipEntry(c, 'date format pattern, not wording'));
        continue;
      }
      final joinWhy = _joinPieceWhy(c, a, b);
      if (joinWhy != null) {
        stats['cond_skipped_join_piece'] =
            stats['cond_skipped_join_piece']! + 1;
        skipped.add(_skipEntry(c, joinWhy));
        continue;
      }
      if (arLits.isEmpty && enLits.isEmpty) {
        if (nested.isNotEmpty) {
          stats['cond_outer_of_nested'] = stats['cond_outer_of_nested']! + 1;
        } else {
          stats['cond_skipped_no_literal'] =
              stats['cond_skipped_no_literal']! + 1;
        }
        skipped.add(_skipEntry(c, nested.isNotEmpty
            ? 'outer conditional; only nested language conditionals carry text'
            : 'no string literal in either branch'));
        continue;
      }
      final m = member(c);
      final comments = <CommentToken>[];
      _addAbove(comments, c.beginToken, m);
      _addTrailing(comments, c.beginToken, c.endToken);
      _addEnclosing(comments, c, m);

      // An enum's switch on both sides, or two lists: one row per case.
      final ra = _resolveSide(arE, true), rb = _resolveSide(enE, false);
      final cases = _matchCases(ra, rb);
      if (cases != null) {
        _addInner(comments, c, nested: false);
        for (final (key, ax, bx) in cases) {
          final cc = <CommentToken>[...comments];
          for (final x in [ax, bx]) {
            final holder = x.parent is SwitchExpressionCase ? x.parent! : x;
            _addAbove(cc, holder.beginToken, m);
            _addTrailing(cc, holder.beginToken, holder.endToken);
          }
          rows.add(_row(
            shape: 'conditional-case',
            member: m,
            key: '${m.key}[$key]',
            kind: m.kind,
            ar: _textOf(ax, true),
            en: _textOf(bx, false),
            node: (ax.offset >= c.offset && ax.end <= c.end) ? ax : bx,
            arNode: ax,
            enNode: bx,
            hitComments: cc,
          ));
          stats['cond_case_rows'] = stats['cond_case_rows']! + 1;
        }
        continue;
      }
      _addInner(comments, c);
      final arT = _textOf(arE, true);
      final enT = _textOf(enE, false);
      if (arT.dynamic || enT.dynamic) {
        stats['cond_dynamic_branch'] = stats['cond_dynamic_branch']! + 1;
      }
      rows.add(_row(
        shape: 'conditional',
        member: m,
        key: m.key,
        kind: m.kind,
        ar: arT,
        en: enT,
        node: c,
        arNode: arE,
        enNode: enE,
        hitComments: comments,
      ));
      stats['cond_rows'] = stats['cond_rows']! + 1;
    }
  }

  static final _punctuationOnly = RegExp(r'^[\s\p{P}\p{S}]*$', unicode: true);
  static const _conjunctions = {'و', 'أو', 'and', 'or', '&'};

  /// A piece that joins wording rather than being wording: both sides only
  /// punctuation or spaces (`isAr ? '، ' : ', '`), or a lone conjunction
  /// handed to .join() or kept in a local that only joins
  /// (`final join = isAr ? ' و' : ' and '`).
  String? _joinPieceWhy(ConditionalExpression c, Expression a, Expression b) {
    if (a is! SimpleStringLiteral || b is! SimpleStringLiteral) return null;
    if (_punctuationOnly.hasMatch(a.value) &&
        _punctuationOnly.hasMatch(b.value)) {
      return 'join separator (punctuation only), not wording';
    }
    if (_isConjunction(a.value) && _isConjunction(b.value) && _usedAsJoin(c)) {
      return 'conjunction used as a join, not wording';
    }
    return null;
  }

  static bool _isConjunction(String v) =>
      _conjunctions.contains(v.trim().toLowerCase());

  /// The same for a pair of same-named locals an if split pairs
  /// (`final and = lead ? '' : 'And '` / `... : 'و'`): each side a lone
  /// conjunction whose local only joins.
  bool _isJoinPair(_PairResult res) {
    if (res.ar.alts.length != 1 || res.en.alts.length != 1) return false;
    final a = res.ar.alts.first, e = res.en.alts.first;
    if (a.ph.isNotEmpty || e.ph.isNotEmpty) return false;
    if (!_isConjunction(a.text) || !_isConjunction(e.text)) return false;
    final lits = [...res.ar.lits, ...res.en.lits];
    return lits.isNotEmpty &&
        lits.every((l) {
          AstNode n = l;
          while (n.parent is ParenthesizedExpression ||
              (n.parent is ConditionalExpression &&
                  !identical((n.parent as ConditionalExpression).condition, n))) {
            n = n.parent!;
          }
          return n is Expression && _usedAsJoin(n);
        });
  }

  static bool _isJoinArg(AstNode n) {
    final parent = n.parent;
    final call = parent?.parent;
    return parent is ArgumentList &&
        call is MethodInvocation &&
        call.methodName.name == 'join';
  }

  bool _usedAsJoin(Expression c) {
    AstNode n = c;
    while (n.parent is ParenthesizedExpression) {
      n = n.parent!;
    }
    if (_isJoinArg(n)) return true;
    final decl = n.parent;
    if (decl is! VariableDeclaration || !identical(decl.initializer, n)) {
      return false;
    }
    final body = decl.thisOrAncestorOfType<FunctionBody>();
    if (body == null) return false;
    final name = decl.name.lexeme;
    var uses = 0;
    var joins = 0;
    body.accept(_NameUses(name, (SimpleIdentifier id) {
      uses++;
      if (id.parent is InterpolationExpression || _isJoinArg(id)) joins++;
    }));
    return uses > 0 && uses == joins;
  }

  /// `westernDate(date, isAr ? 'd MMMM' : 'MMM d', locale)`: a pattern.
  bool _isDatePatternArg(ConditionalExpression c, Expression a, Expression b) {
    if (a is! SimpleStringLiteral || b is! SimpleStringLiteral) return false;
    final pat = RegExp(r"^[dMyEHhmsaLkKQGjJ ,./:\-']+$");
    if (!pat.hasMatch(a.value) || !pat.hasMatch(b.value)) return false;
    final call = c.parent is ArgumentList ? c.parent!.parent : null;
    final callee = call == null ? null : _calleeName(call);
    return callee != null &&
        RegExp(r'(DateFormat|[dD]ate)').hasMatch(callee);
  }

  /// A side as a switch or a list, reading through a getter of the same class
  /// when the side only names one (`: label`).
  Expression _resolveSide(Expression e, bool lang) {
    var x = e.unParenthesized;
    for (var i = 0; i < 3; i++) {
      final body = _memberBody(x);
      if (body == null) break;
      claimed.add(_Range(body.offset, body.end));
      x = body.unParenthesized;
      if (x is ConditionalExpression) {
        final t = langTest(x.condition);
        if (t != null) {
          x = (t == lang ? x.thenExpression : x.elseExpression).unParenthesized;
        }
      }
    }
    return x;
  }

  /// Case-by-case pairs when both sides switch over the same value with the
  /// same cases, or are lists of the same length.
  List<(String, Expression, Expression)>? _matchCases(Expression a, Expression b) {
    if (a is SwitchExpression && b is SwitchExpression) {
      if (_src(a.expression) != _src(b.expression)) return null;
      final ak = {for (final c in a.cases) _caseKey(c.guardedPattern): c};
      final bk = {for (final c in b.cases) _caseKey(c.guardedPattern): c};
      if (ak.length != a.cases.length || bk.length != b.cases.length) return null;
      if (ak.length != bk.length || !ak.keys.every(bk.containsKey)) return null;
      if (ak.length < 2) return null;
      return [
        for (final k in ak.keys) (k, ak[k]!.expression, bk[k]!.expression)
      ];
    }
    if (a is ListLiteral &&
        b is ListLiteral &&
        a.elements.length == b.elements.length &&
        a.elements.length > 1 &&
        a.elements.every((e) => e is Expression) &&
        b.elements.every((e) => e is Expression)) {
      return [
        for (var i = 0; i < a.elements.length; i++)
          ('$i', a.elements[i] as Expression, b.elements[i] as Expression)
      ];
    }
    return null;
  }

  bool _isLocaleCode(String v) =>
      RegExp(r'^(ar|en)([_-][A-Za-z]{2})?$').hasMatch(v);

  Map<String, Object?> _skipEntry(AstNode n, String why) => {
        'file': p.rel,
        'line': line(n.offset),
        'why': why,
        'source': _wordingText(_src(n, 200)),
      };

  // ── (b) named pairs ────────────────────────────────────────────────────

  /// Splits a name into (prefix, 'ar'|'en'), or null.
  (String, String)? splitLang(String name) {
    if (name == 'isAr' || name == 'isArabic' || name == 'isEn') return null;
    const exact = {
      'ar': 'ar',
      'en': 'en',
      'arabic': 'ar',
      'english': 'en',
      'Ar': 'ar',
      'En': 'en',
    };
    if (exact.containsKey(name)) return ('', exact[name]!);
    final m = RegExp(r'^(.+?)(Ar|_ar|Arabic|_arabic|En|_en|English|_english)$')
        .firstMatch(name);
    if (m == null) return null;
    final suffix = m.group(2)!.toLowerCase().replaceAll('_', '');
    final lang = suffix.startsWith('ar') ? 'ar' : 'en';
    var prefix = m.group(1)!;
    return (prefix, lang);
  }

  void _handleArgList(ArgumentList list) {
    final entries = <(String, Expression, AstNode)>[];
    final parent = list.parent;
    List<String>? positionalNames;
    String? calleeName;
    if (parent is InstanceCreationExpression) {
      final t = parent.constructorName.type.name.lexeme;
      final n = parent.constructorName.name?.name;
      calleeName = n == null ? t : '$t.$n';
    } else if (parent is MethodInvocation) {
      final target = parent.target;
      calleeName = target is SimpleIdentifier
          ? '${target.name}.${parent.methodName.name}'
          : parent.methodName.name;
    }
    if (calleeName != null) {
      final sigs = ctorIndex[calleeName];
      if (sigs != null && sigs.length == 1) positionalNames = sigs.first;
    }
    var pos = 0;
    for (final arg in list.arguments) {
      if (arg is NamedExpression) {
        entries.add((arg.name.label.name, arg.expression, arg));
      } else {
        if (positionalNames != null && pos < positionalNames.length) {
          entries.add((positionalNames[pos], arg, arg));
        }
        pos++;
      }
    }
    _pairEntries(entries, list.parent ?? list, 'constructor-args', list);
  }

  void _handleMap(SetOrMapLiteral map) {
    final entries = <(String, Expression, AstNode)>[];
    for (final e in map.elements) {
      if (e is MapLiteralEntry && e.key is SimpleStringLiteral) {
        entries.add(((e.key as SimpleStringLiteral).value, e.value, e));
      }
    }
    _pairEntries(entries, map, 'map-entry', map);
  }

  void _handleRecord(RecordLiteral rec) {
    final entries = <(String, Expression, AstNode)>[];
    for (final f in rec.fields) {
      if (f is NamedExpression) {
        entries.add((f.name.label.name, f.expression, f));
      }
    }
    _pairEntries(entries, rec, 'other', rec);
  }

  void _pairEntries(List<(String, Expression, AstNode)> entries, AstNode owner,
      String kind, AstNode container) {
    if (entries.length < 2) return;
    final byName = {for (final e in entries) e.$1: e};
    final groups = <String, Map<String, (String, Expression, AstNode)>>{};
    for (final e in entries) {
      final s = splitLang(e.$1);
      if (s == null) continue;
      groups.putIfAbsent(s.$1, () => {})[s.$2] = e;
    }
    groups.forEach((prefix, sides) {
      var ar = sides['ar'];
      var en = sides['en'];
      if (ar != null && en == null && prefix.isNotEmpty) en = byName[prefix];
      if (en != null && ar == null && prefix.isNotEmpty) ar = byName[prefix];
      if (ar == null || en == null) return;
      final arLits = _topLiterals(ar.$2);
      final enLits = _topLiterals(en.$2);
      if (arLits.isEmpty && enLits.isEmpty) return;
      if (_isClaimed(ar.$2) && _isClaimed(en.$2)) return;
      claimed.add(_Range(ar.$2.offset, ar.$2.end));
      claimed.add(_Range(en.$2.offset, en.$2.end));
      final av = ar.$2.unParenthesized, ev = en.$2.unParenthesized;
      if (av is SimpleStringLiteral &&
          ev is SimpleStringLiteral &&
          av.value == ev.value &&
          RegExp(r'^[a-z][A-Za-z0-9_]*$').hasMatch(av.value)) {
        // ThemePreset.custom(id: 'preview', nameEn: 'preview', nameAr:
        // 'preview'): an internal name that is never shown.
        skipped.add(_skipEntry(owner,
            'identical identifier on both sides (${av.value}), not shown'));
        return;
      }
      final m = member(owner);
      final path = _indexPath(owner, m);
      final key = [
        m.key,
        path,
        if (prefix.isNotEmpty) '.$prefix',
      ].join();
      final comments = <CommentToken>[];
      _addAbove(comments, owner.beginToken, m);
      _addEnclosing(comments, owner, m);
      for (final side in [ar, en]) {
        _addAbove(comments, side.$3.beginToken, m);
        _addTrailing(comments, side.$3.beginToken, side.$3.endToken);
      }
      final first = ar.$3.offset < en.$3.offset ? ar.$3 : en.$3;
      rows.add(_row(
        shape: 'named-pair',
        member: m,
        key: key,
        kind: kind,
        ar: _textOf(ar.$2, true),
        en: _textOf(en.$2, false),
        node: first,
        arNode: ar.$2,
        enNode: en.$2,
        hitComments: comments,
        pairFields: [ar.$1, en.$1],
      ));
      stats['named_pair_rows'] = stats['named_pair_rows']! + 1;
    });
  }

  /// "[3]" for the 4th element of a list, "[quran_daily_page]" when the
  /// element call carries an id: 'quran_daily_page' argument. Walks up to
  /// the enclosing member so nested lists give "[1][2]".
  String _indexPath(AstNode owner, _Member m) {
    final parts = <String>[];
    AstNode child = owner;
    AstNode? node = owner.parent;
    while (node != null && !identical(node, m.declNode)) {
      if (node is ListLiteral) {
        final idx = node.elements.indexWhere((e) => identical(e, child));
        if (idx >= 0) {
          final id = _idArg(child);
          parts.insert(0, '[${id ?? idx}]');
        }
      } else if (node is MapLiteralEntry && identical(node.value, child)) {
        final k = node.key;
        parts.insert(0, '[${k is SimpleStringLiteral ? k.value : _src(k, 40)}]');
      }
      if (node is ClassMember || node is CompilationUnitMember) break;
      child = node;
      node = node.parent;
    }
    return parts.join();
  }

  String? _idArg(AstNode call) {
    ArgumentList? args;
    if (call is InstanceCreationExpression) args = call.argumentList;
    if (call is MethodInvocation) args = call.argumentList;
    if (args == null) return null;
    for (final a in args.arguments) {
      if (a is NamedExpression &&
          a.name.label.name == 'id' &&
          a.expression is SimpleStringLiteral) {
        return (a.expression as SimpleStringLiteral).value;
      }
    }
    return null;
  }

  // ── (d) parallel members and locals ────────────────────────────────────

  void _handleParallelMembers() {
    // Containers: every class-like body, the unit itself, and every block.
    final containers = <AstNode, List<(String, Expression, AstNode)>>{};
    void add(AstNode container, String name, Expression? expr, AstNode decl) {
      if (expr == null) return;
      containers.putIfAbsent(container, () => []).add((name, expr, decl));
    }

    p.unit.accept(_MemberCollector((container, name, expr, decl) {
      add(container, name, expr, decl);
    }));

    containers.forEach((container, entries) {
      final byName = {for (final e in entries) e.$1: e};
      final groups = <String, Map<String, (String, Expression, AstNode)>>{};
      for (final e in entries) {
        final s = splitLang(e.$1);
        if (s == null) continue;
        groups.putIfAbsent(s.$1, () => {})[s.$2] = e;
      }
      groups.forEach((prefix, sides) {
        var ar = sides['ar'];
        var en = sides['en'];
        if (ar != null && en == null && prefix.isNotEmpty) en = byName[prefix];
        if (en != null && ar == null && prefix.isNotEmpty) ar = byName[prefix];
        if (ar == null || en == null) return;
        if (_topLiterals(ar.$2).isEmpty && _topLiterals(en.$2).isEmpty) return;
        if (_isClaimed(ar.$2) && _isClaimed(en.$2)) return;
        final pairs = <(String, Expression, Expression)>[];
        _pairExprs(ar.$2, en.$2, '', pairs);
        final m = member(ar.$3.offset < en.$3.offset ? ar.$3 : en.$3);
        final isLocal = ar.$3 is VariableDeclaration &&
            ar.$3.parent?.parent is VariableDeclarationStatement;
        final base = isLocal
            ? '${m.key}${prefix.isEmpty ? '' : '.$prefix'}'
            : (m.className == null || _isStringsClass(m.className))
                ? (prefix.isEmpty ? ar.$1 : prefix)
                : '${m.className}.${prefix.isEmpty ? ar.$1 : prefix}';
        claimed.add(_Range(ar.$2.offset, ar.$2.end));
        claimed.add(_Range(en.$2.offset, en.$2.end));
        for (final pr in pairs) {
          if (_topLiterals(pr.$2).isEmpty && _topLiterals(pr.$3).isEmpty) {
            continue;
          }
          final comments = <CommentToken>[];
          for (final d in [ar.$3, en.$3]) {
            final dm = member(d);
            if (isLocal) _addAbove(comments, _firstToken(d), dm);
          }
          for (final e in [pr.$2, pr.$3]) {
            _addAbove(comments, e.beginToken, m);
            _addTrailing(comments, e.beginToken, e.endToken);
            _addEnclosing(comments, e, member(e));
          }
          // The reason also carries the English member's own comments.
          final enMember = member(en.$3);
          if (!isLocal && enMember.declNode != null) {
            _addAbove(comments, _firstToken(enMember.declNode!), null);
          }
          rows.add(_row(
            shape: 'parallel',
            member: m,
            key: '$base${pr.$1}',
            kind: m.kind,
            ar: _textOf(pr.$2, true),
            en: _textOf(pr.$3, false),
            node: pr.$2.offset < pr.$3.offset ? pr.$2 : pr.$3,
            arNode: pr.$2,
            enNode: pr.$3,
            hitComments: comments,
          ));
          stats['parallel_rows'] = stats['parallel_rows']! + 1;
        }
      });
    });
  }

  void _pairExprs(Expression a, Expression b, String path,
      List<(String, Expression, Expression)> out) {
    a = a.unParenthesized;
    b = b.unParenthesized;
    if (a is ListLiteral &&
        b is ListLiteral &&
        a.elements.length == b.elements.length &&
        a.elements.every((e) => e is Expression) &&
        b.elements.every((e) => e is Expression)) {
      for (var i = 0; i < a.elements.length; i++) {
        _pairExprs(a.elements[i] as Expression, b.elements[i] as Expression,
            '$path[$i]', out);
      }
      return;
    }
    if (a is RecordLiteral && b is RecordLiteral) {
      final an = {
        for (final f in a.fields)
          if (f is NamedExpression) f.name.label.name: f.expression
      };
      final bn = {
        for (final f in b.fields)
          if (f is NamedExpression) f.name.label.name: f.expression
      };
      if (an.isNotEmpty && an.keys.toSet().containsAll(bn.keys) &&
          bn.keys.toSet().containsAll(an.keys)) {
        for (final k in an.keys) {
          _pairExprs(an[k]!, bn[k]!, '$path.$k', out);
        }
        return;
      }
    }
    if (a is SwitchExpression && b is SwitchExpression) {
      final ac = {for (final c in a.cases) _caseKey(c.guardedPattern): c};
      final bc = {for (final c in b.cases) _caseKey(c.guardedPattern): c};
      if (ac.length == bc.length && ac.keys.every(bc.containsKey)) {
        for (final k in ac.keys) {
          _pairExprs(ac[k]!.expression, bc[k]!.expression, '$path[$k]', out);
        }
        return;
      }
    }
    if (a is SetOrMapLiteral && b is SetOrMapLiteral) {
      final am = {
        for (final e in a.elements)
          if (e is MapLiteralEntry) _src(e.key, 80): e.value
      };
      final bm = {
        for (final e in b.elements)
          if (e is MapLiteralEntry) _src(e.key, 80): e.value
      };
      if (am.isNotEmpty && am.length == bm.length &&
          am.keys.every(bm.containsKey)) {
        for (final k in am.keys) {
          _pairExprs(am[k]!, bm[k]!, '$path[$k]', out);
        }
        return;
      }
    }
    out.add((path, a, b));
  }

  // ── (c) language if statements and collection ifs ──────────────────────

  void _handleIfs(List<AstNode> ifs) {
    final lang = <(AstNode, bool, List<AstNode>, List<AstNode>)>[];
    for (final n in ifs) {
      if (n is IfStatement) {
        if (n.caseClause != null) continue;
        final t = langTest(n.expression);
        if (t == null) continue;
        final regionThen = <AstNode>[n.thenStatement];
        var regionElse = <AstNode>[];
        if (n.elseStatement != null) {
          regionElse = [n.elseStatement!];
        } else if (_exits(n.thenStatement)) {
          regionElse = _followingSiblings(n);
        }
        lang.add((n, t, regionThen, regionElse));
      } else if (n is IfElement) {
        if (n.caseClause != null) continue;
        final t = langTest(n.expression);
        if (t == null) continue;
        lang.add((
          n,
          t,
          [n.thenElement],
          n.elseElement == null ? <AstNode>[] : [n.elseElement!],
        ));
      }
    }
    stats['if_splits'] = lang.length;
    // Innermost first, so an outer split never re-reads an inner one.
    int depth(AstNode n) {
      var d = 0;
      for (AstNode? x = n.parent; x != null; x = x.parent) {
        d++;
      }
      return d;
    }

    lang.sort((a, b) => depth(b.$1).compareTo(depth(a.$1)));
    for (final (node, thenIsAr, rThen, rElse) in lang) {
      final arRegion = thenIsAr ? rThen : rElse;
      final enRegion = thenIsAr ? rElse : rThen;
      final m = member(node);
      final textValued = _returnsText(node);
      final arUnits = <_Unit>[];
      final enUnits = <_Unit>[];
      final arAlias = <String, String>{};
      final enAlias = <String, String>{};
      _collectUnits(arRegion, arUnits, arAlias);
      _collectUnits(enRegion, enUnits, enAlias);
      final ifComments = <CommentToken>[];
      _addAbove(ifComments, node.beginToken, m);
      final results = <_PairResult>[];

      // Returned values, statement by statement.
      bool wordy(_Unit u) =>
          u.lits.isNotEmpty || _resolvesToWording(u.expr);
      final arWordy = arUnits.where((u) => u.isReturn && wordy(u)).toList();
      final enWordy = enUnits.where((u) => u.isReturn && wordy(u)).toList();
      if (arWordy.isNotEmpty || enWordy.isNotEmpty) {
        List<_Unit> returnsOf(List<_Unit> units, List<_Unit> w) => [
              for (final u in units)
                if (u.isReturn &&
                    (w.contains(u) || (textValued && _isPlainValue(u.expr))))
                  u
            ];
        final arRet = returnsOf(arUnits, arWordy);
        final enRet = returnsOf(enUnits, enWordy);
        final sameShape = arRet.length == enRet.length &&
            [
              for (var i = 0; i < arRet.length; i++)
                arRet[i].cond == enRet[i].cond
            ].every((x) => x);
        if (sameShape) {
          for (var i = 0; i < arRet.length; i++) {
            _pairLenient(arRet[i].expr, enRet[i].expr, results);
          }
        } else {
          results.add(_PairResult(
            _sideOfUnits(arRet, true),
            _sideOfUnits(enRet, false),
          ));
        }
      }

      // Helper values: same-named locals pair; a local that feeds one of the
      // sentences above is written under it; the rest become one row.
      final arHelp =
          arUnits.where((u) => !u.isReturn && u.lits.isNotEmpty).toList();
      final enHelp =
          enUnits.where((u) => !u.isReturn && u.lits.isNotEmpty).toList();
      final enByName = {
        for (final u in enHelp)
          if (u.name != null) u.name!: u
      };
      final arByName = {
        for (final u in arHelp)
          if (u.name != null) u.name!: u
      };
      final usedEn = <_Unit>{};
      final leftAr = <_Unit>[];
      for (final u in arHelp) {
        final partner = u.name == null ? null : enByName[u.name!];
        if (partner != null && !usedEn.contains(partner)) {
          // Same-named locals pair when they line up one to one (a map
          // with the same keys, a condition shared by both); otherwise each
          // is written under the sentence it feeds.
          final trial = <_PairResult>[];
          _pairLenient(u.expr, partner.expr, trial);
          final clean = trial.isNotEmpty &&
              trial.every((t) =>
                  t.ar.alts.length == 1 &&
                  t.en.alts.length == 1 &&
                  t.ar.alts.first.cond == null &&
                  t.en.alts.first.cond == null);
          final foldAr = _referencedBy(results, true, u.name!, arAlias);
          final foldEn = _referencedBy(results, false, partner.name!, enAlias);
          // A joining word both sentences open with (`final and = lead ?
          // '' : 'و'`) is no row of its own, but its readings are written
          // under the sentences that use it, as quitEveningSentence's are.
          final joinWord = trial.length == 1 && _isJoinPair(trial.first);
          if (joinWord && foldAr && foldEn) {
            leftAr.add(u);
            continue;
          }
          if (clean || !(foldAr && foldEn)) {
            usedEn.add(partner);
            results.addAll(trial);
            continue;
          }
        }
        leftAr.add(u);
      }
      final leftEn = <_Unit>[
        for (final u in enHelp)
          if (!usedEn.contains(u)) u
      ];
      final restAr = _foldHelpers(results, true, leftAr, arAlias, arByName);
      final restEn = _foldHelpers(results, false, leftEn, enAlias, enByName);
      if (restAr.isNotEmpty || restEn.isNotEmpty) {
        final r = _PairResult(
          _sideOfUnits(restAr, true, helpers: true),
          _sideOfUnits(restEn, false, helpers: true),
          leftover: true,
        );
        results.add(r);
      }

      for (final res in results) {
        if (res.ar.isEmpty && res.en.isEmpty) continue;
        if (_isJoinPair(res)) {
          final lits = [...res.ar.lits, ...res.en.lits]
            ..sort((x, y) => x.offset.compareTo(y.offset));
          AstNode holder(StringLiteral l) =>
              l.parent is ConditionalExpression ? l.parent! : l;
          skipped.add({
            ..._skipEntry(holder(lits.first),
                'conjunction used as a join, not wording'),
            'source': _wordingText(
                lits.map((l) => _src(holder(l), 200)).toSet().join(' / ')),
            'lines': [for (final l in lits) line(l.offset)],
          });
          stats['cond_skipped_join_piece'] =
              stats['cond_skipped_join_piece']! + 1;
          continue;
        }
        final comments = <CommentToken>[...ifComments];
        _addEnclosing(comments, node, m);
        for (final lit in [...res.ar.lits, ...res.en.lits]) {
          _addAbove(comments, lit.beginToken, m);
          _addTrailing(comments, lit.beginToken, lit.endToken);
          _addEnclosing(comments, lit, m);
        }
        for (final d in [...res.ar.helperDecls, ...res.en.helperDecls]) {
          _addAbove(comments, d.beginToken, m);
        }
        final lead = [...res.ar.leadLits, ...res.en.leadLits];
        final all = [...(lead.isNotEmpty ? lead : [...res.ar.lits, ...res.en.lits])]
          ..sort((x, y) => x.offset.compareTo(y.offset));
        final arT = _joinSide(res.ar);
        final enT = _joinSide(res.en);
        final multi = res.ar.alts.length > 1 ||
            res.en.alts.length > 1 ||
            res.ar.where.isNotEmpty ||
            res.en.where.isNotEmpty;
        final fragment = res.leftover &&
            (res.ar.isEmpty || res.en.isEmpty) &&
            (res.ar.helperDecls.isNotEmpty || res.en.helperDecls.isNotEmpty);
        rows.add(_row(
          shape: multi ? 'if-split-list' : 'if-split',
          member: m,
          key: m.key,
          kind: m.kind,
          ar: arT,
          en: enT,
          node: all.isEmpty ? node : all.first,
          arNode: res.ar.firstNode,
          enNode: res.en.firstNode,
          hitComments: comments,
          fragment: fragment,
          arTexts: [...res.ar.lits],
          enTexts: [...res.en.lits],
        ));
        stats['if_rows'] = stats['if_rows']! + 1;
      }
      for (final u in [...arUnits, ...enUnits]) {
        for (final l in u.lits) {
          claimed.add(_Range(l.offset, l.end));
        }
      }
    }
  }

  /// Whether the member holding [n] returns text, so a return with no
  /// literal of its own (`return daysCount(n);`) is still one of its readings.
  bool _returnsText(AstNode n) {
    for (AstNode? x = n; x != null; x = x.parent) {
      if (x is FunctionExpression && x.parent is! FunctionDeclaration) {
        return false;
      }
      TypeAnnotation? rt;
      if (x is MethodDeclaration) {
        rt = x.returnType;
      } else if (x is FunctionDeclaration) {
        rt = x.returnType;
      } else {
        continue;
      }
      return rt != null && RegExp(r'^String\??$').hasMatch(_src(rt, 40));
    }
    return false;
  }

  bool _isPlainValue(Expression e) {
    final x = e.unParenthesized;
    if (x is StringLiteral) return _hasWording(x);
    if (x is NullLiteral) return false;
    return x is MethodInvocation ||
        x is SimpleIdentifier ||
        x is PrefixedIdentifier ||
        x is PropertyAccess ||
        x is FunctionExpressionInvocation;
  }

  bool _resolvesToWording(Expression e) {
    final body = _memberBody(e.unParenthesized);
    return body != null && _topLiterals(body).any(_hasWording);
  }

  _Side _sideOfUnits(List<_Unit> units, bool lang, {bool helpers = false}) {
    final alts = <_Alt>[];
    final lits = <StringLiteral>[];
    final side = _Side(alts, lits, units.isEmpty ? null : units.first.node);
    for (final u in units) {
      final expr = u.node is Expression && !u.orphan ? u.expr : null;
      if (expr == null) {
        // Orphan literals outside any value (an if condition, say).
        for (final l in u.lits) {
          alts.addAll(_alts(l, lang));
        }
      } else if (helpers && u.name != null) {
        final a = _alts(expr, lang);
        if (a.length == 1) {
          alts.add(_Alt(null, '${u.name} = ${a.first.text}', a.first.ph,
              a.first.visible,
              dynamic: a.first.dynamic));
        } else {
          for (final x in a) {
            alts.add(_Alt(null, '${u.name}, ${x.cond ?? 'otherwise'}: ${x.text}',
                x.ph, x.visible,
                dynamic: x.dynamic));
          }
        }
        side.helperDecls.add(u.node.parent ?? u.node);
      } else {
        for (final a in _alts(expr, lang)) {
          alts.add(a.withCond(_and(u.cond, a.cond)));
        }
      }
      lits.addAll(u.lits);
    }
    return side;
  }

  bool _referencedBy(List<_PairResult> results, bool lang, String name,
      Map<String, String> alias) {
    final names = {name, for (final e in alias.entries) if (e.value == name) e.key};
    final re = RegExp('(?<![A-Za-z0-9_\$])(${names.map(RegExp.escape).join('|')})(?![A-Za-z0-9_\$])');
    for (final r in results) {
      final side = lang ? r.ar : r.en;
      for (final a in side.alts) {
        if (a.ph.any(re.hasMatch)) return true;
      }
    }
    return false;
  }

  /// Writes each helper under every sentence on its side that uses it and
  /// returns the helpers nothing used.
  List<_Unit> _foldHelpers(List<_PairResult> results, bool lang,
      List<_Unit> helpers, Map<String, String> alias, Map<String, _Unit> all) {
    final rest = <_Unit>[];
    for (final u in helpers) {
      if (u.name == null) {
        rest.add(u);
        continue;
      }
      final names = {
        u.name!,
        for (final e in alias.entries)
          if (e.value == u.name) e.key
      };
      final re = RegExp('(?<![A-Za-z0-9_\$])(${names.map(RegExp.escape).join('|')})(?![A-Za-z0-9_\$])');
      var used = false;
      for (final r in results) {
        final side = lang ? r.ar : r.en;
        if (side.alts.any((a) => a.ph.any(re.hasMatch)) ||
            side.where.any((w) => w.$2.any((a) => a.ph.any(re.hasMatch)))) {
          side.where.add((u.name!, _alts(u.expr, lang)));
          side.helperDecls.add(u.node.parent ?? u.node);
          side.lits.addAll(u.lits);
          used = true;
        }
      }
      if (used) {
        stats['if_folded_helpers'] = stats['if_folded_helpers']! + 1;
      } else {
        rest.add(u);
      }
    }
    return rest;
  }

  _Text _joinSide(_Side side) {
    final base = _joinAlts(side.alts);
    if (side.where.isEmpty) return base;
    final lines = <String>[base.text];
    final ph = [...base.placeholders];
    final vis = <String>[if (base.visible.isNotEmpty) base.visible];
    var dyn = base.dynamic;
    for (final (name, alts) in side.where) {
      if (alts.length == 1 && alts.first.cond == null) {
        lines.add('$name = ${_reading(alts.first.text)}');
      } else {
        lines.add('$name =');
        final numbered = alts.every((a) => a.cond == null);
        for (var i = 0; i < alts.length; i++) {
          final a = alts[i];
          lines.add(numbered
              ? '  ${i + 1}. ${_reading(a.text)}'
              : '  ${a.cond ?? 'otherwise'}: ${_reading(a.text)}');
        }
      }
      for (final a in alts) {
        for (final x in a.ph) {
          if (!ph.contains(x)) ph.add(x);
        }
        if (a.visible.isNotEmpty) vis.add(a.visible);
        dyn = dyn || a.dynamic;
      }
    }
    return _Text(lines.join('\n'), ph, dyn, vis.join('\n'));
  }

  /// Splits a region into value-holding units in source order: returned
  /// expressions (with the if conditions they sit under), local initializers,
  /// assignments and bare expressions. Literals outside any unit (an if
  /// condition, say) go into a final unit. Pattern variables that unpack a
  /// local (final (one, two) = forms[unit]) are recorded in [alias].
  void _collectUnits(
      List<AstNode> region, List<_Unit> out, Map<String, String> alias) {
    if (region.length == 1 &&
        region.first is CollectionElement &&
        region.first is! Statement &&
        region.first is Expression) {
      final e = region.first as Expression;
      out.add(_Unit(e, true, null, _unitLits(e), null));
      return;
    }
    final orphan = <StringLiteral>[];
    final localNames = <String>{};

    void walk(AstNode n, String? cond) {
      if (n is ReturnStatement) {
        final e = n.expression;
        if (e != null) out.add(_Unit(e, true, null, _unitLits(e), cond));
        return;
      }
      if (n is IfStatement && n.caseClause == null) {
        orphan.addAll(_unitLits(n.expression));
        final c = _src(n.expression, 100000);
        walk(n.thenStatement, _and(cond, c));
        if (n.elseStatement != null) {
          walk(n.elseStatement!, _and(cond, 'otherwise'));
        }
        return;
      }
      if (n is Block) {
        var exited = false;
        for (final s in n.statements) {
          walk(s, exited ? _and(cond, 'otherwise') : cond);
          if (s is IfStatement &&
              s.elseStatement == null &&
              _exits(s.thenStatement)) {
            exited = true;
          }
        }
        return;
      }
      if (n is VariableDeclaration) {
        final e = n.initializer;
        localNames.add(n.name.lexeme);
        if (e != null) {
          out.add(_Unit(e, false, n.name.lexeme, _unitLits(e), cond));
        }
        return;
      }
      if (n is PatternVariableDeclaration) {
        final src = _src(n.expression, 200);
        for (final ln in localNames) {
          if (RegExp('(?<![A-Za-z0-9_])${RegExp.escape(ln)}(?![A-Za-z0-9_])')
              .hasMatch(src)) {
            n.pattern.accept(_PatternNames((v) => alias[v] = ln));
          }
        }
        orphan.addAll(_unitLits(n.expression));
        return;
      }
      if (n is ExpressionStatement) {
        final e = n.expression;
        if (e is AssignmentExpression) {
          out.add(_Unit(e.rightHandSide, false, _src(e.leftHandSide, 80),
              _unitLits(e.rightHandSide), cond));
        } else {
          out.add(_Unit(e, false, null, _unitLits(e), cond));
        }
        return;
      }
      if (n is FunctionExpression || n is FunctionDeclarationStatement) {
        orphan.addAll(_unitLits(n));
        return;
      }
      if (n is StringLiteral) {
        orphan.addAll(_unitLits(n));
        return;
      }
      for (final c in n.childEntities) {
        if (c is AstNode) walk(c, cond);
      }
    }

    // A region that is a run of statements (the ones after an exiting if)
    // reads like a block.
    var exited = false;
    for (final r in region) {
      walk(r, exited ? 'otherwise' : null);
      if (r is IfStatement && r.elseStatement == null && _exits(r.thenStatement)) {
        exited = true;
      }
    }
    if (orphan.isNotEmpty) {
      out.add(_Unit(orphan.first, false, null, orphan, null, orphan: true));
    }
  }

  List<StringLiteral> _unitLits(AstNode n) => [
        for (final lit in _topLiterals(n))
          if (!_isClaimed(lit) && _hasWording(lit)) lit
      ];

  /// Pairs two same-purpose expressions from the two language sides by
  /// structure; anything whose shapes differ becomes one row that lists each
  /// side's readings with their conditions.
  void _pairLenient(Expression a, Expression b, List<_PairResult> out) {
    a = a.unParenthesized;
    b = b.unParenthesized;
    final la = _unitLits(a);
    final lb = _unitLits(b);
    if (la.isEmpty && lb.isEmpty) {
      if (!_resolvesToWording(a) && !_resolvesToWording(b)) return;
    }
    if (a is StringLiteral && b is StringLiteral) {
      out.add(_PairResult(
          _Side(_alts(a, true), la, a), _Side(_alts(b, false), lb, b)));
      return;
    }
    if (a is ConditionalExpression &&
        b is ConditionalExpression &&
        langTest(a.condition) == null &&
        _src(a.condition, 400) == _src(b.condition, 400)) {
      _pairLenient(a.thenExpression, b.thenExpression, out);
      _pairLenient(a.elseExpression, b.elseExpression, out);
      return;
    }
    if (a is SwitchExpression && b is SwitchExpression) {
      _pairSwitches(a, b, out);
      return;
    }
    List<Expression>? argsA, argsB;
    if (a is MethodInvocation &&
        b is MethodInvocation &&
        a.methodName.name == b.methodName.name) {
      argsA = a.argumentList.arguments.toList();
      argsB = b.argumentList.arguments.toList();
    } else if (a is InstanceCreationExpression &&
        b is InstanceCreationExpression &&
        _src(a.constructorName, 200) == _src(b.constructorName, 200)) {
      argsA = a.argumentList.arguments.toList();
      argsB = b.argumentList.arguments.toList();
    }
    if (argsA != null && argsB != null && argsA.length == argsB.length) {
      for (var i = 0; i < argsA.length; i++) {
        final x = argsA[i], y = argsB[i];
        _pairLenient(x is NamedExpression ? x.expression : x,
            y is NamedExpression ? y.expression : y, out);
      }
      return;
    }
    if (a is ListLiteral &&
        b is ListLiteral &&
        a.elements.length == b.elements.length &&
        a.elements.every((e) => e is Expression) &&
        b.elements.every((e) => e is Expression)) {
      for (var i = 0; i < a.elements.length; i++) {
        _pairLenient(
            a.elements[i] as Expression, b.elements[i] as Expression, out);
      }
      return;
    }
    if (a is RecordLiteral &&
        b is RecordLiteral &&
        a.fields.length == b.fields.length) {
      String fieldKey(Expression f, int i) =>
          f is NamedExpression ? f.name.label.name : '\$$i';
      final bf = {
        for (var i = 0; i < b.fields.length; i++)
          fieldKey(b.fields[i], i): b.fields[i]
      };
      var ok = true;
      for (var i = 0; i < a.fields.length; i++) {
        if (!bf.containsKey(fieldKey(a.fields[i], i))) ok = false;
      }
      if (ok) {
        for (var i = 0; i < a.fields.length; i++) {
          final x = a.fields[i];
          final y = bf[fieldKey(x, i)]!;
          _pairLenient(x is NamedExpression ? x.expression : x,
              y is NamedExpression ? y.expression : y, out);
        }
        return;
      }
    }
    if (a is SetOrMapLiteral && b is SetOrMapLiteral) {
      final am = {
        for (final e in a.elements)
          if (e is MapLiteralEntry) _src(e.key, 80): e.value
      };
      final bm = {
        for (final e in b.elements)
          if (e is MapLiteralEntry) _src(e.key, 80): e.value
      };
      if (am.isNotEmpty &&
          am.length == a.elements.length &&
          am.length == bm.length &&
          am.keys.every(bm.containsKey)) {
        for (final k in am.keys) {
          _pairLenient(am[k]!, bm[k]!, out);
        }
        return;
      }
    }
    out.add(_PairResult(
          _Side(_alts(a, true), la, a), _Side(_alts(b, false), lb, b)));
  }

  /// Two switches over the same value. Cases with the same pattern pair.
  /// A case one side has and the other lacks is read by the other side's
  /// catch-all (`_`), so the Arabic 3-10 and 11+ forms both sit beside the
  /// one English plural instead of one of them standing alone.
  void _pairSwitches(
      SwitchExpression a, SwitchExpression b, List<_PairResult> out) {
    final aCases = a.cases.toList();
    final bCases = b.cases.toList();
    final bByKey = {for (final c in bCases) _caseKey(c.guardedPattern): c};
    final aByKey = {for (final c in aCases) _caseKey(c.guardedPattern): c};
    SwitchExpressionCase? wildcard(List<SwitchExpressionCase> cs) {
      for (final c in cs) {
        if (_isCatchAll(c.guardedPattern)) return c;
      }
      return null;
    }

    final aWild = wildcard(aCases), bWild = wildcard(bCases);
    // Union-find over cases: an edge joins cases that read the same values.
    final parent = <SwitchExpressionCase, SwitchExpressionCase>{};
    SwitchExpressionCase find(SwitchExpressionCase x) {
      while (parent[x] != null && !identical(parent[x], x)) {
        x = parent[x]!;
      }
      return x;
    }

    void union(SwitchExpressionCase x, SwitchExpressionCase y) {
      parent.putIfAbsent(x, () => x);
      parent.putIfAbsent(y, () => y);
      final rx = find(x), ry = find(y);
      if (!identical(rx, ry)) parent[rx] = ry;
    }

    for (final c in [...aCases, ...bCases]) {
      parent.putIfAbsent(c, () => c);
    }
    for (final c in aCases) {
      final k = _caseKey(c.guardedPattern);
      final partner = bByKey[k] ?? bWild;
      if (partner != null) union(c, partner);
    }
    for (final c in bCases) {
      final k = _caseKey(c.guardedPattern);
      if (aByKey.containsKey(k)) continue;
      if (aWild != null) union(c, aWild);
    }
    final order = <SwitchExpressionCase>[];
    final groups = <SwitchExpressionCase, List<SwitchExpressionCase>>{};
    for (final c in [...aCases, ...bCases]) {
      final r = find(c);
      if (!groups.containsKey(r)) order.add(r);
      groups.putIfAbsent(r, () => []).add(c);
    }
    final scrA = _src(a.expression, 100000), scrB = _src(b.expression, 100000);
    for (final r in order) {
      final members = groups[r]!;
      final ga = members.where(aCases.contains).toList();
      final gb = members.where(bCases.contains).toList();
      if (ga.length == 1 && gb.length == 1) {
        _pairLenient(ga.first.expression, gb.first.expression, out);
        continue;
      }
      _Side side(List<SwitchExpressionCase> cs, String scr, bool lang) {
        final alts = <_Alt>[];
        final lits = <StringLiteral>[];
        for (final c in cs) {
          final label = cs.length == 1 ? null : _caseLabel(scr, c.guardedPattern);
          for (final x in _alts(c.expression, lang)) {
            alts.add(x.withCond(_and(label, x.cond)));
          }
          lits.addAll(_unitLits(c.expression));
        }
        return _Side(alts, lits, cs.isEmpty ? null : cs.first.expression);
      }

      out.add(_PairResult(side(ga, scrA, true), side(gb, scrB, false)));
    }
  }

  bool _isCatchAll(GuardedPattern gp) {
    if (gp.whenClause != null) return false;
    final pat = gp.pattern;
    return pat is WildcardPattern ||
        (pat is DeclaredVariablePattern);
  }

  /// A case's pattern as a key that matches across the two sides:
  /// `MatrixQuadrant.doFirst`, `.doFirst` and `doFirst` are the same case.
  String _caseKey(GuardedPattern gp) {
    String key(DartPattern pat) {
      if (pat is ConstantPattern) {
        return _src(pat.expression, 200)
            .replaceFirst(RegExp(r'^[A-Z][A-Za-z0-9_]*\.'), '')
            .replaceFirst(RegExp(r'^\.'), '');
      }
      if (pat is LogicalOrPattern) {
        return '${key(pat.leftOperand)} || ${key(pat.rightOperand)}';
      }
      if (pat is ParenthesizedPattern) return key(pat.pattern);
      return _src(pat, 200);
    }

    final w = gp.whenClause;
    final k = key(gp.pattern);
    return w == null ? k : '$k when ${_src(w.expression, 200)}';
  }

  /// A case's pattern as a condition a reader can follow: `n == 1`,
  /// `n <= 10`, `otherwise`.
  String _caseLabel(String scrutinee, GuardedPattern gp) {
    final isThis = scrutinee == 'this';
    String label(DartPattern pat) {
      if (pat is WildcardPattern) return 'otherwise';
      if (pat is DeclaredVariablePattern) return 'otherwise';
      if (pat is ConstantPattern) {
        final k = _src(pat.expression, 200)
            .replaceFirst(RegExp(r'^[A-Z][A-Za-z0-9_]*\.'), '')
            .replaceFirst(RegExp(r'^\.'), '');
        return isThis ? k : '$scrutinee == $k';
      }
      if (pat is RelationalPattern) {
        return '$scrutinee ${pat.operator.lexeme} ${_src(pat.operand, 100000)}';
      }
      if (pat is LogicalOrPattern) {
        return '${label(pat.leftOperand)} || ${label(pat.rightOperand)}';
      }
      if (pat is ParenthesizedPattern) return label(pat.pattern);
      return '$scrutinee is ${_src(pat, 100000)}';
    }

    var s = label(gp.pattern);
    final w = gp.whenClause;
    if (w != null) {
      final g = _src(w.expression, 100000);
      s = s == 'otherwise' ? g : '$s && $g';
    }
    return s;
  }

  // ── (e) fixed-script sibling pairs ─────────────────────────────────────

  /// A literal kept in one script on purpose (a language's own name on the
  /// language switch, a font sample) beside the same call carrying the
  /// other script: _Segment(label: 'العربية') next to _Segment(label: 'EN').
  void _handleSiblingPairs() {
    final arabicLits = <SimpleStringLiteral>[];
    p.unit.accept(_ArabicFinder((n, text) {
      if (n is SimpleStringLiteral && !_isClaimed(n)) arabicLits.add(n);
    }));
    for (final lit in arabicLits) {
      if (_isClaimed(lit)) continue;
      final parent = lit.parent;
      String? slot;
      ArgumentList? args;
      if (parent is NamedExpression && parent.parent is ArgumentList) {
        slot = parent.name.label.name;
        args = parent.parent as ArgumentList;
      } else if (parent is ArgumentList) {
        slot = '#${parent.arguments.indexOf(lit)}';
        args = parent;
      }
      if (args == null || slot == null) continue;
      final call = args.parent;
      final callee = call == null ? null : _calleeName(call);
      if (callee == null) continue;
      final list = call!.parent;
      if (list is! ListLiteral) continue;
      SimpleStringLiteral? partner;
      for (final el in list.elements) {
        if (identical(el, call) || _calleeName(el) != callee) continue;
        final other = _slotValue(el, slot);
        if (other is SimpleStringLiteral &&
            !_arabicRe.hasMatch(other.value) &&
            _letterRe.hasMatch(other.value) &&
            !_isClaimed(other)) {
          partner = other;
          break;
        }
      }
      if (partner == null) continue;
      final m = member(lit);
      final comments = <CommentToken>[];
      for (final x in [lit, partner]) {
        _addAbove(comments, x.beginToken, m);
        _addTrailing(comments, x.beginToken, x.endToken);
        _addEnclosing(comments, x, m);
      }
      rows.add(_row(
        shape: 'sibling-pair',
        member: m,
        key: m.key,
        kind: 'constructor-args',
        ar: _textOf(lit, true),
        en: _textOf(partner, false),
        node: lit.offset < partner.offset ? lit : partner,
        arNode: lit,
        enNode: partner,
        hitComments: comments,
      ));
      stats['sibling_rows'] = (stats['sibling_rows'] ?? 0) + 1;
      claimed.add(_Range(lit.offset, lit.end));
      claimed.add(_Range(partner.offset, partner.end));
    }
  }

  String? _calleeName(AstNode n) {
    if (n is InstanceCreationExpression) {
      return n.constructorName.type.name.lexeme;
    }
    if (n is MethodInvocation) return n.methodName.name;
    return null;
  }

  Expression? _slotValue(AstNode call, String slot) {
    ArgumentList? args;
    if (call is InstanceCreationExpression) args = call.argumentList;
    if (call is MethodInvocation) args = call.argumentList;
    if (args == null) return null;
    if (slot.startsWith('#')) {
      final i = int.parse(slot.substring(1));
      return i < args.arguments.length ? args.arguments[i] : null;
    }
    for (final a in args.arguments) {
      if (a is NamedExpression && a.name.label.name == slot) {
        return a.expression;
      }
    }
    return null;
  }

  // ── Latin-only text with no language branch ───────────────────────────

  static const _uiSlots = {
    'label',
    'title',
    'hintText',
    'labelText',
    'semanticLabel',
    'semanticsLabel',
    'tooltip',
    'message',
    'text',
    'subtitle',
  };

  static const _labelGetters = {
    'label',
    'shortLabel',
    'title',
    'subtitle',
    'numeral',
    'displayName',
    'caption',
    'headline',
  };

  /// Latin text a reader sees in either language because no branch picks a
  /// language for it. Found in five positions, each checked for a Latin word
  /// so ids, keys and patterns stay out:
  ///   ui       a Text or label-like argument ('PRO', '+$xp XP')
  ///   label    a case of a label getter's switch ('IBM Plex Sans Arabic', 'IV')
  ///   fallback a capitalised name after ??, in a return, or beside a
  ///            non-literal branch ('Warrior', 'Grow Daily')
  ///   period   the AM and PM markers
  ///   mail     a "Label: value" line of a composed mail body
  void _handleLatinOnly() {
    if (p.rel == 'lib/core/l10n/app_strings.dart') return;
    final found = <(StringLiteral, String)>[];
    p.unit.accept(_TopStringVisitor((StringLiteral lit) {
      if (_isClaimed(lit)) return;
      if (lit.parent?.thisOrAncestorOfType<StringLiteral>() != null) return;
      if (_skipContext(lit)) return;
      final parts = _literalParts(lit);
      if (parts == null) return;
      if (_arabicRe.hasMatch(parts)) return;
      if (!RegExp(r'[A-Za-z]').hasMatch(parts)) return;
      final rule = _latinRule(lit, parts);
      if (rule == null) return;
      // One letter is enough only for a label getter's case (the medal
      // numeral 'I'); anywhere else it is a code or a unit.
      if (rule != 'label' && !RegExp(r'[A-Za-z]{2}').hasMatch(parts)) return;
      found.add((lit, rule));
    }));
    for (final (lit, rule) in found) {
      claimed.add(_Range(lit.offset, lit.end));
      final m = member(lit);
      var key = m.key;
      if (rule == 'label') {
        final c = lit.parent as SwitchExpressionCase;
        key = '$key[${_caseKey(c.guardedPattern)}]';
      }
      final comments = <CommentToken>[];
      final holder = lit.parent is SwitchExpressionCase ? lit.parent! : lit;
      _addAbove(comments, holder.beginToken, m);
      _addTrailing(comments, holder.beginToken, holder.endToken);
      _addEnclosing(comments, lit, m);
      // No language side: a language test inside it (the support mail's
      // "Language: ar" or "en") is written out as both readings.
      final en = _textOf(lit, null);
      rows.add(_row(
        shape: 'latin-only',
        member: m,
        key: key,
        kind: m.kind,
        ar: _Text.empty,
        en: en,
        node: lit,
        enNode: lit,
        hitComments: comments,
        latinOnly: true,
        notes: [
          'No language branch: this Latin text shows as written in the '
              'Arabic interface too (found as: ${_latinRuleName[rule]}).',
        ],
      ));
      latinReport.add({
        'file': p.rel,
        'line': line(lit.offset),
        'key': key,
        'rule': rule,
        'text': _wordingText(en.text),
      });
    }
  }

  static const _latinRuleName = {
    'ui': 'a Text or label argument',
    'label': 'a case of a label getter',
    'fallback': 'a fallback name',
    'period': 'an AM or PM marker',
    'mail': 'a line of a composed mail body',
  };

  String? _literalParts(StringLiteral lit) {
    if (lit is SimpleStringLiteral) return lit.value;
    if (lit is StringInterpolation) {
      return lit.elements.whereType<InterpolationString>().map((e) => e.value).join(' ');
    }
    if (lit is AdjacentStrings) {
      final out = <String>[];
      for (final s in lit.strings) {
        final x = _literalParts(s);
        if (x == null) return null;
        out.add(x);
      }
      return out.join();
    }
    return null;
  }

  bool _skipContext(StringLiteral node) {
    final parent = node.parent;
    if (parent is MapLiteralEntry && identical(parent.key, node)) return true;
    if (parent is IndexExpression) return true;
    if (parent is Directive || parent is Annotation) return true;
    if (parent is Configuration) return true;
    for (AstNode? x = parent; x != null; x = x.parent) {
      if (x is MethodInvocation) {
        final n = x.methodName.name;
        if (n == 'debugPrint' || n == 'print' || n == 'log') return true;
        if (n == 'RegExp') return true;
      }
      if (x is InstanceCreationExpression &&
          x.constructorName.type.name.lexeme == 'RegExp') {
        return true;
      }
      if (x is Assertion) return true;
      if (x is Statement || x is ClassMember) break;
    }
    return false;
  }

  String? _latinRule(StringLiteral lit, String parts) {
    final parent = lit.parent;
    if (parent is NamedExpression && _uiSlots.contains(parent.name.label.name)) {
      return 'ui';
    }
    if (parent is ArgumentList && identical(parent.arguments.first, lit)) {
      final call = parent.parent;
      final callee = call == null ? null : _calleeName(call);
      if (callee == 'Text' || callee == 'SelectableText') return 'ui';
    }
    if (parent is SwitchExpressionCase && identical(parent.expression, lit)) {
      final sw = parent.parent;
      final holder = sw?.parent;
      final decl = holder?.parent;
      if (sw is SwitchExpression &&
          holder is ExpressionFunctionBody &&
          decl is MethodDeclaration &&
          decl.isGetter &&
          _labelGetters.contains(decl.name.lexeme) &&
          sw.cases.every((c) => c.expression is SimpleStringLiteral)) {
        return 'label';
      }
    }
    if (lit is SimpleStringLiteral && {'AM', 'PM'}.contains(lit.value)) {
      if (parent is ConditionalExpression) return 'period';
    }
    if (lit is StringInterpolation &&
        parent is ListLiteral &&
        RegExp(r'^[A-Z][a-z]+: ').hasMatch(
            (lit.elements.first as InterpolationString).value)) {
      return 'mail';
    }
    if (lit is SimpleStringLiteral && _looksLikeName(lit.value)) {
      final isFallback = (parent is BinaryExpression &&
              parent.operator.type == TokenType.QUESTION_QUESTION &&
              identical(parent.rightOperand, lit)) ||
          parent is ReturnStatement ||
          parent is ExpressionFunctionBody ||
          (parent is ConditionalExpression &&
              langTest(parent.condition) == null &&
              _otherBranch(parent, lit) is! StringLiteral);
      if (isFallback) return 'fallback';
    }
    return null;
  }

  Expression _otherBranch(ConditionalExpression c, Expression lit) =>
      identical(c.thenExpression, lit) ? c.elseExpression : c.thenExpression;

  /// 'Warrior', 'Grow Daily': one or two capitalised words, nothing else.
  bool _looksLikeName(String v) =>
      RegExp(r'^[A-Z][a-z]+( [A-Z][a-z]+)?$').hasMatch(v);

  // ── Rendering ──────────────────────────────────────────────────────────

  _Text _textOf(Expression e, bool? lang) => _joinAlts(_alts(e, lang));

  _Text _joinAlts(List<_Alt> alts) {
    if (alts.isEmpty) return _Text.empty;
    final ph = <String>[];
    var dyn = false;
    final vis = <String>[];
    for (final a in alts) {
      for (final x in a.ph) {
        if (!ph.contains(x)) ph.add(x);
      }
      dyn = dyn || a.dynamic;
      if (a.visible.isNotEmpty) vis.add(a.visible);
    }
    String text;
    if (alts.length == 1) {
      text = alts.first.text;
    } else if (alts.every((a) => a.cond == null)) {
      text = [
        for (var i = 0; i < alts.length; i++)
          '${i + 1}. ${_reading(alts[i].text)}'
      ].join('\n');
    } else {
      text = alts
          .map((a) => '${a.cond ?? 'otherwise'}: ${_reading(a.text)}')
          .join('\n');
    }
    return _Text(text, ph, dyn, vis.join('\n'));
  }

  /// One reading among several: an empty string (a joining word that is
  /// left out for the first sentence) is written as "(empty)".
  static String _reading(String text) => text.isEmpty ? '(empty)' : text;

  /// Every way [e] can read, each with the condition it reads that way under.
  /// [lang] picks the side of a language conditional met on the way (true:
  /// Arabic), for a getter read through (`: label`).
  List<_Alt> _alts(Expression e, bool? lang, [int depth = 0]) {
    e = e.unParenthesized;
    if (depth <= 8 && (e is StringInterpolation || e is AdjacentStrings)) {
      final expanded = _expandInterpolation(e, lang, depth);
      if (expanded != null) return expanded;
    }
    final ph = <String>[];
    final vis = StringBuffer();
    final s = _renderString(e, ph, vis);
    if (s != null) return [_Alt(null, s, ph, vis.toString())];
    if (depth > 8) return [_codeAlt(e)];
    if (e is ConditionalExpression) {
      final t = langTest(e.condition);
      if (t != null) {
        if (lang == null) return [_codeAlt(e)];
        return _alts(t == lang ? e.thenExpression : e.elseExpression, lang,
            depth + 1);
      }
      final c = _src(e.condition, 100000);
      final out = <_Alt>[
        for (final a in _alts(e.thenExpression, lang, depth + 1))
          a.withCond(_and(c, a.cond)),
      ];
      final elseE = e.elseExpression.unParenthesized;
      final chained =
          elseE is ConditionalExpression && langTest(elseE.condition) == null;
      for (final a in _alts(elseE, lang, depth + 1)) {
        out.add(chained ? a : a.withCond(_and('otherwise', a.cond)));
      }
      return out;
    }
    if (e is SwitchExpression) {
      final scr = _src(e.expression, 100000);
      return [
        for (final c in e.cases)
          for (final a in _alts(c.expression, lang, depth + 1))
            a.withCond(_and(_caseLabel(scr, c.guardedPattern), a.cond)),
      ];
    }
    if (e is ListLiteral &&
        e.elements.isNotEmpty &&
        e.elements.every((x) => x is Expression) &&
        _hasWordingIn(e)) {
      final out = <_Alt>[];
      for (var i = 0; i < e.elements.length; i++) {
        for (final a in _alts(e.elements[i] as Expression, lang, depth + 1)) {
          out.add(a.withCond(_and('item ${i + 1}', a.cond)));
        }
      }
      return out;
    }
    if (e is SetOrMapLiteral &&
        e.elements.isNotEmpty &&
        e.elements.every((x) => x is MapLiteralEntry) &&
        _hasWordingIn(e)) {
      final out = <_Alt>[];
      for (final el in e.elements.cast<MapLiteralEntry>()) {
        final k = _src(el.key, 100000);
        for (final a in _alts(el.value, lang, depth + 1)) {
          out.add(a.withCond(_and(k, a.cond)));
        }
      }
      return out;
    }
    if (e is RecordLiteral && _hasWordingIn(e)) {
      final parts = <_Alt>[];
      for (final f in e.fields) {
        final x = f is NamedExpression ? f.expression : f;
        final a = _alts(x, lang, depth + 1);
        if (a.length != 1 || a.first.cond != null) return [_codeAlt(e)];
        parts.add(a.first);
      }
      return [
        _Alt(
          null,
          parts.map((a) => a.text).join(' / '),
          [for (final a in parts) ...a.ph],
          parts.map((a) => a.visible).where((v) => v.isNotEmpty).join(' / '),
          dynamic: parts.any((a) => a.dynamic),
        )
      ];
    }
    if (e is BinaryExpression &&
        e.operator.type == TokenType.QUESTION_QUESTION &&
        _hasLetters(e.rightOperand)) {
      final left = _src(e.leftOperand, 100000);
      return [
        for (final a in _alts(e.leftOperand, lang, depth + 1))
          a.withCond(_and('$left != null', a.cond)),
        for (final a in _alts(e.rightOperand, lang, depth + 1))
          a.withCond(_and('otherwise', a.cond)),
      ];
    }
    if (e is MethodInvocation &&
        e.target == null &&
        (e.methodName.name == '_pick' || e.methodName.name == '_pickLine') &&
        e.argumentList.arguments.isNotEmpty) {
      final first = e.argumentList.arguments.first;
      if (_hasWordingIn(first)) return _alts(first, lang, depth + 1);
    }
    final body = _memberBody(e);
    if (body != null && _hasWordingIn(body)) {
      // The getter's text now shows in this row; it is not a Latin-only
      // row of its own.
      claimed.add(_Range(body.offset, body.end));
      return _alts(body, lang, depth + 1);
    }
    return [_codeAlt(e)];
  }

  /// A string whose interpolation holds a conditional with a literal branch
  /// (`'App: Grow Daily${v == null ? '' : ' $v'}'`), written as one reading
  /// per branch after the branch's condition, the way the other conditional
  /// readings are: "v == null: App: Grow Daily", "otherwise: App: Grow Daily
  /// {v}". Null when there is none, or when the readings would pass eight.
  List<_Alt>? _expandInterpolation(Expression e, bool? lang, int depth) {
    final parts = <StringLiteral>[];
    if (e is AdjacentStrings) {
      for (final x in e.strings) {
        if (x is! SimpleStringLiteral && x is! StringInterpolation) return null;
        parts.add(x);
      }
    } else {
      parts.add(e as StringLiteral);
    }
    var found = false;
    var combos = <_Alt>[_Alt(null, '', const [], '')];
    List<_Alt> append(List<_Alt> heads, List<_Alt> tails) => [
          for (final h in heads)
            for (final t in tails)
              _Alt(
                _and(h.cond, t.cond),
                h.text + t.text,
                [...h.ph, ...t.ph.where((x) => !h.ph.contains(x))],
                h.visible + t.visible,
                dynamic: h.dynamic || t.dynamic,
              )
        ];
    for (final part in parts) {
      if (part is SimpleStringLiteral) {
        combos = append(combos, [_Alt(null, part.value, const [], part.value)]);
        continue;
      }
      for (final el in (part as StringInterpolation).elements) {
        if (el is InterpolationString) {
          combos = append(combos, [_Alt(null, el.value, const [], el.value)]);
          continue;
        }
        final x = (el as InterpolationExpression).expression.unParenthesized;
        if (x is ConditionalExpression && _hasLiteralBranch(x)) {
          found = true;
          combos = append(combos, _branchAlts(x, lang, depth + 1));
        } else {
          final src = _src(x, 100000);
          combos = append(combos, [_Alt(null, '{$src}', [src], ' ')]);
        }
        if (combos.length > 8) return null;
      }
    }
    return found ? combos : null;
  }

  static bool _hasLiteralBranch(ConditionalExpression x) =>
      x.thenExpression.unParenthesized is StringLiteral ||
      x.elseExpression.unParenthesized is StringLiteral;

  List<_Alt> _branchAlts(ConditionalExpression x, bool? lang, int depth) {
    final t = langTest(x.condition);
    if (t != null && lang != null) {
      return _pieceAlts(t == lang ? x.thenExpression : x.elseExpression, lang, depth);
    }
    final cond = _src(x.condition, 100000);
    final elseE = x.elseExpression.unParenthesized;
    final chained = elseE is ConditionalExpression &&
        langTest(elseE.condition) == null &&
        _hasLiteralBranch(elseE);
    return [
      for (final a in _pieceAlts(x.thenExpression, lang, depth))
        a.withCond(_and(cond, a.cond)),
      for (final a in _pieceAlts(elseE, lang, depth))
        chained ? a : a.withCond(_and('otherwise', a.cond)),
    ];
  }

  List<_Alt> _pieceAlts(Expression y, bool? lang, int depth) {
    y = y.unParenthesized;
    if (y is StringLiteral) return _alts(y, lang, depth);
    if (y is ConditionalExpression && _hasLiteralBranch(y)) {
      return _branchAlts(y, lang, depth + 1);
    }
    final src = _src(y, 100000);
    return [_Alt(null, '{$src}', [src], ' ')];
  }

  /// A value that is not a literal. Code that carries no wording reads like
  /// an interpolation ({daysCount(n)}); code that does is shown as source.
  _Alt _codeAlt(Expression e) {
    if (!_hasLetters(e)) {
      final src = _src(e, 100000);
      return _Alt(null, '{$src}', [src], '');
    }
    final ph = <String>[];
    final vis = <String>[];
    for (final lit in _topLiterals(e)) {
      final b = StringBuffer();
      _renderString(lit, ph, b);
      if (b.isNotEmpty) vis.add(b.toString());
    }
    return _Alt(null, '[dynamic] ${_src(e, 100000)}', ph, vis.join('\n'),
        dynamic: true);
  }

  bool _hasWordingIn(AstNode n) => _topLiterals(n).any(_hasWording);

  /// Whether a literal inside [n] carries a letter, not only punctuation
  /// such as the Arabic comma a join uses.
  bool _hasLetters(AstNode n) => _topLiterals(n).any((lit) {
        final text = _renderString(lit, [], StringBuffer()) ?? '';
        return RegExp(r'[A-Za-zء-يٮ-ۓۺ-ۿ]').hasMatch(text);
      });

  /// The expression a bare name stands for when it names a getter or field
  /// of the same class, enum or extension, or of the file's top level, and
  /// is not shadowed by a local or a parameter.
  Expression? _memberBody(Expression e) {
    String? name;
    if (e is SimpleIdentifier) {
      name = e.name;
    } else if (e is PropertyAccess && e.target is ThisExpression) {
      name = e.propertyName.name;
    }
    if (name == null || _isLocalName(e, name)) return null;
    final cls = _classLike(e);
    Expression? found;
    void look(AstNode scope, bool topLevelOnly) {
      scope.accept(_MemberBodyFinder(name!, (decl, expr) {
        if (found != null) return;
        final owner = _classLike(decl);
        if (topLevelOnly ? owner == null : identical(owner, cls)) found = expr;
      }));
    }

    if (cls != null) look(cls, false);
    if (found == null) look(p.unit, true);
    return found;
  }

  bool _isLocalName(AstNode from, String name) {
    for (AstNode? x = from.parent; x != null; x = x.parent) {
      FormalParameterList? params;
      if (x is FunctionExpression) params = x.parameters;
      if (x is MethodDeclaration) params = x.parameters;
      if (x is ConstructorDeclaration) params = x.parameters;
      if (params != null &&
          params.parameters.any((pp) => pp.name?.lexeme == name)) {
        return true;
      }
      if (x is Block) {
        for (final s in x.statements) {
          if (s.offset >= from.offset) break;
          if (s is VariableDeclarationStatement &&
              s.variables.variables.any((v) => v.name.lexeme == name)) {
            return true;
          }
          if (s is PatternVariableDeclarationStatement) {
            var hit = false;
            s.declaration.pattern
                .accept(_PatternNames((v) => hit = hit || v == name));
            if (hit) return true;
          }
        }
      }
      if (x is SwitchExpressionCase) {
        var hit = false;
        x.guardedPattern.pattern
            .accept(_PatternNames((v) => hit = hit || v == name));
        if (hit) return true;
      }
      if (x is ClassMember || x is CompilationUnitMember) break;
    }
    return false;
  }

  bool _exits(AstNode s) {
    if (s is ReturnStatement) return true;
    if (s is ExpressionStatement && s.expression is ThrowExpression) {
      return true;
    }
    if (s is Block) return s.statements.isNotEmpty && _exits(s.statements.last);
    if (s is IfStatement) {
      return s.elseStatement != null &&
          _exits(s.thenStatement) &&
          _exits(s.elseStatement!);
    }
    return false;
  }

  List<AstNode> _followingSiblings(Statement s) {
    final parent = s.parent;
    NodeList<Statement>? list;
    if (parent is Block) list = parent.statements;
    if (parent is SwitchMember) list = parent.statements;
    if (list == null) return [];
    final i = list.indexOf(s);
    return i < 0 ? [] : list.sublist(i + 1);
  }

  /// A literal that could be read by a person: not a bare locale code, and
  /// carrying a letter or an interpolation.
  bool _isWordingLiteral(StringLiteral lit) {
    if (lit is SimpleStringLiteral && _isLocaleCode(lit.value)) return false;
    return _hasWording(lit);
  }

  bool _hasWording(StringLiteral lit) {
    final ph = <String>[];
    final text = _renderString(lit, ph, StringBuffer()) ?? '';
    return _letterRe.hasMatch(text) || ph.isNotEmpty;
  }

  bool _isClaimed(AstNode n) =>
      claimed.any((r) => r.contains(n.offset, n.end));

  // ── Literal discovery and rendering ────────────────────────────────────

  /// String literals not nested in another string literal, skipping
  /// debug output, map keys, index keys and, when given, anything inside
  /// [excludeWithin].
  List<StringLiteral> _topLiterals(AstNode root,
      {List<AstNode> excludeWithin = const []}) {
    final out = <StringLiteral>[];
    root.accept(_LiteralFinder(out, excludeWithin));
    if (root is StringLiteral && out.isEmpty) out.add(root);
    return out;
  }

  String? _renderString(Expression e, List<String> ph, StringBuffer vis) {
    if (e is SimpleStringLiteral) {
      vis.write(e.value);
      return e.value;
    }
    if (e is AdjacentStrings) {
      final b = StringBuffer();
      for (final s in e.strings) {
        final t = _renderString(s, ph, vis);
        if (t == null) return null;
        b.write(t);
      }
      return b.toString();
    }
    if (e is StringInterpolation) {
      final b = StringBuffer();
      for (final el in e.elements) {
        if (el is InterpolationString) {
          b.write(el.value);
          vis.write(el.value);
        } else if (el is InterpolationExpression) {
          final src = _src(el.expression, 100000);
          if (!ph.contains(src)) ph.add(src);
          b.write('{$src}');
          vis.write(' ');
        }
      }
      return b.toString();
    }
    return null;
  }

  String _src(AstNode n, [int max = 200]) {
    var s = p.content
        .substring(n.offset, n.end)
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (s.length > max) s = '${s.substring(0, max)}...';
    return s;
  }

  // ── Members, sections, comments ────────────────────────────────────────

  _Member member(AstNode node) {
    AstNode? decl;
    String? name;
    var kind = 'other';
    var declKind = 'other';
    for (AstNode? x = node; x != null; x = x.parent) {
      if (x is MethodDeclaration) {
        decl = x;
        name = x.name.lexeme;
        kind = x.isGetter ? 'getter' : 'method';
        declKind = kind;
        break;
      }
      if (x is FunctionDeclaration && x.parent is CompilationUnit) {
        decl = x;
        name = x.name.lexeme;
        kind = x.isGetter ? 'getter' : 'method';
        declKind = x.isGetter ? 'getter' : 'function';
        break;
      }
      if (x is ConstructorDeclaration) {
        decl = x;
        name = x.name == null ? 'new' : x.name!.lexeme;
        kind = 'method';
        declKind = 'constructor';
        break;
      }
      if (x is EnumConstantDeclaration) {
        decl = x;
        name = x.name.lexeme;
        kind = 'constructor-args';
        declKind = 'enum-constant';
        break;
      }
      if (x is VariableDeclaration &&
          (x.parent?.parent is FieldDeclaration ||
              x.parent?.parent is TopLevelVariableDeclaration)) {
        decl = x.parent!.parent;
        name = x.name.lexeme;
        kind = 'field';
        declKind = 'field';
        break;
      }
    }
    String? className;
    CompilationUnitMember? top;
    for (AstNode? x = decl ?? node; x != null; x = x.parent) {
      if (className == null) {
        if (x is ClassDeclaration) className = x.namePart.typeName.lexeme;
        if (x is EnumDeclaration) className = x.namePart.typeName.lexeme;
        if (x is MixinDeclaration) className = x.name.lexeme;
        if (x is ExtensionDeclaration) className = x.name?.lexeme ?? 'extension';
        if (x is ExtensionTypeDeclaration) {
          className = x.primaryConstructor.typeName.lexeme;
        }
      }
      if (x is CompilationUnitMember && x.parent is CompilationUnit) top = x;
    }
    name ??= '(unknown)';
    final isS = _isStringsClass(className);
    final key = (className == null || isS) ? name : '$className.$name';
    return _Member(key, kind, decl, className, name, declKind, top);
  }

  /// The S class in app_strings.dart: its members are keyed by bare name.
  bool _isStringsClass(String? className) =>
      p.rel == 'lib/core/l10n/app_strings.dart' && className == 'S';

  /// Section banners, each with the comment range it covers (a wrapped
  /// banner spans several comment lines).
  List<({int offset, int end, String text, CompilationUnitMember? top})>
      _collectBanners() {
    final out =
        <({int offset, int end, String text, CompilationUnitMember? top})>[];
    Token? t = p.unit.beginToken;
    while (t != null) {
      final comments = <CommentToken>[];
      for (Token? c = t.precedingComments; c != null; c = c.next) {
        comments.add(c as CommentToken);
      }
      for (var i = 0; i < comments.length; i++) {
        final c = comments[i];
        final lex = c.lexeme.trimLeft();
        if (lex.startsWith('///')) continue;
        final m = _bannerStartRe.firstMatch(lex);
        if (m == null) continue;
        final texts = <String>[m.group(1)!];
        var endIdx = -1;
        if (_ruleEndRe.hasMatch(lex)) {
          endIdx = i;
        } else {
          for (var j = i + 1; j < comments.length && j <= i + 3; j++) {
            final lj = comments[j].lexeme.trimLeft();
            if (!lj.startsWith('//') || lj.startsWith('///')) break;
            if (line(comments[j].offset) != line(comments[j - 1].offset) + 1) {
              break;
            }
            texts.add(lj.replaceFirst(RegExp(r'^//\s*'), ''));
            if (_ruleEndRe.hasMatch(lj)) {
              endIdx = j;
              break;
            }
          }
        }
        if (endIdx < 0) continue; // a heading-like comment, not a banner
        final text = _commentText(texts.join(' '))
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        CompilationUnitMember? top;
        for (final d in p.unit.declarations) {
          if (c.offset >= d.offset && c.offset < d.end) top = d;
        }
        out.add((
          offset: c.offset,
          end: comments[endIdx].end,
          text: text,
          top: top
        ));
        i = endIdx;
      }
      if (t.type == TokenType.EOF) break;
      t = t.next;
    }
    return out;
  }

  bool _inBanner(CommentToken c) =>
      banners.any((b) => c.offset >= b.offset && c.end <= b.end);

  String section(AstNode node, _Member m) {
    String? best;
    for (final b in banners) {
      if (b.offset >= node.offset) break;
      if (b.top == null || identical(b.top, m.topLevel)) best = b.text;
    }
    return best ?? m.className ?? '(top level)';
  }

  Token _firstToken(AstNode n) {
    if (n is AnnotatedNode) {
      return n.metadata.isNotEmpty
          ? n.metadata.first.beginToken
          : n.firstTokenAfterCommentAndMetadata;
    }
    return n.beginToken;
  }

  /// Comments directly above the line [t] sits on (contiguous, not trailing
  /// a previous code line, stopping at a section banner). Skips the
  /// declaration's own first token, whose comments are added separately.
  void _addAbove(List<CommentToken> out, Token t, _Member? m) {
    // Move to the first token on this line.
    var first = t;
    while (true) {
      final prev = first.previous;
      if (prev == null || prev.type == TokenType.EOF || prev.offset < 0) break;
      if (line(prev.offset) != line(first.offset)) break;
      first = prev;
    }
    if (m != null && m.declNode != null) {
      if (identical(first, _firstToken(m.declNode!)) ||
          first.offset == _firstToken(m.declNode!).offset) {
        return;
      }
    }
    _commentsAbove(out, first);
  }

  void _commentsAbove(List<CommentToken> out, Token first) {
    final comments = <CommentToken>[];
    for (CommentToken? c = first.precedingComments;
        c != null;
        c = c.next as CommentToken?) {
      comments.add(c);
    }
    final prev = first.previous;
    final prevLine = (prev == null || prev.type == TokenType.EOF || prev.offset < 0)
        ? 0
        : line(prev.end > 0 ? prev.end - 1 : prev.offset);
    var expected = line(first.offset) - 1;
    final picked = <CommentToken>[];
    for (final c in comments.reversed) {
      final endLine = line(c.end > 0 ? c.end - 1 : c.offset);
      final startLine = line(c.offset);
      if (endLine != expected) break;
      if (startLine == prevLine) break;
      if (_inBanner(c)) break;
      picked.insert(0, c);
      expected = startLine - 1;
    }
    for (final c in picked) {
      if (!out.any((o) => o.offset == c.offset)) out.add(c);
    }
  }

  /// Comments written inside a language conditional, between its parts:
  /// before the `?` (after `isAr`), between the `?` and the Arabic side,
  /// before the `:` and between the `:` and the English side. With
  /// [nested], the same for every other (not language) conditional inside
  /// it, so a comment above one reading of `n == 1 ? ... : ...` counts too.
  void _addInner(List<CommentToken> out, ConditionalExpression c,
      {bool nested = true}) {
    final conds = <ConditionalExpression>[c];
    if (nested) {
      c.accept(_ConditionalFinder((x) {
        if (!identical(x, c) && langTest(x.condition) == null) conds.add(x);
      }));
    }
    for (final x in conds) {
      for (final t in [
        x.question,
        x.thenExpression.beginToken,
        x.colon,
        x.elseExpression.beginToken,
      ]) {
        for (CommentToken? k = t.precedingComments;
            k != null;
            k = k.next as CommentToken?) {
          if (_inBanner(k)) continue;
          if (!out.any((o) => o.offset == k!.offset)) out.add(k);
        }
      }
    }
  }

  /// The first token on the line [t] sits on.
  Token _lineStart(Token t) {
    var first = t;
    while (true) {
      final prev = first.previous;
      if (prev == null || prev.type == TokenType.EOF || prev.offset < 0) break;
      if (line(prev.offset) != line(first.offset)) break;
      first = prev;
    }
    return first;
  }

  /// Whether [n] opens its line, allowing only a prefix that leads into it
  /// (`return`, `await`, `child:`, `final x =`), never the end of something
  /// else (`} else if`, `), Text(`).
  bool _opensLine(AstNode n) {
    final begin = n.beginToken;
    for (Token t = _lineStart(begin); t.offset < begin.offset; t = t.next!) {
      final l = t.lexeme;
      if (l == ')' || l == ']' || l == '}' || l == ',' || l == ';') {
        return false;
      }
    }
    return true;
  }

  /// Comments above the statement, switch arm or call that holds the text,
  /// not only above the text's own line: walks up from [text] to the member.
  /// The innermost call or widget that takes the text as an argument counts
  /// (`_SettingsRow(` above `label: isAr ? ...`), and so does the statement
  /// that holds that call; with no call in between, every enclosing statement
  /// counts (`// Late...` above `final stamp = ...`, a comment above an `if`
  /// for every row inside it). A statement with no comment of its own takes
  /// the comment that heads its run of statements (see [_addParagraph]).
  /// Stops at a closure, a second call or the member.
  void _addEnclosing(List<CommentToken> out, AstNode text, _Member m) {
    var calls = 0;
    for (AstNode? x = text; x != null; x = x.parent) {
      if (identical(x, m.declNode)) break;
      if (x is FunctionBody || x is FunctionExpression) break;
      if (x is ClassMember || x is CompilationUnitMember) break;
      if (x is EnumConstantDeclaration) break;
      final isCall = x is InstanceCreationExpression ||
          x is MethodInvocation ||
          x is FunctionExpressionInvocation;
      if (isCall) {
        calls++;
        if (calls > 1) break;
        if (_opensLine(x)) _addAbove(out, x.beginToken, m);
        continue;
      }
      if (identical(x, text)) continue;
      if (x is Statement && x is! Block) {
        final elseIf = x.parent is IfStatement &&
            identical((x.parent as IfStatement).elseStatement, x);
        if (!elseIf && _opensLine(x)) {
          final before = out.length;
          _addAbove(out, x.beginToken, m);
          if (out.length == before) _addParagraph(out, x, m);
        }
        if (calls > 0) break;
        continue;
      }
      if (x is SwitchMember ||
          x is SwitchExpressionCase ||
          x is IfElement ||
          x is ForElement) {
        if (_opensLine(x)) _addAbove(out, x.beginToken, m);
        continue;
      }
    }
  }

  /// [s] has no comment of its own: when the statements right above it, with
  /// no blank line in between, open with a comment, that comment heads the
  /// whole run and is [s]'s comment too. So `// Zero and the first day are
  /// sentences...` above `if (won == 0) {...}` also covers the
  /// `if (counted == 1)` right under it, and `// 2. The moment, the ask...`
  /// covers the statements that build the moment and the ask.
  void _addParagraph(List<CommentToken> out, Statement s, _Member m) {
    final parent = s.parent;
    if (parent is! Block) return;
    final list = parent.statements;
    var i = list.indexOf(s);
    Statement cur = s;
    while (i > 0) {
      final prev = list[i - 1];
      if (!_opensLine(prev)) return;
      if (line(prev.endToken.offset) + 1 != line(cur.beginToken.offset)) return;
      final got = <CommentToken>[];
      _addAbove(got, prev.beginToken, m);
      if (got.isNotEmpty) {
        for (final c in got) {
          if (!out.any((o) => o.offset == c.offset)) out.add(c);
        }
        return;
      }
      cur = prev;
      i--;
    }
  }

  /// Comments that trail code on the lines from [begin] to [end].
  void _addTrailing(List<CommentToken> out, Token begin, Token end) {
    final startLine = line(begin.offset);
    final endLine = line(end.end > 0 ? end.end - 1 : end.offset);
    Token? t = begin.next;
    while (t != null) {
      final prev = t.previous!;
      final prevLine = line(prev.end > 0 ? prev.end - 1 : prev.offset);
      for (CommentToken? c = t.precedingComments;
          c != null;
          c = c.next as CommentToken?) {
        final cl = line(c.offset);
        if (cl >= startLine && cl <= endLine && cl == prevLine) {
          if (!out.any((o) => o.offset == c!.offset)) out.add(c);
        }
      }
      if (t.type == TokenType.EOF) break;
      if (line(t.offset) > endLine) break;
      t = t.next;
    }
  }

  String _normalizeComments(List<CommentToken> comments) {
    final paragraphs = <String>[];
    var current = <String>[];
    void flush() {
      if (current.isNotEmpty) {
        paragraphs.add(current.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim());
        current = [];
      }
    }

    int? lastLine;
    for (final c in comments) {
      final startLine = line(c.offset);
      if (lastLine != null && startLine > lastLine + 1) flush();
      var lex = c.lexeme;
      final lines = <String>[];
      if (lex.startsWith('/*')) {
        lex = lex.replaceFirst(RegExp(r'^/\*+'), '').replaceFirst(RegExp(r'\*+/$'), '');
        for (final l in lex.split('\n')) {
          lines.add(l.replaceFirst(RegExp(r'^\s*\*?'), ''));
        }
      } else {
        lines.add(lex.replaceFirst(RegExp(r'^///?'), ''));
      }
      for (final l in lines) {
        final cleaned = _commentText(l).trim();
        if (cleaned.isEmpty) {
          flush();
        } else {
          // A dash that opens a line continues the line above, so it becomes
          // that line's trailing comma rather than vanishing.
          if (RegExp('^\\s*$_emDash').hasMatch(l) &&
              current.isNotEmpty &&
              !current.last.endsWith(',')) {
            current[current.length - 1] = '${current.last},';
          }
          current.add(cleaned);
        }
      }
      lastLine = line(c.end > 0 ? c.end - 1 : c.offset);
    }
    flush();
    return paragraphs.join('\n');
  }

  Map<String, Object?> _row({
    required String shape,
    required _Member member,
    required String key,
    required String kind,
    required _Text ar,
    required _Text en,
    required AstNode node,
    AstNode? arNode,
    AstNode? enNode,
    required List<CommentToken> hitComments,
    List<String>? pairFields,
    bool fragment = false,
    bool latinOnly = false,
    String? group,
    String? section,
    List<String> notes = const [],
    List<AstNode>? arTexts,
    List<AstNode>? enTexts,
  }) {
    final ph = <String>[
      ...ar.placeholders,
      ...en.placeholders.where((x) => !ar.placeholders.contains(x)),
    ];
    final m = member;
    final decl = m.declNode;
    final declLine = decl == null
        ? line(node.offset)
        : line(decl is AnnotatedNode
            ? decl.firstTokenAfterCommentAndMetadata.offset
            : decl.offset);
    final visAr = _wordingText(ar.visible);
    final visEn = _wordingText(en.visible);
    // A conditional inside one arm of a switch is named by that arm's case,
    // as the per-case rows are: HabitCue._presetLabel['fajr'].
    var rowKey = key;
    if (shape == 'conditional' && !key.endsWith(']')) {
      final arm = _armKey(node, m);
      if (arm != null) rowKey = '$key[$arm]';
    }
    final row = <String, Object?>{
      'id': '',
      'source_group': group ?? _sourceGroup(key),
      'section': _commentText(section ?? this.section(node, m)),
      'key': rowKey,
      'arabic': _wordingText(ar.text),
      'english': _wordingText(en.text),
      'placeholders': ph,
      'reason': _reasonOf(member, hitComments),
      'file': p.rel,
      'line': declLine,
      'kind': kind,
      'decl_line': decl == null ? line(node.offset) : line(_firstToken(decl).offset),
      'text_line': line(node.offset),
      'ar_line': ar.text.isEmpty || arNode == null ? null : line(arNode.offset),
      'en_line': en.text.isEmpty || enNode == null ? null : line(enNode.offset),
      'shape': shape,
      'dynamic': ar.dynamic || en.dynamic,
      if (visAr != _wordingText(ar.text)) 'arabic_visible': visAr,
      if (visEn != _wordingText(en.text)) 'english_visible': visEn,
      if (fragment) 'fragment': true,
      if (latinOnly) 'latin_only': true,
      if (_runtimeDigits(ar, m)) 'arabic_digits_runtime': true,
      'member': {
        'class': m.className,
        'name': m.name,
        'kind': m.declKind,
      },
      if (pairFields != null) 'pair_fields': pairFields,
      if (notes.isNotEmpty) 'notes': notes,
      '_offset': node.offset,
    };
    _info[row] = _RowInfo(
      member,
      node,
      [...hitComments],
      ar,
      en,
      arTexts ?? [if (arNode != null) arNode],
      enTexts ?? [if (enNode != null) enNode],
    );
    return row;
  }

  /// The declaration's own doc comment first, then the comments on the
  /// lines, statements and calls that hold the text.
  String _reasonOf(_Member member, List<CommentToken> hitComments) {
    final declComments = <CommentToken>[];
    if (member.declNode != null) {
      _commentsAbove(declComments, _firstToken(member.declNode!));
      // A trailing comment on a one-line declaration.
      final d = member.declNode!;
      if (line(d.offset) == line(d.end - 1) || d is! MethodDeclaration) {
        final lastLine = line(d.end - 1);
        if (lastLine - line(_firstToken(d).offset) <= 3) {
          _addTrailing(declComments, _firstToken(d), d.endToken);
        }
      }
    }
    final specific = hitComments
        .where((c) => !declComments.any((d) => d.offset == c.offset))
        .toList()
      ..sort((a, b) => a.offset.compareTo(b.offset));
    return <String>[
      _normalizeComments(declComments),
      _normalizeComments(specific),
    ].where((s) => s.isNotEmpty).join('\n');
  }

  /// The case of the switch arm that holds [node], inside its member.
  String? _armKey(AstNode node, _Member m) {
    for (AstNode? x = node.parent; x != null; x = x.parent) {
      if (identical(x, m.declNode)) break;
      if (x is SwitchExpressionCase) {
        final e = x.expression;
        if (node.offset >= e.offset && node.end <= e.end) {
          return _caseKey(x.guardedPattern);
        }
        return null;
      }
      if (x is SwitchPatternCase) return _caseKey(x.guardedPattern);
      if (x is SwitchCase) {
        return _src(x.expression, 200)
            .replaceFirst(RegExp(r'^[A-Z][A-Za-z0-9_]*\.'), '');
      }
      if (x is SwitchDefault) return 'default';
      if (x is ClassMember || x is CompilationUnitMember) break;
    }
    return null;
  }

  /// Whether the Arabic side puts a number through arabicDigits(): in the
  /// placeholder itself, through a function that does (countedOffsetPhrase),
  /// or through a local assigned from either (`final d = arabicDigits(done)`).
  bool _runtimeDigits(_Text ar, _Member m) {
    if (ar.text.trim().isEmpty) return false;
    final seen = <String>{};
    return ar.placeholders.any((ph) => _digitSource(ph, m, seen, 0));
  }

  bool _digitSource(String src, _Member m, Set<String> seen, int depth) {
    if (src.contains('arabicDigits(')) return true;
    for (final call in RegExp(r'([A-Za-z_$][\w$]*)\s*\(').allMatches(src)) {
      if (digitFns.contains(call.group(1))) return true;
    }
    final decl = m.declNode;
    if (decl == null || depth > 6) return false;
    for (final id in RegExp(r'(?<![\w$.])([A-Za-z_$][\w$]*)(?![\w$]*\s*\()')
        .allMatches(src)) {
      final name = id.group(1)!;
      if (!seen.add(name)) continue;
      final values = <Expression>[];
      decl.accept(_LocalValues(name, values));
      for (final v in values) {
        if (_digitSource(_src(v, 100000), m, seen, depth + 1)) return true;
      }
    }
    return false;
  }

  String _sourceGroup(String key) {
    final rel = p.rel;
    if (rel == 'lib/core/l10n/app_strings.dart') {
      return 'App strings (app_strings.dart)';
    }
    if (rel == 'lib/core/l10n/reminder_copy.dart' ||
        rel == 'lib/core/services/notification_service.dart' ||
        RegExp(r'^lib/core/services/[^/]*notification[^/]*\.dart$')
            .hasMatch(rel)) {
      return 'Notification and reminder copy';
    }
    if (rel == 'lib/core/l10n/daily_quotes.dart') return 'Daily quotes';
    if (rel.endsWith('/help_support_screen.dart') &&
        key.startsWith('kFaqEntries')) {
      return 'Help and Support FAQ';
    }
    return 'In-screen strings (other Dart files)';
  }

  /// Every Arabic literal piece that no row covers.
  List<Map<String, Object?>> unpairedArabic() {
    final out = <Map<String, Object?>>[];
    p.unit.accept(_ArabicFinder((AstNode n, String text) {
      if (_isClaimed(n)) return;
      final m = member(n);
      out.add({
        'file': p.rel,
        'line': line(n.offset),
        'key': m.key,
        'text': _wordingText(
            text.length > 200 ? '${text.substring(0, 200)}...' : text),
      });
    }));
    return out;
  }
}

class _Collector extends RecursiveAstVisitor<void> {
  final List<ConditionalExpression> conds;
  final List<AstNode> ifs;
  final List<ArgumentList> argLists;
  final List<SetOrMapLiteral> maps;
  final List<RecordLiteral> records;
  _Collector(this.conds, this.ifs, this.argLists, this.maps, this.records);

  @override
  void visitConditionalExpression(ConditionalExpression node) {
    conds.add(node);
    super.visitConditionalExpression(node);
  }

  @override
  void visitIfStatement(IfStatement node) {
    ifs.add(node);
    super.visitIfStatement(node);
  }

  @override
  void visitIfElement(IfElement node) {
    ifs.add(node);
    super.visitIfElement(node);
  }

  @override
  void visitArgumentList(ArgumentList node) {
    argLists.add(node);
    super.visitArgumentList(node);
  }

  @override
  void visitSetOrMapLiteral(SetOrMapLiteral node) {
    maps.add(node);
    super.visitSetOrMapLiteral(node);
  }

  @override
  void visitRecordLiteral(RecordLiteral node) {
    records.add(node);
    super.visitRecordLiteral(node);
  }
}

/// Feeds (container, name, expression, declaration) for every member,
/// top-level declaration and local variable that has a value expression.
class _MemberCollector extends RecursiveAstVisitor<void> {
  final void Function(AstNode container, String name, Expression? expr,
      AstNode decl) add;
  _MemberCollector(this.add);

  Expression? _bodyExpr(FunctionBody body) {
    if (body is ExpressionFunctionBody) return body.expression;
    if (body is BlockFunctionBody) {
      final st = body.block.statements;
      if (st.length == 1 && st.first is ReturnStatement) {
        return (st.first as ReturnStatement).expression;
      }
    }
    return null;
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (!node.isSetter) {
      add(node.parent!, node.name.lexeme, _bodyExpr(node.body), node);
    }
    super.visitMethodDeclaration(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    if (node.parent is CompilationUnit && !node.isSetter) {
      add(node.parent!, node.name.lexeme,
          _bodyExpr(node.functionExpression.body), node);
    }
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    final list = node.parent;
    final holder = list?.parent;
    if (holder is FieldDeclaration) {
      add(holder.parent!, node.name.lexeme, node.initializer, node);
    } else if (holder is TopLevelVariableDeclaration) {
      add(holder.parent!, node.name.lexeme, node.initializer, node);
    } else if (holder is VariableDeclarationStatement) {
      add(holder.parent!, node.name.lexeme, node.initializer, node);
    }
    super.visitVariableDeclaration(node);
  }
}

/// Getters (expression body or a single return) and initialised fields or
/// top-level variables named [name].
class _MemberBodyFinder extends RecursiveAstVisitor<void> {
  final String name;
  final void Function(AstNode decl, Expression expr) found;
  _MemberBodyFinder(this.name, this.found);

  Expression? _bodyExpr(FunctionBody body) {
    if (body is ExpressionFunctionBody) return body.expression;
    if (body is BlockFunctionBody) {
      final st = body.block.statements;
      if (st.length == 1 && st.first is ReturnStatement) {
        return (st.first as ReturnStatement).expression;
      }
    }
    return null;
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (node.isGetter && node.name.lexeme == name) {
      final e = _bodyExpr(node.body);
      if (e != null) found(node, e);
    }
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    if (node.parent is CompilationUnit &&
        node.isGetter &&
        node.name.lexeme == name) {
      final e = _bodyExpr(node.functionExpression.body);
      if (e != null) found(node, e);
    }
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    final holder = node.parent?.parent;
    if ((holder is FieldDeclaration || holder is TopLevelVariableDeclaration) &&
        node.name.lexeme == name &&
        node.initializer != null) {
      found(node, node.initializer!);
    }
    super.visitVariableDeclaration(node);
  }
}

class _VarFinder extends RecursiveAstVisitor<void> {
  final String name;
  final void Function(VariableDeclaration v) found;
  _VarFinder(this.name, this.found);

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    if (node.name.lexeme == name) found(node);
    super.visitVariableDeclaration(node);
  }
}

class _PatternNames extends RecursiveAstVisitor<void> {
  final void Function(String name) found;
  _PatternNames(this.found);

  @override
  void visitDeclaredVariablePattern(DeclaredVariablePattern node) {
    found(node.name.lexeme);
    super.visitDeclaredVariablePattern(node);
  }
}

class _LiteralFinder extends RecursiveAstVisitor<void> {
  final List<StringLiteral> out;
  final List<AstNode> exclude;
  _LiteralFinder(this.out, this.exclude);

  bool _excluded(AstNode n) =>
      exclude.any((x) => n.offset >= x.offset && n.end <= x.end);

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    if (!_skip(node)) out.add(node);
  }

  @override
  void visitStringInterpolation(StringInterpolation node) {
    if (!_skip(node)) out.add(node);
  }

  @override
  void visitAdjacentStrings(AdjacentStrings node) {
    if (!_skip(node)) out.add(node);
  }

  bool _skip(StringLiteral node) {
    if (_excluded(node)) return true;
    final parent = node.parent;
    if (parent is MapLiteralEntry && identical(parent.key, node)) return true;
    if (parent is IndexExpression) return true;
    if (parent is Directive || parent is Annotation) return true;
    if (parent is Configuration) return true;
    // A switch case's own pattern ('minutes' =>) is a key, not text.
    if (parent is ConstantPattern) return true;
    for (AstNode? x = parent; x != null; x = x.parent) {
      if (x is MethodInvocation) {
        final n = x.methodName.name;
        if (n == 'debugPrint' || n == 'print' || n == 'log') return true;
        // A pattern is never wording.
        if (n == 'RegExp') return true;
      }
      if (x is InstanceCreationExpression &&
          x.constructorName.type.name.lexeme == 'RegExp') {
        return true;
      }
      if (x is Assertion) return true;
      if (x is Statement || x is ClassMember) break;
    }
    return false;
  }

  @override
  void visitImportDirective(ImportDirective node) {}
  @override
  void visitExportDirective(ExportDirective node) {}
  @override
  void visitPartDirective(PartDirective node) {}
  @override
  void visitPartOfDirective(PartOfDirective node) {}
}

/// String literals that are not part of a bigger string literal.
class _TopStringVisitor extends RecursiveAstVisitor<void> {
  final void Function(StringLiteral lit) found;
  _TopStringVisitor(this.found);

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) => found(node);

  @override
  void visitStringInterpolation(StringInterpolation node) {
    found(node);
    super.visitStringInterpolation(node);
  }

  @override
  void visitAdjacentStrings(AdjacentStrings node) {
    found(node);
  }

  @override
  void visitImportDirective(ImportDirective node) {}
  @override
  void visitExportDirective(ExportDirective node) {}
  @override
  void visitPartDirective(PartDirective node) {}
  @override
  void visitPartOfDirective(PartOfDirective node) {}
}

/// The values a local of this name is given: its initializer and every
/// plain assignment to it.
class _LocalValues extends RecursiveAstVisitor<void> {
  _LocalValues(this.name, this.out);
  final String name;
  final List<Expression> out;

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    final init = node.initializer;
    if (node.name.lexeme == name && init != null) out.add(init);
    super.visitVariableDeclaration(node);
  }

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    final lhs = node.leftHandSide;
    if (lhs is SimpleIdentifier && lhs.name == name) out.add(node.rightHandSide);
    super.visitAssignmentExpression(node);
  }
}

/// Reads of a bare name (not a method name or a property after a dot).
class _NameUses extends RecursiveAstVisitor<void> {
  _NameUses(this.name, this.hit);
  final String name;
  final void Function(SimpleIdentifier) hit;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final p = node.parent;
    final dotted = (p is MethodInvocation && identical(p.methodName, node)) ||
        (p is PropertyAccess && identical(p.propertyName, node)) ||
        (p is PrefixedIdentifier && identical(p.identifier, node)) ||
        p is Label;
    if (node.name == name && !dotted && !node.inDeclarationContext()) hit(node);
    super.visitSimpleIdentifier(node);
  }
}

class _ConditionalFinder extends RecursiveAstVisitor<void> {
  _ConditionalFinder(this.found);
  final void Function(ConditionalExpression c) found;

  @override
  void visitConditionalExpression(ConditionalExpression node) {
    found(node);
    super.visitConditionalExpression(node);
  }
}

class _ArabicFinder extends RecursiveAstVisitor<void> {
  final void Function(AstNode node, String text) found;
  _ArabicFinder(this.found);

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    if (_arabicRe.hasMatch(node.value)) found(node, node.value);
  }

  @override
  void visitInterpolationString(InterpolationString node) {
    if (_arabicRe.hasMatch(node.value)) found(node, node.value);
  }
}

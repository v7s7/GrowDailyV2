// Resolved references for the usage map (map_usage.py), found by the Dart
// analyzer from every file under lib/:
//
//   refs         every reference to a member of class S
//                (lib/core/l10n/app_strings.dart) or to a top-level
//                declaration of lib/core/l10n/reminder_copy.dart and
//                lib/core/l10n/daily_quotes.dart. map_usage.py --verify
//                compares these with its own text-based answer.
//   member_refs  every reference to a getter, method, field, top-level
//                function or top-level variable declared anywhere under lib/
//                (enum constants, types, constructors, locals and parameters
//                are left out), with where the referenced VALUE goes next
//                (its flow, see below) and, when the receiver is an enum
//                constant (MilestoneType.levelUp.localizedName), that
//                constant's name; when a switch case has already narrowed
//                the receiver (`case MilestoneType.levelUp:` then
//                `e.type.localizedName(isAr)`), that case's constants,
//                joined with "||".
//   param_refs   for every parameter of a function, method or constructor
//                declared under lib/ that can carry text, each place its
//                value is read and where that value goes. A flow into a
//                parameter ("P") is followed through here. A record
//                parameter (or a list of records) has one more entry per
//                field, keyed ...|field, following only reads of that field.
//   ctor_args    every argument holding a string literal in a call to a
//                constructor declared under lib/, with where the argument
//                goes: the field a `this.name` parameter fills, or the
//                parameter. map_usage.py uses it to find the field that holds
//                a catalog entry's text (IslamicHabitTemplate.description)
//                instead of the list that holds the entry.
//   enums        every enum declared under lib/.
//   literals     every string literal under lib/ with a letter in it, and
//                where its value goes inside the member that holds it: R when
//                the member hands it back, XD when the member shows it
//                itself (a thrown exception, a notification), F or P when it
//                is stored in a field or passed on.
//   non_text_members  every method and function under lib/ whose result
//                cannot carry text (void, Future<void>, bool, a number).
//                Wording inside one is shown or sent by the member itself
//                (a notification, a thrown exception, a snack bar), so
//                map_usage.py maps it to the places that CALL the member.
//
// A flow says what happens to a value after it is read, following it through
// expressions that keep text (a conditional, ??, an interpolation, a list, a
// record, .trim(), .join(), a local variable, a closure passed to .map) until
// it lands somewhere:
//
//   R                the value becomes the result of the member that holds
//                    the use (a return, an expression body, a closure whose
//                    result is not traced, a field initializer)
//   F|file|Class|f   it is stored in a field: a `this.f` constructor
//                    parameter, `x.f = value`, a field initializer
//   P|file|C|m|p     it is passed to parameter p of a function, method or
//                    constructor m declared under lib/; P|file|C|m|p|f when
//                    it sits in field f of a record passed whole
//   XD|callee        it is handed to an API outside lib/ that shows it: a
//                    Flutter widget or service, a notification plugin, the
//                    home widget plugin, a thrown exception
//   XS|callee        it is handed to an API that stores or sends it: Firestore,
//                    shared preferences, Hive, Firebase Auth, HTTP
//   XU|callee        it is handed to another API outside lib/
//   D                it is used for something that is not text: a comparison,
//                    a condition, a length or other number, a log line, a key
//   U|NodeType       a place this analysis does not model (map_usage.py
//                    treats it like R)
//   Q<flow>          after a P flow: where the call's own result goes, used
//                    when the callee hands that parameter back
//
// member_refs is written compactly: "files" and "flows" are string tables
// and each reference is [target file, target container, target name, using
// file, line, using container, using member, flows, receiver constant],
// where a container is the enclosing class, enum, mixin or extension ("" at
// the top level), the file values index "files", flows indexes "flows" (a
// list of flow strings joined with a space) and the receiver constant is ""
// when there is none.
//
// Doc-comment references such as [S.tagline] resolve too. In refs they are
// written out with "in_comment": true so the comparison can leave them aside;
// member_refs leaves them out.
//
// Usage, from docs/wording/generator:
//   dart run bin/verify_usage.dart <repo root> <out.json>
//
// Reads only. Needs the app's .dart_tool/package_config.json (it resolves
// Flutter and every package the app imports) and never builds anything.

import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln('usage: dart run bin/verify_usage.dart <repo root> <out.json>');
    exitCode = 64;
    return;
  }
  final repo = Directory(args[0]).absolute.path;
  final out = args[1];
  final collection =
      AnalysisContextCollection(includedPaths: ['$repo/lib']);
  final refs = <Map<String, Object?>>[];
  final table = _StringTable();
  final flows = _StringTable();
  final memberRefs = <List<Object>>[];
  final paramRefs = <String, List<List<Object>>>{};
  final ctorArgs = <List<Object>>[];
  final enums = <List<Object>>[];
  final nonTextMembers = <String>[];
  final literals = <List<Object>>[];
  final unmodelled = <String, int>{};
  var files = 0;
  for (final ctx in collection.contexts) {
    for (final path in ctx.contextRoot.analyzedFiles()) {
      if (!path.endsWith('.dart')) continue;
      final result = await ctx.currentSession.getResolvedUnit(path);
      if (result is! ResolvedUnitResult) continue;
      files++;
      final rel = path.substring(repo.length + 1);
      final flow = _Flow(repo, result, unmodelled);
      result.unit.accept(_LocalIndexer(flow.localRefs));
      result.unit.accept(_Refs(rel, result, refs, table, flows, memberRefs,
          paramRefs, ctorArgs, enums, flow, nonTextMembers, literals));
    }
  }
  File(out).writeAsStringSync(const JsonEncoder.withIndent(' ').convert({
    'files': files,
    'refs': refs,
    'member_refs': {
      'columns': [
        'target_file',
        'target_container',
        'target_name',
        'use_file',
        'use_line',
        'use_container',
        'use_member',
        'flows',
        'receiver_constant',
      ],
      'files': table.names,
      'flows': flows.names,
      'rows': memberRefs,
    },
    'param_refs': {
      'columns': ['use_line', 'flows', 'use_container', 'use_member'],
      'rows': paramRefs,
    },
    'ctor_args': {
      'columns': ['file', 'start_line', 'end_line', 'parameter', 'flows'],
      'rows': ctorArgs,
    },
    'enums': enums,
    'non_text_members': nonTextMembers,
    'literals': {
      'columns': ['file', 'line', 'flows', 'use_container', 'use_member'],
      'rows': literals,
    },
    'unmodelled_contexts': unmodelled,
  }));
  stdout.writeln('resolved $files files, ${refs.length} references, '
      '${memberRefs.length} member references, ${paramRefs.length} '
      'parameters, ${ctorArgs.length} constructor arguments');
}

class _StringTable {
  final names = <String>[];
  final _index = <String, int>{};

  int indexOf(String s) => _index.putIfAbsent(s, () {
        names.add(s);
        return names.length - 1;
      });
}

String? _owner(Element base) {
  final uri = base.library?.uri.toString() ?? '';
  final enc = base.enclosingElement;
  if (uri.endsWith('core/l10n/app_strings.dart') &&
      enc is ClassElement &&
      enc.name == 'S') {
    return 'S';
  }
  final copy = uri.endsWith('core/l10n/reminder_copy.dart')
      ? 'reminder_copy'
      : uri.endsWith('core/l10n/daily_quotes.dart')
          ? 'daily_quotes'
          : null;
  if (copy == null) return null;
  if (enc is LibraryElement) return copy;
  // A constructor call such as DailyQuote(...) names the class.
  if (base is ConstructorElement) return copy;
  return null;
}

/// The enclosing class-like and member names of a use site.
(String, String) _useSite(AstNode node) {
  var container = '';
  var member = '';
  for (AstNode? x = node; x != null; x = x.parent) {
    if (member.isEmpty) {
      if (x is MethodDeclaration) member = x.name.lexeme;
      if (x is FunctionDeclaration && x.parent is CompilationUnit) {
        member = x.name.lexeme;
      }
      if (x is ConstructorDeclaration) {
        member = x.name?.lexeme ?? 'new';
      }
      if (x is VariableDeclaration &&
          (x.parent?.parent is FieldDeclaration ||
              x.parent?.parent is TopLevelVariableDeclaration)) {
        member = x.name.lexeme;
      }
      if (x is EnumConstantDeclaration) member = x.name.lexeme;
    }
    if (x is ClassDeclaration) {
      container = x.namePart.typeName.lexeme;
      break;
    }
    if (x is EnumDeclaration) {
      container = x.namePart.typeName.lexeme;
      break;
    }
    if (x is MixinDeclaration) {
      container = x.name.lexeme;
      break;
    }
    if (x is ExtensionDeclaration) {
      container = x.name?.lexeme ?? 'extension';
      break;
    }
    if (x is ExtensionTypeDeclaration) {
      container = x.primaryConstructor.typeName.lexeme;
      break;
    }
  }
  return (container, member);
}

/// Every read of a local variable or parameter, per element, for one unit.
class _LocalIndexer extends RecursiveAstVisitor<void> {
  _LocalIndexer(this.index);
  final Map<Element, List<SimpleIdentifier>> index;

  @override
  void visitComment(Comment node) {} // [param] in a doc comment is no read

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final el = node.element?.baseElement;
    if (el != null &&
        !node.inDeclarationContext() &&
        node.parent is! Label && // the `name:` of a named argument
        (el is LocalVariableElement || el is FormalParameterElement)) {
      index.putIfAbsent(el, () => []).add(node);
    }
    super.visitSimpleIdentifier(node);
  }
}

/// Where a value goes after it is read (see the flow list at the top).
class _Flow {
  _Flow(this.repo, this.result, this.unmodelled);
  final String repo;
  final ResolvedUnitResult result;
  final Map<String, int> unmodelled;
  final localRefs = <Element, List<SimpleIdentifier>>{};

  static const _plainTypes = {
    'DateTime', 'Duration', 'Color', 'IconData', 'TimeOfDay', 'Offset',
    'Size', 'EdgeInsets', 'EdgeInsetsGeometry', 'BorderRadius', 'Alignment',
    'Rect', 'Radius', 'Curve', 'Matrix4', 'Key', 'ValueKey', 'Timestamp',
  };

  static const _loggers = {'debugPrint', 'print', 'log', 'debugPrintStack'};
  static const _keys = {
    'Key', 'ValueKey', 'ObjectKey', 'PageStorageKey', 'GlobalObjectKey',
    'RegExp', 'Symbol',
  };
  static const _mutators = {
    'add', 'addAll', 'insert', 'insertAll', 'write', 'writeln', 'writeAll',
    'putIfAbsent', 'addEntries', 'update', 'setAll', 'fillRange',
  };
  static const _storeLibs = [
    'package:cloud_firestore/', 'package:firebase_database/',
    'package:shared_preferences/', 'package:hive/', 'package:hive_flutter/',
    'package:firebase_storage/', 'package:cloud_functions/',
    'package:firebase_auth/', 'package:http/', 'package:firebase_messaging/',
  ];
  static const _silentLibs = [
    'package:firebase_analytics/', 'package:firebase_crashlytics/',
    'dart:developer',
  ];
  static const _displayLibs = [
    'package:flutter/', 'package:flutter_local_notifications/',
    'package:home_widget/', 'package:share_plus/', 'package:url_launcher/',
    'package:live_activities/',
  ];

  bool inLib(Element e) {
    final path = e.firstFragment.libraryFragment?.source.fullName;
    return path != null && path.startsWith('$repo/lib/');
  }

  String libPath(Element e) =>
      e.firstFragment.libraryFragment!.source.fullName.substring(repo.length + 1);

  static String containerOf(Element e) {
    final enc = e.enclosingElement;
    if (enc is LibraryElement || enc == null) return '';
    return enc.name ?? '';
  }

  static String memberName(ExecutableElement e) {
    if (e is ConstructorElement) {
      final n = e.name;
      return (n == null || n.isEmpty || n == 'new') ? 'new' : n;
    }
    return e.name ?? '';
  }

  /// A value of this type can carry wording.
  static bool textCapable(DartType? t) {
    if (t == null) return true;
    if (t is VoidType || t is NeverType) return false;
    if (t.isDartCoreBool ||
        t.isDartCoreInt ||
        t.isDartCoreDouble ||
        t.isDartCoreNum ||
        t.isDartCoreNull) {
      return false;
    }
    if (t is InterfaceType) {
      if ((t.isDartAsyncFuture || t.isDartAsyncFutureOr) &&
          t.typeArguments.isNotEmpty) {
        return textCapable(t.typeArguments.first);
      }
      final el = t.element;
      if (el is EnumElement) return false;
      if (_plainTypes.contains(el.name)) return false;
    }
    return true;
  }

  List<String> _unmodelled(AstNode n) {
    final k = n.runtimeType.toString().replaceAll('Impl', '');
    unmodelled.update(k, (v) => v + 1, ifAbsent: () => 1);
    return ['U|$k'];
  }

  /// The expression a reference to a member stands for: `a.b`, `a.b()`.
  static Expression startOf(SimpleIdentifier node) {
    final p = node.parent;
    if (p is PrefixedIdentifier && identical(p.identifier, node)) return p;
    if (p is PropertyAccess && identical(p.propertyName, node)) return p;
    if (p is MethodInvocation && identical(p.methodName, node)) return p;
    return node;
  }

  /// The enum constant a member is read on, `MilestoneType.levelUp.x`.
  static String receiverConstant(SimpleIdentifier node) {
    final p = node.parent;
    Expression? target;
    if (p is PrefixedIdentifier && identical(p.identifier, node)) {
      target = p.prefix;
    } else if (p is PropertyAccess && identical(p.propertyName, node)) {
      target = p.realTarget;
    } else if (p is MethodInvocation && identical(p.methodName, node)) {
      target = p.realTarget;
    }
    Element? el;
    if (target is PrefixedIdentifier) el = target.identifier.element;
    if (target is PropertyAccess) el = target.propertyName.element;
    if (target is SimpleIdentifier) el = target.element;
    el = el?.baseElement;
    if (el is GetterElement) {
      final v = el.variable;
      if (v is FieldElement && v.isEnumConstant) return v.name ?? '';
    }
    if (el is FieldElement && el.isEnumConstant) return el.name ?? '';
    if (target != null) return _narrowedBySwitch(node, target);
    return '';
  }

  /// A receiver that a switch has already narrowed to some enum constants:
  /// `e.type.localizedName(isAr)` inside `case MilestoneType.levelUp:` of
  /// `switch (e.type)` is read on levelUp only. Returns the constant names
  /// joined with "||" (a case that falls through from the ones above it
  /// covers theirs too), or "" when no enclosing case narrows the receiver.
  static String _narrowedBySwitch(AstNode node, Expression target) {
    final receiver = target.toSource();
    String? names(GuardedPattern gp) {
      if (gp.whenClause != null) return null;
      final out = <String>[];
      bool walk(DartPattern p) {
        if (p is ParenthesizedPattern) return walk(p.pattern);
        if (p is LogicalOrPattern) return walk(p.leftOperand) && walk(p.rightOperand);
        if (p is ConstantPattern) {
          final e = p.expression;
          Element? el;
          if (e is PrefixedIdentifier) el = e.identifier.element;
          if (e is PropertyAccess) el = e.propertyName.element;
          if (e is SimpleIdentifier) el = e.element;
          el = el?.baseElement;
          if (el is GetterElement) el = el.variable;
          if (el is FieldElement && el.isEnumConstant && el.name != null) {
            out.add(el.name!);
            return true;
          }
        }
        return false;
      }

      return walk(gp.pattern) ? out.join('||') : null;
    }

    for (AstNode? x = node.parent; x != null; x = x.parent) {
      if (x is FunctionBody || x is ClassMember || x is CompilationUnitMember) {
        break;
      }
      if (x is SwitchExpressionCase) {
        final sw = x.parent;
        if (sw is SwitchExpression &&
            sw.expression.toSource() == receiver &&
            node.offset >= x.expression.offset) {
          return names(x.guardedPattern) ?? '';
        }
      }
      if (x is SwitchPatternCase) {
        final sw = x.parent;
        if (sw is SwitchStatement && sw.expression.toSource() == receiver) {
          final members = sw.members;
          final all = <String>[];
          for (var i = members.indexOf(x); i >= 0; i--) {
            final m = members[i];
            if (!identical(m, x) && m.statements.isNotEmpty) break;
            if (m is! SwitchPatternCase) return '';
            final n = names(m.guardedPattern);
            if (n == null) return '';
            all.insert(0, n);
          }
          return all.join('||');
        }
      }
    }
    return '';
  }

  List<String> ofReference(SimpleIdentifier node) =>
      _dedupe(flows(startOf(node), <Object>{}, 0, const []));

  List<String> ofLocalUse(SimpleIdentifier u, [List<String> fs = const []]) =>
      _dedupe(flows(u, <Object>{}, 0, fs));

  List<String> ofLiteral(StringLiteral lit) =>
      _dedupe(flows(lit, <Object>{}, 0, const []));

  List<String> ofArgument(ArgumentList list, Expression arg) =>
      _dedupe(_argument(list, arg, <Object>{}, 0, const []));

  static List<String> _dedupe(List<String> xs) {
    final out = <String>[];
    for (final x in xs) {
      if (!out.contains(x)) out.add(x);
    }
    out.sort();
    return out;
  }

  List<String> _local(Element el, Set<Object> seen, int depth, List<String> fs) {
    if (!seen.add((el, fs.join('.')))) return [];
    final uses = localRefs[el] ?? const [];
    final out = <String>[];
    for (final u in uses) {
      if (u.inSetterContext() && !u.inGetterContext()) continue;
      out.addAll(flows(u, seen, depth + 1, fs));
    }
    return out.isEmpty ? ['D'] : out;
  }

  /// Flows of the value held by [target] (a list a text was added to).
  List<String> _container(
      Expression target, Set<Object> seen, int depth, List<String> fs) {
    final t = target.unParenthesized;
    Element? el;
    if (t is SimpleIdentifier) el = t.element?.baseElement;
    if (t is PrefixedIdentifier) el = t.identifier.element?.baseElement;
    if (t is PropertyAccess) el = t.propertyName.element?.baseElement;
    if (el is LocalVariableElement || el is FormalParameterElement) {
      return _local(el!, seen, depth + 1, fs);
    }
    if (el is GetterElement) el = el.variable;
    if (el is FieldElement && inLib(el)) {
      return ['F|${libPath(el)}|${containerOf(el)}|${el.name}'];
    }
    if (el is TopLevelVariableElement && inLib(el)) {
      return ['F|${libPath(el)}||${el.name}'];
    }
    return _unmodelled(t);
  }

  /// [fs]: the record fields the value sits in, innermost last, so a read of
  /// another field of the same record (h.id beside h.anchorLabel) is not
  /// taken for the text.
  List<String> flows(
      Expression start, Set<Object> seen, int depth, List<String> fs) {
    if (depth > 24) return ['U|depth'];
    AstNode node = start;
    for (var steps = 0; steps < 80; steps++) {
      final parent = node.parent;
      if (parent == null) return _unmodelled(node);

      bool keep(Expression e) => textCapable(e.staticType);

      if (parent is ParenthesizedExpression ||
          parent is AwaitExpression ||
          parent is AsExpression ||
          parent is AdjacentStrings ||
          parent is CascadeExpression ||
          (parent is PostfixExpression &&
              parent.operator.type == TokenType.BANG)) {
        if (parent is CascadeExpression && !identical(parent.target, node)) {
          return ['D'];
        }
        node = parent;
        continue;
      }
      if (parent is PostfixExpression || parent is PrefixExpression) {
        return ['D'];
      }
      if (parent is IsExpression) return ['D'];
      if (parent is ConditionalExpression) {
        if (identical(parent.condition, node)) return ['D'];
        node = parent;
        continue;
      }
      if (parent is BinaryExpression) {
        final op = parent.operator.type;
        if (op == TokenType.QUESTION_QUESTION ||
            (op == TokenType.PLUS && keep(parent))) {
          node = parent;
          continue;
        }
        return ['D'];
      }
      if (parent is InterpolationExpression) {
        node = parent.parent!; // the StringInterpolation
        continue;
      }
      if (parent is RecordLiteral) {
        // A positional field: $1, $2, ...
        final positional =
            parent.fields.where((f) => f is! NamedExpression).toList();
        fs = [...fs, '\$${positional.indexOf(node as Expression) + 1}'];
        node = parent;
        continue;
      }
      if (parent is ListLiteral ||
          parent is SetOrMapLiteral ||
          parent is SpreadElement ||
          parent is NullAwareElement) {
        node = parent;
        continue;
      }
      if (parent is MapLiteralEntry) {
        if (identical(parent.key, node)) return ['D'];
        node = parent;
        continue;
      }
      if (parent is ForElement) {
        if (identical(parent.body, node)) {
          node = parent;
          continue;
        }
        return ['D'];
      }
      if (parent is IfElement) {
        if (identical(parent.expression, node)) return ['D'];
        node = parent;
        continue;
      }
      if (parent is SwitchExpressionCase) {
        if (!identical(parent.expression, node)) return ['D'];
        node = parent.parent!; // the SwitchExpression
        continue;
      }
      if (parent is SwitchExpression) return ['D']; // the scrutinee
      if (parent is IndexExpression) {
        if (identical(parent.index, node)) return ['D'];
        if (!keep(parent)) return ['D'];
        node = parent;
        continue;
      }
      if (parent is PropertyAccess || parent is PrefixedIdentifier) {
        final targetType = (node as Expression).staticType;
        final prop = parent is PropertyAccess
            ? parent.propertyName.name
            : (parent as PrefixedIdentifier).identifier.name;
        if (targetType is RecordType && fs.isNotEmpty) {
          if (prop != fs.last) return ['D']; // another field of the record
          fs = fs.sublist(0, fs.length - 1);
        }
        final e = parent as Expression;
        if (!keep(e)) return ['D'];
        node = e;
        continue;
      }
      if (parent is FunctionExpressionInvocation) {
        if (!keep(parent)) return ['D'];
        node = parent;
        continue;
      }
      if (parent is MethodInvocation) {
        if (identical(parent.target, node)) {
          if (!keep(parent)) return ['D'];
          node = parent;
          continue;
        }
        return _unmodelled(parent);
      }
      if (parent is NamedExpression) {
        final gp = parent.parent;
        if (gp is RecordLiteral) {
          fs = [...fs, parent.name.label.name];
          node = gp;
          continue;
        }
        if (gp is ArgumentList) return _argument(gp, parent, seen, depth, fs);
        return _unmodelled(parent);
      }
      if (parent is ArgumentList) {
        return _argument(parent, node as Expression, seen, depth, fs);
      }
      if (parent is ThrowExpression) return ['XD|throw'];
      if (parent is ReturnStatement ||
          parent is ExpressionFunctionBody ||
          parent is YieldStatement) {
        return _returned(parent, seen, depth, fs);
      }
      if (parent is VariableDeclaration) {
        if (!identical(parent.initializer, node)) return ['D'];
        final el = parent.declaredFragment?.element;
        if (el is LocalVariableElement) return _local(el, seen, depth + 1, fs);
        return ['R']; // a field or top-level variable: the member itself
      }
      if (parent is AssignmentExpression) {
        if (!identical(parent.rightHandSide, node)) return ['D'];
        final lhs = parent.leftHandSide;
        final w = parent.writeElement?.baseElement;
        if (w is LocalVariableElement || w is FormalParameterElement) {
          return _local(w!, seen, depth + 1, fs);
        }
        if (lhs is IndexExpression && lhs.target != null) {
          return _container(lhs.target!, seen, depth, fs);
        }
        var v = w;
        if (v is SetterElement) v = v.variable;
        if (v is FieldElement && inLib(v)) {
          return ['F|${libPath(v)}|${containerOf(v)}|${v.name}'];
        }
        if (v is TopLevelVariableElement && inLib(v)) {
          return ['F|${libPath(v)}||${v.name}'];
        }
        if (v != null && !inLib(v)) {
          // A setter outside lib/, such as a Riverpod notifier's state.
          return ['XU|=${v.name}'];
        }
        return _unmodelled(parent);
      }
      if (parent is ForEachPartsWithDeclaration) {
        if (!identical(parent.iterable, node)) return ['D'];
        final el = parent.loopVariable.declaredFragment?.element;
        return el == null ? ['D'] : _local(el, seen, depth + 1, fs);
      }
      if (parent is ForEachPartsWithIdentifier) {
        if (!identical(parent.iterable, node)) return ['D'];
        final el = parent.identifier.element?.baseElement;
        return el == null ? ['D'] : _local(el, seen, depth + 1, fs);
      }
      if (parent is DefaultFormalParameter) {
        // A default value: the text is what the parameter holds.
        if (!identical(parent.defaultValue, node)) return ['D'];
        final el = parent.declaredFragment?.element.baseElement;
        return el == null ? ['D'] : _local(el, seen, depth + 1, fs);
      }
      if (parent is ForEachPartsWithPattern) {
        if (!identical(parent.iterable, node)) return ['D'];
        final vars = <Element>[];
        parent.pattern.accept(_PatternVariables(vars));
        final out = <String>[];
        for (final v in vars) {
          out.addAll(_local(v, seen, depth + 1, fs));
        }
        return out.isEmpty ? ['D'] : out;
      }
      if (parent is ConstructorFieldInitializer) {
        final f = parent.fieldName.element?.baseElement;
        if (f is FieldElement && inLib(f)) {
          return ['F|${libPath(f)}|${containerOf(f)}|${f.name}'];
        }
        return _unmodelled(parent);
      }
      if (parent is ExpressionStatement ||
          parent is IfStatement ||
          parent is WhileStatement ||
          parent is DoStatement ||
          parent is SwitchStatement ||
          parent is Assertion ||
          parent is ForPartsWithDeclarations ||
          parent is ForPartsWithExpression ||
          parent is ForParts ||
          parent is SwitchCase ||
          parent is ConstantPattern ||
          parent is WhenClause ||
          parent is Annotation ||
          parent is VariableDeclarationList) {
        return ['D'];
      }
      if (parent is PatternVariableDeclaration ||
          parent is PatternAssignment) {
        return ['R'];
      }
      return _unmodelled(parent);
    }
    return ['U|steps'];
  }

  /// A value that ends a function body: the member's result, or, for a
  /// closure handed to .map / .expand / .then on a collection or future, the
  /// result of that call.
  List<String> _returned(
      AstNode at, Set<Object> seen, int depth, List<String> fs) {
    final body = at is FunctionBody ? at : at.thisOrAncestorOfType<FunctionBody>();
    final fe = body?.parent;
    if (fe is FunctionExpression && fe.parent is! FunctionDeclaration) {
      var holder = fe.parent;
      if (holder is NamedExpression) holder = holder.parent;
      final inv = holder?.parent;
      if (holder is ArgumentList && inv is MethodInvocation) {
        final recv = inv.realTarget?.staticType;
        final isCollection = recv is InterfaceType &&
            (recv.element.library.isDartCore || recv.element.library.isDartAsync);
        const transforms = {
          'map', 'expand', 'then', 'fold', 'reduce', 'firstWhere',
          'lastWhere', 'singleWhere', 'putIfAbsent', 'update', 'generate',
          'orElse', 'asyncMap', 'whenComplete',
        };
        if (isCollection && transforms.contains(inv.methodName.name)) {
          if (!textCapable(inv.staticType)) return ['D'];
          return flows(inv, seen, depth + 1, fs);
        }
        if (inv.realTarget == null && inv.methodName.name == 'generate') {
          return flows(inv, seen, depth + 1, fs);
        }
      }
      if (holder is ArgumentList &&
          inv is InstanceCreationExpression &&
          inv.constructorName.type.name.lexeme == 'List') {
        return flows(inv, seen, depth + 1, fs);
      }
    }
    return ['R'];
  }

  /// A value passed as an argument.
  List<String> _argument(ArgumentList list, Expression arg, Set<Object> seen,
      int depth, List<String> fs) {
    final inv = list.parent;
    if (inv is MethodInvocation && inv.realTarget != null) {
      final recv = inv.realTarget!.staticType;
      if (recv is InterfaceType &&
          (recv.element.library.isDartCore) &&
          _mutators.contains(inv.methodName.name)) {
        // The text now lives in the list, map or buffer.
        return _container(inv.realTarget!, seen, depth, fs);
      }
    }
    if (inv is Annotation) return ['D'];
    FormalParameterElement? param =
        arg is NamedExpression ? arg.element : arg.correspondingParameter;
    param = param?.baseElement;
    final callee = _calleeElement(inv);
    final calleeName = callee == null
        ? (inv is MethodInvocation ? inv.methodName.name : inv.runtimeType.toString())
        : (callee is ConstructorElement
            ? (callee.enclosingElement.name ?? '')
            : (callee.name ?? ''));
    if (_loggers.contains(calleeName) || _keys.contains(calleeName)) {
      return ['D'];
    }
    while (param is SuperFormalParameterElement) {
      final next = param.superConstructorParameter?.baseElement;
      if (next == null) break;
      param = next;
    }
    if (param is FieldFormalParameterElement) {
      final f = param.field?.baseElement;
      if (f != null && inLib(f)) {
        return ['F|${libPath(f)}|${containerOf(f)}|${f.name}'];
      }
    }
    final exec = param?.enclosingElement;
    if (param != null && exec is ExecutableElement && inLib(exec)) {
      if (exec is LocalFunctionElement) return ['R'];
      final container = exec is ConstructorElement
          ? (exec.enclosingElement.name ?? '')
          : containerOf(exec);
      // A record passed whole names the field the text sits in, so the
      // parameter's reads of THAT field are followed (see param_refs).
      final field = fs.length == 1 ? '|${fs.single}' : '';
      final sinks = [
        'P|${libPath(exec)}|$container|${memberName(exec)}|${param.name}$field'
      ];
      // Where the call's own result goes, for a callee that hands the
      // parameter back (toWesternDigits(text), _pick(ar, en)): Q + a flow.
      if (inv is Expression && textCapable(inv.staticType)) {
        for (final q in flows(inv, seen, depth + 1, fs)) {
          if (!q.startsWith('Q')) sinks.add('Q$q');
        }
      }
      return sinks;
    }
    if (callee != null && inLib(callee)) {
      // A parameter that cannot be resolved (a function-typed parameter or
      // a field holding a callback): the text reaches code that is not a
      // declared member.
      return ['XU|$calleeName'];
    }
    final uri = callee?.library?.uri.toString() ?? '';
    if (callee is ConstructorElement &&
        RegExp(r'(Exception|Error)$').hasMatch(calleeName)) {
      return ['XD|$calleeName']; // an exception message may reach the user
    }
    if (_silentLibs.any(uri.startsWith)) return ['D'];
    if (_storeLibs.any(uri.startsWith)) return ['XS|$calleeName'];
    if (_displayLibs.any(uri.startsWith)) return ['XD|$calleeName'];
    if (callee == null || inv is FunctionExpressionInvocation) {
      // A callback held in a variable or field: where it goes is not known.
      return ['XU|$calleeName'];
    }
    if (inv is Expression && textCapable(inv.staticType)) {
      // A transform outside lib/ that hands text back: Uri.encodeFull,
      // jsonEncode, String.replaceAll(pattern, text), ref.watch(provider).
      return flows(inv, seen, depth + 1, fs);
    }
    // A call outside lib/ that returns a number, a flag or nothing:
    // contains, compareTo, int.tryParse, ref.invalidate.
    return ['D'];
  }

  static Element? _calleeElement(AstNode? inv) {
    Element? e;
    if (inv is MethodInvocation) e = inv.methodName.element;
    if (inv is InstanceCreationExpression) e = inv.constructorName.element;
    if (inv is FunctionExpressionInvocation) e = inv.element;
    if (inv is SuperConstructorInvocation) e = inv.element;
    if (inv is RedirectingConstructorInvocation) e = inv.element;
    return e?.baseElement;
  }
}

class _Refs extends RecursiveAstVisitor<void> {
  _Refs(this.rel, this.result, this.refs, this.table, this.flowTable,
      this.memberRefs, this.paramRefs, this.ctorArgs, this.enums, this.flow,
      this.nonTextMembers, this.literals);

  final String rel;
  final ResolvedUnitResult result;
  final List<Map<String, Object?>> refs;
  final _StringTable table;
  final _StringTable flowTable;
  final List<List<Object>> memberRefs;
  final Map<String, List<List<Object>>> paramRefs;
  final List<List<Object>> ctorArgs;
  final List<List<Object>> enums;
  final _Flow flow;
  final List<String> nonTextMembers;
  final List<List<Object>> literals;
  int _commentDepth = 0;

  int _line(int offset) => result.lineInfo.getLocation(offset).lineNumber;

  void _add(String owner, String name, int offset) {
    refs.add({
      'owner': owner,
      'name': name,
      'file': rel,
      'line': _line(offset),
      'in_comment': _commentDepth > 0,
    });
  }

  @override
  void visitComment(Comment node) {
    _commentDepth++;
    super.visitComment(node);
    _commentDepth--;
  }

  @override
  void visitEnumDeclaration(EnumDeclaration node) {
    enums.add([rel, node.namePart.typeName.lexeme]);
    super.visitEnumDeclaration(node);
  }

  void _addMember(SimpleIdentifier node, Element base) {
    if (_commentDepth > 0) return;
    // `import ... show habitListProvider` names a member but uses nothing.
    if (node.thisOrAncestorOfType<Directive>() != null) return;
    Element target = base;
    if (base is PropertyAccessorElement) {
      if (base is SetterElement) return;
      // A field's implicit getter stands for the field; an explicit getter
      // for itself. Both carry the same name and container.
      target = base;
    } else if (base is FieldElement) {
      if (base.isEnumConstant) return;
    } else if (base is! MethodElement &&
        base is! TopLevelFunctionElement &&
        base is! TopLevelVariableElement) {
      return;
    }
    final name = target.name;
    if (name == null || name.isEmpty) return;
    final path = target.firstFragment.libraryFragment?.source.fullName;
    if (path == null || !path.startsWith('${flow.repo}/lib/')) return;
    final enc = target.enclosingElement;
    final container = (enc is LibraryElement || enc == null) ? '' : (enc.name ?? '');
    if (enc is FieldElement && enc.isEnumConstant) return;
    final (useContainer, useMember) = _useSite(node);
    memberRefs.add([
      table.indexOf(path.substring(flow.repo.length + 1)),
      container,
      name,
      table.indexOf(rel),
      _line(node.offset),
      useContainer,
      useMember,
      flowTable.indexOf(flow.ofReference(node).join(' ')),
      _Flow.receiverConstant(node),
    ]);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final el = node.element;
    if (el != null && !node.inDeclarationContext()) {
      final base = el.baseElement;
      final owner = _owner(base);
      if (owner != null) {
        final name = base is ConstructorElement
            ? (base.enclosingElement.name ?? '')
            : (base.name ?? '');
        _add(owner, name, node.offset);
      }
      _addMember(node, base);
    }
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitNamedType(NamedType node) {
    final el = node.element;
    if (el != null) {
      final uri = el.library?.uri.toString() ?? '';
      if (uri.endsWith('core/l10n/reminder_copy.dart')) {
        _add('reminder_copy', el.name ?? '', node.offset);
      } else if (uri.endsWith('core/l10n/daily_quotes.dart')) {
        _add('daily_quotes', el.name ?? '', node.offset);
      }
    }
    super.visitNamedType(node);
  }

  // ── Parameters ──────────────────────────────────────────────────────────

  void _params(FormalParameterList? list, ExecutableElement? exec) {
    if (list == null || exec == null) return;
    if (exec is LocalFunctionElement) return;
    final container = exec is ConstructorElement
        ? (exec.enclosingElement.name ?? '')
        : _Flow.containerOf(exec);
    final member = _Flow.memberName(exec);
    for (final p in list.parameters) {
      final el = p.declaredFragment?.element.baseElement;
      if (el == null) continue;
      if (el is FieldFormalParameterElement || el is SuperFormalParameterElement) {
        continue;
      }
      if (!_Flow.textCapable(el.type)) continue;
      final uses = flow.localRefs[el] ?? const [];
      // A record parameter (or a list of records) also gets one summary per
      // field, for text that arrives inside that field.
      final record = _recordIn(el.type);
      final variants = <String>[
        '',
        if (record != null) ...[
          for (var i = 0; i < record.positionalFields.length; i++) '\$${i + 1}',
          for (final f in record.namedFields) f.name,
        ],
      ];
      for (final field in variants) {
        final rows = <List<Object>>[];
        for (final u in uses) {
          if (u.inSetterContext() && !u.inGetterContext()) continue;
          final (uc, um) = _useSite(u);
          rows.add([
            _line(u.offset),
            flowTable.indexOf(
                flow.ofLocalUse(u, field.isEmpty ? const [] : [field]).join(' ')),
            uc,
            um,
          ]);
        }
        paramRefs['$rel|$container|$member|${el.name}${field.isEmpty ? '' : '|$field'}'] =
            rows;
      }
    }
  }

  /// A member whose value cannot carry text (void, Future<void>, bool): any
  /// wording in it is shown or sent by the member itself, so it shows where
  /// the member is called.
  void _noText(ExecutableElement? exec) {
    if (exec == null || _Flow.textCapable(exec.returnType)) return;
    nonTextMembers.add('$rel|${_Flow.containerOf(exec)}|${exec.name}');
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    _params(node.parameters, node.declaredFragment?.element);
    _noText(node.declaredFragment?.element);
    super.visitMethodDeclaration(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    if (node.parent is CompilationUnit) {
      _params(node.functionExpression.parameters, node.declaredFragment?.element);
      _noText(node.declaredFragment?.element);
    }
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    _params(node.parameters, node.declaredFragment?.element);
    super.visitConstructorDeclaration(node);
  }

  // ── String literals ─────────────────────────────────────────────────────

  static final _letter = RegExp(r'[A-Za-z\u0600-\u06FF]');

  void _literal(StringLiteral node, String text) {
    if (_commentDepth > 0 || !_letter.hasMatch(text)) return;
    if (node.thisOrAncestorOfType<Directive>() != null ||
        node.thisOrAncestorOfType<Annotation>() != null) {
      return;
    }
    final (uc, um) = _useSite(node);
    literals.add([
      table.indexOf(rel),
      _line(node.offset),
      flowTable.indexOf(flow.ofLiteral(node).join(' ')),
      uc,
      um,
    ]);
  }

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    _literal(node, node.value);
    super.visitSimpleStringLiteral(node);
  }

  @override
  void visitStringInterpolation(StringInterpolation node) {
    _literal(node,
        node.elements.whereType<InterpolationString>().map((e) => e.value).join());
    super.visitStringInterpolation(node);
  }

  // ── Constructor arguments holding a literal ─────────────────────────────

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final ctor = node.constructorName.element?.baseElement;
    if (ctor != null && flow.inLib(ctor)) {
      for (final a in node.argumentList.arguments) {
        final value = a is NamedExpression ? a.expression : a;
        if (!_holdsLiteral(value)) continue;
        FormalParameterElement? param =
            a is NamedExpression ? a.element : a.correspondingParameter;
        param = param?.baseElement;
        if (param == null) continue;
        ctorArgs.add([
          table.indexOf(rel),
          _line(a.offset),
          _line(a.end),
          param.name ?? '',
          flowTable.indexOf(flow.ofArgument(node.argumentList, a).join(' ')),
        ]);
      }
    }
    super.visitInstanceCreationExpression(node);
  }

  static bool _holdsLiteral(Expression e) {
    var found = false;
    e.accept(_LiteralFinder(() => found = true));
    return found;
  }
}

RecordType? _recordIn(DartType? t) {
  if (t is RecordType) return t;
  if (t is InterfaceType) {
    for (final a in t.typeArguments) {
      final r = _recordIn(a);
      if (r != null) return r;
    }
  }
  return null;
}

class _PatternVariables extends RecursiveAstVisitor<void> {
  _PatternVariables(this.out);
  final List<Element> out;

  @override
  void visitDeclaredVariablePattern(DeclaredVariablePattern node) {
    final el = node.declaredFragment?.element;
    if (el != null) out.add(el.baseElement);
    super.visitDeclaredVariablePattern(node);
  }
}

class _LiteralFinder extends RecursiveAstVisitor<void> {
  _LiteralFinder(this.hit);
  final void Function() hit;

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) => hit();

  @override
  void visitStringInterpolation(StringInterpolation node) {
    hit();
    super.visitStringInterpolation(node);
  }
}


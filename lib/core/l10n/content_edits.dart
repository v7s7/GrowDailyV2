/// The FAQ and the Premium page's benefit list, edited from the admin tool.
///
/// ── Why this exists ─────────────────────────────────────────────────────
/// Aziz, 2026-09-26: "make the faq, and the premium details all in the admin
/// change firebase, online change not hard code". The wording layer
/// (wording_edits.dart) already reached every S string, including every
/// sentence on the paywall, but not the two LISTS: the FAQ's questions
/// (kFaqEntries in help_support_screen.dart) and the paywall's benefit rows
/// (kBuiltInPremiumBenefits in premium_benefits.dart). A list needs more
/// than new words: questions added, taken off, moved between groups; a
/// benefit added with its own icon, or put first.
///
/// ── Where the edits live ────────────────────────────────────────────────
/// In the same document as the string edits, wording/live, as two more
/// optional maps. Same rule (anyone may read it, no client may write it),
/// same listener, same copy on the device, so nothing new to deploy:
///
///   faq       order?   [{group, items: [id]}]   every group and its questions
///             hidden?  [id]                     built-in questions taken off
///             text?    {id: {qAr?, qEn?, aAr?, aEn?}}
///                      only the edited fields of a built-in question, all
///                      four of one added on the admin tool
///             groups?  {id: {ar?, en?}}         group headings, same idea
///   benefits  order?   [id]
///             hidden?  [id]                     built-in benefits taken off
///             icons?   {id: name}               a built-in benefit's new icon
///             added?   {id: {icon, titleAr, titleEn, descAr, descEn}}
///
/// A built-in benefit's words are S strings (premiumBenefit*Title/Desc), so
/// they are edited as strings, in `strings` beside every other one. This
/// file never holds them, which is what keeps the admin tool's App text tab
/// and its Premium page from ever disagreeing about one.
///
/// ── The rule that keeps a saved list honest ─────────────────────────────
/// Edits are per item, never a frozen copy of the whole list. A built-in
/// question or benefit that was not edited keeps following the code, so a
/// fix to its wording in a later build still reaches phones. One added to
/// the code AFTER the admin saved still shows too: right after the built-in
/// item it follows in the code, or first when none of those is shown. Only
/// `hidden` takes a built-in item off, and only the one it names.
///
/// scripts/admin_lookup/wording/content_rules.js resolves the same way for
/// the admin tool's preview and its saves. Both are held to one set of cases
/// (scripts/admin_lookup/test/fixtures/content_cases.json), so what the
/// admin sees before pressing Save is what phones show after it.
///
/// ── What a malformed document costs ─────────────────────────────────────
/// The entry that is malformed, and nothing else: the same rule as the
/// account loader and the string edits. A question added on the admin tool
/// with a language missing, a group with no heading, an id nobody knows:
/// each is left out, and the built-in list is always the floor.
library;

import 'package:flutter/foundation.dart';

/// Longest id accepted from the document. The admin tool writes ids of a
/// dozen characters; this only stops something absurd from being carried
/// around in memory and in the device's copy.
const int _maxIdLength = 64;

String? _text(Object? raw) {
  if (raw is! String) return null;
  final trimmed = raw.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String? _id(Object? raw) {
  final id = _text(raw);
  return id == null || id.length > _maxIdLength ? null : id;
}

List<String> _ids(Object? raw) {
  if (raw is! List) return const [];
  final out = <String>[];
  for (final entry in raw) {
    final id = _id(entry);
    if (id != null && !out.contains(id)) out.add(id);
  }
  return out;
}

// ─── Two languages ──────────────────────────────────────────────────────────

/// One text in Arabic and English, either of which may be missing.
@immutable
class WordingPair {
  const WordingPair({this.ar, this.en});

  final String? ar;
  final String? en;

  bool get isEmpty => ar == null && en == null;

  static WordingPair? fromData(Object? raw) {
    if (raw is! Map) return null;
    final pair = WordingPair(ar: _text(raw['ar']), en: _text(raw['en']));
    return pair.isEmpty ? null : pair;
  }

  Map<String, Object?> toJson() => {
        if (ar != null) 'ar': ar,
        if (en != null) 'en': en,
      };
}

// ─── The FAQ ────────────────────────────────────────────────────────────────

/// One group in the order the admin saved, with its questions by id.
@immutable
class FaqOrderGroup {
  const FaqOrderGroup(this.group, this.items);

  final String group;
  final List<String> items;
}

/// The words of one question as the admin wrote them: only the edited
/// fields of a built-in question, all four of an added one.
@immutable
class FaqTextEdit {
  const FaqTextEdit({
    this.questionAr,
    this.questionEn,
    this.answerAr,
    this.answerEn,
  });

  final String? questionAr;
  final String? questionEn;
  final String? answerAr;
  final String? answerEn;

  bool get isEmpty =>
      questionAr == null &&
      questionEn == null &&
      answerAr == null &&
      answerEn == null;

  /// Every field present: what an added question needs to be shown at all.
  bool get isComplete =>
      questionAr != null &&
      questionEn != null &&
      answerAr != null &&
      answerEn != null;

  static FaqTextEdit? fromData(Object? raw) {
    if (raw is! Map) return null;
    final edit = FaqTextEdit(
      questionAr: _text(raw['qAr']),
      questionEn: _text(raw['qEn']),
      answerAr: _text(raw['aAr']),
      answerEn: _text(raw['aEn']),
    );
    return edit.isEmpty ? null : edit;
  }

  Map<String, Object?> toJson() => {
        if (questionAr != null) 'qAr': questionAr,
        if (questionEn != null) 'qEn': questionEn,
        if (answerAr != null) 'aAr': answerAr,
        if (answerEn != null) 'aEn': answerEn,
      };
}

/// The admin's edits to the FAQ. See this file's own doc comment for the
/// shape and for what each part may and may not change.
@immutable
class FaqEdits {
  const FaqEdits({
    this.order,
    this.hidden = const {},
    this.text = const {},
    this.groups = const {},
  });

  /// Every group in the order the admin saved it, each with its questions.
  /// Null for the app's own order, which is also what the admin tool saves
  /// when nothing was moved, so a later build's new order still arrives.
  final List<FaqOrderGroup>? order;

  /// Built-in questions the admin took off the FAQ.
  final Set<String> hidden;

  /// Words by question id.
  final Map<String, FaqTextEdit> text;

  /// Headings by group id.
  final Map<String, WordingPair> groups;

  bool get isEmpty =>
      order == null && hidden.isEmpty && text.isEmpty && groups.isEmpty;

  /// The `faq` map of the document, or null when there is nothing usable in
  /// it, which is the built-in FAQ.
  static FaqEdits? fromData(Object? raw) {
    if (raw is! Map) return null;
    final order = <FaqOrderGroup>[];
    final rawOrder = raw['order'];
    if (rawOrder is List) {
      for (final entry in rawOrder) {
        if (entry is! Map) continue;
        final group = _id(entry['group']);
        if (group == null || order.any((g) => g.group == group)) continue;
        order.add(FaqOrderGroup(group, List.unmodifiable(_ids(entry['items']))));
      }
    }
    final text = <String, FaqTextEdit>{};
    final rawText = raw['text'];
    if (rawText is Map) {
      rawText.forEach((key, value) {
        final id = _id(key);
        final edit = FaqTextEdit.fromData(value);
        if (id != null && edit != null) text[id] = edit;
      });
    }
    final groups = <String, WordingPair>{};
    final rawGroups = raw['groups'];
    if (rawGroups is Map) {
      rawGroups.forEach((key, value) {
        final id = _id(key);
        final pair = WordingPair.fromData(value);
        if (id != null && pair != null) groups[id] = pair;
      });
    }
    final edits = FaqEdits(
      order: order.isEmpty ? null : List.unmodifiable(order),
      hidden: Set.unmodifiable(_ids(raw['hidden'])),
      text: Map.unmodifiable(text),
      groups: Map.unmodifiable(groups),
    );
    return edits.isEmpty ? null : edits;
  }

  /// The shape [fromData] reads back, for this device's copy.
  Map<String, Object?> toJson() => {
        if (order != null)
          'order': [
            for (final g in order!) {'group': g.group, 'items': g.items},
          ],
        if (hidden.isNotEmpty) 'hidden': hidden.toList(),
        if (text.isNotEmpty)
          'text': {for (final e in text.entries) e.key: e.value.toJson()},
        if (groups.isNotEmpty)
          'groups': {for (final e in groups.entries) e.key: e.value.toJson()},
      };
}

/// One question as the app shows it, in both languages.
@immutable
class FaqItem {
  const FaqItem({
    required this.id,
    required this.questionAr,
    required this.questionEn,
    required this.answerAr,
    required this.answerEn,
  });

  /// Stable across releases: the admin's edits are keyed by it.
  final String id;
  final String questionAr;
  final String questionEn;
  final String answerAr;
  final String answerEn;

  String question(bool isAr) => isAr ? questionAr : questionEn;
  String answer(bool isAr) => isAr ? answerAr : answerEn;
}

/// A built-in question: its words and the group the code puts it in.
@immutable
class FaqBuiltInItem {
  const FaqBuiltInItem({required this.group, required this.item});

  final String group;
  final FaqItem item;
}

/// A built-in group and its heading.
@immutable
class FaqBuiltInGroup {
  const FaqBuiltInGroup({required this.id, required this.ar, required this.en});

  final String id;
  final String ar;
  final String en;
}

/// One group as the app shows it: its heading and its questions, never
/// empty (a group with nothing to show is left out).
@immutable
class FaqSection {
  const FaqSection({
    required this.id,
    required this.titleAr,
    required this.titleEn,
    required this.items,
  });

  final String id;
  final String titleAr;
  final String titleEn;
  final List<FaqItem> items;

  String title(bool isAr) => isAr ? titleAr : titleEn;
}

class _Placing {
  _Placing(this.id);

  final String id;
  final List<String> ids = [];
}

/// The FAQ as phones show it: the built-in [groups] and [items] (both in
/// the code's order), with [edits] laid over them.
///
/// Step by step, the same as resolveFaq in content_rules.js:
///  1. The saved order, when there is one: each group the app knows (a
///     built-in one, or one added with a heading), with each question the
///     app knows (a built-in one not hidden, or an added one with all four
///     fields). The first mention of a group or question wins.
///  2. Every built-in question not placed by step 1 and not hidden, in the
///     code's order: into its own built-in group (added after the last shown
///     group that comes before it in the code, or first), right after the
///     nearest question before it in the code that is in that group, or
///     first. With no saved order this alone rebuilds the code's own layout.
///  3. The words: a built-in question's own, with any edited field laid
///     over it; an added question's four fields. A built-in group's heading
///     with an edited language laid over it; an added group's heading in
///     either language for both when one is missing.
///  4. Groups with no questions are left out.
List<FaqSection> resolveFaq({
  required List<FaqBuiltInGroup> groups,
  required List<FaqBuiltInItem> items,
  FaqEdits? edits,
}) {
  final groupById = {for (final g in groups) g.id: g};
  final groupRank = {for (var i = 0; i < groups.length; i++) groups[i].id: i};
  final itemById = {for (final e in items) e.item.id: e};
  final hidden = edits?.hidden ?? const <String>{};
  final text = edits?.text ?? const <String, FaqTextEdit>{};
  final headings = edits?.groups ?? const <String, WordingPair>{};

  final sections = <_Placing>[];
  final placed = <String>{};

  for (final saved in edits?.order ?? const <FaqOrderGroup>[]) {
    if (sections.any((s) => s.id == saved.group)) continue;
    if (!groupById.containsKey(saved.group) &&
        (headings[saved.group]?.isEmpty ?? true)) {
      continue;
    }
    final section = _Placing(saved.group);
    for (final id in saved.items) {
      if (placed.contains(id)) continue;
      if (itemById.containsKey(id)) {
        if (hidden.contains(id)) continue;
      } else if (!(text[id]?.isComplete ?? false)) {
        continue;
      }
      section.ids.add(id);
      placed.add(id);
    }
    sections.add(section);
  }

  for (var i = 0; i < items.length; i++) {
    final entry = items[i];
    final id = entry.item.id;
    if (placed.contains(id) || hidden.contains(id)) continue;
    var section = sections.where((s) => s.id == entry.group).firstOrNull;
    if (section == null) {
      final rank = groupRank[entry.group] ?? groups.length;
      var at = 0;
      for (var k = sections.length - 1; k >= 0; k--) {
        final r = groupRank[sections[k].id];
        if (r != null && r < rank) {
          at = k + 1;
          break;
        }
      }
      section = _Placing(entry.group);
      sections.insert(at, section);
    }
    var pos = 0;
    for (var j = i - 1; j >= 0; j--) {
      if (items[j].group != entry.group) continue;
      final at = section.ids.indexOf(items[j].item.id);
      if (at >= 0) {
        pos = at + 1;
        break;
      }
    }
    section.ids.insert(pos, id);
    placed.add(id);
  }

  FaqItem itemFor(String id) {
    final edit = text[id];
    final builtIn = itemById[id]?.item;
    if (builtIn == null) {
      return FaqItem(
        id: id,
        questionAr: edit!.questionAr!,
        questionEn: edit.questionEn!,
        answerAr: edit.answerAr!,
        answerEn: edit.answerEn!,
      );
    }
    return FaqItem(
      id: id,
      questionAr: edit?.questionAr ?? builtIn.questionAr,
      questionEn: edit?.questionEn ?? builtIn.questionEn,
      answerAr: edit?.answerAr ?? builtIn.answerAr,
      answerEn: edit?.answerEn ?? builtIn.answerEn,
    );
  }

  return [
    for (final s in sections)
      if (s.ids.isNotEmpty)
        FaqSection(
          id: s.id,
          titleAr: groupById[s.id] != null
              ? headings[s.id]?.ar ?? groupById[s.id]!.ar
              : headings[s.id]!.ar ?? headings[s.id]!.en!,
          titleEn: groupById[s.id] != null
              ? headings[s.id]?.en ?? groupById[s.id]!.en
              : headings[s.id]!.en ?? headings[s.id]!.ar!,
          items: [for (final id in s.ids) itemFor(id)],
        ),
  ];
}

// ─── The Premium page's benefits ────────────────────────────────────────────

/// A benefit added on the admin tool: its icon and its words, all required.
@immutable
class AddedBenefit {
  const AddedBenefit({
    required this.icon,
    required this.titleAr,
    required this.titleEn,
    required this.descAr,
    required this.descEn,
  });

  final String icon;
  final String titleAr;
  final String titleEn;
  final String descAr;
  final String descEn;

  String title(bool isAr) => isAr ? titleAr : titleEn;
  String desc(bool isAr) => isAr ? descAr : descEn;

  /// Null unless every field is there: a benefit with a language missing
  /// would show a blank row to half the people reading the paywall.
  static AddedBenefit? fromData(Object? raw) {
    if (raw is! Map) return null;
    final icon = _text(raw['icon']);
    final titleAr = _text(raw['titleAr']);
    final titleEn = _text(raw['titleEn']);
    final descAr = _text(raw['descAr']);
    final descEn = _text(raw['descEn']);
    if (icon == null ||
        titleAr == null ||
        titleEn == null ||
        descAr == null ||
        descEn == null) {
      return null;
    }
    return AddedBenefit(
      icon: icon,
      titleAr: titleAr,
      titleEn: titleEn,
      descAr: descAr,
      descEn: descEn,
    );
  }

  Map<String, Object?> toJson() => {
        'icon': icon,
        'titleAr': titleAr,
        'titleEn': titleEn,
        'descAr': descAr,
        'descEn': descEn,
      };
}

/// The admin's edits to the paywall's benefit list. The words of a built-in
/// benefit are S strings and are not here (see this file's doc comment).
@immutable
class BenefitEdits {
  const BenefitEdits({
    this.order,
    this.hidden = const {},
    this.icons = const {},
    this.added = const {},
  });

  /// The benefits by id in the order the admin saved. Null for the code's
  /// own order.
  final List<String>? order;

  /// Built-in benefits the admin took off the paywall.
  final Set<String> hidden;

  /// A built-in benefit's icon, by benefit id, when the admin changed it.
  final Map<String, String> icons;

  /// Benefits added on the admin tool, by id.
  final Map<String, AddedBenefit> added;

  bool get isEmpty =>
      order == null && hidden.isEmpty && icons.isEmpty && added.isEmpty;

  static BenefitEdits? fromData(Object? raw) {
    if (raw is! Map) return null;
    final order = _ids(raw['order']);
    final icons = <String, String>{};
    final rawIcons = raw['icons'];
    if (rawIcons is Map) {
      rawIcons.forEach((key, value) {
        final id = _id(key);
        final icon = _text(value);
        if (id != null && icon != null) icons[id] = icon;
      });
    }
    final added = <String, AddedBenefit>{};
    final rawAdded = raw['added'];
    if (rawAdded is Map) {
      rawAdded.forEach((key, value) {
        final id = _id(key);
        final benefit = AddedBenefit.fromData(value);
        if (id != null && benefit != null) added[id] = benefit;
      });
    }
    final edits = BenefitEdits(
      order: order.isEmpty ? null : List.unmodifiable(order),
      hidden: Set.unmodifiable(_ids(raw['hidden'])),
      icons: Map.unmodifiable(icons),
      added: Map.unmodifiable(added),
    );
    return edits.isEmpty ? null : edits;
  }

  Map<String, Object?> toJson() => {
        if (order != null) 'order': order,
        if (hidden.isNotEmpty) 'hidden': hidden.toList(),
        if (icons.isNotEmpty) 'icons': icons,
        if (added.isNotEmpty)
          'added': {for (final e in added.entries) e.key: e.value.toJson()},
      };
}

/// A built-in benefit as the resolver needs it: its id and its icon.
@immutable
class BenefitBuiltIn {
  const BenefitBuiltIn({required this.id, required this.icon});

  final String id;
  final String icon;
}

/// One row of the paywall's benefit list: which benefit, with which icon.
/// [added] is set for a benefit added on the admin tool, and carries its
/// words; a built-in one takes its words from S.
@immutable
class BenefitSlot {
  const BenefitSlot({required this.id, required this.icon, this.added});

  final String id;
  final String icon;
  final AddedBenefit? added;
}

/// The benefit list as phones show it: [builtIn] (in the code's order) with
/// [edits] laid over it. Same steps as [resolveFaq], in one list: the saved
/// order of the benefits the app knows, then every built-in one it did not
/// place and that is not hidden, right after the nearest one before it in
/// the code that is shown, or first.
///
/// An icon this build does not have ([knownIcons]) is never drawn as a
/// blank: a built-in benefit keeps its own icon, an added one takes
/// [fallbackIcon]. The admin tool only offers icons the app has, so this
/// only matters when a newer admin list meets an older build.
List<BenefitSlot> resolveBenefits({
  required List<BenefitBuiltIn> builtIn,
  required Set<String> knownIcons,
  required String fallbackIcon,
  BenefitEdits? edits,
}) {
  final byId = {for (final b in builtIn) b.id: b};
  final hidden = edits?.hidden ?? const <String>{};
  final added = edits?.added ?? const <String, AddedBenefit>{};
  final icons = edits?.icons ?? const <String, String>{};

  final ids = <String>[];
  for (final id in edits?.order ?? const <String>[]) {
    if (ids.contains(id)) continue;
    if (byId.containsKey(id)) {
      if (hidden.contains(id)) continue;
    } else if (!added.containsKey(id)) {
      continue;
    }
    ids.add(id);
  }
  for (var i = 0; i < builtIn.length; i++) {
    final id = builtIn[i].id;
    if (ids.contains(id) || hidden.contains(id)) continue;
    var pos = 0;
    for (var j = i - 1; j >= 0; j--) {
      final at = ids.indexOf(builtIn[j].id);
      if (at >= 0) {
        pos = at + 1;
        break;
      }
    }
    ids.insert(pos, id);
  }

  return [
    for (final id in ids)
      if (byId[id] case final b?)
        BenefitSlot(
          id: id,
          icon: knownIcons.contains(icons[id]) ? icons[id]! : b.icon,
        )
      else
        BenefitSlot(
          id: id,
          icon: knownIcons.contains(added[id]!.icon)
              ? added[id]!.icon
              : fallbackIcon,
          added: added[id],
        ),
  ];
}

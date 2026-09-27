/**
 * The FAQ and the Premium page's benefit list: how the admin's edits are
 * read, laid over the app's built-in lists, checked and turned back into
 * edits. Shared by the browser (the FAQ and Premium pages, and History on
 * the Wording page) and the server (lib/wording.js), for the same reason
 * as rules.js: the checks run as you type and again on every save, from one
 * copy.
 *
 * The app does the same in lib/core/l10n/content_edits.dart. Both are held
 * to one set of cases (test/fixtures/content_cases.json, run by
 * test/content.test.js here and test/core/content_edits_test.dart in the
 * app), so what these pages show before Save is what phones show after it.
 *
 * The shape in wording/live, and why edits are per item rather than a copy
 * of the whole list, is written up at the top of content_edits.dart.
 *
 * Needs rules.js (window.WordingRules) loaded first in the browser.
 *
 * No em dash anywhere in this file, including comments (see rules.js).
 */
(function (root, factory) {
  if (typeof module === 'object' && module.exports) {
    module.exports = factory(require('./rules'));
  } else {
    root.ContentRules = factory(root.WordingRules);
  }
})(typeof self !== 'undefined' ? self : this, function (R) {
  'use strict';

  const ch = (code) => String.fromCharCode(code);
  const EM_DASH = ch(0x2014);

  /** Longest id the app reads. The ids made here are a dozen characters. */
  const MAX_ID_LENGTH = 64;
  const MAX_QUESTION_LENGTH = 200;
  const MAX_ANSWER_LENGTH = 1000;
  const MAX_HEADING_LENGTH = 60;
  const MAX_BENEFIT_TITLE_LENGTH = 70;
  const MAX_BENEFIT_DESC_LENGTH = 240;
  const MAX_QUESTIONS = 150;
  const MAX_GROUPS = 20;
  const MAX_BENEFITS = 24;

  /** How the ids of what this tool adds begin. A built-in id never does. */
  const ADDED = { question: 'q-', group: 'g-', benefit: 'b-' };
  const ID_SHAPE = /^[a-z0-9]+(-[a-z0-9]+)*$/;

  /**
   * Words a benefit row must not sell: things every free user already has,
   * or asks that read as charity. The same list premium_benefit_copy_test
   * holds the built-in rows to (guidelines 2.3.1(a) and 3.1.2).
   */
  const NOT_A_BENEFIT = ['ads', 'donat', 'tip', 'coffee', 'إعلان', 'تبرع', 'تبر' + ch(0x0651) + 'ع', 'قهوة', 'ادعم'];

  // ---- Reading the document, the same way the app does -------------------

  // Dart's trim also drops U+0085 (next line) at either end; JavaScript's
  // does not. Stripped here too, so both sides agree on what is empty.
  const NEL_ENDS = new RegExp('^' + ch(0x85) + '+|' + ch(0x85) + '+$', 'g');

  function text(raw) {
    if (typeof raw !== 'string') return null;
    let t = raw.trim();
    for (;;) {
      const next = t.replace(NEL_ENDS, '').trim();
      if (next === t) break;
      t = next;
    }
    return t ? t : null;
  }

  /**
   * [map]'s own value under [key], or undefined. Every lookup by an id goes
   * through this: an id is text from the document, and a plain object
   * would answer "toString" or "constructor" from its prototype.
   */
  function own(map, key) {
    return map && Object.prototype.hasOwnProperty.call(map, key) ? map[key] : undefined;
  }

  function id(raw) {
    const t = text(raw);
    return t !== null && t.length <= MAX_ID_LENGTH ? t : null;
  }

  function ids(raw) {
    if (!Array.isArray(raw)) return [];
    const out = [];
    for (const entry of raw) {
      const i = id(entry);
      if (i !== null && !out.includes(i)) out.push(i);
    }
    return out;
  }

  function isMap(raw) {
    return !!raw && typeof raw === 'object' && !Array.isArray(raw);
  }

  function pair(raw) {
    if (!isMap(raw)) return null;
    const out = {};
    const ar = text(raw.ar);
    const en = text(raw.en);
    if (ar !== null) out.ar = ar;
    if (en !== null) out.en = en;
    return Object.keys(out).length ? out : null;
  }

  function faqTextEdit(raw) {
    if (!isMap(raw)) return null;
    const out = {};
    for (const field of ['qAr', 'qEn', 'aAr', 'aEn']) {
      const t = text(raw[field]);
      if (t !== null) out[field] = t;
    }
    return Object.keys(out).length ? out : null;
  }

  function complete(edit) {
    return !!edit && !!edit.qAr && !!edit.qEn && !!edit.aAr && !!edit.aEn;
  }

  /**
   * wording/live's `faq` as the app reads it (FaqEdits.fromData): every
   * malformed entry left out, and null when nothing usable is left.
   */
  function parseFaqEdits(raw) {
    if (!isMap(raw)) return null;
    const order = [];
    if (Array.isArray(raw.order)) {
      for (const entry of raw.order) {
        if (!isMap(entry)) continue;
        const group = id(entry.group);
        if (group === null || order.some((g) => g.group === group)) continue;
        order.push({ group, items: ids(entry.items) });
      }
    }
    const textEdits = {};
    if (isMap(raw.text)) {
      for (const [key, value] of Object.entries(raw.text)) {
        const k = id(key);
        const edit = faqTextEdit(value);
        if (k !== null && edit) textEdits[k] = edit;
      }
    }
    const groups = {};
    if (isMap(raw.groups)) {
      for (const [key, value] of Object.entries(raw.groups)) {
        const k = id(key);
        const p = pair(value);
        if (k !== null && p) groups[k] = p;
      }
    }
    const edits = {
      order: order.length ? order : null,
      hidden: ids(raw.hidden),
      text: textEdits,
      groups,
    };
    return faqEditsEmpty(edits) ? null : edits;
  }

  function faqEditsEmpty(edits) {
    return !edits || (edits.order === null && !edits.hidden.length &&
      !Object.keys(edits.text).length && !Object.keys(edits.groups).length);
  }

  function addedBenefit(raw) {
    if (!isMap(raw)) return null;
    const out = {};
    for (const field of ['icon', 'titleAr', 'titleEn', 'descAr', 'descEn']) {
      const t = text(raw[field]);
      if (t === null) return null;
      out[field] = t;
    }
    return out;
  }

  /** wording/live's `benefits` as the app reads it (BenefitEdits.fromData). */
  function parseBenefitEdits(raw) {
    if (!isMap(raw)) return null;
    const order = ids(raw.order);
    const icons = {};
    if (isMap(raw.icons)) {
      for (const [key, value] of Object.entries(raw.icons)) {
        const k = id(key);
        const icon = text(value);
        if (k !== null && icon !== null) icons[k] = icon;
      }
    }
    const added = {};
    if (isMap(raw.added)) {
      for (const [key, value] of Object.entries(raw.added)) {
        const k = id(key);
        const benefit = addedBenefit(value);
        if (k !== null && benefit) added[k] = benefit;
      }
    }
    const edits = { order: order.length ? order : null, hidden: ids(raw.hidden), icons, added };
    return benefitEditsEmpty(edits) ? null : edits;
  }

  function benefitEditsEmpty(edits) {
    return !edits || (edits.order === null && !edits.hidden.length &&
      !Object.keys(edits.icons).length && !Object.keys(edits.added).length);
  }

  /**
   * The edits as the document stores them: only what is there, nothing
   * empty. What a save writes and what History keeps.
   */
  function faqDocument(edits) {
    if (faqEditsEmpty(edits)) return null;
    const out = {};
    if (edits.order) out.order = edits.order.map((g) => ({ group: g.group, items: g.items.slice() }));
    if (edits.hidden.length) out.hidden = edits.hidden.slice();
    if (Object.keys(edits.text).length) out.text = clone(edits.text);
    if (Object.keys(edits.groups).length) out.groups = clone(edits.groups);
    return out;
  }

  function benefitsDocument(edits) {
    if (benefitEditsEmpty(edits)) return null;
    const out = {};
    if (edits.order) out.order = edits.order.slice();
    if (edits.hidden.length) out.hidden = edits.hidden.slice();
    if (Object.keys(edits.icons).length) out.icons = Object.assign({}, edits.icons);
    if (Object.keys(edits.added).length) out.added = clone(edits.added);
    return out;
  }

  function clone(value) {
    return JSON.parse(JSON.stringify(value));
  }

  /**
   * [value] as JSON with every map's keys sorted, so two readings of the
   * same document compare equal however Firestore ordered the keys.
   */
  function canonical(value) {
    if (Array.isArray(value)) return '[' + value.map(canonical).join(',') + ']';
    if (isMap(value)) {
      return '{' + Object.keys(value).sort().map((k) => JSON.stringify(k) + ':' + canonical(value[k])).join(',') + '}';
    }
    return JSON.stringify(value === undefined ? null : value);
  }

  function same(a, b) {
    return canonical(a === undefined ? null : a) === canonical(b === undefined ? null : b);
  }

  // ---- Laying the edits over the built-in lists ---------------------------

  /**
   * The FAQ as phones show it. [builtIn] is the catalog's `faq`:
   * { groups: [{id, ar, en}], items: [{id, group, qAr, qEn, aAr, aEn}] },
   * both in the code's order. [edits] is parseFaqEdits' result, or null.
   * The steps are resolveFaq's in content_edits.dart, one for one.
   *
   * Returns [{ id, title: {ar, en}, items: [{ id, q: {ar, en}, a: {ar, en} }] }].
   */
  function resolveFaq(builtIn, edits) {
    const layout = faqLayout(builtIn, edits);
    const groupById = new Map(builtIn.groups.map((g) => [g.id, g]));
    const itemById = new Map(builtIn.items.map((i) => [i.id, i]));
    const textEdits = (edits && edits.text) || {};
    const headings = (edits && edits.groups) || {};
    return layout.filter((s) => s.items.length).map((s) => {
      const g = groupById.get(s.id);
      const h = own(headings, s.id) || {};
      return {
        id: s.id,
        title: g
          ? { ar: h.ar || g.ar, en: h.en || g.en }
          : { ar: h.ar || h.en, en: h.en || h.ar },
        items: s.items.map((itemId) => {
          const b = itemById.get(itemId);
          const t = own(textEdits, itemId) || {};
          return b
            ? { id: itemId, q: { ar: t.qAr || b.qAr, en: t.qEn || b.qEn }, a: { ar: t.aAr || b.aAr, en: t.aEn || b.aEn } }
            : { id: itemId, q: { ar: t.qAr, en: t.qEn }, a: { ar: t.aAr, en: t.aEn } };
        }),
      };
    });
  }

  /**
   * Steps 1 and 2 of resolveFaq: which groups, in what order, with which
   * questions by id. Groups may come out empty here; resolveFaq drops them.
   */
  function faqLayout(builtIn, edits) {
    const groupRank = new Map(builtIn.groups.map((g, i) => [g.id, i]));
    const itemById = new Map(builtIn.items.map((i) => [i.id, i]));
    const hidden = new Set((edits && edits.hidden) || []);
    const textEdits = (edits && edits.text) || {};
    const headings = (edits && edits.groups) || {};
    const sections = [];
    const placed = new Set();

    for (const saved of (edits && edits.order) || []) {
      if (sections.some((s) => s.id === saved.group)) continue;
      if (!groupRank.has(saved.group) && !own(headings, saved.group)) continue;
      const section = { id: saved.group, items: [] };
      for (const itemId of saved.items) {
        if (placed.has(itemId)) continue;
        if (itemById.has(itemId)) {
          if (hidden.has(itemId)) continue;
        } else if (!complete(own(textEdits, itemId))) {
          continue;
        }
        section.items.push(itemId);
        placed.add(itemId);
      }
      sections.push(section);
    }

    builtIn.items.forEach((item, i) => {
      if (placed.has(item.id) || hidden.has(item.id)) return;
      let section = sections.find((s) => s.id === item.group);
      if (!section) {
        const rank = groupRank.has(item.group) ? groupRank.get(item.group) : builtIn.groups.length;
        let at = 0;
        for (let k = sections.length - 1; k >= 0; k--) {
          const r = groupRank.get(sections[k].id);
          if (r !== undefined && r < rank) {
            at = k + 1;
            break;
          }
        }
        section = { id: item.group, items: [] };
        sections.splice(at, 0, section);
      }
      let pos = 0;
      for (let j = i - 1; j >= 0; j--) {
        if (builtIn.items[j].group !== item.group) continue;
        const at = section.items.indexOf(builtIn.items[j].id);
        if (at >= 0) {
          pos = at + 1;
          break;
        }
      }
      section.items.splice(pos, 0, item.id);
      placed.add(item.id);
    });
    return sections;
  }

  /**
   * The benefit list as phones show it: [{ id, icon, added? }]. [builtIn]
   * is the catalog's `benefits`: { items: [{id, icon, titleKey, descKey}],
   * icons: [name], fallbackIcon }. The steps are resolveBenefits' in
   * content_edits.dart, one for one. A built-in row's words are its S
   * strings and are not looked up here.
   */
  function resolveBenefits(builtIn, edits) {
    const byId = new Map(builtIn.items.map((b) => [b.id, b]));
    const known = new Set(builtIn.icons);
    const hidden = new Set((edits && edits.hidden) || []);
    const added = (edits && edits.added) || {};
    const icons = (edits && edits.icons) || {};
    const list = [];
    for (const benefitId of (edits && edits.order) || []) {
      if (list.includes(benefitId)) continue;
      if (byId.has(benefitId)) {
        if (hidden.has(benefitId)) continue;
      } else if (!own(added, benefitId)) {
        continue;
      }
      list.push(benefitId);
    }
    builtIn.items.forEach((b, i) => {
      if (list.includes(b.id) || hidden.has(b.id)) return;
      let pos = 0;
      for (let j = i - 1; j >= 0; j--) {
        const at = list.indexOf(builtIn.items[j].id);
        if (at >= 0) {
          pos = at + 1;
          break;
        }
      }
      list.splice(pos, 0, b.id);
    });
    return list.map((benefitId) => {
      const b = byId.get(benefitId);
      if (b) {
        const icon = own(icons, benefitId);
        return { id: benefitId, icon: known.has(icon) ? icon : b.icon };
      }
      const a = own(added, benefitId);
      return { id: benefitId, icon: known.has(a.icon) ? a.icon : builtIn.fallbackIcon, added: a };
    });
  }

  // ---- Checking what is typed ---------------------------------------------

  /**
   * One field's text, checked: errors block a save, warnings are shown.
   * [label] names the field in a message ("Question, Arabic").
   */
  function checkField(label, lang, raw, max) {
    const errors = [];
    const warnings = [];
    const t = R.normalizeText(raw);
    if (!t) errors.push(label + ' is empty.');
    if (t.length > max) errors.push(label + ' is too long: ' + t.length + ' characters, the limit is ' + max + '.');
    if (t.includes(EM_DASH)) errors.push(label + ' has an em dash. Use a comma, a colon or a full stop.');
    if (lang === 'ar') {
      for (const rule of R.ARABIC_STYLE) {
        if (rule.test.test(t)) warnings.push(label + ': ' + rule.say);
      }
    }
    return { text: t, errors, warnings };
  }

  /** A benefit's words sell something free users already have. */
  function notABenefit(label, t) {
    const lower = t.toLowerCase();
    const hit = NOT_A_BENEFIT.find((w) => lower.includes(w));
    return hit
      ? [label + ' mentions "' + hit + '". Premium must not be sold on what free users already have, or as a donation.']
      : [];
  }

  function isAddedId(value, prefix) {
    return typeof value === 'string' && value.startsWith(prefix) &&
      value.length <= MAX_ID_LENGTH && ID_SHAPE.test(value);
  }

  /** A new id for something added on these pages: [prefix] and 8 letters or digits. */
  function newId(prefix, taken) {
    const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
    for (;;) {
      let out = prefix;
      for (let i = 0; i < 8; i++) out += alphabet[Math.floor(Math.random() * alphabet.length)];
      if (!taken || !taken.has(out)) return out;
    }
  }

  // ---- The FAQ page's draft, turned into edits ------------------------------

  const LANG_WORD = { ar: 'Arabic', en: 'English' };

  /**
   * The FAQ page's draft, turned into the edits a save writes.
   *
   * [draft] is the whole FAQ as the page shows it: { groups: [{ id, title:
   * {ar, en}, items: [{ id, q: {ar, en}, a: {ar, en} }] }] }. Everything is
   * checked; nothing is stored that the built-in text already says:
   *   - a built-in question keeps only the fields that differ from the
   *     code, so the rest keep following it;
   *   - a built-in question left out of the draft is `hidden`;
   *   - the order is stored only when it differs from the order phones
   *     would show with no order at all, so a later build's new order still
   *     arrives when nothing was moved here.
   *
   * Returns { ok, edits (the document's `faq`, or null for the built-in
   * FAQ), bases, errors, warnings }. [bases] is the built-in text each
   * stored field replaced, for the page's "changed in code" flag.
   */
  function faqEditsFromDraft(builtIn, draft) {
    const errors = [];
    const warnings = [];
    const groupById = new Map(builtIn.groups.map((g) => [g.id, g]));
    const itemById = new Map(builtIn.items.map((i) => [i.id, i]));
    const fail = (message) => ({ ok: false, edits: null, bases: null, errors: [message], warnings });
    if (!draft || !Array.isArray(draft.groups)) return fail('Nothing to save.');
    if (draft.groups.length > MAX_GROUPS) errors.push('Too many groups: ' + draft.groups.length + ', the limit is ' + MAX_GROUPS + '.');

    const seenGroups = new Set();
    const seenItems = new Set();
    const order = [];
    const textEdits = {};
    const headings = {};
    const bases = { items: {}, groups: {} };
    let questions = 0;
    let addedAny = false;

    draft.groups.forEach((g, gi) => {
      const gid = g && typeof g.id === 'string' ? g.id : '';
      const builtInGroup = groupById.get(gid);
      const where = 'Group ' + (gi + 1);
      if (seenGroups.has(gid)) {
        errors.push(where + ' is in the list twice.');
        return;
      }
      seenGroups.add(gid);
      if (!builtInGroup && !isAddedId(gid, ADDED.group)) {
        errors.push(where + ' has an id the app does not know.');
        return;
      }
      const itemIds = [];
      const items = Array.isArray(g && g.items) ? g.items : [];
      items.forEach((item, ii) => {
        const iid = item && typeof item.id === 'string' ? item.id : '';
        const b = itemById.get(iid);
        const at = where + ', question ' + (ii + 1);
        if (seenItems.has(iid)) {
          errors.push(at + ' is in the FAQ twice.');
          return;
        }
        seenItems.add(iid);
        if (!b && !isAddedId(iid, ADDED.question)) {
          errors.push(at + ' has an id the app does not know.');
          return;
        }
        questions++;
        const fields = {
          qAr: checkField(at + ', question in Arabic', 'ar', item.q && item.q.ar, MAX_QUESTION_LENGTH),
          qEn: checkField(at + ', question in English', 'en', item.q && item.q.en, MAX_QUESTION_LENGTH),
          aAr: checkField(at + ', answer in Arabic', 'ar', item.a && item.a.ar, MAX_ANSWER_LENGTH),
          aEn: checkField(at + ', answer in English', 'en', item.a && item.a.en, MAX_ANSWER_LENGTH),
        };
        const edit = {};
        for (const [field, check] of Object.entries(fields)) {
          // A built-in field left as the app wrote it is the app's own
          // text: nothing is stored for it and nothing about it can block
          // a save, even if a later build writes one that breaks a rule here.
          if (b && check.text === R.normalizeText(b[field])) continue;
          errors.push(...check.errors);
          warnings.push(...check.warnings);
          if (check.errors.length) continue;
          edit[field] = check.text;
          if (b) bases.items[iid] = Object.assign(bases.items[iid] || {}, { [field]: b[field] });
        }
        if (Object.keys(edit).length) textEdits[iid] = edit;
        if (!b) addedAny = true;
        itemIds.push(iid);
      });
      // A group with nothing in it shows nothing on phones, so neither it
      // nor its heading is kept, and a heading left blank there blocks
      // nothing.
      if (!itemIds.length) {
        if (!builtInGroup) warnings.push(where + ' has no questions, so phones do not show it and it is not kept.');
        return;
      }
      if (!builtInGroup) addedAny = true;

      const title = (g && g.title) || {};
      const heading = {};
      ['ar', 'en'].forEach((lang) => {
        const check = checkField(where + ' heading, ' + LANG_WORD[lang], lang, title[lang], MAX_HEADING_LENGTH);
        const base = builtInGroup ? builtInGroup[lang] : null;
        if (builtInGroup && check.text === R.normalizeText(base)) return;
        errors.push(...check.errors);
        warnings.push(...check.warnings);
        if (check.errors.length) return;
        heading[lang] = check.text;
        if (builtInGroup) bases.groups[gid] = Object.assign(bases.groups[gid] || {}, { [lang]: base });
      });
      if (Object.keys(heading).length) headings[gid] = heading;
      order.push({ group: gid, items: itemIds });
    });
    if (questions > MAX_QUESTIONS) errors.push('Too many questions: ' + questions + ', the limit is ' + MAX_QUESTIONS + '.');
    if (!questions && !errors.length) errors.push('The FAQ would be empty. Keep at least one question.');
    if (errors.length) return { ok: false, edits: null, bases: null, errors, warnings };

    const hidden = builtIn.items.filter((i) => !seenItems.has(i.id)).map((i) => i.id);
    const edits = { order, hidden, text: textEdits, groups: headings };
    // The order is only kept when it says something the code does not.
    const natural = faqLayout(builtIn, { order: null, hidden, text: {}, groups: {} })
      .filter((s) => s.items.length);
    if (!addedAny && same(natural.map((s) => ({ group: s.id, items: s.items })), order)) edits.order = null;
    return { ok: true, edits: faqDocument(edits), bases: faqEditsEmpty(edits) ? null : bases, errors, warnings };
  }

  // ---- The Premium page's benefit rows, turned into edits -------------------

  /**
   * The Premium page's benefit rows, turned into the list edits a save
   * writes: order, rows taken off, a built-in row's new icon, rows added.
   *
   * [rows] is the list as the page shows it: [{ id, icon, title: {ar, en},
   * desc: {ar, en} }]. A built-in row's words are its S strings, and the
   * page sends any change to them as strings, worked out against what it
   * loaded (so a tab left open never re-sends words it did not change);
   * they are not read here. An added row's words are part of its edit.
   *
   * Returns { ok, edits (the document's `benefits`, or null for the
   * built-in list), errors, warnings }.
   */
  function benefitEditsFromRows(builtIn, rows) {
    const errors = [];
    const warnings = [];
    const byId = new Map(builtIn.items.map((b) => [b.id, b]));
    const known = new Set(builtIn.icons);
    if (!Array.isArray(rows)) {
      return { ok: false, edits: null, errors: ['Nothing to save.'], warnings };
    }
    if (rows.length > MAX_BENEFITS) errors.push('Too many benefits: ' + rows.length + ', the limit is ' + MAX_BENEFITS + '.');
    if (!rows.length) errors.push('The list would be empty. Keep at least one benefit.');
    const seen = new Set();
    const order = [];
    const icons = {};
    const added = {};
    let addedAny = false;

    rows.forEach((row, i) => {
      const rid = row && typeof row.id === 'string' ? row.id : '';
      const b = byId.get(rid);
      const where = 'Benefit ' + (i + 1);
      if (seen.has(rid)) {
        errors.push(where + ' is in the list twice.');
        return;
      }
      seen.add(rid);
      if (!b && !isAddedId(rid, ADDED.benefit)) {
        errors.push(where + ' has an id the app does not know.');
        return;
      }
      const icon = row && typeof row.icon === 'string' ? row.icon : '';
      if (!known.has(icon)) errors.push(where + ' has an icon the app does not have.');
      if (b) {
        if (known.has(icon) && icon !== b.icon) icons[rid] = icon;
      } else {
        addedAny = true;
        const title = (row && row.title) || {};
        const desc = (row && row.desc) || {};
        const fields = {
          titleAr: checkField(where + ' title, Arabic', 'ar', title.ar, MAX_BENEFIT_TITLE_LENGTH),
          titleEn: checkField(where + ' title, English', 'en', title.en, MAX_BENEFIT_TITLE_LENGTH),
          descAr: checkField(where + ' description, Arabic', 'ar', desc.ar, MAX_BENEFIT_DESC_LENGTH),
          descEn: checkField(where + ' description, English', 'en', desc.en, MAX_BENEFIT_DESC_LENGTH),
        };
        const benefit = { icon };
        for (const [field, check] of Object.entries(fields)) {
          errors.push(...check.errors);
          warnings.push(...check.warnings);
          warnings.push(...notABenefit(where + (field.startsWith('title') ? ' title' : ' description'), check.text));
          benefit[field] = check.text;
        }
        added[rid] = benefit;
      }
      order.push(rid);
    });
    if (errors.length) return { ok: false, edits: null, errors, warnings };

    const hidden = builtIn.items.filter((b) => !seen.has(b.id)).map((b) => b.id);
    const edits = { order, hidden, icons, added };
    const natural = resolveBenefits(builtIn, { order: null, hidden, icons: {}, added: {} }).map((b) => b.id);
    if (!addedAny && same(natural, order)) edits.order = null;
    return { ok: true, edits: benefitsDocument(edits), errors, warnings };
  }

  // ---- Knowing what a page was built from -----------------------------------

  /**
   * A short fingerprint of [value] (FNV-1a over its canonical JSON). A page
   * sends the fingerprint of the app's own list it was built from, and a
   * save is refused when the app's list has changed in the code since: a
   * page drawn from the old list would store its old words as edits and
   * hide what the new one added.
   */
  function fingerprint(value) {
    return R.fnv1a(new TextEncoder().encode(canonical(value === undefined ? null : value)));
  }

  // ---- Saying what changed, for History ------------------------------------

  /**
   * What one FAQ save changed, in words: "2 questions edited, 1 added, 1
   * moved". Told by id, so a question moved to another group counts once.
   */
  function describeFaqChange(builtIn, before, after) {
    const a = resolveFaq(builtIn, parseFaqEdits(before));
    const b = resolveFaq(builtIn, parseFaqEdits(after));
    const flat = (sections) => {
      const out = [];
      sections.forEach((s) => s.items.forEach((item) => out.push({ group: s.id, item })));
      return out;
    };
    const was = flat(a);
    const now = flat(b);
    const wasById = new Map(was.map((x, i) => [x.item.id, { x, i }]));
    const nowIds = new Set(now.map((x) => x.item.id));
    let edited = 0;
    let added = 0;
    let movedGroup = 0;
    const from = [];
    now.forEach((x) => {
      const prev = wasById.get(x.item.id);
      if (!prev) {
        added++;
        return;
      }
      from.push(prev.i);
      if (!same(prev.x.item, x.item)) edited++;
      if (prev.x.group !== x.group) movedGroup++;
    });
    const removed = was.filter((x) => !nowIds.has(x.item.id)).length;
    const moved = Math.max(movedGroup, from.length - R.longestRising(from));
    const headings = b.filter((s) => {
      const old = a.find((o) => o.id === s.id);
      return old && !same(old.title, s.title);
    }).length;
    const groupsAdded = b.filter((s) => !a.some((o) => o.id === s.id)).length;
    const groupsGone = a.filter((s) => !b.some((o) => o.id === s.id)).length;
    const parts = [];
    const n = (count, one, many) => count + ' ' + (count === 1 ? one : many);
    if (edited) parts.push(n(edited, 'question', 'questions') + ' edited');
    if (added) parts.push((parts.length ? added : n(added, 'question', 'questions')) + ' added');
    if (removed) parts.push((parts.length ? removed : n(removed, 'question', 'questions')) + ' taken off');
    if (moved) parts.push((parts.length ? moved : n(moved, 'question', 'questions')) + ' moved');
    if (headings) parts.push(n(headings, 'heading', 'headings') + ' changed');
    if (groupsAdded) parts.push(n(groupsAdded, 'group', 'groups') + ' added');
    if (groupsGone) parts.push(n(groupsGone, 'group', 'groups') + ' gone');
    return parts.join(', ');
  }

  /** What one save of the benefit list's order, icons or added rows changed. */
  function describeBenefitsChange(builtIn, before, after) {
    const a = resolveBenefits(builtIn, parseBenefitEdits(before));
    const b = resolveBenefits(builtIn, parseBenefitEdits(after));
    const wasById = new Map(a.map((x, i) => [x.id, { x, i }]));
    const nowIds = new Set(b.map((x) => x.id));
    let edited = 0;
    let added = 0;
    const from = [];
    b.forEach((x) => {
      const prev = wasById.get(x.id);
      if (!prev) {
        added++;
        return;
      }
      from.push(prev.i);
      if (!same(prev.x, x)) edited++;
    });
    const removed = a.filter((x) => !nowIds.has(x.id)).length;
    const moved = from.length - R.longestRising(from);
    const parts = [];
    const n = (count, one, many) => count + ' ' + (count === 1 ? one : many);
    if (edited) parts.push(n(edited, 'benefit', 'benefits') + ' changed');
    if (added) parts.push((parts.length ? added : n(added, 'benefit', 'benefits')) + ' added');
    if (removed) parts.push((parts.length ? removed : n(removed, 'benefit', 'benefits')) + ' taken off');
    if (moved) parts.push((parts.length ? moved : n(moved, 'benefit', 'benefits')) + ' moved');
    return parts.join(', ');
  }

  return {
    MAX_QUESTION_LENGTH,
    MAX_ANSWER_LENGTH,
    MAX_HEADING_LENGTH,
    MAX_BENEFIT_TITLE_LENGTH,
    MAX_BENEFIT_DESC_LENGTH,
    MAX_QUESTIONS,
    MAX_GROUPS,
    MAX_BENEFITS,
    ADDED,
    parseFaqEdits,
    parseBenefitEdits,
    faqDocument,
    benefitsDocument,
    canonical,
    same,
    resolveFaq,
    faqLayout,
    resolveBenefits,
    checkField,
    notABenefit,
    isAddedId,
    newId,
    faqEditsFromDraft,
    benefitEditsFromRows,
    fingerprint,
    own,
    describeFaqChange,
    describeBenefitsChange,
  };
});

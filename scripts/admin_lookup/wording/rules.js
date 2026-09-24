/**
 * What the Wording page lets through, shared by the browser and the server.
 *
 * The same file runs in both places on purpose. The page runs these checks
 * as you type, so a problem shows before you press Save; the server runs
 * them again on every save, so nothing the page misses (or a request that
 * never came from the page) can reach the document every phone reads. Two
 * copies of the rules would be two things that drift apart.
 *
 * Errors block a save. Warnings are shown and the save goes through: they
 * are house-style reminders, and the person saving is the one who set them.
 *
 * No em dash anywhere in this file, including comments (see the wording
 * workbook's README: the check covers every text file under docs/wording,
 * and the same habit holds here).
 */
(function (root, factory) {
  if (typeof module === 'object' && module.exports) {
    module.exports = factory();
  } else {
    root.WordingRules = factory();
  }
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  /** Longest edit accepted. The longest built-in string is 210 characters. */
  const MAX_STRING_LENGTH = 600;
  /** Longest daily line accepted. The longest built-in one is 125. */
  const MAX_QUOTE_LENGTH = 300;
  const MAX_QUOTES = 400;
  /** Lines needed for a line never to repeat inside one month. */
  const MONTH_WITHOUT_REPEATS = 31;

  /**
   * One character from its code point. This file never types an em dash,
   * a haraka or any other mark that is invisible or easy to confuse; it
   * builds them, so what the file says is what a reader sees.
   */
  const ch = (code) => String.fromCharCode(code);
  const EM_DASH = ch(0x2014);

  /** The day the app's quote rotation counts from (daily_quotes.dart). */
  const ROTATION_EPOCH = '2026-01-01';

  /**
   * [text] as it will be stored: line endings made plain, ends trimmed.
   * Inner spacing and line breaks are kept, because some built-in strings
   * break lines on purpose.
   */
  function normalizeText(text) {
    return String(text == null ? '' : text).replace(/\r\n?/g, '\n').trim();
  }

  /** Every {part} written in [text], in order, without the braces. */
  function partsIn(text) {
    const out = [];
    const re = /\{([^{}\n]+)\}/g;
    let m;
    while ((m = re.exec(text)) !== null) out.push(m[1]);
    return out;
  }

  /**
   * A regex for [pattern] as a whole Arabic word. Letters and harakat count
   * as part of a word; everything else, Arabic punctuation included (، ؛ ؟
   * sit in the same Unicode block as the letters), is a boundary.
   */
  function arabicWord(pattern) {
    // U+0621 to U+065F (letters and harakat) and U+0670 to U+06D3.
    const letter = ch(0x0621) + '-' + ch(0x065F) + ch(0x0670) + '-' + ch(0x06D3);
    return new RegExp('(^|[^' + letter + '])(?:' + pattern + ')(?=$|[^' + letter + '])');
  }

  /**
   * Reminders of the house style, Arabic side. Each one is a rule Aziz set
   * for the app's Arabic (see lib/core/l10n/daily_quotes.dart and the
   * project's wording notes); none of them is a grammar check.
   */
  const ARABIC_STYLE = [
    {
      // With or without shadda, and with a leading و or ف (ولسا, فلسه).
      test: arabicWord('[وف]?لس' + ch(0x0651) + '?[اهة]'),
      say: 'House style: write «إلى الآن», never «لسا» or «لسه».',
    },
    {
      test: /[چگ]/,
      say: 'House style: avoid چ and گ (باجر, not باچر). Most readers cannot scan them.',
    },
    {
      test: arabicWord('هذي'),
      say: 'House style: هذه, not هذي.',
    },
    {
      test: new RegExp('[' + ch(0x0660) + '-' + ch(0x0669) + ']'),
      say: 'House style: Latin digits in the app (3, not ٣). Notifications are the one exception.',
    },
  ];

  /**
   * Checks one edit of one string in one language.
   *
   * [entry] is the string's catalog row: its built-in text and the {parts}
   * the app can fill for it. Returns the text as it would be stored, whether
   * it is simply the built-in text again (so the save should remove the
   * edit instead of storing a copy), and the errors and warnings.
   */
  function checkStringEdit(entry, lang, rawText) {
    const errors = [];
    const warnings = [];
    if (!entry) {
      return { ok: false, text: '', sameAsBuiltIn: false, errors: ['No such string in the app.'], warnings };
    }
    if (!entry.editable) {
      return { ok: false, text: '', sameAsBuiltIn: false, errors: [entry.why || 'This string can only change in the app’s code.'], warnings };
    }
    if (lang !== 'ar' && lang !== 'en') {
      return { ok: false, text: '', sameAsBuiltIn: false, errors: ['Unknown language.'], warnings };
    }
    const text = normalizeText(rawText);
    const builtIn = lang === 'ar' ? entry.ar : entry.en;
    const known = (lang === 'ar' ? entry.tokensAr : entry.tokensEn) || [];

    if (!text) {
      errors.push('Empty. To go back to the app’s own text, use Back to built-in.');
    }
    if (text.length > MAX_STRING_LENGTH) {
      errors.push('Too long: ' + text.length + ' characters, the limit is ' + MAX_STRING_LENGTH + '.');
    }
    if (text.includes(EM_DASH)) {
      errors.push('Has an em dash. Use a comma, a colon or a full stop.');
    }
    const unknown = partsIn(text).filter((p) => !known.includes(p));
    if (unknown.length) {
      errors.push(
        'The app cannot fill ' + unknown.map((p) => '{' + p + '}').join(', ') + '. ' +
        (known.length
          ? 'It can fill: ' + known.map((p) => '{' + p + '}').join(', ') + '.'
          : 'This string has no parts to fill.'),
      );
    }
    const used = partsIn(text);
    const dropped = known.filter((p) => !used.includes(p));
    if (text && dropped.length) {
      warnings.push(
        'Leaves out ' + dropped.map((p) => '{' + p + '}').join(', ') +
        ': the app fills ' + (dropped.length === 1 ? 'it' : 'them') + ' in the built-in text, and will not show ' +
        (dropped.length === 1 ? 'it' : 'them') + ' with this edit.',
      );
    }
    if (lang === 'ar') {
      for (const rule of ARABIC_STYLE) {
        if (rule.test.test(text)) warnings.push(rule.say);
      }
    }
    return {
      ok: errors.length === 0,
      text,
      sameAsBuiltIn: text === normalizeText(builtIn),
      errors,
      warnings,
    };
  }

  /**
   * Checks a whole daily rotation. [items] is the list as it would be saved,
   * in order.
   */
  function checkQuotes(items) {
    const errors = [];
    const warnings = [];
    if (!Array.isArray(items) || items.length === 0) {
      return { ok: false, items: [], errors: ['The list is empty. The Grid needs at least one line.'], warnings };
    }
    if (items.length > MAX_QUOTES) {
      errors.push('Too many lines: ' + items.length + ', the limit is ' + MAX_QUOTES + '.');
    }
    const clean = items.map((q) => ({
      ar: normalizeText(q && q.ar),
      en: normalizeText(q && q.en),
    }));
    clean.forEach((q, i) => {
      const n = 'Line ' + (i + 1);
      if (!q.ar) errors.push(n + ' has no Arabic.');
      if (!q.en) errors.push(n + ' has no English.');
      if (q.ar.length > MAX_QUOTE_LENGTH || q.en.length > MAX_QUOTE_LENGTH) {
        errors.push(n + ' is longer than ' + MAX_QUOTE_LENGTH + ' characters.');
      }
      if (q.ar.includes(EM_DASH) || q.en.includes(EM_DASH)) {
        errors.push(n + ' has an em dash. Use a comma, a colon or a full stop.');
      }
      for (const rule of ARABIC_STYLE) {
        if (rule.test.test(q.ar)) warnings.push(n + ': ' + rule.say);
      }
    });
    const seen = new Map();
    clean.forEach((q, i) => {
      if (!q.ar) return;
      if (seen.has(q.ar)) warnings.push('Line ' + (i + 1) + ' repeats line ' + (seen.get(q.ar) + 1) + '.');
      else seen.set(q.ar, i);
    });
    if (clean.length < MONTH_WITHOUT_REPEATS) {
      warnings.push(
        'Only ' + clean.length + ' lines: with fewer than ' + MONTH_WITHOUT_REPEATS +
        ', a line comes back inside the same month.',
      );
    }
    return { ok: errors.length === 0, items: clean, errors, warnings };
  }

  /** Whole days from the rotation's first day to [dateKey] ('YYYY-MM-DD'). */
  function daysSinceEpoch(dateKey) {
    const [y, m, d] = String(dateKey).split('-').map(Number);
    const [ey, em, ed] = ROTATION_EPOCH.split('-').map(Number);
    return Math.round((Date.UTC(y, m - 1, d) - Date.UTC(ey, em - 1, ed)) / 86400000);
  }

  /**
   * Which line of an [n]-line rotation the app shows on [dateKey]. The same
   * arithmetic as _indexForDay in daily_quotes.dart, including the wrap for
   * dates before the epoch.
   */
  function rotationIndex(dateKey, n) {
    if (!n) return -1;
    const days = daysSinceEpoch(dateKey);
    return ((days % n) + n) % n;
  }

  /** [dateKey] moved by [delta] days. */
  function addDays(dateKey, delta) {
    const [y, m, d] = String(dateKey).split('-').map(Number);
    const t = new Date(Date.UTC(y, m - 1, d + delta));
    return t.toISOString().slice(0, 10);
  }

  /**
   * [list] with the lines at [picked] (indices, any order) taken out and put
   * back together, in their order, starting at index [to]. Everything else
   * keeps its order. Returns a new array; [list] is not touched.
   *
   * Without [wrap], [to] is a place in the list as the page shows it, and a
   * group that would run past the last line is pulled back until it fits.
   * With [wrap], [to] is a day's place in the rotation, and the group runs
   * on past the last line into the first, because that is what the phones
   * show next: "three lines from tomorrow" still means tomorrow, the day
   * after and the day after that when tomorrow is the last line.
   */
  function moveLines(list, picked, to, wrap) {
    const n = list.length;
    const idx = Array.from(new Set(picked))
      .filter((i) => Number.isInteger(i) && i >= 0 && i < n)
      .sort((a, b) => a - b);
    if (!idx.length) return list.slice();
    const g = idx.length;
    const inGroup = new Set(idx);
    const group = idx.map((i) => list[i]);
    const rest = list.filter((_, i) => !inGroup.has(i));
    let start = Math.round(Number(to));
    if (!Number.isFinite(start)) start = 0;
    if (!wrap) {
      start = Math.max(0, Math.min(n - g, start));
      return rest.slice(0, start).concat(group, rest.slice(start));
    }
    start = ((start % n) + n) % n;
    const out = new Array(n);
    const taken = new Array(n).fill(false);
    group.forEach((line, k) => {
      out[(start + k) % n] = line;
      taken[(start + k) % n] = true;
    });
    let r = 0;
    for (let i = 0; i < n; i++) {
      if (!taken[i]) out[i] = rest[r++];
    }
    return out;
  }

  /**
   * Length of the longest strictly rising run hidden in [seq] (not
   * necessarily side by side). For a list of where each line used to be,
   * this is how many lines kept their order, so everything else is the
   * fewest lines that moved: one line dragged from 30 to 9 is 1 moved, not
   * the 22 whose line numbers shifted.
   */
  function longestRising(seq) {
    const tails = [];
    for (const v of seq) {
      let lo = 0;
      let hi = tails.length;
      while (lo < hi) {
        const mid = (lo + hi) >> 1;
        if (tails[mid] < v) lo = mid + 1;
        else hi = mid;
      }
      tails[lo] = v;
    }
    return tails.length;
  }

  /**
   * What changed from one daily list to another, told by the text alone
   * (History has nothing else): { moved, edited, added, removed }.
   * A line found again with both languages the same is the same line; one
   * with only its Arabic or only its English the same is that line, edited.
   * Moved is counted over every line found again, see longestRising.
   */
  function describeLineChanges(before, after) {
    const b = (before || []).map((q) => ({ ar: normalizeText(q && q.ar), en: normalizeText(q && q.en) }));
    const a = (after || []).map((q) => ({ ar: normalizeText(q && q.ar), en: normalizeText(q && q.en) }));
    const both = (q) => q.ar + '\n' + q.en;
    const from = new Array(a.length).fill(-1);
    const used = new Array(b.length).fill(false);
    // Unchanged lines first, through a lookup (History runs this once per
    // row, on lists of up to MAX_QUOTES lines).
    const waiting = new Map();
    b.forEach((q, j) => {
      const key = both(q);
      if (!waiting.has(key)) waiting.set(key, []);
      waiting.get(key).push(j);
    });
    a.forEach((q, i) => {
      const queue = waiting.get(both(q));
      if (!queue || !queue.length) return;
      from[i] = queue.shift();
      used[from[i]] = true;
    });
    // Then edits, among the few lines left over.
    let edited = 0;
    const pass = (same) => {
      a.forEach((q, i) => {
        if (from[i] >= 0) return;
        const j = b.findIndex((p, k) => !used[k] && same(p, q));
        if (j < 0) return;
        from[i] = j;
        used[j] = true;
        edited++;
      });
    };
    pass((p, q) => p.ar !== '' && p.ar === q.ar);
    pass((p, q) => p.en !== '' && p.en === q.en);
    const found = from.filter((j) => j >= 0);
    return {
      moved: found.length - longestRising(found),
      edited,
      added: a.length - found.length,
      removed: b.length - found.length,
    };
  }

  /** [changes] from describeLineChanges (or the page's own count) in words. */
  function lineChangeWords(changes) {
    const lines = (count) => count + (count === 1 ? ' line' : ' lines');
    const parts = [];
    if (changes.moved) parts.push(lines(changes.moved) + ' moved');
    if (changes.edited) parts.push((parts.length ? changes.edited : lines(changes.edited)) + ' edited');
    if (changes.added) parts.push((parts.length ? changes.added : lines(changes.added)) + ' added');
    if (changes.removed) parts.push((parts.length ? changes.removed : lines(changes.removed)) + ' removed');
    return parts.join(', ');
  }

  /**
   * [text] reduced for searching: no harakat or tatweel, one alef, ya for
   * alef maqsura, ha for ta marbuta, lower case. So «التقدير» finds
   * «التّقدير», and «إلى» finds «الى».
   */
  function searchKey(text) {
    return String(text || '')
      .replace(HARAKAT_AND_TATWEEL, '')
      .replace(ALEF_FORMS, ch(0x0627))
      .replace(ALEF_MAQSURA, ch(0x064A))
      .replace(TA_MARBUTA, ch(0x0647))
      .toLowerCase();
  }

  // U+064B to U+065F and U+0670 (harakat), U+0640 (tatweel).
  const HARAKAT_AND_TATWEEL = new RegExp('[' + ch(0x064B) + '-' + ch(0x065F) + ch(0x0670) + ch(0x0640) + ']', 'g');
  // Alef with madda, hamza above, hamza below, wasla: all read as plain alef (U+0627).
  const ALEF_FORMS = new RegExp('[' + ch(0x0622) + ch(0x0623) + ch(0x0625) + ch(0x0671) + ']', 'g');
  const ALEF_MAQSURA = new RegExp(ch(0x0649), 'g');
  const TA_MARBUTA = new RegExp(ch(0x0629), 'g');

  /**
   * FNV-1a, 32 bits, over [bytes] (a Uint8Array or Buffer), as eight hex
   * digits. gen_wording_edits.dart computes the same thing to fingerprint
   * the sources a catalog was built from.
   */
  function fnv1a(bytes) {
    let hash = 0x811c9dc5;
    for (let i = 0; i < bytes.length; i++) {
      hash ^= bytes[i];
      hash = Math.imul(hash, 0x01000193) >>> 0;
    }
    return hash.toString(16).padStart(8, '0');
  }

  return {
    MAX_STRING_LENGTH,
    MAX_QUOTE_LENGTH,
    MONTH_WITHOUT_REPEATS,
    ROTATION_EPOCH,
    // Exported so a second page that checks short, non-interpolated text
    // against the same house style (the Achievements page's names and
    // descriptions) does not need its own copy of these four rules.
    ARABIC_STYLE,
    normalizeText,
    partsIn,
    checkStringEdit,
    checkQuotes,
    rotationIndex,
    addDays,
    moveLines,
    longestRising,
    describeLineChanges,
    lineChangeWords,
    searchKey,
    fnv1a,
  };
});

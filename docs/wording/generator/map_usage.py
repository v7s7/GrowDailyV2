#!/usr/bin/env python3
"""Usage map for the Grow Daily wording inventory.

Answers "WHERE is this wording shown?" for every text member of class S in
lib/core/l10n/app_strings.dart, and for the top-level functions and
constants of lib/core/l10n/reminder_copy.dart and daily_quotes.dart.

How it works, in order:

1. Every Dart file under lib/ is masked: comments and the literal text of
   string literals become spaces (newlines are kept, so offsets and line
   numbers stay true), while string interpolations (${...} and $name) stay
   visible as code. Nothing inside a comment or a string can be mistaken
   for a usage.
2. The body of class S is split into members with a bracket-aware
   segmenter, which gives each member's name, return type, kind and line.
3. Every lib file except app_strings.dart is scanned for ".name" followed
   by a non-identifier character. The receiver in front of the dot is then
   checked, so that habit.title or user.email does not count as a usage of
   S.title or S.email:
     * S.of(...) or S(...) directly            -> confidence "direct"
     * an identifier the same library binds to S (S s, s = S.of(context),
       final S strings, S get s, a function returning S) -> "typed"
   A match whose receiver is anything else is kept apart in
   "rejected_usages" for review, never counted.
   The receiver is resolved by scope, not only by name: the innermost
   binding of that identifier visible at the match wins (a parameter, a
   local, a for-in variable or a closure parameter, each with an
   approximate scope). A name bound to a non-S value there, such as
   `final s = stats;` followed by s.total, is rejected. An untyped closure
   parameter, such as `(s) => s.gridTitle` passed where a
   `String Function(S)` is expected, is counted with confidence "inferred".
   Bare-name references inside app_strings.dart, reminder_copy.dart and
   daily_quotes.dart get the same scope check, so a parameter called
   `level` is not mistaken for the member S.level.
4. Top-level functions of reminder_copy.dart and daily_quotes.dart are
   matched as bare identifiers (not after a dot) in every other lib file.
5. Each using file is mapped to a readable screen name: a hand-written
   override table for the important files, and a name derived from the
   feature folder and the file name for everything else.
6. A member is "unused" when nothing outside app_strings.dart uses it AND
   no used member reaches it from inside app_strings.dart (liveness is
   followed transitively, so a helper string called only by a live string
   is not flagged). "internal_only" marks members that are alive only
   through another member. A reference inside the same file that only
   reads a list's size (`days % kDailyQuotes.length`) is not a use of its
   text: it goes under "internal_non_text_reads", counts for no liveness
   and no via chain, and is still compared with the analyzer by --verify.

7. Every other Dart row (a model's localizedName, a catalog entry, a
   service's label, a Latin-only literal) is mapped with the Dart analyzer:
   bin/verify_usage.dart resolves lib/ and lists every reference to every
   getter, method, field and top-level declaration, and for each one where
   the referenced value goes next (its flow): returned by the member that
   holds the use (R), stored in a field (F), passed to a parameter (P, with
   Q flows for where that call's own result goes), shown by an API outside
   lib/ (XD: a Flutter widget, a notification, a thrown exception), stored
   or sent (XS: Firestore, preferences), handed to another API (XU), or used
   for something that is not text (D: a comparison, a length, a log line).
   It records the same for every string literal and every parameter.
   The row's text is followed along those flows, up to ten steps:
     * a catalog entry (a constructor call inside a list or constant) starts
       from the fields its arguments fill (IslamicHabitTemplate.description,
       AchievementModel.name), found through ctor_args, not from the list,
       so AchievementCatalog.all.length counts for nothing;
     * a method's own literals say how its text leaves it: handed back (the
       uses of the method are followed), shown by the method itself or by a
       widget of its own file (the places that CALL the method), or stored
       in a field or passed on (followed from there). A method whose result
       cannot carry text (void, bool) is mapped by its calls.
     * a flow into a widget or field of another screen file shows at the use
       line; within a screen file it shows there only if that field is drawn;
       a flow to storage is kept as "stored" and a D flow is dropped. So a
       write or an action (RoomsController._profileFields, a completeHabit
       chain) is never a screen: the "Warrior" fallback reaches the Room
       page through RoomParticipant.displayName instead.
     * a member read on an enum constant (MilestoneType.levelUp.localizedName)
       counts only for that constant's per-case row, and so does one read
       inside a switch case that has narrowed its receiver (`case
       MilestoneType.levelUp:` then `e.type.localizedName(isAr)`).
   Several chains can reach the same line: "usages" keeps one entry per
   file:line with the chains merged, shortest first ("(via A; or via B >
   C)", "(directly; or via A)"), see merge_usage_texts.
   A Riverpod provider, or a member that reaches more than 25 places, is not
   walked place by place: the use keeps its own line, "(in habitListProvider,
   which reaches N places)", and the row gets the screens behind it (or
   "Many screens, through X" past 12). A row whose text reaches no screen is
   unused; when it only reaches storage the write lines go in its notes.
   The rows come from .cache/dart_rows.json, so extract_dart.dart runs
   first. Native rows whose text a Dart call brings up (an iOS permission
   sheet, see PERMISSION_TRIGGERS in extract_native.py) are mapped by the
   calls that open them, from .cache/native_rows.json. The result is under
   "dart_rows", keyed by row id.

8. With --verify, the same analyzer references are compared with the text
   search of steps 1 to 6, reference by reference (doc-comment references
   like [S.tagline] are left aside, they are not usages). The result lands in
   _meta.analyzer_check. On 2026-09-17 the two agreed exactly: 1434 usages
   of S members, 76 usages of the top-level copy functions, every internal
   reference, and the same 164 members with no outside usage.

Reads only. Writes one JSON file: the first non-flag argument, or by default
docs/wording/generator/.cache/usage.json.
Run: python3 docs/wording/generator/map_usage.py [out.json] [--verify] [--no-analyzer]
--no-analyzer skips step 7 (and --verify): no Dart SDK run, and the rows of
step 7 get only their own file's screen.
"""

from __future__ import annotations

import bisect
import json
import os
import re
import sys
from collections import Counter, OrderedDict, defaultdict

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
# generator/.cache is gitignored; build_workbook.py reads from there by default.
DEFAULT_OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '.cache', 'usage.json')

APP_STRINGS = 'lib/core/l10n/app_strings.dart'
REMINDER_COPY = 'lib/core/l10n/reminder_copy.dart'
DAILY_QUOTES = 'lib/core/l10n/daily_quotes.dart'

IDENT_CHARS = set('ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_$')

# A reference that reads only a list's size, not its text:
# `days % kDailyQuotes.length`, `if (kFaqEntries.isEmpty)`.
NON_TEXT_READ_RE = re.compile(r'\s*[?!]?\s*\.\s*(length|isEmpty|isNotEmpty)(?![\w$])')


def is_non_text_read(masked: str, end: int) -> bool:
    return NON_TEXT_READ_RE.match(masked, end) is not None


# ─── 1. Masking ──────────────────────────────────────────────────────────────

def mask_dart(src: str) -> str:
    """Comments and literal string text become spaces; code stays.

    Handles // and nested /* */ comments, raw strings (r'..'), triple-quoted
    strings, backslash escapes, and interpolation (${expr} with nested
    strings and braces, and $identifier).
    """
    out = list(src)
    n = len(src)
    i = 0
    # Stack entries: ['code', brace_depth, is_interpolation]
    #                ['str', quote_char, triple, raw]
    stack: list[list] = [['code', 0, False]]

    def blank(a: int, b: int) -> None:
        for k in range(a, min(b, n)):
            if out[k] != '\n':
                out[k] = ' '

    while i < n:
        top = stack[-1]
        c = src[i]
        if top[0] == 'code':
            if c == '/' and i + 1 < n and src[i + 1] == '/':
                j = src.find('\n', i)
                j = n if j == -1 else j
                blank(i, j)
                i = j
                continue
            if c == '/' and i + 1 < n and src[i + 1] == '*':
                depth = 0
                j = i
                while j < n:
                    if src.startswith('/*', j):
                        depth += 1
                        j += 2
                    elif src.startswith('*/', j):
                        depth -= 1
                        j += 2
                        if depth == 0:
                            break
                    else:
                        j += 1
                blank(i, j)
                i = j
                continue
            raw = False
            qpos = -1
            if c in '\'"':
                qpos = i
            elif (c in 'rR' and i + 1 < n and src[i + 1] in '\'"'
                  and (i == 0 or src[i - 1] not in IDENT_CHARS)):
                raw = True
                qpos = i + 1
            if qpos >= 0:
                q = src[qpos]
                triple = src.startswith(q * 3, qpos)
                start_content = qpos + (3 if triple else 1)
                stack.append(['str', q, triple, raw])
                i = start_content
                continue
            if c == '{':
                top[1] += 1
            elif c == '}':
                if top[2] and top[1] == 0:
                    out[i] = ' '
                    stack.pop()
                    i += 1
                    continue
                top[1] -= 1
            i += 1
            continue

        # Inside a string literal.
        _, q, triple, raw = top
        closer = q * 3 if triple else q
        if not raw and c == '\\':
            blank(i, i + 2)
            i += 2
            continue
        if src.startswith(closer, i):
            stack.pop()
            i += len(closer)
            continue
        if not triple and c == '\n':
            # Unterminated single-line string: recover rather than eat the file.
            stack.pop()
            i += 1
            continue
        if not raw and c == '$' and i + 1 < n:
            nxt = src[i + 1]
            if nxt == '{':
                blank(i, i + 2)
                stack.append(['code', 0, True])
                i += 2
                continue
            if nxt.isalpha() or nxt == '_':
                out[i] = ' '
                j = i + 1
                while j < n and (src[j].isalnum() or src[j] == '_'):
                    j += 1
                i = j  # keep the identifier visible as code
                continue
        if c != '\n':
            out[i] = ' '
        i += 1
    return ''.join(out)


# ─── Tokens and segmentation ─────────────────────────────────────────────────

TOKEN_RE = re.compile(
    r"[A-Za-z_$][A-Za-z0-9_$]*"      # identifiers and keywords
    r"|[0-9][0-9A-Za-z_.]*"          # numbers
    r"|=>|\?\?=|\?\?|\.\.\.|\?\.|\.\.|==|!=|<=|>=|&&|\|\|"
    r"|[^\sA-Za-z0-9_$]"             # any other single char
)
OPEN = {'(': ')', '[': ']', '{': '}'}
CLOSE = {')', ']', '}'}


class Tok:
    __slots__ = ('text', 'pos')

    def __init__(self, text: str, pos: int):
        self.text = text
        self.pos = pos

    def __repr__(self) -> str:
        return f'Tok({self.text!r}@{self.pos})'


def tokenize(masked: str) -> list[Tok]:
    return [Tok(m.group(0), m.start()) for m in TOKEN_RE.finditer(masked)
            if m.group(0) not in ("'", '"')]


def bracket_matches(toks: list[Tok]) -> dict[int, int]:
    match: dict[int, int] = {}
    stack: list[int] = []
    for k, t in enumerate(toks):
        if t.text in OPEN:
            stack.append(k)
        elif t.text in CLOSE and stack:
            o = stack.pop()
            match[o] = k
            match[k] = o
    return match


MODIFIERS = {'static', 'final', 'const', 'late', 'external', 'abstract',
             'covariant', 'factory', 'required', 'sealed', 'base', 'interface',
             'augment'}


class Segment:
    """One declaration: a member of a class body, or a top-level item."""

    def __init__(self, toks, start, header_end, body_open, end, match, masked):
        self.toks = toks
        self.masked = masked
        self.start = start          # first token index
        self.header_end = header_end  # token index where the body begins
        self.body_open = body_open  # index of '{' of a block body, or None
        self.end = end              # last token index (inclusive)
        self.match = match
        self.name, self.kind, self.return_type = self._describe()

    @property
    def start_pos(self) -> int:
        return self.toks[self.start].pos

    @property
    def end_pos(self) -> int:
        return self.toks[self.end].pos + 1

    def header_tokens(self):
        """(index, token) pairs of the header at bracket depth 0."""
        k = self.start
        while k < self.header_end:
            t = self.toks[k]
            yield k, t
            if t.text in OPEN and k in self.match and self.match[k] < self.header_end:
                k = self.match[k] + 1
            else:
                k += 1

    def _describe(self):
        head = list(self.header_tokens())
        texts = [t.text for _, t in head]
        # Skip annotations: '@' ident ('.' ident)* optional (...)
        clean = []
        k = 0
        while k < len(head):
            idx, t = head[k]
            if t.text == '@':
                k += 2
                while k + 1 < len(head) and head[k][1].text == '.':
                    k += 2
                if k < len(head) and head[k][1].text == '(':
                    k += 1
                continue
            clean.append((idx, t))
            k += 1
        texts = [t.text for _, t in clean]
        for kw in ('class', 'mixin', 'enum', 'typedef'):
            if kw in texts:
                j = texts.index(kw)
                if j + 1 < len(texts):
                    return texts[j + 1], kw, ''
        if 'extension' in texts:
            j = texts.index('extension')
            if j + 1 < len(texts) and texts[j + 1] == 'type' and j + 2 < len(texts):
                return texts[j + 2], 'extension type', ''
            if j + 1 < len(texts) and texts[j + 1] != 'on':
                return texts[j + 1], 'extension', ''
            return 'extension on ' + ' '.join(texts[j + 2:j + 3]), 'extension', ''
        if texts[:1] in (['import'], ['export'], ['part'], ['library']):
            return '', texts[0], ''
        def rt_before(k: int) -> str:
            """Return type: the source between the first header token and clean[k]."""
            if not clean or k <= 0:
                return ''
            a = clean[0][1].pos
            b = clean[k][1].pos
            words = re.sub(r'\s+', ' ', self.masked[a:b]).strip()
            parts = words.split(' ')
            while parts and parts[0] in MODIFIERS:
                parts.pop(0)
            return ' '.join(parts)

        for j, tx in enumerate(texts):
            if tx in ('get', 'set') and j + 1 < len(texts) and re.match(r'[A-Za-z_$]', texts[j + 1]):
                if j + 2 >= len(texts) or texts[j + 2] in ('(', '=>', '{', ';') or tx == 'get':
                    return texts[j + 1], ('getter' if tx == 'get' else 'setter'), rt_before(j)
        if 'operator' in texts:
            j = texts.index('operator')
            return 'operator ' + ''.join(texts[j + 1:j + 2]), 'operator', rt_before(j)
        for j, tx in enumerate(texts):
            if tx != '(' or j == 0:
                continue
            prev = texts[j - 1]
            if prev == 'Function':
                continue  # a function TYPE, not the declaration's own parameters
            if not (re.match(r'[A-Za-z_$]', prev) or prev == '>'):
                continue  # e.g. a record return type: (int, Unit) name(...)
            # Walk back over <...> type parameters.
            b = j - 1
            if texts[b] == '>':
                depth = 0
                while b >= 0:
                    if texts[b] == '>':
                        depth += 1
                    elif texts[b] == '<':
                        depth -= 1
                        if depth == 0:
                            b -= 1
                            break
                    b -= 1
            if b < 0:
                continue
            name = texts[b]
            # Named constructor: Foo.bar(
            if b >= 2 and texts[b - 1] == '.':
                return texts[b - 2] + '.' + name, 'constructor', ''
            return name, 'function', rt_before(b)
        # Field / variable: last identifier in the header.
        idents = [k for k, tx in enumerate(texts) if re.match(r'[A-Za-z_$]', tx)]
        if idents:
            k = idents[-1]
            return texts[k], 'field', rt_before(k)
        return '', 'other', ''


def segment(toks: list[Tok], lo: int, hi: int, match: dict[int, int], masked: str) -> list[Segment]:
    """Split tokens lo..hi (exclusive) into declarations at depth 0."""
    segs: list[Segment] = []
    i = lo
    while i < hi:
        start = i
        seen_arrow = False
        seen_eq = False
        init_colon = False
        header_end = None
        body_open = None
        end = None
        while i < hi:
            t = toks[i].text
            if t in OPEN:
                if (t == '{' and not seen_arrow
                        and (not seen_eq or init_colon)):
                    header_end = i if header_end is None else header_end
                    body_open = i
                    i = match.get(i, hi - 1)
                    end = i
                    i += 1
                    # A block body may still be followed by ';' (rare); absorb it.
                    if i < hi and toks[i].text == ';':
                        end = i
                        i += 1
                    break
                i = match.get(i, i) + 1
                continue
            if t in CLOSE:
                i += 1
                continue
            if t == '=>' and not seen_arrow:
                seen_arrow = True
                header_end = i if header_end is None else header_end
            elif t == '=' and not seen_eq and not seen_arrow:
                seen_eq = True
                if not init_colon:
                    header_end = i if header_end is None else header_end
            elif t == ':' and not seen_eq and not seen_arrow and i > start and toks[i - 1].text == ')':
                init_colon = True
                header_end = i if header_end is None else header_end
            elif t == ';':
                header_end = i if header_end is None else header_end
                end = i
                i += 1
                break
            i += 1
        if end is None:
            end = hi - 1
            header_end = hi if header_end is None else header_end
        if end >= start:
            segs.append(Segment(toks, start, header_end, body_open, end, match, masked))
    return segs


class DartFile:
    def __init__(self, rel: str):
        self.rel = rel
        with open(os.path.join(REPO, rel), encoding='utf-8') as fh:
            self.src = fh.read()
        self.masked = mask_dart(self.src)
        self.toks = tokenize(self.masked)
        self.match = bracket_matches(self.toks)
        self.tok_pos = [t.pos for t in self.toks]
        # Innermost enclosing open bracket for each token (-1 at top level).
        self.parent: list[int] = []
        stack: list[int] = []
        for k, t in enumerate(self.toks):
            if t.text in CLOSE and stack:
                stack.pop()
                self.parent.append(stack[-1] if stack else -1)
                continue
            self.parent.append(stack[-1] if stack else -1)
            if t.text in OPEN:
                stack.append(k)
        self.newlines = [m.start() for m in re.finditer('\n', self.src)]
        self.top = segment(self.toks, 0, len(self.toks), self.match, self.masked)
        # Enclosing ranges: (start_pos, end_pos, qualified name), outer then inner.
        self.ranges: list[tuple[int, int, str]] = []
        for seg in self.top:
            if not seg.name:
                continue
            self.ranges.append((seg.start_pos, seg.end_pos, seg.name))
            if seg.kind in ('class', 'mixin', 'enum', 'extension', 'extension type') and seg.body_open is not None:
                close = self.match.get(seg.body_open)
                if close is None:
                    continue
                for m in segment(self.toks, seg.body_open + 1, close, self.match, self.masked):
                    if m.name:
                        self.ranges.append((m.start_pos, m.end_pos, f'{seg.name}.{m.name}'))

    def line_of(self, pos: int) -> int:
        return bisect.bisect_right(self.newlines, pos - 1) + 1

    def enclosing(self, pos: int) -> str:
        best = ''
        best_len = None
        for a, b, name in self.ranges:
            if a <= pos < b and (best_len is None or b - a < best_len):
                best, best_len = name, b - a
        return best

    def enclosing_range(self, pos: int) -> tuple[int, int]:
        best = (0, len(self.src))
        for a, b, _ in self.ranges:
            if a <= pos < b and b - a < best[1] - best[0]:
                best = (a, b)
        return best

    def class_segment(self, name: str):
        for seg in self.top:
            if seg.kind == 'class' and seg.name == name:
                return seg
        return None


# ─── 2. Members of class S ───────────────────────────────────────────────────

def is_text_type(rt: str) -> bool:
    return bool(re.search(r'\bString\b|\bReminderLine\b|\bDailyQuote\b', rt))


def collect_s_members(af: DartFile):
    seg = af.class_segment('S')
    if seg is None:
        raise SystemExit('class S not found in app_strings.dart')
    close = af.match[seg.body_open]
    members = []
    for m in segment(af.toks, seg.body_open + 1, close, af.match, af.masked):
        if not m.name:
            continue
        # Line of the declaration start is the line of the first token that is
        # not an annotation (annotations are rare here, the first token is it).
        members.append({
            'name': m.name,
            'kind': m.kind if m.kind != 'function' else ('constructor' if m.name == 'S' else 'method'),
            'return_type': m.return_type,
            'line': af.line_of(m.start_pos),
            'start_pos': m.start_pos,
            'end_pos': m.end_pos,
            'name_pos': _name_pos(af, m),
            'static': any(af.toks[k].text == 'static' for k in range(m.start, m.header_end)),
        })
    return seg, members


def _name_pos(df: DartFile, m: Segment) -> int:
    base = m.name.split('.')[-1]
    for _, t in m.header_tokens():
        if t.text == base:
            return t.pos
    return m.start_pos


# ─── 3. S-typed receivers ────────────────────────────────────────────────────

def balanced_call_end(masked: str, open_paren: int) -> int:
    depth = 0
    for k in range(open_paren, len(masked)):
        ch = masked[k]
        if ch == '(':
            depth += 1
        elif ch == ')':
            depth -= 1
            if depth == 0:
                return k
    return -1


S_DECL_RE = re.compile(r'(?<![\w$.])S\??\s+([A-Za-z_$][\w$]*)\s*(?=[=;,)}\]:])')
S_GETTER_RE = re.compile(r'(?<![\w$.])S\??\s+get\s+([A-Za-z_$][\w$]*)')
S_FUNC_RE = re.compile(r'(?<![\w$.])S\??\s+([A-Za-z_$][\w$]*)\s*\(')
S_ASSIGN_RE = re.compile(r'([A-Za-z_$][\w$]*)\s*(?::|=)\s*S\s*(\.\s*of\s*)?\(')


def s_typed_names(df: DartFile) -> tuple[set[str], set[str]]:
    """Identifiers bound to an S instance, and functions returning S."""
    names: set[str] = set()
    funcs: set[str] = set()
    m = df.masked
    for x in S_DECL_RE.finditer(m):
        names.add(x.group(1))
    for x in S_GETTER_RE.finditer(m):
        names.add(x.group(1))
    for x in S_FUNC_RE.finditer(m):
        if x.group(1) not in ('get', 'of'):
            funcs.add(x.group(1))
    for x in S_ASSIGN_RE.finditer(m):
        paren = x.end() - 1
        close = balanced_call_end(m, paren)
        if close < 0:
            continue
        rest = m[close + 1:close + 40].lstrip()
        # `x = S.of(context);` binds S. `x = S.of(context).foo` does not.
        if rest[:1] in (';', ',', ')', '}', ']', ''):
            # A named argument `s: S.of(context)` names a parameter, not a local,
            # but that parameter is declared `S s` in its own file anyway.
            names.add(x.group(1))
    names.discard('S')
    return names, funcs


NOT_TYPES = {'return', 'get', 'set', 'await', 'case', 'else', 'new', 'throw',
             'yield', 'is', 'as', 'in', 'on', 'if', 'do', 'when', 'with', 'async',
             'sync', 'default', 'assert', 'break', 'continue', 'extends',
             'implements', 'required', 'covariant', 'this', 'super', 'show',
             'hide', 'of', 'part', 'import', 'export'}


class Binding:
    __slots__ = ('pos', 'kind', 'scope_end')

    def __init__(self, pos: int, kind: str, scope_end: int):
        self.pos = pos
        self.kind = kind            # 'S', 'nonS' or 'untyped'
        self.scope_end = scope_end


def _tok_index_at(df: DartFile, pos: int) -> int:
    return bisect.bisect_right(df.tok_pos, pos) - 1


def binding_scope_end(df: DartFile, pos: int) -> int:
    """Where a name bound at [pos] stops being visible, approximately.

    * a parameter of a function or closure: the end of that function's body
      (a block body, or an arrow body up to the ';' or bracket that ends it)
    * a for-in or catch variable: the end of the statement it heads
    * a local or a field: the end of the block or class body holding it
    """
    ti = _tok_index_at(df, pos)
    op = df.parent[ti] if ti >= 0 else -1
    if op < 0:
        return len(df.masked)
    close = df.match.get(op, len(df.toks) - 1)
    ch = df.toks[op].text
    # Named or optional parameters: `({required S s})` or `(a, [S? s])`. The
    # braces close right before the parameter list does, so the list is the
    # real scope holder.
    if ch in ('{', '[') and df.parent[op] >= 0:
        outer = df.parent[op]
        if df.toks[outer].text == '(' and df.match.get(outer) == close + 1:
            op, close, ch = outer, close + 1, '('
    if ch != '(':
        return df.toks[close].pos
    prev = df.toks[op - 1].text if op > 0 else ''
    nx = close + 1
    while nx < len(df.toks) and df.toks[nx].text in ('async', 'sync', '*'):
        nx += 1
    nxt = df.toks[nx].text if nx < len(df.toks) else ''
    if prev in ('for', 'catch') or nxt in ('{', '=>'):
        if nxt == '{' and nx in df.match:
            return df.toks[df.match[nx]].pos
        # Arrow body or a single statement: up to ';' or ',' at this depth, or
        # the bracket that closes the group around it.
        depth = 0
        k = nx + 1 if nxt == '=>' else nx
        outer = df.parent[op]
        outer_close = df.match.get(outer, len(df.toks) - 1) if outer >= 0 else len(df.toks) - 1
        while k < len(df.toks) and k < outer_close:
            t = df.toks[k].text
            if t in OPEN:
                k = df.match.get(k, k) + 1
                continue
            if t in (';', ','):
                return df.toks[k].pos
            k += 1
        return df.toks[min(outer_close, len(df.toks) - 1)].pos
    return df.toks[close].pos


def collect_bindings(df: DartFile, ident: str) -> list[Binding]:
    """Every place [ident] is introduced as a name, and whether it is an S."""
    m = df.masked
    e = re.escape(ident)
    out: list[Binding] = []
    seen: set[int] = set()

    def add(pos: int, kind: str) -> None:
        if pos in seen:
            return
        seen.add(pos)
        out.append(Binding(pos, kind, binding_scope_end(df, pos)))

    typed = re.compile(
        rf'(?<![\w$.])([A-Za-z_$][\w$]*(?:\s*<[^;{{}}()=]*>)?\??)\s+({e})(?![\w$])\s*(?=[=;,)}}\]:]|in\b)')
    for x in typed.finditer(m):
        tname = re.sub(r'\s+', '', x.group(1))
        if tname in NOT_TYPES:
            continue
        pos = x.start(2)
        base = tname.rstrip('?')
        if base == 'S':
            add(pos, 'S')
            continue
        if base in ('final', 'var', 'const', 'late'):
            after = m[x.end(2):x.end(2) + 80]
            if re.match(r'\s*in\b', after):
                add(pos, 'nonS')
            elif re.match(r'\s*=\s*S\s*(\.\s*of\s*)?\(', after):
                add(pos, 'S')
            elif re.match(r'\s*=', after):
                add(pos, 'nonS')
            else:
                add(pos, 'untyped')
            continue
        add(pos, 'nonS')
    # Untyped closure parameters: (s) =>, (s, i) {, (i, s) =>
    for x in re.finditer(rf'[(,]\s*({e})\s*(?=[,)])', m):
        pos = x.start(1)
        if pos in seen:
            continue
        ti = _tok_index_at(df, pos)
        op = df.parent[ti] if ti >= 0 else -1
        if op < 0 or df.toks[op].text != '(':
            continue
        close = df.match.get(op)
        if close is None or close + 1 >= len(df.toks):
            continue
        nx = close + 1
        while nx < len(df.toks) and df.toks[nx].text in ('async', 'sync', '*'):
            nx += 1
        if df.toks[nx].text not in ('=>', '{'):
            continue
        # A call like foo(s) { is not valid Dart, so ( ... ) => / { is a closure
        # or a function signature, unless the thing before '(' is a control word.
        before = df.toks[op - 1].text if op > 0 else ''
        if before in ('if', 'while', 'switch', 'for', 'catch'):
            continue
        # A named function declaration `void f(s) {` would have a type before s;
        # a bare identifier list is a closure's parameters.
        add(pos, 'untyped')
    # Plain assignment `s = S.of(context);` to an existing field or variable.
    for x in re.finditer(rf'(?<![\w$.])({e})\s*=\s*S\s*(\.\s*of\s*)?\(', m):
        add(x.start(1), 'S')
    out.sort(key=lambda b: b.pos)
    return out


def is_named_arg_label(masked: str, start: int, end: int) -> bool:
    """`foo(level: 3)`: the word before ':' names a parameter, it is no use."""
    k = end
    while k < len(masked) and masked[k] in ' \t\n':
        k += 1
    if k >= len(masked) or masked[k] != ':' or masked.startswith('::', k):
        return False
    j = start - 1
    while j >= 0 and masked[j] in ' \t\n':
        j -= 1
    return j >= 0 and masked[j] in '(,{'


def resolve_receiver(bindings: list[Binding], pos: int) -> str | None:
    """Kind of the innermost binding visible at [pos], or None if none is."""
    best = None
    for b in bindings:
        if b.pos < pos <= b.scope_end:
            if best is None or b.pos > best.pos:
                best = b
    return best.kind if best else None


# ─── 5. Screen names ─────────────────────────────────────────────────────────

SCREEN_OVERRIDES = OrderedDict([
    ('lib/main.dart', 'App start and shell (main.dart)'),
    ('lib/core/services/notification_service.dart', 'Local notifications'),
    ('lib/core/services/push_notification_service.dart', 'Push notifications (client)'),
    ('lib/core/services/home_widget_service.dart', 'Home screen widgets'),
    ('lib/core/services/notification_action_background.dart', 'Local notifications (buttons under a reminder)'),
    ('lib/core/services/alarm_service.dart', 'Ringing alarms (AlarmKit, through the platform channel)'),
    ('lib/core/theme/game_theme.dart', 'App theme and fonts'),
    ('lib/features/auth/screens/auth_screen.dart', 'Sign-in screen'),
    ('lib/features/auth/screens/set_new_password_screen.dart', 'Set new password screen'),
    ('lib/features/auth/widgets/reconnect_guest_sheet.dart', 'Move guest data sheet'),
    ('lib/features/auth/widgets/language_toggle.dart', 'Sign-in screen'),
    ('lib/features/auth/widgets/social_sign_in_buttons.dart', 'Sign-in screen'),
    ('lib/features/premium/screens/premium_screen.dart', 'Premium paywall'),
    ('lib/features/profile/screens/help_support_screen.dart', 'Help and Support'),
    ('lib/features/profile/screens/profile_screen_settings.dart', 'Settings'),
    ('lib/features/profile/screens/profile_screen_sheets.dart', 'Settings: language, theme and font sheets'),
    ('lib/features/profile/screens/profile_screen.dart', 'Profile'),
    ('lib/features/profile/screens/profile_screen_banners.dart', 'Profile'),
    ('lib/features/profile/screens/profile_screen_hero_dashboard.dart', 'Profile'),
    ('lib/features/profile/screens/progress_hub_screen.dart', 'Progress hub'),
    ('lib/features/profile/screens/progress_day_chart.dart', 'Progress hub'),
    ('lib/features/profile/screens/achievements_screen.dart', 'Achievements'),
    ('lib/features/profile/screens/theme_preview_screen.dart', 'Theme preview'),
    ('lib/features/profile/widgets/delete_account_sheet.dart', 'Delete account sheet'),
    ('lib/features/profile/widgets/edit_name_sheet.dart', 'Edit name sheet'),
    ('lib/features/profile/widgets/stat_info_sheet.dart', 'Profile'),
    ('lib/features/grid/screens/grid_screen.dart', 'Habits grid'),
    ('lib/features/grid/screens/grid_screen_table.dart', 'Habits grid'),
    ('lib/features/grid/screens/grid_screen_summary.dart', 'Habits grid'),
    ('lib/features/grid/screens/grid_screen_misc.dart', 'Habits grid'),
    ('lib/features/grid/screens/grid_screen_cell_editor.dart', 'Habits grid'),
    ('lib/features/grid/screens/grid_screen_reorder_sheet.dart', 'Habits grid'),
    ('lib/features/grid/screens/grid_journal_screen.dart', 'Habit notes journal'),
    ('lib/features/grid/screens/monthly_heatmap_screen.dart', 'Monthly heatmap'),
    ('lib/features/grid/widgets/weekly_recap_card.dart', 'Habits grid: weekly recap card'),
    ('lib/features/grid/widgets/daily_quote_line.dart', 'Habits grid: daily quote'),
    ('lib/features/grid/widgets/habit_note_block.dart', 'Habit note block (journal, heatmap, progress hub)'),
    ('lib/features/habits/widgets/add_habit_sheet.dart', 'Add or edit habit'),
    ('lib/features/habits/widgets/add_habit_sheet_small_widgets.dart', 'Add or edit habit'),
    ('lib/features/habits/widgets/add_habit_hub_sheet.dart', 'Add habit hub (plans and goals)'),
    ('lib/features/habits/widgets/plan_picker_sheet.dart', 'Habit plans picker'),
    ('lib/features/habits/widgets/habit_actions_sheet.dart', 'Habit actions menu'),
    ('lib/features/habits/widgets/habit_offset_sheet.dart', 'Habit reminder offset sheet'),
    ('lib/features/habits/widgets/pause_until_sheet.dart', 'Pause habit sheet'),
    ('lib/features/habits/widgets/steps_day_card.dart', 'Steps day card'),
    ('lib/features/habits/widgets/habit_color_picker.dart', 'Habit colour picker'),
    ('lib/features/matrix/screens/matrix_screen.dart', 'Tasks'),
    ('lib/features/matrix/screens/matrix_history_screen.dart', 'Tasks history'),
    ('lib/features/matrix/widgets/add_task_sheet.dart', 'Tasks: add task sheet'),
    ('lib/features/matrix/widgets/task_detail_sheet.dart', 'Tasks: task detail sheet'),
    ('lib/features/matrix/widgets/reminder_picker.dart', 'Tasks: reminder picker'),
    ('lib/features/matrix/widgets/custom_offset_sheet.dart', 'Tasks: custom reminder offset sheet'),
    ('lib/features/matrix/widgets/edit_quadrant_sheet.dart', 'Tasks: edit quadrant sheet'),
    ('lib/features/matrix/widgets/move_task_sheet.dart', 'Tasks: move task sheet'),
    ('lib/features/matrix/widgets/quadrant_card.dart', 'Tasks: quadrant card'),
    ('lib/features/matrix/widgets/quadrant_card_animated_stack.dart', 'Tasks: quadrant card'),
    ('lib/features/matrix/widgets/quadrant_card_task_tile.dart', 'Tasks: quadrant card'),
    ('lib/features/matrix/widgets/quadrant_card_tile_helpers.dart', 'Tasks: quadrant card'),
    ('lib/features/matrix/widgets/quadrant_card_expanded_screen.dart', 'Tasks: expanded quadrant'),
    ('lib/features/matrix/widgets/voice_note_player.dart', 'Voice note player'),
    ('lib/features/matrix/widgets/reward_float.dart', 'Tasks: reward float'),
    ('lib/features/rooms/screens/rooms_hub_screen.dart', 'Rooms hub'),
    ('lib/features/rooms/screens/room_detail_screen.dart', 'Room page'),
    ('lib/features/rooms/screens/room_detail_screen_countdown_finale.dart', 'Room page'),
    ('lib/features/rooms/screens/room_detail_screen_header_progress.dart', 'Room page'),
    ('lib/features/rooms/screens/room_detail_screen_leaderboard_extend.dart', 'Room page'),
    ('lib/features/rooms/screens/room_detail_screen_lobby.dart', 'Room page'),
    ('lib/features/rooms/screens/room_detail_screen_participant_calendar.dart', 'Room page: member calendar'),
    ('lib/features/rooms/widgets/create_room_sheet.dart', 'Create room sheet'),
    ('lib/features/rooms/widgets/join_room_sheet.dart', 'Join room sheet'),
    ('lib/features/rooms/widgets/report_member_sheet.dart', 'Report or block member sheet'),
    ('lib/features/rooms/widgets/pick_own_habit_sheet.dart', 'Room: pick own habit sheet'),
    ('lib/features/rooms/widgets/resolve_new_shared_habits_sheet.dart', 'Room: link new shared habits sheet'),
    ('lib/features/rooms/widgets/room_finale_announcer.dart', 'Room finale announcement'),
    ('lib/features/rooms/widgets/room_reactions.dart', 'Room live reactions'),
    ('lib/features/night_review/screens/night_review_screen.dart', 'Night Review'),
    ('lib/features/night_review/screens/night_review_history_screen.dart', 'Night Review history'),
    ('lib/features/settings/screens/notification_settings_screen.dart', 'Notification settings'),
    ('lib/features/settings/screens/nav_bar_settings_screen.dart', 'Bottom bar settings'),
    ('lib/features/settings/widgets/city_search_sheet.dart', 'Prayer location search sheet'),
    ('lib/features/insights/insights_screen.dart', 'Insights'),
    ('lib/features/milestones/reports/reports_screen.dart', 'Reports'),
    ('lib/features/milestones/reports/period_report_section.dart', 'Reports'),
    ('lib/features/milestones/reports/report_sections.dart', 'Reports'),
    ('lib/features/milestones/reports/habit_detail_sheet.dart', 'Habit detail sheet'),
    ('lib/features/milestones/screens/journey_screen.dart', 'Journey'),
    ('lib/features/milestones/screens/life_timeline_screen.dart', 'Life timeline'),
    ('lib/features/character/screens/character_closet_screen.dart', 'Character closet'),
    ('lib/features/character/screens/prestige_picker_sheet.dart', 'Prestige rank picker'),
    ('lib/features/character/widgets/accessory_detail_sheet.dart', 'Character closet: accessory detail'),
    ('lib/features/character/widgets/accessory_shop_tile.dart', 'Character closet'),
    ('lib/features/character/widgets/character_locked_sheet.dart', 'Character closet: locked character'),
    ('lib/features/character/widgets/rank_up_celebration.dart', 'Rank-up celebration'),
    ('lib/features/character/widgets/prestige_mark.dart', 'Prestige rank mark'),
    ('lib/features/dashboard/widgets/reaction_overlays.dart', 'Celebrations (level up, achievements, milestones)'),
    ('lib/features/achievements/widgets/tier_detail_sheet.dart', 'Achievement detail sheet'),
    ('lib/features/achievements/widgets/achievement_medal.dart', 'Achievements'),
    ('lib/features/rewards/screens/custom_rewards_screen.dart', 'My Rewards'),
    ('lib/features/rewards/widgets/custom_reward_sheet.dart', 'My Rewards: add or edit reward'),
    ('lib/features/rewards/widgets/custom_rewards_entry_card.dart', 'My Rewards entry card'),
    ('lib/features/onboarding/screens/onboarding_screen.dart', 'Onboarding slides'),
    ('lib/features/onboarding/screens/first_run_offer_screen.dart', 'First-run guide offer'),
    ('lib/features/onboarding/screens/app_guide_screen.dart', 'App Guide'),
    ('lib/features/onboarding/notifiers/guide_steps_provider.dart', 'App Guide'),
    ('lib/features/tasbih/tasbih_screen.dart', 'Tasbih counter'),
    ('lib/shared/widgets/home_shell.dart', 'Bottom navigation bar'),
    ('lib/shared/widgets/nav_tabs.dart', 'Bottom navigation bar'),
    ('lib/shared/widgets/game_nav_bar.dart', 'Bottom navigation bar'),
    ('lib/shared/providers/nav_badges_provider.dart', 'Bottom navigation bar'),
    ('lib/shared/widgets/comeback_card.dart', 'Comeback card'),
    ('lib/shared/widgets/get_started_checklist_card.dart', 'Get started checklist'),
    ('lib/shared/widgets/history_demo_gate.dart', 'Premium history demo gate'),
    ('lib/shared/widgets/guest_limit_sheet.dart', 'Guest limit sheet'),
    ('lib/shared/widgets/habit_limit_gate.dart', 'Habit limit gate'),
    ('lib/shared/widgets/reminder_limit_gate.dart', 'Reminder limit gate'),
    ('lib/shared/widgets/voice_note_gate.dart', 'Voice note gate'),
    ('lib/shared/widgets/month_picker_sheet.dart', 'Month picker sheet'),
    ('lib/shared/widgets/week_picker_sheet.dart', 'Week picker sheet'),
    ('lib/shared/widgets/coach_mark_overlay.dart', 'Coach marks'),
    ('lib/shared/widgets/reminder_style_choice.dart', 'Reminder style choice (notification or alarm)'),
])

FEATURE_LABELS = {
    'achievements': 'Achievements',
    'auth': 'Sign-in',
    'character': 'Character closet',
    'dashboard': 'Progression',
    'grid': 'Habits grid',
    'habits': 'Habits',
    'insights': 'Insights',
    'language': 'Language',
    'matrix': 'Tasks',
    'milestones': 'Reports',
    'night_review': 'Night Review',
    'onboarding': 'Onboarding',
    'premium': 'Premium',
    'profile': 'Profile',
    'rewards': 'My Rewards',
    'rooms': 'Rooms',
    'settings': 'Settings',
    'tasbih': 'Tasbih',
    'user': 'Account',
}
AREA_LABELS = {
    ('core', 'services'): 'Service',
    ('core', 'providers'): 'App state',
    ('core', 'theme'): 'Theme',
    ('core', 'utils'): 'Utility',
    ('core', 'constants'): 'Constants',
    ('core', 'extensions'): 'Date helpers',
    ('core', 'l10n'): 'Wording library',
    ('shared', 'widgets'): 'Shared widget',
    ('shared', 'providers'): 'Shared state',
}


# Files named after the screen they feed, but which are logic, not a place
# text shows: a use there is followed on to its own users.
NON_SURFACE_OVERRIDES = {'lib/core/theme/game_theme.dart'}
SURFACE_SUFFIXES = ('_screen', '_sheet', '_card', '_overlay', '_overlays', '_dialog', '_page', '_view')


def is_surface(rel: str) -> bool:
    """A file whose code draws what a person reads (a screen, a sheet, a
    widget, a notification), as opposed to a model, notifier or service."""
    if rel in NON_SURFACE_OVERRIDES:
        return False
    if rel in SCREEN_OVERRIDES or rel == 'lib/main.dart':
        return True
    parts = rel.split('/')
    if any(p in ('screens', 'widgets', 'reports') for p in parts[:-1]):
        return True
    return os.path.splitext(parts[-1])[0].endswith(SURFACE_SUFFIXES)


def is_widget_file(rel: str) -> bool:
    """A surface file that holds widgets. The service surfaces (notification
    and home widget services) and main.dart hold data classes too, such as
    HabitReminderInput, so text handed to one of those is followed on."""
    return is_surface(rel) and not rel.startswith('lib/core/') and rel != 'lib/main.dart'


def humanize(stem: str) -> str:
    words = stem.replace('_', ' ').strip()
    return words[:1].upper() + words[1:]


def screen_for(rel: str) -> str:
    if rel in SCREEN_OVERRIDES:
        return SCREEN_OVERRIDES[rel]
    parts = rel.split('/')
    stem = os.path.splitext(parts[-1])[0]
    if len(parts) >= 3 and parts[1] == 'features':
        label = FEATURE_LABELS.get(parts[2], humanize(parts[2]))
        sub = parts[3] if len(parts) > 4 else ''
        nice = humanize(stem).lower()
        if sub == 'models':
            return f'{label}: {nice} (model)'
        if sub == 'notifiers':
            return f'{label}: {nice} (logic)'
        if nice.lower() == label.lower():
            return label
        return f'{label}: {nice}'
    if len(parts) >= 3 and (parts[1], parts[2]) in AREA_LABELS:
        return f'{AREA_LABELS[(parts[1], parts[2])]}: {humanize(stem).lower()}'
    return humanize(stem)


# ─── Library grouping (part / part of) ───────────────────────────────────────

def library_roots(files: dict[str, DartFile]) -> dict[str, str]:
    root = {rel: rel for rel in files}
    for rel, df in files.items():
        m = re.search(r"^part\s+of\s+'([^']+)'\s*;", df.src, re.M)
        if m:
            target = os.path.normpath(os.path.join(os.path.dirname(rel), m.group(1)))
            if target in files:
                root[rel] = target
    return root


# ─── Main ────────────────────────────────────────────────────────────────────

def run_analyzer():
    """Run bin/verify_usage.dart once. Returns (data, error)."""
    import subprocess
    import tempfile
    gen = os.path.dirname(os.path.abspath(__file__))
    with tempfile.TemporaryDirectory() as tmp:
        refs_path = os.path.join(tmp, 'analyzer_refs.json')
        proc = subprocess.run(['dart', 'run', 'bin/verify_usage.dart', REPO, refs_path],
                              cwd=gen, capture_output=True, text=True)
        if proc.returncode != 0 or not os.path.exists(refs_path):
            return None, (proc.stderr or proc.stdout)[-2000:]
        with open(refs_path, encoding='utf-8') as fh:
            return json.load(fh), None


COPY_FILES_SKIPPED = (APP_STRINGS, REMINDER_COPY, DAILY_QUOTES)
MAX_CHAIN = 10
CHAIN_FAN_OUT = 25
HUB_SCREENS = 12


class _Graph:
    """The analyzer's references, with where each referenced value goes.

    A target is ('m', file, container, name) for a member, or ('p', key) for a
    parameter (key "file|container|member|parameter"). Each reference is
    (using file, line, using container, using member, flows, receiver
    constant), where flows is the list of flow strings verify_usage.dart
    wrote (R, F|..., P|..., XD|..., XS|..., XU|..., D, U|...).
    """

    def __init__(self, data):
        mr = data['member_refs']
        names = mr['files']
        self.flow_table = [f.split(' ') if f else [] for f in mr['flows']]
        self.by_target = defaultdict(list)
        for t_f, t_c, t_n, u_f, line, u_c, u_m, fl, recv in mr['rows']:
            self.by_target[('m', names[t_f], t_c, t_n)].append(
                (names[u_f], line, u_c, u_m, self.flow_table[fl], recv))
        self.params = {}
        for key, rows in data['param_refs']['rows'].items():
            f = key.split('|')[0]
            self.params[('p', key)] = [(f, line, uc, um, self.flow_table[fl], '')
                                       for line, fl, uc, um in rows]
        self.ctor_args = defaultdict(list)
        for f, start, end, param, fl in data['ctor_args']['rows']:
            self.ctor_args[names[f]].append((start, end, param, self.flow_table[fl]))
        self.enums = {(f, n) for f, n in data['enums']}
        self.non_text = set(data.get('non_text_members', []))
        self.literals = defaultdict(list)
        for f, line, fl, uc, um in data.get('literals', {}).get('rows', []):
            self.literals[(names[f], line)].append((self.flow_table[fl], uc, um))
        self.memo = {}

    def refs(self, target):
        if target[0] == 'm':
            return self.by_target.get(target, [])
        got = self.params.get(target)
        if got is None and target[1].count('|') == 4:
            # No per-field entry (not a record parameter): the whole parameter.
            got = self.params.get(('p', target[1].rsplit('|', 1)[0]))
        return got or []

    @staticmethod
    def label(target) -> str:
        if target[0] == 'm':
            _, _, c, n = target
            return f'{c}.{n}' if c else n
        f, c, m, p = target[1].split('|')[:4]
        return f"{c + '.' if c and m != 'new' else ''}{c if m == 'new' else m}({p})"

    @staticmethod
    def sink_target(sink: str):
        k = sink.split('|')
        if k[0] == 'F':
            return ('m', k[1], k[2], k[3])
        if k[0] == 'P':
            return ('p', '|'.join(k[1:]))
        return None

    def resolve(self, target, stack=(), recv_ok=None, ret=None):
        """Places where the text a target holds is shown or stored. Each place
        is {kind: display|stored, file, line, screens, via, note, deep}.
        Returns (places, cut): cut when a loop back into the walk was dropped,
        so the answer is only complete for the walk that started it.

        ret: for a parameter target reached from one call, that call's own
        reference and the Q flows of its result, so a callee that hands the
        parameter back (return text) continues at THAT call instead of at
        every call of the callee."""
        memoable = recv_ok is None and ret is None
        if memoable and target in self.memo:
            return self.memo[target], False
        out, seen, cut = [], set(), [False]

        def add(p):
            k = (p['kind'], p['file'], p['line'], tuple(p['via']), p['note'])
            if k not in seen:
                seen.add(k)
                out.append(p)

        for ref in sorted(set((a, b, c, d, tuple(e), f) for a, b, c, d, e, f in self.refs(target))):
            if recv_ok is not None and ref[5] and not set(ref[5].split('||')) & recv_ok:
                continue  # the member read on another enum constant, or in another case
            self._sinks(ref, ref[4], target, stack, add, cut, ret)
        if memoable and (not cut[0] or not stack):
            self.memo[target] = out
        return out, cut[0]

    def _sinks(self, ref, flows, target, stack, add, cut, ret):
        uf, line, uc, um = ref[:4]
        surface = is_surface(uf)
        site = {'kind': 'display', 'file': uf, 'line': line, 'screens': [screen_for(uf)],
                'via': [], 'note': '', 'deep': False}
        results = [x[1:] for x in flows if x.startswith('Q')]
        for sink in flows:
            if sink.startswith('Q'):
                continue
            kind = sink.split('|')[0]
            if kind == 'D':
                continue
            if kind == 'XS':
                add({**site, 'kind': 'stored', 'screens': []})
                continue
            if kind in ('XD', 'XU'):
                add(site)
                continue
            sub_ret = None
            here_if_shown = False
            if kind in ('R', 'U'):
                if ret is not None and target[0] == 'p':
                    # The callee hands the parameter back: carry on from the
                    # call that passed it.
                    call_ref, call_flows = ret
                    self._sinks(call_ref, call_flows, target, stack, add, cut, None)
                    continue
                if not um:
                    add(site)
                    continue
                nxt = ('m', uf, uc, um)
            else:
                nxt = self.sink_target(sink)
                if nxt is None:
                    continue
                nxt_file = nxt[1] if nxt[0] == 'm' else nxt[1].split('|')[0]
                if surface and is_widget_file(nxt_file):
                    if nxt_file != uf:
                        # Handed to a widget of another screen file: it
                        # shows here, as part of this screen.
                        add(site)
                        continue
                    # A widget or state field of this same file: it shows
                    # here only if that field or parameter is drawn (a
                    # selection key compared with == is not).
                    here_if_shown = True
                if nxt[0] == 'p' and results:
                    sub_ret = (ref, results)
            if nxt == target or nxt in stack:
                cut[0] = True
                continue
            if len(stack) >= MAX_CHAIN:
                add({**site, 'deep': True})
                continue
            subs, sub_cut = self.resolve(nxt, stack + (target,), None, sub_ret)
            cut[0] = cut[0] or sub_cut
            if not subs:
                if surface and kind in ('R', 'U') and not self.refs(nxt):
                    # Nothing calls the member that hands it back (a build
                    # method or a callback): it shows where it is written.
                    add(site)
                continue
            if here_if_shown:
                if any(x['kind'] == 'display' for x in subs):
                    add(site)
                if any(x['kind'] == 'stored' for x in subs):
                    add({**site, 'kind': 'stored', 'screens': []})
                continue
            shown = [x for x in subs if x['kind'] == 'display']
            stored = [x for x in subs if x['kind'] == 'stored']
            step = self.label(nxt)
            hub = (kind in ('R', 'U') and um.endswith('Provider') and not uc) or len(shown) > CHAIN_FAN_OUT
            if hub and shown:
                best = prefer_shallow(shown)
                screens = list(OrderedDict((sc, None) for x in best for sc in x['screens']))
                if len(screens) > HUB_SCREENS:
                    screens = [f'Many screens, through {step}']
                add({**site, 'screens': screens, 'deep': all(x['deep'] for x in shown),
                     'note': f'in {step}, which reaches {len(shown)} places'})
            else:
                for x in shown:
                    add({**x, 'via': [step] + x['via']})
            for x in stored:
                add({**x, 'via': [step] + x['via']})


def prefer_shallow(uses: list[dict]) -> list[dict]:
    shallow = [u for u in uses if not u['deep']]
    return shallow or uses


def usage_text(u: dict) -> str:
    text = f"{u['file']}:{u['line']}"
    if u['via']:
        text += f" (via {' > '.join(u['via'])})"
    if u['note']:
        text += f" ({u['note']})"
    return text


def _split_usage(text: str) -> tuple[str, list[str], list[str]]:
    """'file:line (via A > B; or via C) (in X, which reaches N places)' as
    (place, via chains, notes). 'directly' stands for no chain."""
    place, _, rest = text.partition(' ')
    vias, notes = [], []
    i = 0
    while i < len(rest):
        if rest[i] != '(':
            i += 1
            continue
        depth, j = 0, i
        while j < len(rest):
            if rest[j] == '(':
                depth += 1
            elif rest[j] == ')':
                depth -= 1
                if depth == 0:
                    break
            j += 1
        group = rest[i + 1:j]
        if group.startswith('via ') or group.startswith('directly'):
            for part in re.split(r'; or ', group):
                part = part[4:] if part.startswith('via ') else ''
                if part not in vias:
                    vias.append(part)
        elif group not in notes:
            notes.append(group)
        i = j + 1
    return place, vias or [''], notes


def merge_usage_texts(texts: list[str]) -> list[str]:
    """One line per file:line. When several chains reach the same place,
    the chains are merged, shortest first: 'file:line (via A; or via B > C)',
    or '(directly; or via A)' when the text also reaches it with no step in
    between. Order follows the first time each place appears."""
    groups: OrderedDict[str, tuple[list[str], list[str]]] = OrderedDict()
    for t in texts:
        place, vias, notes = _split_usage(t)
        g = groups.setdefault(place, ([], []))
        g[0].extend(v for v in vias if v not in g[0])
        g[1].extend(n for n in notes if n not in g[1])
    out = []
    for place, (vias, notes) in groups.items():
        text = place
        vias = sorted(vias, key=lambda v: (v.count(' > ') if v else -1, len(v), v))
        if vias != ['']:
            parts = ['directly' if not v else f'via {v}' for v in vias]
            text += f" ({'; or '.join(parts)})"
        for n in notes:
            text += f' ({n})'
        out.append(text)
    return out


def resolve_calls(graph: _Graph, target, stack=()) -> list[dict]:
    """Places that CALL a member, whatever happens to its value: how an iOS
    permission sheet is reached (the call opens the sheet, nothing is shown
    from its result). A call inside logic is followed to the callers of the
    member that holds it."""
    out, seen = [], set()
    for uf, line, uc, um, _flows, _recv in sorted(set(
            (a, b, c, d, tuple(e), f) for a, b, c, d, e, f in graph.refs(target))):
        nxt = ('m', uf, uc, um)
        site = {'file': uf, 'line': line, 'screens': [screen_for(uf)], 'via': [], 'note': '', 'deep': False}
        if nxt == target or nxt in stack:
            finals = []
        elif is_surface(uf) or not um:
            finals = [site]
        elif len(stack) >= MAX_CHAIN:
            finals = [{**site, 'deep': True}]
        else:
            subs = resolve_calls(graph, nxt, stack + (target,))
            if not subs:
                finals = []
            elif (um.endswith('Provider') and not uc) or len(subs) > CHAIN_FAN_OUT:
                shown = prefer_shallow(subs)
                screens = list(OrderedDict((sc, None) for sub in shown for sc in sub['screens']))
                if len(screens) > HUB_SCREENS:
                    screens = [f'Many screens, through {_Graph.label(nxt)}']
                finals = [{**site, 'screens': screens, 'deep': all(sub['deep'] for sub in subs),
                           'note': f'in {_Graph.label(nxt)}, which reaches {len(subs)} places'}]
            else:
                finals = [{**sub, 'via': [_Graph.label(nxt)] + sub['via']} for sub in subs]
        for f in finals:
            k = (f['file'], f['line'], tuple(f['via']))
            if k not in seen:
                seen.add(k)
                out.append(f)
    return out


def _case_names(row) -> set[str] | None:
    """The enum constants a per-case row stands for: [levelUp] or
    [faith || quran]. None when the key names no case."""
    m = re.search(r'\[([^\[\]]+)\]$', row['key'])
    if not m:
        return None
    names = {p.strip() for p in m.group(1).split('||')}
    if not all(re.fullmatch(r'[A-Za-z_$][\w$]*', n) for n in names):
        return None
    return names


def dart_row_usage(dart_rows, native_rows, data) -> tuple[OrderedDict, OrderedDict]:
    """Where each Dart row outside app_strings, reminder_copy and daily_quotes
    shows, from the analyzer's member references and flows (see step 7)."""
    graph = _Graph(data)

    result: OrderedDict[str, dict] = OrderedDict()
    no_refs, stored_only, field_rows, case_filtered = [], [], [], []
    for row in native_rows:
        # A native row whose text a Dart call brings up (an iOS permission
        # sheet): the screens behind that call.
        targets = [('m',) + tuple(t.split('|')) for t in row.get('usage_targets') or []]
        if not targets:
            continue
        uses = []
        for t in targets:
            for u in resolve_calls(graph, t):
                if u not in uses:
                    uses.append(u)
        uses = prefer_shallow(uses)
        uses.sort(key=lambda u: (u['file'], u['line'], u['via']))
        entry = OrderedDict()
        entry['targets'] = ['|'.join(t[1:]) for t in targets]
        entry['usages'] = merge_usage_texts([usage_text(u) for u in uses])
        entry['screens'] = list(OrderedDict((sc, None) for u in uses for sc in u['screens']))
        entry['usage_count'] = len(entry['usages'])
        entry['in_place'] = False
        entry['unused'] = False
        result[row['id']] = entry

    for row in dart_rows:
        f = row['file']
        if f in COPY_FILES_SKIPPED:
            continue
        m = row.get('member') or {}
        cls, name, kind = m.get('class') or '', m.get('name') or '', m.get('kind') or ''
        if not name or name == '(unknown)':
            continue
        container = None
        how = ''
        if kind == 'enum-constant':
            targets = [('m', f, cls, pf) for pf in row.get('pair_fields') or []]
        elif kind in ('getter', 'method', 'function', 'field'):
            targets = [('m', f, cls, name)]
            pair = row.get('pair_fields') or []
            if row.get('shape') == 'named-pair' and pair:
                # A catalog entry: the text lives in the fields the constructor
                # arguments fill, and shows wherever THOSE are read, not
                # wherever the list holding the entry is.
                lines = {row.get('ar_line'), row.get('en_line'), row.get('text_line')} - {None}
                found = []
                for start, end, param, flows in graph.ctor_args.get(f, []):
                    if param in pair and any(start <= ln <= end for ln in lines):
                        for sink in flows:
                            t = graph.sink_target(sink)
                            if t is not None and t not in found:
                                found.append(t)
                if found:
                    container = targets[0]
                    targets = found
                    how = 'fields'
                    field_rows.append(row['id'])
        else:
            targets = []
        in_place_shown = False

        def take_one(u):
            if u not in places:
                places.append(u)

        recv_ok = None
        cases = _case_names(row)
        if cases is not None and (f, cls) in graph.enums:
            recv_ok = cases
            case_filtered.append(row['id'])
        places = []

        def take(got):
            for u in got:
                if u not in places:
                    places.append(u)

        # Where the row's own literals go inside the member (verify_usage.dart
        # "literals"): handed back (R), shown by the member itself (XD, a
        # thrown exception or a notification), stored in a field or passed on.
        lit_flows = []
        if kind in ('method', 'function', 'getter') and len(targets) == 1 and how != 'fields':
            for ln in sorted({row.get('ar_line'), row.get('en_line'), row.get('text_line')} - {None}):
                for flows, uc, um in graph.literals.get((f, ln), []):
                    if uc == cls and um == name:
                        lit_flows += [x for x in flows if x not in lit_flows]
        if lit_flows:
            kinds = {x.split('|')[0] for x in lit_flows if not x.startswith('Q')}
            shown_here = bool(kinds & {'XD', 'XU'})
            rest = [x for x in lit_flows if x.split('|')[0] in ('F', 'P', 'XS')
                    or (x.startswith('Q') and 'P' in kinds)]
            if rest:
                line0 = row.get('text_line') or row['line']
                here = []
                graph._sinks((f, line0, cls, name), rest, ('lit', f, line0), (), here.append, [False], None)
                for u in here:
                    if (u['kind'], u['file'], u['line'], u['via']) == ('display', f, line0, []):
                        # Handed straight to a widget where it is written.
                        shown_here = True
                    else:
                        take_one(u)
            if kinds & {'R', 'U'}:
                take(graph.resolve(targets[0], (), recv_ok)[0])
            if shown_here:
                # Shown by the member when it runs: where it is called, or
                # where it is written when nothing calls it (a build method).
                calls = resolve_calls(graph, targets[0])
                take([{**u, 'kind': 'display'} for u in calls])
                if not calls:
                    in_place_shown = True
        else:
            by_call = (kind in ('method', 'function', 'getter')
                       and f'{f}|{cls}|{name}' in graph.non_text and len(targets) == 1)
            for t in targets:
                if by_call:
                    # The member returns nothing that carries text, so its
                    # wording is shown by the member itself when it runs.
                    take([{**u, 'kind': 'display'} for u in resolve_calls(graph, t)])
                else:
                    take(graph.resolve(t, (), recv_ok)[0])
        shown = prefer_shallow([u for u in places if u['kind'] == 'display'])
        shown.sort(key=lambda u: (u['file'], u['line'], u['via']))
        stored = sorted((u for u in places if u['kind'] == 'stored'),
                        key=lambda u: (u['file'], u['line'], u['via']))
        container_unreached = container is not None and not graph.refs(container)
        if container_unreached:
            shown = []
        screens = list(OrderedDict((sc, None) for u in shown for sc in u['screens']))
        entry = OrderedDict()
        entry['targets'] = ['|'.join(t[1:]) for t in targets]
        if container is not None:
            entry['container'] = '|'.join(container[1:])
        # Several chains can reach the same line: one entry per place.
        entry['usages'] = merge_usage_texts([usage_text(u) for u in shown])
        entry['screens'] = screens
        entry['usage_count'] = len(entry['usages'])
        entry['stored'] = merge_usage_texts([usage_text(u) for u in stored])
        # build() and constructors are called by the framework or by a
        # constructor call, which is not a member reference: their text
        # shows where it is written.
        entry['in_place'] = not targets or (not shown and (name == 'build' or kind == 'constructor'
                                                          or in_place_shown))
        entry['unused'] = bool(targets) and not shown and not entry['in_place']
        notes = []
        if how == 'fields':
            notes.append('Usage is followed from ' + ' and '.join(_Graph.label(t) for t in targets)
                         + ', the fields this entry\'s text fills, not from the uses of '
                         + _Graph.label(container) + ', the list or constant that holds the entry.')
        if container_unreached:
            notes.append(f'Nothing in lib/ reads {_Graph.label(container)}, so this entry is never reached.')
        if entry['unused'] and stored:
            notes.append('Only written to stored data (' + '; '.join(entry['stored'][:4])
                         + ('; ...' if len(entry['stored']) > 4 else '')
                         + '). Nothing in lib/ was traced reading it back into a screen.')
            stored_only.append(row['id'])
        if notes:
            entry['notes'] = notes
        if entry['unused']:
            no_refs.append(row['id'])
        result[row['id']] = entry
    meta = OrderedDict([
        ('rows_mapped', len(result)),
        ('rows_with_usages', sum(1 for e in result.values() if e['usages'])),
        ('rows_in_place', sum(1 for e in result.values() if e['in_place'])),
        ('rows_no_reference_found', no_refs),
        ('rows_only_stored', stored_only),
        ('rows_read_through_fields', len(field_rows)),
        ('rows_filtered_by_enum_constant', len(case_filtered)),
        ('unmodelled_contexts', data.get('unmodelled_contexts', {})),
    ])
    return result, meta


def analyzer_check(members_out, top_out, data) -> OrderedDict:
    """Compare the analyzer's resolved references with ours."""
    refs = [r for r in data['refs'] if not r.get('in_comment')]
    comment_refs = sum(1 for r in data['refs'] if r.get('in_comment'))

    ana_ext = Counter((r['name'], r['file'], r['line']) for r in refs
                      if r['owner'] == 'S' and r['name'] in members_out and r['file'] != APP_STRINGS)
    ours_ext = Counter((n, u['file'], u['line']) for n, e in members_out.items()
                       for u in e['usage_details'])
    ana_int = Counter((r['name'], r['line']) for r in refs
                      if r['owner'] == 'S' and r['name'] in members_out and r['file'] == APP_STRINGS)
    ours_int = Counter()
    for n, e in members_out.items():
        # A read of only the size is still a reference the analyzer lists.
        for u in e.get('internal_usages', []) + e.get('internal_non_text_reads', []):
            ours_int[(n, int(u.split(':')[1].split(' ')[0]))] += 1
    copy_files = (REMINDER_COPY, DAILY_QUOTES)
    ana_top = Counter((f"{r['owner']}.{r['name']}", r['file'], r['line']) for r in refs
                      if r['owner'] != 'S' and r['file'] not in copy_files
                      and f"{r['owner']}.{r['name']}" in top_out)
    ours_top = Counter((k, u['file'], u['line']) for k, e in top_out.items()
                       for u in e['usage_details'])
    ana_unused = {n for n in members_out if not any(k[0] == n for k in ana_ext)}
    ours_unused = {n for n, e in members_out.items() if not e['usages']}

    def diff(a, b):
        return [list(k) + [v] for k, v in sorted((a - b).items())]

    return OrderedDict([
        ('resolved_files', data['files']),
        ('ignored_doc_comment_references', comment_refs),
        ('s_usages_analyzer', sum(ana_ext.values())),
        ('s_usages_python', sum(ours_ext.values())),
        ('s_usages_only_analyzer', diff(ana_ext, ours_ext)),
        ('s_usages_only_python', diff(ours_ext, ana_ext)),
        ('s_internal_only_analyzer', diff(ana_int, ours_int)),
        ('s_internal_only_python', diff(ours_int, ana_int)),
        ('no_external_usage_sets_equal', ana_unused == ours_unused),
        ('top_level_usages_analyzer', sum(ana_top.values())),
        ('top_level_usages_python', sum(ours_top.values())),
        ('top_level_only_analyzer', diff(ana_top, ours_top)),
        ('top_level_only_python', diff(ours_top, ana_top)),
    ])


def main() -> None:
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    use_analyzer = '--no-analyzer' not in sys.argv[1:]
    verify = '--verify' in sys.argv[1:] and use_analyzer
    out_path = args[0] if args else DEFAULT_OUT

    lib_files = []
    for dirpath, _, names in os.walk(os.path.join(REPO, 'lib')):
        for nm in names:
            if nm.endswith('.dart'):
                lib_files.append(os.path.relpath(os.path.join(dirpath, nm), REPO))
    lib_files.sort()
    files = {rel: DartFile(rel) for rel in lib_files}
    roots = library_roots(files)

    af = files[APP_STRINGS]
    _, all_members = collect_s_members(af)

    text_members = [m for m in all_members if is_text_type(m['return_type'])]
    non_text = [m for m in all_members if not is_text_type(m['return_type'])]
    names = {m['name'] for m in text_members}
    all_names = {m['name'] for m in all_members}

    # S-typed identifiers per library.
    lib_names: dict[str, set[str]] = defaultdict(set)
    lib_funcs: dict[str, set[str]] = defaultdict(set)
    for rel, df in files.items():
        if rel == APP_STRINGS:
            continue
        n, f = s_typed_names(df)
        lib_names[roots[rel]] |= n
        lib_funcs[roots[rel]] |= f

    usages: dict[str, list[dict]] = defaultdict(list)
    bindings_cache: dict[tuple[str, str], list[Binding]] = {}
    rejected: dict[str, list[dict]] = defaultdict(list)
    dot_re = re.compile(r'(?<!\.)\.\s*([A-Za-z_$][\w$]*)(?![\w$])')

    for rel, df in files.items():
        if rel == APP_STRINGS:
            continue
        m = df.masked
        s_names = lib_names[roots[rel]]
        s_funcs = lib_funcs[roots[rel]]
        for x in dot_re.finditer(m):
            name = x.group(1)
            if name not in all_names:
                continue
            dot = x.start()
            # Skip `..` cascades and `...` spreads: the char before must not be '.'.
            if dot > 0 and m[dot - 1] == '.':
                continue
            k = dot - 1
            while k >= 0 and m[k] in ' \t\n':
                k -= 1
            if k >= 0 and m[k] in '?!':
                k -= 1
            receiver = ''
            confidence = None
            rejected_reason = 'receiver is not an S instance'
            if k >= 0 and m[k] in IDENT_CHARS:
                e = k
                while k >= 0 and m[k] in IDENT_CHARS:
                    k -= 1
                receiver = m[k + 1:e + 1]
                r0 = k + 1
                while k >= 0 and m[k] in ' \t\n?!':
                    k -= 1
                property_access = k >= 0 and m[k] == '.'
                if receiver == 'S':
                    confidence = None  # static access S.of etc, not a string
                elif receiver in s_names:
                    if property_access:
                        # widget.s, this.s: a field the library declares as S.
                        confidence = 'typed'
                    else:
                        key = (rel, receiver)
                        if key not in bindings_cache:
                            bindings_cache[key] = collect_bindings(df, receiver)
                        kind = resolve_receiver(bindings_cache[key], r0)
                        if kind in ('S', None):
                            # None: no binding in this file, so a field or getter
                            # from another part of the library, all S-typed.
                            confidence = 'typed'
                        elif kind == 'untyped':
                            confidence = 'inferred'
                        else:
                            rejected_reason = f'{receiver} is bound to a non-S value here'
            elif k >= 0 and m[k] == ')':
                depth = 0
                j = k
                while j >= 0:
                    if m[j] == ')':
                        depth += 1
                    elif m[j] == '(':
                        depth -= 1
                        if depth == 0:
                            break
                    j -= 1
                j -= 1
                while j >= 0 and m[j] in ' \t\n':
                    j -= 1
                e = j
                while j >= 0 and m[j] in IDENT_CHARS:
                    j -= 1
                callee = m[j + 1:e + 1]
                # What stands in front of the callee: `S .of(`, `x.S(`, `S(`.
                p = j
                while p >= 0 and m[p] in ' \t\n':
                    p -= 1
                callee_after_dot = p >= 0 and m[p] == '.'
                qualifier = ''
                if callee_after_dot:
                    q = p - 1
                    while q >= 0 and m[q] in ' \t\n':
                        q -= 1
                    qe = q
                    while q >= 0 and m[q] in IDENT_CHARS:
                        q -= 1
                    qualifier = m[q + 1:qe + 1]
                    # `a.S.of(` would be a prefixed import; the app has none.
                    if q >= 0 and m[q] == '.':
                        qualifier = '.' + qualifier
                if callee == 'of' and qualifier == 'S':
                    receiver, confidence = 'S.of(...)', 'direct'
                elif callee == 'S' and not callee_after_dot:
                    receiver, confidence = 'S(...)', 'direct'
                elif callee in s_funcs:
                    receiver, confidence = f'{callee}(...)', 'typed'
                else:
                    receiver = f'{callee}(...)'
            else:
                receiver = m[max(0, k):k + 1] if k >= 0 else ''
            line = df.line_of(x.start(1))
            enclosing = df.enclosing(x.start(1))
            rec = {
                'file': rel,
                'line': line,
                'screen': screen_for(rel),
                'enclosing': enclosing,
                'receiver': receiver,
            }
            if confidence:
                rec['confidence'] = confidence
                usages[name].append(rec)
            elif receiver != 'S':
                rec['reason'] = rejected_reason
                rejected[name].append(rec)

    # Internal references inside app_strings.dart (bare identifiers).
    internal: dict[str, list[dict]] = defaultdict(list)
    internal_non_text: dict[str, list[dict]] = defaultdict(list)
    member_by_pos = sorted((m['start_pos'], m['end_pos'], m['name']) for m in all_members)
    am = af.masked
    for mm in all_members:
        name = mm['name']
        local_bindings = None
        for x in re.finditer(rf'(?<![\w$]){re.escape(name)}(?![\w$])', am):
            if x.start() == mm['name_pos']:
                continue
            if is_named_arg_label(am, x.start(), x.end()):
                continue
            if local_bindings is None:
                # A binding inside the member's own declaration (a field's name,
                # say) is the member itself, not a shadow of it.
                local_bindings = [b for b in collect_bindings(af, name)
                                  if not (mm['start_pos'] <= b.pos < mm['end_pos'])]
            if resolve_receiver(local_bindings, x.start()) is not None or any(
                    b.pos == x.start() for b in local_bindings):
                continue  # a parameter or local that happens to share the name
            # Preceded by '.' is fine only for this. / S. access.
            k = x.start() - 1
            while k >= 0 and am[k] in ' \t\n':
                k -= 1
            if k >= 0 and am[k] == '.':
                pre = am[max(0, k - 4):k]
                if not (pre.endswith('this') or pre.rstrip().endswith('S')):
                    continue
            caller = ''
            for a, b, nm in member_by_pos:
                if a <= x.start() < b:
                    caller = nm
                    break
            if caller == name:
                continue  # recursion or the member's own parameter named alike
            rec = {'line': af.line_of(x.start()), 'caller': caller or '(outside class S)'}
            if is_non_text_read(am, x.end()):
                # Only the size is read: the text does not go through the caller.
                internal_non_text[name].append(rec)
                continue
            internal[name].append(rec)

    # Liveness: used from outside, or reached from a live member internally.
    live: set[str] = {n for n in all_names if usages.get(n)}
    callers_of = {n: {r['caller'] for r in internal.get(n, [])} for n in all_names}
    changed = True
    while changed:
        changed = False
        for n in all_names:
            if n in live:
                continue
            if any(c in live for c in callers_of[n]):
                live.add(n)
                changed = True

    def screens_of(recs):
        seen = OrderedDict()
        for r in sorted(recs, key=lambda r: (r['file'], r['line'])):
            seen.setdefault(r['screen'], None)
        return list(seen)

    members_out: OrderedDict[str, dict] = OrderedDict()
    for mm in text_members:
        name = mm['name']
        recs = sorted(usages.get(name, []), key=lambda r: (r['file'], r['line']))
        entry = OrderedDict()
        entry['id'] = f'app_strings.{name}'
        entry['file'] = APP_STRINGS
        entry['line'] = mm['line']
        entry['kind'] = mm['kind']
        entry['return_type'] = mm['return_type']
        entry['private'] = name.startswith('_')
        entry['static'] = mm['static']
        entry['usages'] = [f"{r['file']}:{r['line']}" for r in recs]
        entry['screens'] = screens_of(recs)
        entry['usage_count'] = len(recs)
        entry['usage_details'] = recs
        ints = internal.get(name, [])
        if ints:
            entry['internal_usages'] = [f"{APP_STRINGS}:{r['line']} ({r['caller']})" for r in ints]
        nts = internal_non_text.get(name, [])
        if nts:
            entry['internal_non_text_reads'] = [f"{APP_STRINGS}:{r['line']} ({r['caller']})" for r in nts]
        entry['unused'] = name not in live
        if not recs and name in live:
            entry['internal_only'] = True
        if any(r['confidence'] == 'inferred' for r in recs):
            entry['has_inferred_usage'] = True
        rej = rejected.get(name, [])
        if rej:
            entry['rejected_match_count'] = len(rej)
        members_out[name] = entry

    # ── Top-level functions of reminder_copy.dart and daily_quotes.dart ──
    top_out: OrderedDict[str, dict] = OrderedDict()
    for lib_rel, prefix in ((REMINDER_COPY, 'reminder_copy'), (DAILY_QUOTES, 'daily_quotes')):
        df = files[lib_rel]
        decls = [s for s in df.top if s.name and s.kind in
                 ('function', 'field', 'enum', 'typedef', 'class', 'getter')]
        decl_names = {s.name for s in decls}
        ext_uses: dict[str, list[dict]] = defaultdict(list)
        int_uses: dict[str, list[dict]] = defaultdict(list)
        int_non_text: dict[str, list[dict]] = defaultdict(list)
        for s in decls:
            name = s.name
            pat = re.compile(rf'(?<![\w$.]){re.escape(name)}(?![\w$])')
            for rel, other in files.items():
                if rel == lib_rel:
                    local_bindings = [b for b in collect_bindings(other, name)
                                      if not (s.start_pos <= b.pos < s.end_pos)]
                    for x in pat.finditer(other.masked):
                        if s.start_pos <= x.start() < s.end_pos:
                            continue
                        if is_named_arg_label(other.masked, x.start(), x.end()):
                            continue
                        if resolve_receiver(local_bindings, x.start()) is not None or any(
                                b.pos == x.start() for b in local_bindings):
                            continue
                        rec = {'line': other.line_of(x.start()), 'caller': other.enclosing(x.start())}
                        if is_non_text_read(other.masked, x.end()):
                            # `days % kDailyQuotes.length` reads the size, not a quote.
                            int_non_text[name].append(rec)
                            continue
                        int_uses[name].append(rec)
                    continue
                if name.startswith('_'):
                    continue  # library-private
                other_bindings = None
                for x in pat.finditer(other.masked):
                    if is_named_arg_label(other.masked, x.start(), x.end()):
                        continue
                    if other_bindings is None:
                        other_bindings = collect_bindings(other, name)
                    if resolve_receiver(other_bindings, x.start()) is not None or any(
                            b.pos == x.start() for b in other_bindings):
                        continue
                    ext_uses[name].append({
                        'file': rel,
                        'line': other.line_of(x.start()),
                        'screen': screen_for(rel),
                        'enclosing': other.enclosing(x.start()),
                    })
        live_top = {n for n in decl_names if ext_uses.get(n)}
        changed = True
        while changed:
            changed = False
            for n in decl_names:
                if n in live_top:
                    continue
                callers = {r['caller'].split('.')[0] for r in int_uses.get(n, [])}
                if any(c in live_top for c in callers):
                    live_top.add(n)
                    changed = True
        for s in decls:
            name = s.name
            recs = sorted(ext_uses.get(name, []), key=lambda r: (r['file'], r['line']))
            entry = OrderedDict()
            entry['id'] = f'{prefix}.{name}'
            entry['file'] = lib_rel
            entry['line'] = df.line_of(s.start_pos)
            entry['kind'] = s.kind
            entry['return_type'] = s.return_type
            entry['is_text'] = is_text_type(s.return_type) or name in ('kDailyQuotes', 'DailyQuote')
            entry['usages'] = [f"{r['file']}:{r['line']}" for r in recs]
            entry['screens'] = screens_of(recs)
            entry['usage_count'] = len(recs)
            entry['usage_details'] = recs
            ints = int_uses.get(name, [])
            if ints:
                entry['internal_usages'] = [f"{lib_rel}:{r['line']} ({r['caller'] or 'top level'})" for r in ints]
            nts = int_non_text.get(name, [])
            if nts:
                entry['internal_non_text_reads'] = [f"{lib_rel}:{r['line']} ({r['caller'] or 'top level'})"
                                                    for r in nts]
            entry['unused'] = name not in live_top
            if not recs and name in live_top:
                entry['internal_only'] = True
            top_out[f'{prefix}.{name}'] = entry

    # ── file_to_screen: every lib file ──
    file_to_screen = OrderedDict((rel, screen_for(rel)) for rel in lib_files)

    # ── screen totals ──
    screen_strings: dict[str, set[str]] = defaultdict(set)
    for name, e in members_out.items():
        for sc in e['screens']:
            screen_strings[sc].add(e['id'])
    for key, e in top_out.items():
        if e['is_text']:
            for sc in e['screens']:
                screen_strings[sc].add(e['id'])
    screen_counts = sorted(((sc, len(ids)) for sc, ids in screen_strings.items()),
                           key=lambda p: (-p[1], p[0]))

    rejected_by_receiver = Counter()
    for name, recs in rejected.items():
        if name in names:
            for r in recs:
                rejected_by_receiver[r['receiver']] += 1

    s_nontext = [OrderedDict(name=m['name'], kind=m['kind'], return_type=m['return_type'],
                             line=m['line']) for m in non_text]

    result = OrderedDict()
    result['_meta'] = OrderedDict([
        ('generated_by', 'docs/wording/generator/map_usage.py'),
        ('repo', REPO),
        ('scope', 'lib/**/*.dart; app_strings.dart itself is excluded from usages, '
                  'its internal references are listed separately as internal_usages'),
        ('members_key', 'bare member name of class S; reminder_copy and daily_quotes '
                        'top-level declarations are under top_level, keyed "reminder_copy.name"'),
        ('usage_rule', 'a ".name" match counts only when its receiver is S.of(...), S(...), '
                       'or an identifier the same library binds to S; everything else is '
                       'in rejected_usages'),
        ('unused_rule', 'no usage outside app_strings.dart and not reached from a used member '
                        'inside it (transitive)'),
        ('lib_files_scanned', len(lib_files)),
        ('s_members_total', len(all_members)),
        ('s_text_members', len(text_members)),
        ('s_text_members_unused', sum(1 for e in members_out.values() if e['unused'])),
        ('s_text_members_internal_only', sum(1 for e in members_out.values() if e.get('internal_only'))),
        ('s_text_members_with_inferred_usage', sum(1 for e in members_out.values() if e.get('has_inferred_usage'))),
        ('s_non_text_members_skipped', s_nontext),
        ('s_typed_identifiers', sorted({n for v in lib_names.values() for n in v})),
        ('s_returning_functions', sorted({n for v in lib_funcs.values() for n in v})),
        ('rejected_by_receiver', OrderedDict(rejected_by_receiver.most_common())),
        ('screen_string_counts', OrderedDict(screen_counts)),
    ])
    result['members'] = members_out
    result['top_level'] = top_out
    result['file_to_screen'] = file_to_screen
    result['screen_to_ids'] = OrderedDict(
        (sc, sorted(screen_strings[sc])) for sc, _ in screen_counts)
    result['rejected_usages'] = OrderedDict(
        (n, sorted(recs, key=lambda r: (r['file'], r['line'])))
        for n, recs in sorted(rejected.items()) if n in names)

    data, error = (run_analyzer() if use_analyzer else (None, 'skipped with --no-analyzer'))
    dart_rows_path = os.path.join(os.path.dirname(DEFAULT_OUT), 'dart_rows.json')
    if data is not None and os.path.exists(dart_rows_path):
        with open(dart_rows_path, encoding='utf-8') as fh:
            dart_rows = json.load(fh)
        native_path = os.path.join(os.path.dirname(DEFAULT_OUT), 'native_rows.json')
        native_rows = []
        if os.path.exists(native_path):
            with open(native_path, encoding='utf-8') as fh:
                native_rows = json.load(fh)
        rows_usage, rows_meta = dart_row_usage(dart_rows, native_rows, data)
        result['dart_rows'] = rows_usage
        result['_meta']['dart_rows_usage'] = rows_meta
    else:
        result['dart_rows'] = OrderedDict()
        result['_meta']['dart_rows_usage'] = OrderedDict([
            ('ran', False),
            ('why', error if data is None else f'{dart_rows_path} is missing; run extract_dart.dart first')])
    if verify and data is not None:
        chk = analyzer_check(members_out, top_out, data)
        result['_meta']['analyzer_check'] = OrderedDict([('ran', True)] + list(chk.items()))
    elif verify:
        result['_meta']['analyzer_check'] = OrderedDict([('ran', False), ('error', error)])
    else:
        result['_meta']['analyzer_check'] = OrderedDict([('ran', False),
                                                         ('how', 'python3 map_usage.py --verify')])

    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, 'w', encoding='utf-8') as fh:
        json.dump(result, fh, ensure_ascii=False, indent=1)

    # ── Report ──
    meta = result['_meta']
    print(f'wrote {out_path}')
    print(f"lib files scanned: {meta['lib_files_scanned']}")
    print(f"class S members: {meta['s_members_total']} "
          f"(text {meta['s_text_members']}, non-text {len(s_nontext)})")
    print(f"text members with no usage outside app_strings.dart: "
          f"{sum(1 for e in members_out.values() if not e['usages'])}")
    print(f"  of which alive through another member: {meta['s_text_members_internal_only']}")
    print(f"  unused (possibly dead): {meta['s_text_members_unused']}")
    print(f"text members reached through an untyped closure parameter: {meta['s_text_members_with_inferred_usage']}")
    tl_text = [e for e in top_out.values()]
    print(f"top-level declarations mapped: {len(tl_text)} "
          f"(unused {sum(1 for e in tl_text if e['unused'])})")
    chk = meta['analyzer_check']
    if chk.get('ran'):
        print(f"analyzer check: {chk['resolved_files']} files resolved; S usages "
              f"analyzer {chk['s_usages_analyzer']} vs python {chk['s_usages_python']}, "
              f"only-analyzer {len(chk['s_usages_only_analyzer'])}, only-python {len(chk['s_usages_only_python'])}; "
              f"internal diffs {len(chk['s_internal_only_analyzer'])}/{len(chk['s_internal_only_python'])}; "
              f"top-level {chk['top_level_usages_analyzer']} vs {chk['top_level_usages_python']}, "
              f"diffs {len(chk['top_level_only_analyzer'])}/{len(chk['top_level_only_python'])}; "
              f"no-usage sets equal: {chk['no_external_usage_sets_equal']}")
    elif verify:
        print('analyzer check FAILED to run: ' + chk.get('error', '')[:500])
    du = meta.get('dart_rows_usage', {})
    if 'rows_mapped' in du:
        print(f"other Dart rows mapped with the analyzer: {du['rows_mapped']} "
              f"(with usages {du['rows_with_usages']}, in place {du['rows_in_place']}, "
              f"no reference found {len(du['rows_no_reference_found'])})")
    else:
        print('other Dart rows NOT mapped: ' + str(du.get('why', ''))[:300])
    print('top 20 screens by number of strings:')
    for sc, cnt in screen_counts[:20]:
        print(f'  {cnt:4d}  {sc}')


if __name__ == '__main__':
    main()

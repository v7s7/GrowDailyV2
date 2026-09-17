#!/usr/bin/env python3
"""Extract the user-facing wording that does NOT live in Dart.

Part of the wording inventory (docs/wording). The Dart extractor covers lib/;
this script covers everything else a person can read:

  * iOS system strings: ios/Runner/Info.plist paired with
    ios/Runner/ar.lproj/InfoPlist.strings, plus the Swift in ios/ (Home Screen
    and Lock Screen widgets, the AlarmKit Live Activity and its intents, the
    iOS 18 Lock Screen controls, the AlarmKit bridge's fallback label).
  * Android system strings: AndroidManifest.xml labels and any
    res/values*/strings.xml (there are none today; the script says so).
  * Server push copy: functions/index.js and functions/room_messages.js.
  * Web pages: public/**/*.html, plus the Flutter web shell (web/index.html,
    web/manifest.json) because a browser tab shows those words too.

It only READS the app. Output is a JSON list of rows in the common schema:

  id, source_group, section, key, arabic, english, placeholders, reason,
  file, line, kind

Rules this script enforces on its own output:

  * No U+2014 anywhere. In wording (arabic / english) the character is
    rendered as the visible token "[em dash]" so the inventory still shows
    where the app's copy carries one; in reasons (developer comments) it is
    turned into a comma. The ids of rows whose wording had one are listed in
    the summary file.
  * Every server-push row is built from literal fragments that must be found
    verbatim in the JS source, so the script fails loudly when the copy
    changes instead of emitting stale text.
  * A coverage pass lists every string literal the rules did not pick up
    (Swift literals with letters, JS literals with Arabic or several English
    words), so a reviewer can confirm nothing user-facing was skipped.

Usage:
  python3 docs/wording/generator/extract_native.py [OUT_JSON]

OUT_JSON defaults to docs/wording/generator/.cache/native_rows.json, and
native_summary.json is written next to it.
"""

import json
import plistlib
import re
import sys
from html.parser import HTMLParser
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
# generator/.cache is gitignored; build_workbook.py reads from there by default.
DEFAULT_OUT = Path(__file__).resolve().parent / ".cache" / "native_rows.json"

EM_DASH = "\u2014"
EM_TOKEN = "[em dash]"
LETTER_RE = re.compile(r"[A-Za-z\u0600-\u06FF]")
ARABIC_RE = re.compile(r"[\u0600-\u06FF]")

G_IOS = "iOS system strings"
G_ANDROID = "Android system strings"
G_PUSH = "Push notifications (server)"
G_WEB = "Web pages"

EM_DASH_IDS = []
COVERAGE = {"swift_unpicked": [], "js_uncovered_arabic": [], "js_unreviewed_english": []}


# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------

def read_lines(rel):
    return (REPO / rel).read_text(encoding="utf-8").split("\n")


def norm_ws(s):
    return re.sub(r"\s+", " ", s or "").strip()


def wording(s):
    return (s or "").replace(EM_DASH, EM_TOKEN)


def prose(s):
    s = re.sub(r"\s*\u2014\s*", ", ", s or "")
    return norm_ws(s)


def prose_paragraphs(s):
    """Like prose, but keeps the paragraph breaks join_reason puts between
    comments from different places."""
    return "\n".join(p for p in (prose(x) for x in (s or "").split("\n")) if p)


def placeholders_of(*texts):
    seen = []
    for t in texts:
        for m in re.finditer(r"\{([^{}]+)\}", t or ""):
            name = m.group(1).strip()
            if name not in seen:
                seen.append(name)
    return seen


def sanitize_id(rid):
    """Ids are stable keys: no spaces, parentheses or operators (the same
    rule as extract_dart.dart)."""
    sep = "\u0001"
    for pat, word in ((r"\s*<=\s*", "le"), (r"\s*>=\s*", "ge"), (r"\s*==\s*", "eq"),
                      (r"\s*!=\s*", "ne"), (r"\s*<\s*", "lt"), (r"\s*>\s*", "gt"),
                      (r"\s*\|\|\s*", "or"), (r"\s*&&\s*", "and")):
        rid = re.sub(pat, sep + word + sep, rid)
    rid = re.sub("[^A-Za-z0-9_.#\\[\\]:\\-" + sep + "]", sep, rid)
    rid = re.sub(sep + "+", sep, rid)
    rid = re.sub(sep + "(?=[\\[\\].#])|(?<=[\\[\\].#])" + sep, "", rid)
    return rid.replace(sep, "_")


def make_row(rid, group, section, key, arabic, english, reason, file, line, kind,
             placeholders=None, ar_loc=None, en_loc=None, notes=None, used_in=None,
             usage_targets=None, arabic_digits_runtime=False):
    """ar_loc / en_loc: (file, line) of each side's own text when it is not
    the declaration line itself; notes: generator remarks that are not the
    developers' comments; used_in: "file:line" places that send or show it;
    usage_targets: Dart members ("file|Class|member") whose callers
    map_usage.py follows to the screens behind them."""
    rid = sanitize_id(rid)
    if EM_DASH in (arabic or "") or EM_DASH in (english or ""):
        EM_DASH_IDS.append(rid)
    ar = wording(arabic)
    en = wording(english)
    row = {
        "id": rid,
        "source_group": group,
        "section": prose(section),
        "key": key,
        "arabic": ar,
        "english": en,
        "placeholders": placeholders if placeholders is not None else placeholders_of(ar, en),
        "reason": prose_paragraphs(reason),
        "file": file,
        "line": line,
        "kind": kind,
    }
    if ar and ar_loc:
        row["ar_file"], row["ar_line"] = ar_loc
    if en and en_loc:
        row["en_file"], row["en_line"] = en_loc
    if notes:
        row["notes"] = [prose(n) for n in notes if n]
    if used_in:
        row["used_in"] = used_in
    if usage_targets:
        row["usage_targets"] = usage_targets
    if arabic_digits_runtime:
        row["arabic_digits_runtime"] = True
    return row


JSDOC_BARE_TAG = re.compile(r"^@(param|return|returns)\s+\{.*\}\s*[\w.\[\]=]*\s*$")


def clean_comment_lines(raw_lines):
    out = []
    for s in raw_lines:
        s = s.strip()
        s = re.sub(r"^<!--", "", s)
        s = re.sub(r"-->$", "", s)
        s = re.sub(r"^/\*\*?", "", s)
        s = re.sub(r"\*/$", "", s)
        s = re.sub(r"^///?", "", s)
        s = re.sub(r"^\*(?!\*)", "", s)
        s = s.strip()
        if s.startswith("MARK:"):
            continue
        if JSDOC_BARE_TAG.match(s):
            continue
        out.append(s)
    return norm_ws(" ".join(out))


def c_comment_above(lines, idx, skip_attributes=False, skip_blank=False):
    """Comment block directly above lines[idx] (0-based), C-style comments.

    Contiguous // lines and /* */ blocks. With skip_attributes, Swift
    attribute lines (@available(...), @MainActor) between the comment and the
    declaration are stepped over. With skip_blank, blank lines between the
    comment and the line are allowed (used for .strings files).
    """
    j = idx - 1
    if skip_attributes:
        while j >= 0 and re.match(r"^\s*@\w+(\(.*\))?\s*$", lines[j]):
            j -= 1
    if skip_blank:
        while j >= 0 and lines[j].strip() == "":
            j -= 1
    collected = []
    while j >= 0:
        s = lines[j].strip()
        if s.startswith("//"):
            collected.append(s)
            j -= 1
            continue
        if s.endswith("*/"):
            block = []
            k = j
            while k >= 0:
                block.append(lines[k].strip())
                if "/*" in lines[k]:
                    break
                k -= 1
            collected.extend(block)
            j = k - 1
            continue
        break
    collected.reverse()
    return clean_comment_lines(collected)


def xml_comment_above(lines, idx):
    j = idx - 1
    if j < 0 or not lines[j].strip().endswith("-->"):
        return ""
    block = []
    k = j
    while k >= 0:
        block.append(lines[k])
        if "<!--" in lines[k]:
            break
        k -= 1
    block.reverse()
    return clean_comment_lines(block)


def find_line(lines, needle, start=0):
    for i in range(start, len(lines)):
        if needle in lines[i]:
            return i
    raise SystemExit(f"extract_native: could not find {needle!r} (from line {start + 1})")


def join_reason(*parts):
    """Comments from different places, one paragraph each."""
    return "\n".join(p for p in (norm_ws(x) for x in parts) if p)


# ---------------------------------------------------------------------------
# Source scanners (strings and comments), used by Swift and the JS checks
# ---------------------------------------------------------------------------

def _swift_string_end(text, i):
    """text[i] is the opening quote. Returns index just past the closing one."""
    if text.startswith('"""', i):
        end = text.find('"""', i + 3)
        if end < 0:
            raise SystemExit("extract_native: unterminated Swift multi-line string")
        return end + 3
    j = i + 1
    while j < len(text):
        c = text[j]
        if c == "\\":
            if j + 1 < len(text) and text[j + 1] == "(":
                depth = 1
                k = j + 2
                while k < len(text) and depth:
                    if text[k] == '"':
                        k = _swift_string_end(text, k)
                        continue
                    if text[k] == "(":
                        depth += 1
                    elif text[k] == ")":
                        depth -= 1
                    k += 1
                j = k
                continue
            j += 2
            continue
        if c == '"':
            return j + 1
        if c == "\n":
            raise SystemExit("extract_native: newline inside a Swift string literal")
        j += 1
    raise SystemExit("extract_native: unterminated Swift string literal")


def scan_swift(text):
    """Returns (literals, sanitized). literals: list of (start, end) offsets of
    each top-level string literal including quotes. sanitized: the text with
    comments blanked and string contents blanked (quotes and newlines kept)."""
    literals = []
    san = list(text)
    i = 0
    n = len(text)
    while i < n:
        c = text[i]
        if text.startswith("//", i):
            j = text.find("\n", i)
            j = n if j < 0 else j
            for k in range(i, j):
                san[k] = " "
            i = j
            continue
        if text.startswith("/*", i):
            j = text.find("*/", i + 2)
            j = n if j < 0 else j + 2
            for k in range(i, j):
                if san[k] != "\n":
                    san[k] = " "
            i = j
            continue
        if c == '"':
            j = _swift_string_end(text, i)
            literals.append((i, j))
            for k in range(i + 1, j - 1):
                if san[k] != "\n":
                    san[k] = " "
            i = j
            continue
        i += 1
    return literals, "".join(san)


def _find_matching_paren(s, i):
    """s[i] == '(' ; returns index of the matching ')', skipping strings."""
    depth = 0
    k = i
    while k < len(s):
        if s[k] == '"':
            k = _swift_string_end(s, k)
            continue
        if s[k] == "(":
            depth += 1
        elif s[k] == ")":
            depth -= 1
            if depth == 0:
                return k
        k += 1
    raise SystemExit("extract_native: unbalanced interpolation")


def render_swift_literal(lit):
    """lit includes its quotes. Interpolations become {expr}."""
    inner = lit[1:-1]
    out = []
    i = 0
    while i < len(inner):
        c = inner[i]
        if c == "\\" and i + 1 < len(inner):
            nxt = inner[i + 1]
            if nxt == "(":
                close = _find_matching_paren(inner, i + 1)
                out.append("{" + inner[i + 2:close].strip() + "}")
                i = close + 1
                continue
            if nxt == "u" and inner.startswith("{", i + 2):
                close = inner.index("}", i + 2)
                out.append(chr(int(inner[i + 3:close], 16)))
                i = close + 1
                continue
            out.append({"n": "\n", "t": "\t", '"': '"', "\\": "\\", "'": "'"}.get(nxt, nxt))
            i += 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


def has_wording_letters(rendered):
    return bool(LETTER_RE.search(re.sub(r"\{[^{}]*\}", "", rendered)))


def scan_js(text):
    """Returns list of (start, end, quote) for string and template literals
    outside comments. Regex literals are skipped by a conventional heuristic."""
    lits = []
    i = 0
    n = len(text)
    prev_sig = ""

    def template_end(i):
        j = i + 1
        while j < n:
            c = text[j]
            if c == "\\":
                j += 2
                continue
            if c == "`":
                return j + 1
            if text.startswith("${", j):
                j = code_until_brace(j + 2)
                continue
            j += 1
        raise SystemExit("extract_native: unterminated template literal")

    def quote_end(i, q):
        j = i + 1
        while j < n:
            c = text[j]
            if c == "\\":
                j += 2
                continue
            if c == q:
                return j + 1
            j += 1
        raise SystemExit("extract_native: unterminated JS string")

    def code_until_brace(j):
        depth = 1
        while j < n:
            c = text[j]
            if c in "\"'":
                j = quote_end(j, c)
                continue
            if c == "`":
                j = template_end(j)
                continue
            if c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
                if depth == 0:
                    return j + 1
            j += 1
        raise SystemExit("extract_native: unbalanced ${ } in template literal")

    while i < n:
        c = text[i]
        if text.startswith("//", i):
            j = text.find("\n", i)
            i = n if j < 0 else j
            continue
        if text.startswith("/*", i):
            j = text.find("*/", i + 2)
            i = n if j < 0 else j + 2
            continue
        if c in "\"'":
            j = quote_end(i, c)
            lits.append((i, j, c))
            prev_sig = c
            i = j
            continue
        if c == "`":
            j = template_end(i)
            lits.append((i, j, "`"))
            prev_sig = "`"
            i = j
            continue
        if c == "/" and (prev_sig == "" or prev_sig in "(,=:[!&|?{};"
                         or text[max(0, i - 7):i].rstrip().endswith("return")):
            j = i + 1
            in_class = False
            while j < n and text[j] != "\n":
                if text[j] == "\\":
                    j += 2
                    continue
                if text[j] == "[":
                    in_class = True
                elif text[j] == "]":
                    in_class = False
                elif text[j] == "/" and not in_class:
                    break
                j += 1
            i = j + 1
            prev_sig = "/"
            continue
        if not c.isspace():
            prev_sig = c
        i += 1
    return lits


def render_js_literal(lit):
    q = lit[0]
    inner = lit[1:-1]
    out = []
    i = 0
    while i < len(inner):
        c = inner[i]
        if q == "`" and inner.startswith("${", i):
            depth = 1
            k = i + 2
            while k < len(inner) and depth:
                if inner[k] == "{":
                    depth += 1
                elif inner[k] == "}":
                    depth -= 1
                k += 1
            out.append("{" + inner[i + 2:k - 1].strip() + "}")
            i = k
            continue
        if c == "\\" and i + 1 < len(inner):
            nxt = inner[i + 1]
            if nxt == "u" and inner.startswith("{", i + 2):
                close = inner.index("}", i + 2)
                out.append(chr(int(inner[i + 3:close], 16)))
                i = close + 1
                continue
            if nxt == "u":
                out.append(chr(int(inner[i + 2:i + 6], 16)))
                i += 6
                continue
            out.append({"n": "\n", "t": "\t"}.get(nxt, nxt))
            i += 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


def line_of_offset(text, off):
    return text.count("\n", 0, off) + 1


# ---------------------------------------------------------------------------
# iOS: Info.plist + ar.lproj/InfoPlist.strings
# ---------------------------------------------------------------------------

# The Dart member whose call makes iOS show each permission sheet. map_usage.py
# follows its callers to the screens the sheet opens over. An empty list:
# the sheet is never shown. Each target is checked to exist.
PERMISSION_TRIGGERS = {
    "NSLocationWhenInUseUsageDescription": [
        "lib/core/services/device_location_service.dart|DeviceLocationService|detect"],
    "NSLocationAlwaysAndWhenInUseUsageDescription": [],
    "NSMicrophoneUsageDescription": [
        "lib/core/services/voice_note_service.dart|VoiceNoteService|hasPermission",
        "lib/core/services/voice_note_service.dart|VoiceNoteService|startRecording"],
    "NSHealthShareUsageDescription": [
        "lib/core/services/health_steps_service.dart|HealthStepsService|requestPermission"],
    "NSHealthUpdateUsageDescription": [
        "lib/core/services/health_steps_service.dart|HealthStepsService|requestPermission"],
    "NSAlarmKitUsageDescription": [
        "lib/core/services/alarm_service.dart|AlarmService|requestPermission"],
}


def check_target(target):
    rel, cls, member = target.split("|")
    text = (REPO / rel).read_text(encoding="utf-8")
    if not re.search(r"\bclass\s+" + re.escape(cls) + r"\b", text) or \
            not re.search(r"\b" + re.escape(member) + r"\s*\(", text):
        raise SystemExit(f"extract_native: permission trigger {target} no longer exists")
    return target


def ios_plist_rows():
    rows = []
    plist_rel = "ios/Runner/Info.plist"
    strings_rel = "ios/Runner/ar.lproj/InfoPlist.strings"
    plist_lines = read_lines(plist_rel)
    with open(REPO / plist_rel, "rb") as fh:
        plist = plistlib.load(fh)

    s_lines = read_lines(strings_rel)
    header = ""
    m = re.search(r"/\*(.*?)\*/", "\n".join(s_lines), re.S)
    if m and "\n".join(s_lines).lstrip().startswith("/*"):
        header = clean_comment_lines(("/*" + m.group(1) + "*/").split("\n"))
    ar_entries = {}
    entry_re = re.compile(r'^\s*"([^"]+)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;')
    for i, line in enumerate(s_lines):
        em = entry_re.match(line)
        if em:
            value = em.group(2).replace('\\"', '"').replace("\\n", "\n").replace("\\\\", "\\")
            ar_entries[em.group(1)] = (value, i + 1, c_comment_above(s_lines, i, skip_blank=True))

    user_visible = ["CFBundleDisplayName", "CFBundleName"] + sorted(
        k for k in plist if re.match(r"^NS\w+UsageDescription$", k))
    # Keep the plist's own order, which is the order a reviewer reads.
    order = {k: i for i, k in enumerate(plist.keys())}
    user_visible.sort(key=lambda k: order.get(k, 10 ** 6))

    for key in user_visible:
        if key not in plist or not isinstance(plist[key], str):
            continue
        key_idx = find_line(plist_lines, f"<key>{key}</key>")
        plist_comment = xml_comment_above(plist_lines, key_idx)
        ar_value, ar_line, ar_comment = ar_entries.get(key, ("", None, ""))
        parts, sources = [], []
        if plist_comment:
            parts.append(plist_comment)
            sources.append("the comment above the key in Info.plist")
        if ar_line is not None:
            if ar_comment and ar_comment != header:
                parts.append(ar_comment)
                sources.append("the comment above the key in ar.lproj/InfoPlist.strings")
            if header:
                parts.append(header)
                sources.append("the header comment of ar.lproj/InfoPlist.strings")
        notes = []
        if len(sources) > 1:
            notes.append("Reason joins " + ", then ".join(sources) + ", one paragraph each.")
        elif sources and sources[0] != "the comment above the key in Info.plist":
            # Nothing sits above the key itself, so the only reason is a
            # comment about the whole file.
            notes.append("Reason is " + sources[0] + ".")
        trigger = PERMISSION_TRIGGERS.get(key)
        if trigger is not None and not trigger:
            notes.append("iOS never shows this sheet: the app only asks for when-in-use location. "
                         "The key is there because App Store validation requires it (see Reason).")
        section = ("Permission prompts (NS*UsageDescription)"
                   if key.endswith("UsageDescription") else "App name")
        string_line = key_idx + 2 if "<string>" in plist_lines[key_idx + 1] else key_idx + 1
        rows.append(make_row(
            f"ios.InfoPlist.{key}", G_IOS, section, key, ar_value, plist[key],
            join_reason(*parts), plist_rel, key_idx + 1, "plist",
            ar_loc=(strings_rel, ar_line) if ar_line else None,
            en_loc=(plist_rel, string_line),
            notes=notes,
            usage_targets=[check_target(t) for t in (trigger or [])]))

    missing = sorted(set(ar_entries) - set(user_visible))
    if missing:
        raise SystemExit(f"extract_native: InfoPlist.strings keys not in Info.plist: {missing}")
    return rows


# ---------------------------------------------------------------------------
# iOS: Swift (widgets, Live Activity, controls, AlarmKit bridge)
# ---------------------------------------------------------------------------

SWIFT_FILES = [
    "ios/GrowDailyWidget/GrowDailyWidget.swift",
    "ios/GrowDailyWidget/GrowDailyControls.swift",
    "ios/GrowDailyWidget/GrowDailyAlarmLiveActivity.swift",
    "ios/GrowDailyWidget/GrowDailyWidgetBundle.swift",
    "ios/Runner/AlarmKitBridge.swift",
    "ios/Runner/AppDelegate.swift",
    "ios/Runner/HealthStepsBridge.swift",
    "ios/Runner/SceneDelegate.swift",
]

DECL_RE = re.compile(
    r"\b(struct|enum|class|extension|protocol|func|init|var|let)\b\s*([A-Za-z_][A-Za-z0-9_]*)?")


def swift_frames(lines, san_lines):
    """For each line, the stack of enclosing named declarations at the start
    of the line, and any var/let name declared on the line itself.

    Returns (frames_at_line, decl_on_line) where frames_at_line[i] is a list
    of dicts {name, kind, line, doc} and decl_on_line[i] is a name or None.
    """
    stack = []  # items: dict or None (anonymous brace)
    frames_at_line = []
    decl_on_line = []
    pending = None
    for i, code in enumerate(san_lines):
        frames_at_line.append([f for f in stack if f])
        on_line = None
        m = None
        for cand in DECL_RE.finditer(code):
            prefix = code[:cand.start()]
            if re.search(r"\b(if|guard|while|for|case)\b[^{]*$", prefix) or prefix.rstrip().endswith(","):
                continue
            m = cand
            break
        start_col = 0
        if m:
            kind, name = m.group(1), m.group(2)
            if kind == "init":
                name = "init"
            pending = {"name": name or kind, "kind": kind, "line": i,
                       "doc": c_comment_above(lines, i, skip_attributes=True),
                       "parens": 0}
            if kind in ("var", "let") and name:
                on_line = name
            start_col = m.end()
        decl_on_line.append(on_line)
        for pos, ch in enumerate(code):
            if pending is not None and pending["line"] == i and pos < start_col:
                continue
            if ch == "(" and pending is not None:
                pending["parens"] += 1
            elif ch == ")" and pending is not None:
                pending["parens"] -= 1
            elif ch == "{":
                if pending is not None and pending["parens"] <= 0:
                    stack.append(pending)
                    pending = None
                else:
                    stack.append(None)
            elif ch == "}":
                if stack:
                    stack.pop()
        if pending is not None and pending["parens"] <= 0 and pending["line"] <= i:
            # A declaration whose line ended without opening a body (a stored
            # property, a constant) opens nothing.
            if not code.rstrip().endswith(("(", ",", "->", "=")):
                pending = None
    return frames_at_line, decl_on_line


def swift_context(pre, frames, rel):
    """Decide whether the literal after `pre` (sanitized code on the same line
    before the opening quote) is user-facing. Returns (kind, modifier) or None."""
    p = pre.rstrip()
    m = re.search(r"\.(configurationDisplayName|displayName|description)\($", p)
    if m:
        return "other", m.group(1)
    if re.search(r"IntentDescription\($", p):
        return "field", None
    if re.search(r"LocalizedStringResource\s*=$", p):
        return "field", None
    if re.search(r"@Parameter\(title:$", p):
        return "field", "parameter title"
    if p.endswith("??") and "Label" in p:
        # A label Dart normally supplies (stopLabel), with the English the
        # system shows when it does not.
        return "field", "fallback"
    # Inside an open Text( or Label( call, and not its systemImage argument.
    for fn in ("Text(", "Label("):
        idx = p.rfind(fn)
        if idx >= 0:
            seg = p[idx + len(fn):]
            if seg.count("(") - seg.count(")") >= 0 and "systemImage" not in seg:
                return "other", None
    if rel.startswith("ios/GrowDailyWidget/") and re.search(r"\b(name|title|roomName):$", p):
        if any(f["name"] == "placeholder" for f in frames):
            return "constructor-args", "sample"
        return "constructor-args", "argument"
    if re.search(r"\breturn\b[^;]*$", p):
        return "method", "return"
    return None


def swift_rows():
    rows = []
    for rel in SWIFT_FILES:
        path = REPO / rel
        if not path.exists():
            continue
        text = path.read_text(encoding="utf-8")
        lines = text.split("\n")
        literals, san = scan_swift(text)
        san_lines = san.split("\n")
        frames_at_line, decl_on_line = swift_frames(lines, san_lines)
        stem = Path(rel).stem

        # MARK sections.
        mark_at = []
        current = None
        for line in lines:
            mm = re.match(r"^\s*//\s*MARK:\s*-?\s*(.+?)\s*$", line)
            if mm:
                current = mm.group(1)
            mark_at.append(current)

        # Line starts, for offset to column.
        starts = [0]
        for line in lines:
            starts.append(starts[-1] + len(line) + 1)

        per_key = {}
        pending_rows = []
        for (s, e) in literals:
            lit = text[s:e]
            rendered = render_swift_literal(lit)
            li = line_of_offset(text, s) - 1
            col = s - starts[li]
            pre = san_lines[li][:col]
            frames = frames_at_line[li]
            if not has_wording_letters(rendered):
                continue
            ctx = swift_context(pre, frames, rel)
            if ctx is None:
                COVERAGE["swift_unpicked"].append(f"{rel}:{li + 1}: {rendered}")
                continue
            kind, modifier = ctx
            # Identifier-like returns ("authorized", "notDetermined") are
            # protocol values handed back to Dart, not wording.
            # Wording that a function returns is a phrase. Single tokens
            # ("authorized", "notDetermined") are protocol values handed back
            # to Dart, and format strings are ids.
            if modifier == "return" and " " not in re.sub(r"\{[^{}]*\}", "", rendered).strip():
                COVERAGE["swift_unpicked"].append(f"{rel}:{li + 1}: {rendered}")
                continue
            # Outside a gallery placeholder, a name:/title: argument is wording
            # only when it reads as words (URL query names like "tab" are not).
            if modifier == "argument" and not (" " in rendered or rendered[:1].isupper()):
                COVERAGE["swift_unpicked"].append(f"{rel}:{li + 1}: {rendered}")
                continue

            names = [f["name"] for f in frames]
            key_parts = list(names)
            if modifier == "parameter title":
                # The property the @Parameter decorates is on the next line.
                nxt = decl_on_line[li + 1] if li + 1 < len(decl_on_line) else None
                key_parts.append((nxt or "parameter") + " (parameter title)")
            elif decl_on_line[li]:
                key_parts.append(decl_on_line[li])
            elif modifier in ("configurationDisplayName", "displayName", "description"):
                key_parts.append(modifier)
            if modifier == "sample":
                key_parts.append("gallery preview sample")
            if modifier == "fallback":
                key_parts.append("fallback")
            key = ".".join(key_parts) if key_parts else stem

            section = mark_at[li] or (names[0] if names else stem)

            reason = c_comment_above(lines, li)
            trailing = san_lines[li]
            tc = lines[li].find("//", len(trailing.rstrip()))
            if tc >= 0:
                reason = join_reason(reason, clean_comment_lines([lines[li][tc:]]))
            notes = []
            if not reason:
                for f in reversed(frames):
                    if f["doc"]:
                        reason = f["doc"]
                        notes.append(f"Reason is the doc comment of {f['kind']} {f['name']} "
                                     f"(line {f['line'] + 1}), which holds this text; the line "
                                     "itself has no comment.")
                        break

            # "line" is where the declaration that holds the text starts (the
            # func, var or struct around it), as for the Dart rows; the text's
            # own line goes in en_loc when it is elsewhere.
            if modifier == "parameter title" and li + 1 < len(decl_on_line) and decl_on_line[li + 1]:
                # The attribute decorates the property declared on the next
                # line; like a Dart annotation it is not where it starts.
                decl_line = li + 2
            elif decl_on_line[li] or not frames:
                decl_line = li + 1
            else:
                decl_line = frames[-1]["line"] + 1

            per_key.setdefault(key, 0)
            per_key[key] += 1
            pending_rows.append((key, per_key[key], dict(
                group=G_IOS, section=section, key=key, arabic="", english=rendered,
                reason=reason, file=rel, line=decl_line, text_line=li + 1, kind=kind,
                notes=notes)))

        for key, n, r in pending_rows:
            rid = f"ios.{stem}.{key}" + (f"#{n}" if per_key[key] > 1 else "")
            row = make_row(rid, r["group"], r["section"], r["key"], r["arabic"],
                           r["english"], r["reason"], r["file"], r["line"], r["kind"],
                           en_loc=(r["file"], r["text_line"]), notes=r["notes"])
            row["text_line"] = r["text_line"]
            rows.append(row)
    return rows


# ---------------------------------------------------------------------------
# Android
# ---------------------------------------------------------------------------

def android_rows():
    rows = []
    res = REPO / "android/app/src/main/res"
    strings_files = sorted(res.glob("values*/strings.xml"))
    for sf in strings_files:
        rel = str(sf.relative_to(REPO))
        lines = rel and (REPO / rel).read_text(encoding="utf-8").split("\n")
        for i, line in enumerate(lines):
            m = re.search(r'<string\s+name="([^"]+)"[^>]*>(.*?)</string>', line)
            if not m:
                continue
            qualifier = sf.parent.name
            is_ar = qualifier.startswith("values-ar")
            rows.append(make_row(
                f"android.{qualifier}.strings.{m.group(1)}", G_ANDROID, qualifier,
                m.group(1), m.group(2) if is_ar else "", "" if is_ar else m.group(2),
                xml_comment_above(lines, i), rel, i + 1, "xml"))

    for rel in ["android/app/src/main/AndroidManifest.xml",
                "android/app/src/debug/AndroidManifest.xml",
                "android/app/src/profile/AndroidManifest.xml"]:
        if not (REPO / rel).exists():
            continue
        lines = read_lines(rel)
        for i, line in enumerate(lines):
            for m in re.finditer(r'android:(label|description)="([^"@]+)"', line):
                # The owning element opens on this line or above it.
                j = i
                while j >= 0 and not re.search(r"<\w", lines[j]):
                    j -= 1
                tag = re.search(r"<([\w.-]+)", lines[j]).group(1)
                rid = f"android.{Path(rel).parent.name}.AndroidManifest.{tag}.{m.group(1)}"
                rows.append(make_row(
                    rid, G_ANDROID, f"AndroidManifest <{tag}>", f"{tag} android:{m.group(1)}",
                    "", m.group(2), xml_comment_above(lines, j), rel, i + 1, "xml"))
    return rows, [str(p.relative_to(REPO)) for p in strings_files]


# ---------------------------------------------------------------------------
# Server push copy (functions/)
# ---------------------------------------------------------------------------

class JsSource:
    def __init__(self, rel):
        self.rel = rel
        self.text = (REPO / rel).read_text(encoding="utf-8")
        self.lines = self.text.split("\n")
        self.used = set()

    def frag(self, literal):
        """A literal exactly as written in the source, quotes included.
        Fails when it is not in the file. Returns its rendered text."""
        if literal not in self.text:
            raise SystemExit(f"extract_native: {self.rel} no longer contains {literal!r}")
        self.used.add(literal)
        return render_js_literal(literal)

    def at(self, literal, start=0):
        """(file, 1-based line) where a literal starts."""
        off = self.text.find(literal, self.offset_of_line(start))
        if off < 0:
            off = self.text.find(literal)
        if off < 0:
            raise SystemExit(f"extract_native: {self.rel} no longer contains {literal!r}")
        return (self.rel, line_of_offset(self.text, off))

    def offset_of_line(self, idx):
        return sum(len(x) + 1 for x in self.lines[:idx])

    def line(self, needle, start=0):
        return find_line(self.lines, needle, start)

    def comment_above(self, idx):
        return c_comment_above(self.lines, idx)

    def uses(self, pattern, exclude_idx=()):
        """"file:line" for every line matching pattern, outside comments."""
        out = []
        for i, ln in enumerate(self.lines):
            s = ln.strip()
            if i in exclude_idx or s.startswith(("//", "*", "/*")):
                continue
            if re.search(pattern, ln):
                out.append(f"{self.rel}:{i + 1}")
        return out


def push_rows():
    rows = []
    idx = JsSource("functions/index.js")
    msg = JsSource("functions/room_messages.js")
    L = idx.lines
    banner_i = idx.line("── The three room events")
    events_section = "The three room events"

    def banner_event(letter):
        """The lettered paragraph for one event in the banner comment above
        the message tables ("A. FIRST_TODAY - ..."), and where it is."""
        start = None
        for k in range(banner_i, len(L)):
            if L[k].strip() == "*/":
                break
            if re.match(r"^\s*\*\s+" + letter + r"\.\s", L[k]):
                start = k
                continue
            if start is not None and (re.match(r"^\s*\*\s+[A-Z]\.\s", L[k])
                                      or L[k].strip() == "*"):
                end = k
                break
        else:
            end = None
        if start is None:
            raise SystemExit(f"extract_native: event {letter} not found in the banner")
        text = clean_comment_lines(L[start:end])
        note = (f"Reason also carries event {letter}'s paragraph from the banner comment at "
                f"functions/index.js:{banner_i + 1}.")
        return text, note

    def add(rid, section, key, ar, en, reason, src, decl_idx, ar_loc, en_loc, notes=(),
            used_in=None, runtime_digits=False):
        rows.append(make_row(rid, G_PUSH, section, key, ar, en, reason, src.rel,
                             decl_idx + 1, "js", ar_loc=ar_loc, en_loc=en_loc,
                             notes=list(notes), used_in=used_in,
                             arabic_digits_runtime=runtime_digits))

    def table_uses(name, decl):
        return idx.uses(r"\b" + re.escape(name) + r"\b", exclude_idx=(decl,))

    # Event A: first to finish today. The Arabic agrees with the FINISHER.
    c = idx.line("const FIRST_TODAY_MESSAGES = {")
    ev_text, ev_note = banner_event("A")
    creason = join_reason(idx.comment_above(c), ev_text)
    used = table_uses("FIRST_TODAY_MESSAGES", c)
    en_t_lit = '`${finisherName} is first to finish in "${roomName}"`'
    en_b_lit = '"First one done today. Your turn."'
    en_t = idx.frag(en_t_lit)
    en_b = idx.frag(en_b_lit)
    for rid, key, ar_lit, en_text, en_lit in (
            ("push.FIRST_TODAY_MESSAGES.title#male", "FIRST_TODAY_MESSAGES.title (male finisher)",
             '`${finisherName} أول من أنهى في "${roomName}"`', en_t, en_t_lit),
            ("push.FIRST_TODAY_MESSAGES.title#female", "FIRST_TODAY_MESSAGES.title (female finisher)",
             '`${finisherName} أول من أنهت في "${roomName}"`', en_t, en_t_lit),
            ("push.FIRST_TODAY_MESSAGES.body#male", "FIRST_TODAY_MESSAGES.body (male finisher)",
             '"أول واحد يخلّص اليوم. دورك."', en_b, en_b_lit),
            ("push.FIRST_TODAY_MESSAGES.body#female", "FIRST_TODAY_MESSAGES.body (female finisher)",
             '"أول وحدة تخلّص اليوم. دورك."', en_b, en_b_lit)):
        add(rid, events_section, key, idx.frag(ar_lit), en_text, creason, idx, c,
            idx.at(ar_lit, c), idx.at(en_lit, c), [ev_note], used)

    # Event C: perfect day.
    c = idx.line("const ROOM_PERFECT_MESSAGES = {")
    ev_text, ev_note = banner_event("C")
    creason = join_reason(idx.comment_above(c), ev_text)
    used = table_uses("ROOM_PERFECT_MESSAGES", c)
    for rid, key, ar_lit, en_lit in (
            ("push.ROOM_PERFECT_MESSAGES.title", "ROOM_PERFECT_MESSAGES.title",
             '`يوم كامل في "${roomName}" 🎉`', '`Perfect day in "${roomName}" 🎉`'),
            ("push.ROOM_PERFECT_MESSAGES.body", "ROOM_PERFECT_MESSAGES.body",
             '"الكل خلّص عاداته اليوم."', '"Everyone finished today."')):
        add(rid, events_section, key, idx.frag(ar_lit), idx.frag(en_lit), creason, idx, c,
            idx.at(ar_lit, c), idx.at(en_lit, c), [ev_note], used)

    # Event B, opt-in playful variant. The Arabic agrees with the READER.
    c = idx.line("const NUDGE_MESSAGES = {")
    b_note_end = idx.line("const ROOM_PERFECT_MESSAGES = {") - 1
    b_note_start = idx.line("* Event B's words live in room_messages.js") - 1
    b_note = clean_comment_lines(L[b_note_start:b_note_end])
    ev_text, ev_note = banner_event("B")
    creason = join_reason(idx.comment_above(c), ev_text, b_note)
    notes = [ev_note, f"Reason also carries the comment at functions/index.js:{b_note_start + 1}, "
                      "which is about this push."]
    used = table_uses("NUDGE_MESSAGES", c)
    en_b_lit = '"Still waiting on you."'
    title_ar, title_en = '`الكل خلّص في "${roomName}" 👀`', '`Everyone else finished in "${roomName}" 👀`'
    add("push.NUDGE_MESSAGES.title", events_section, "NUDGE_MESSAGES.title",
        idx.frag(title_ar), idx.frag(title_en), creason, idx, c,
        idx.at(title_ar, c), idx.at(title_en, c), notes, used)
    for rid, key, ar_lit in (("push.NUDGE_MESSAGES.body#male", "NUDGE_MESSAGES.body (male reader)", '"باقي أنت."'),
                             ("push.NUDGE_MESSAGES.body#female", "NUDGE_MESSAGES.body (female reader)", '"باقية أنتِ."')):
        add(rid, events_section, key, idx.frag(ar_lit), idx.frag(en_b_lit), creason, idx, c,
            idx.at(ar_lit, c), idx.at(en_b_lit, c), notes, used)

    # A habit was added to a shared room's plan.
    c = idx.line("const HABIT_ADDED_MESSAGES = {")
    creason = idx.comment_above(c)
    used = table_uses("HABIT_ADDED_MESSAGES", c)
    t_ar, t_en = '`عادة جديدة في "${roomName}"`', '`New habit in "${roomName}"`'
    add("push.HABIT_ADDED_MESSAGES.title", "notifyRoomHabitAdded", "HABIT_ADDED_MESSAGES.title",
        idx.frag(t_ar), idx.frag(t_en), creason, idx, c, idx.at(t_ar, c), idx.at(t_en, c), (), used)
    b_ar1, b_ar2 = '`انضافت «${habitName}» للخطة. اربطها من عندك وتبدأ تنحسب لك `', '"من اليوم \\u{1F331}"'
    b_en1, b_en2 = '`"${habitName}" was added to the plan. Link it on your side and `', '"it counts for you from today \\u{1F331}"'
    add("push.HABIT_ADDED_MESSAGES.body", "notifyRoomHabitAdded", "HABIT_ADDED_MESSAGES.body",
        idx.frag(b_ar1) + idx.frag(b_ar2), idx.frag(b_en1) + idx.frag(b_en2),
        creason, idx, c, idx.at(b_ar1, c), idx.at(b_en1, c), (), used)

    # English stand-ins that reach events A and C and the nudge in BOTH
    # languages when the doc has no name.
    fin_i = idx.line('participant.displayName || "Someone"')
    room_i = idx.line('room.name || "your room"')
    note_i = idx.line("// Worded from the stored docs, not roomName's English")
    note = clean_comment_lines(L[note_i:note_i + 3])
    related = (f"Reason also carries the comment at functions/index.js:{note_i + 1}, which names this "
               "stand-in. The same English word is spliced into the Arabic pushes of events A and C "
               "and the nudge, so an Arabic reader can see it.")
    add("push.notifyRoomFinish.finisherName.fallback", "notifyRoomFinish",
        "finisherName fallback (no displayName)", "", idx.frag('"Someone"'),
        join_reason(idx.comment_above(fin_i), note), idx, fin_i,
        None, (idx.rel, fin_i + 1), [related])
    again = [i for i, ln in enumerate(L) if 'room.name || "your room"' in ln and i != room_i]
    room_notes = [related] + ([
        "The same stand-in is set again at " + ", ".join(f"functions/index.js:{i + 1}" for i in again)
        + " (the habit-added push), so it reaches that Arabic push too."] if again else [])
    add("push.notifyRoomFinish.roomName.fallback", "notifyRoomFinish",
        "roomName fallback (room has no name)", "", idx.frag('"your room"'),
        join_reason(idx.comment_above(room_i), note), idx, room_i,
        None, (idx.rel, room_i + 1), room_notes,
        [f"{idx.rel}:{i + 1}" for i in [room_i] + again])

    # Event B: the last one still to go (room_messages.js, lastOneMessage).
    ML = msg.lines
    header = clean_comment_lines(ML[0:ML.index(" */") + 1])
    fn_i = msg.line("function lastOneMessage(")
    fn_doc = msg.comment_above(fn_i)
    verb_i = msg.line("// The verb follows the number")
    verb_note = clean_comment_lines(ML[verb_i:verb_i + 2])
    ev_text, ev_note = banner_event("B")
    base_reason = join_reason(header, fn_doc, ev_text)
    base_notes = ["Reason joins the header comment of functions/room_messages.js, the doc comment of "
                  "lastOneMessage and event B's paragraph from the banner comment in functions/index.js."]
    section = "lastOneMessage (event B, last one still to go)"
    used = idx.uses(r"\blastOneMessageFor\s*\(")

    ar_block = msg.line('if (locale === "ar") {', fn_i)
    add("push.lastOneMessage.title.fallback", section, "lastOneMessage.title (room has no name)",
        msg.frag('"غرفتك"'), msg.frag('"Your room"'), base_reason, msg, fn_i,
        msg.at('"غرفتك"', fn_i), msg.at('"Your room"', fn_i),
        base_notes + ["The title is the room's own name when it has one; this is the stand-in."], used)

    ar_ask_lit = {1: '"سوي عادتك الحين"', 2: '"سوي عاداتك الحين"'}
    ar_ask = {k: msg.frag(v) for k, v in ar_ask_lit.items()}
    ar_named_lit, ar_all_lit = "`عند ${name} كل شي خلص.`", '"الكل خلّص."'
    ar_pair_lit = "`${opener} ${ask} ويصير يومكم كامل 🤝`"
    en_named_lit, en_all_lit = "`${name} is all done.`", '"Everyone else is done."'
    en_pair_lit = "`${opener} Do yours now and your day together is complete 🤝`"
    ar_named, ar_all, ar_pair_tpl = msg.frag(ar_named_lit), msg.frag(ar_all_lit), msg.frag(ar_pair_lit)
    en_named, en_all, en_pair_tpl = msg.frag(en_named_lit), msg.frag(en_all_lit), msg.frag(en_pair_lit)

    def subst(tpl, mapping):
        for k, v in mapping.items():
            tpl = tpl.replace("{" + k + "}", v)
        return tpl

    habits_label = {1: "one habit left", 2: "several habits left"}
    for opener_key, ar_op, en_op in (("named", ar_named, en_named), ("everyone", ar_all, en_all)):
        for h in (1, 2):
            add(f"push.lastOneMessage.body.pair.{opener_key}#{h}", section,
                f"lastOneMessage.body (room of two, "
                f"{'finisher named' if opener_key == 'named' else 'no usable name'}, {habits_label[h]})",
                subst(ar_pair_tpl, {"opener": ar_op, "ask": ar_ask[h]}),
                subst(en_pair_tpl, {"opener": en_op}),
                base_reason, msg, fn_i, msg.at(ar_pair_lit, fn_i), msg.at(en_pair_lit, fn_i),
                base_notes, used)

    ar_verb = {1: msg.frag('"خلّص"'), 2: msg.frag('"خلّصوا"')}
    en_verb = {1: msg.frag('"has"'), 2: msg.frag('"have"')}
    ar_count_lit = "`${arabicDigits(finished)} من ${arabicDigits(members)} ${verb} `"
    en_count_lit = "`${finished} of ${members} ${verb} finished today. Do yours now `"
    ar_count_tpl = msg.frag(ar_count_lit) + msg.frag("`اليوم. ${ask} ويصير يوم الغرفة كامل 🤝`")
    en_count_tpl = msg.frag(en_count_lit) + msg.frag("\"and the room's day is complete 🤝\"")
    for v in (1, 2):
        for h in (1, 2):
            ar_text = subst(ar_count_tpl, {"verb": ar_verb[v], "ask": ar_ask[h]})
            ar_text = ar_text.replace("{arabicDigits(finished)}", "{finished}") \
                             .replace("{arabicDigits(members)}", "{members}")
            add(f"push.lastOneMessage.body.count.{'one' if v == 1 else 'many'}#{h}", section,
                f"lastOneMessage.body (bigger room, {'1 finished' if v == 1 else '2+ finished'}, "
                f"{habits_label[h]})",
                ar_text, subst(en_count_tpl, {"verb": en_verb[v]}),
                join_reason(base_reason, verb_note), msg, fn_i,
                msg.at(ar_count_lit, fn_i), msg.at(en_count_lit, fn_i),
                base_notes + [f"Reason also carries the comment at functions/room_messages.js:{verb_i + 1}.",
                              "In Arabic, {finished} and {members} are written in Arabic-Indic digits "
                              "by arabicDigits()."],
                used, runtime_digits=True)

    # Coverage: every Arabic literal and every multi-word English literal in
    # functions/*.js must be one of the fragments above, or be listed.
    for rel in sorted(p.relative_to(REPO).as_posix() for p in (REPO / "functions").glob("*.js")):
        text = (REPO / rel).read_text(encoding="utf-8")
        used_frags = idx.used if rel.endswith("index.js") else msg.used if rel.endswith("room_messages.js") else set()
        for s0, e0, _q in scan_js(text):
            lit = text[s0:e0]
            covered = any(lit in u or u in lit for u in used_frags)
            rendered = render_js_literal(lit)
            where = f"{rel}:{line_of_offset(text, s0)}: {rendered}"
            if ARABIC_RE.search(rendered):
                if not covered:
                    COVERAGE["js_uncovered_arabic"].append(where)
            elif not covered and len(re.findall(r"[A-Za-z]{2,}", rendered)) >= 3 and " " in rendered:
                COVERAGE["js_unreviewed_english"].append(where)
    return rows


# ---------------------------------------------------------------------------
# Web pages
# ---------------------------------------------------------------------------

VOID_TAGS = {"meta", "link", "br", "input", "img", "hr", "source", "area", "base",
             "col", "embed", "param", "track", "wbr"}


class Node:
    def __init__(self, tag, attrs, line, parent):
        self.tag = tag
        self.attrs = attrs
        self.line = line
        self.parent = parent
        self.children = []

    def text(self, skip=("script", "style", "svg")):
        out = []
        for ch in self.children:
            if isinstance(ch, str):
                out.append(ch)
            elif ch.tag == "br":
                out.append(" ")
            elif ch.tag not in skip:
                out.append(ch.text(skip))
        return "".join(out)

    def iter(self):
        for ch in self.children:
            if isinstance(ch, Node):
                yield ch
                yield from ch.iter()

    def ancestor(self, tag):
        p = self.parent
        while p is not None:
            if p.tag == tag:
                return p
            p = p.parent
        return None


class TreeBuilder(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.root = Node("#root", {}, 0, None)
        self.stack = [self.root]

    def handle_starttag(self, tag, attrs):
        node = Node(tag, dict(attrs), self.getpos()[0], self.stack[-1])
        self.stack[-1].children.append(node)
        if tag not in VOID_TAGS:
            self.stack.append(node)

    def handle_startendtag(self, tag, attrs):
        node = Node(tag, dict(attrs), self.getpos()[0], self.stack[-1])
        self.stack[-1].children.append(node)

    def handle_endtag(self, tag):
        for k in range(len(self.stack) - 1, 0, -1):
            if self.stack[k].tag == tag:
                del self.stack[k:]
                return

    def handle_data(self, data):
        self.stack[-1].children.append(data)


def parse_html(rel):
    tb = TreeBuilder()
    text = (REPO / rel).read_text(encoding="utf-8")
    tb.feed(text)
    tb.close()
    return tb.root, text.split("\n")


def first(root, tag, **attrs):
    for n in root.iter():
        if n.tag == tag and all(n.attrs.get(k) == v for k, v in attrs.items()):
            return n
    return None


def page_header_comment(lines):
    """The first HTML comment inside <head> that is not a one-liner about a
    single tag: the page's own description, when it has one."""
    text = "\n".join(lines)
    head_end = text.find("</head>")
    m = re.search(r"<!--(.*?)-->", text[:head_end if head_end > 0 else len(text)], re.S)
    if not m:
        return ""
    return clean_comment_lines(("<!--" + m.group(1) + "-->").split("\n"))


def web_rows():
    rows = []

    def add(rid, section, key, ar, en, reason, rel, line, kind="html", ar_line=None, en_line=None,
            notes=None):
        rows.append(make_row(rid, G_WEB, section, key, norm_ws(ar), norm_ws(en), reason,
                             rel, line, kind,
                             ar_loc=(rel, ar_line or line), en_loc=(rel, en_line or line),
                             notes=notes))

    # --- /join/<code>: Arabic only --------------------------------------
    rel = "public/join/index.html"
    root, lines = parse_html(rel)
    sec = "Room invite page (/join/<code>)"
    t = first(root, "title")
    add("web.join.title", sec, "title", t.text(), "", "", rel, t.line)
    for prop in ("og:title", "og:description"):
        m = first(root, "meta", property=prop)
        add(f"web.join.meta.{prop}", sec, f"meta {prop}", m.attrs["content"], "",
            xml_comment_above(lines, m.line - 1), rel, m.line)
    card = first(root, "div", **{"class": "card"})
    for n in card.iter():
        label = None
        if n.tag == "h1":
            label = "h1"
        elif n.tag == "p":
            label = "p." + n.attrs["class"] if n.attrs.get("class") else "p"
        elif n.tag == "a":
            label = "a#" + n.attrs.get("id", "")
        if not label or not LETTER_RE.search(n.text()):
            continue
        add(f"web.join.{label}", sec, label, n.text(), "",
            xml_comment_above(lines, n.line - 1), rel, n.line)

    # --- /open: English only --------------------------------------------
    rel = "public/open/index.html"
    root, lines = parse_html(rel)
    sec = "Lock Screen control fallback page (/open)"
    header = page_header_comment(lines)
    t = first(root, "title")
    add("web.open.title", sec, "title", "", t.text(), header, rel, t.line,
        notes=["Reason is the page's own header comment."] if header else None)
    for n in first(root, "div", **{"class": "card"}).iter():
        if n.tag in ("h1", "p", "a") and LETTER_RE.search(n.text()):
            label = n.tag + ("#" + n.attrs["id"] if n.attrs.get("id") else "")
            add(f"web.open.{label}", sec, label, "", n.text(),
                xml_comment_above(lines, n.line - 1), rel, n.line)

    # --- /reset: Arabic in the HTML, English in the script ----------------
    rel = "public/reset/index.html"
    root, lines = parse_html(rel)
    full = "\n".join(lines)
    header = page_header_comment(lines)

    def js_dict(name):
        m = re.search(r"var\s+" + name + r"\s*=\s*\{(.*?)\};", full, re.S)
        start_line = line_of_offset(full, m.start())
        out = {}
        for km in re.finditer(r'(\w+)\s*:\s*"((?:[^"\\]|\\.)*)"', m.group(1)):
            value = km.group(2).replace('\\"', '"')
            line = start_line + m.group(1)[:km.start()].count("\n") + \
                m.group(0)[:m.group(0).index("{")].count("\n")
            out[km.group(1)] = (value, line)
        return out

    EN = js_dict("EN")
    AR_EXTRA = js_dict("AR_EXTRA")
    t = first(root, "title")
    doc_title_line = find_line(lines, "document.title = ")
    en_title = re.search(r'document\.title\s*=\s*"([^"]*)"', lines[doc_title_line]).group(1)
    add("web.reset.title", "Password reset page (/reset)", "title", t.text(), en_title,
        header, rel, t.line, en_line=doc_title_line + 1,
        notes=["Reason is the page's own header comment. The script sets the English title."])
    seen_keys = {}
    tnodes = [n for n in root.iter() if "data-t" in n.attrs]
    for n in tnodes:
        k = n.attrs["data-t"]
        seen_keys[k] = seen_keys.get(k, 0) + 1
    counter = {}
    for n in tnodes:
        k = n.attrs["data-t"]
        counter[k] = counter.get(k, 0) + 1
        section_node = n.ancestor("section")
        sec = "Password reset page (/reset)"
        if section_node is not None:
            c = xml_comment_above(lines, section_node.line - 1)
            if c:
                sec += ": " + c
        rid = f"web.reset.{k}" + (f"#{counter[k]}" if seen_keys[k] > 1 else "")
        en_value, en_line = EN.get(k, ("", None))
        ar_value = n.text()
        # The account's email is painted into the span that follows, so the
        # sentence the person reads ends with it.
        siblings = [ch for ch in n.parent.children if isinstance(ch, Node)]
        pos = siblings.index(n)
        if pos + 1 < len(siblings) and siblings[pos + 1].attrs.get("id") == "email":
            ar_value += " {email}"
            en_value += " {email}"
        reason = xml_comment_above(lines, n.line - 1)
        add(rid, sec, f"data-t={k}", ar_value, en_value, reason, rel, n.line, en_line=en_line)
    for k, (ar_value, ar_line) in AR_EXTRA.items():
        en_value, en_line = EN.get(k, ("", None))
        add(f"web.reset.{k}", "Password reset page (/reset): script-only strings",
            f"AR_EXTRA.{k} / EN.{k}", ar_value, en_value, "", rel, ar_line, en_line=en_line)
    unused_en = sorted(set(EN) - set(seen_keys) - set(AR_EXTRA))
    if unused_en:
        raise SystemExit(f"extract_native: reset EN keys with no Arabic twin: {unused_en}")

    # --- /support.html: English first, Arabic below -----------------------
    rel = "public/support.html"
    root, lines = parse_html(rel)
    sec = "Support page (/support.html)"
    t = first(root, "title")
    add("web.support.title", sec, "title", "", t.text(), "", rel, t.line)
    h1 = first(root, "h1")
    add("web.support.h1", sec, "h1", "", h1.text(), "", rel, h1.line)
    upd = first(root, "p", **{"class": "updated"})
    en_part, _, ar_part = upd.text().partition("·")
    add("web.support.p.updated", sec, "p.updated", ar_part, en_part, "", rel, upd.line)
    body_ps = [n for n in root.iter() if n.tag == "p" and not n.attrs.get("class")]
    en_intro = [n for n in body_ps if not n.attrs.get("dir") and first(n, "strong") is None]
    for i, n in enumerate(en_intro, 1):
        add(f"web.support.p.intro#{i}" if len(en_intro) > 1 else "web.support.p.intro", sec,
            "p (intro)", "", n.text(), "", rel, n.line)
    contacts = [n for n in root.iter() if n.tag == "div" and n.attrs.get("class") == "contact"]
    en_contact = next(c for c in contacts if not c.attrs.get("dir"))
    ar_contact = next((c for c in contacts if c.attrs.get("dir") == "rtl"), None)
    add("web.support.contact.label", sec, "div.contact strong",
        first(ar_contact, "strong").text() if ar_contact else "",
        first(en_contact, "strong").text(),
        "", rel, en_contact.line, ar_line=ar_contact.line if ar_contact else None)
    h2s = [n for n in root.iter() if n.tag == "h2"]
    en_h2 = [n for n in h2s if not n.attrs.get("dir")]
    ar_h2 = [n for n in h2s if n.attrs.get("dir") == "rtl"]
    for i, en in enumerate(en_h2):
        ar = ar_h2[i] if i < len(ar_h2) else None
        add(f"web.support.h2#{i + 1}" if len(en_h2) > 1 else "web.support.h2", sec, "h2",
            ar.text() if ar else "", en.text(), "", rel, en.line,
            ar_line=ar.line if ar else None)
    en_q = [n for n in body_ps if not n.attrs.get("dir") and first(n, "strong") is not None]
    ar_q = [n for n in body_ps if n.attrs.get("dir") == "rtl" and first(n, "strong") is not None]

    def q_and_a(p):
        q = first(p, "strong").text()
        whole = p.text()
        return norm_ws(q), norm_ws(whole.replace(q, "", 1))

    for i, en in enumerate(en_q):
        ar = ar_q[i] if i < len(ar_q) else None
        eq, ea = q_and_a(en)
        aq, aa = q_and_a(ar) if ar else ("", "")
        note = ("The English and Arabic questions are paired by their order on the page." if ar
                else "The page has no Arabic version of this question.")
        add(f"web.support.faq#{i + 1}.question", sec + ": Common questions", "faq question",
            aq, eq, "", rel, en.line, ar_line=ar.line if ar else None, notes=[note])
        add(f"web.support.faq#{i + 1}.answer", sec + ": Common questions", "faq answer",
            aa, ea, "", rel, en.line, ar_line=ar.line if ar else None, notes=[note])

    # --- /privacy.html: English only, itemised like support.html -----------
    rel = "public/privacy.html"
    root, lines = parse_html(rel)
    base_sec = "Privacy policy page (/privacy.html)"
    main_activity = REPO / "android/app/src/main/kotlin/com/growdaily/v2/MainActivity.kt"
    rationale = (main_activity.exists()
                 and "privacy.html" in main_activity.read_text(encoding="utf-8"))
    page_note = ("English only: the page has no Arabic version."
                 + (" Android Health Connect's permission rationale opens this page "
                    "(privacyPolicyUrl in MainActivity.kt)." if rationale else ""))
    t = first(root, "title")
    add("web.privacy.title", base_sec, "title", "", t.text(), "", rel, t.line, notes=[page_note])
    counters = {}
    current_h2 = None
    for n in first(root, "body").children:
        if not isinstance(n, Node) or n.tag in ("script", "style"):
            continue
        items = []
        if n.tag == "h1":
            items.append(("h1", n))
        elif n.tag == "h2":
            current_h2 = norm_ws(n.text())
            items.append(("h2", n))
        elif n.tag == "p":
            items.append(("p.updated" if n.attrs.get("class") == "updated" else "p", n))
        elif n.tag == "ul":
            items.extend(("li", li) for li in n.iter() if li.tag == "li")
        elif n.tag == "div" and n.attrs.get("class") == "contact":
            strong = first(n, "strong")
            label_text = strong.text() if strong else ""
            rest = norm_ws(n.text().replace(label_text, "", 1))
            add("web.privacy.contact.label", base_sec + ": contact", "div.contact strong",
                "", label_text, xml_comment_above(lines, n.line - 1), rel,
                strong.line if strong else n.line)
            add("web.privacy.contact.text", base_sec + ": contact", "div.contact",
                "", rest, "", rel, strong.line + 1 if strong else n.line)
            continue
        for label, node in items:
            text = node.text()
            if not LETTER_RE.search(text):
                continue
            counters[label] = counters.get(label, 0) + 1
            unique = label in ("h1", "p.updated")
            rid = f"web.privacy.{label}" + ("" if unique else f"#{counters[label]}")
            sec = base_sec if label in ("h1", "p.updated") or current_h2 is None \
                else f"{base_sec}: {current_h2}"
            add(rid, sec, label, "", text, xml_comment_above(lines, node.line - 1), rel, node.line)

    # --- Flutter web shell (web/) ------------------------------------------
    rel = "web/index.html"
    if (REPO / rel).exists():
        root, lines = parse_html(rel)
        sec = "Flutter web shell (web/index.html)"
        t = first(root, "title")
        add("web.shell.title", sec, "title", "", t.text(), "", rel, t.line)
        for name in ("description", "apple-mobile-web-app-title"):
            m = first(root, "meta", name=name)
            if m is not None:
                add(f"web.shell.meta.{name}", sec, f"meta {name}", "", m.attrs.get("content", ""),
                    xml_comment_above(lines, m.line - 1), rel, m.line)
    rel = "web/manifest.json"
    if (REPO / rel).exists():
        lines = read_lines(rel)
        data = json.loads("\n".join(lines))
        for name in ("name", "short_name", "description"):
            if name in data:
                li = find_line(lines, f'"{name}"')
                add(f"web.manifest.{name}", "Flutter web app manifest (web/manifest.json)", name,
                    "", data[name], "", rel, li + 1, kind="other")
    return rows


# ---------------------------------------------------------------------------

def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_OUT
    rows = []
    rows += ios_plist_rows()
    rows += swift_rows()
    a_rows, strings_files = android_rows()
    rows += a_rows
    rows += push_rows()
    rows += web_rows()

    ids = [r["id"] for r in rows]
    dupes = sorted({i for i in ids if ids.count(i) > 1})
    if dupes:
        raise SystemExit(f"extract_native: duplicate ids {dupes}")
    blob = json.dumps(rows, ensure_ascii=False, indent=2)
    if EM_DASH in blob:
        raise SystemExit("extract_native: an em dash survived into the output")

    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(blob + "\n", encoding="utf-8")

    counts = {}
    for r in rows:
        counts[r["source_group"]] = counts.get(r["source_group"], 0) + 1
    summary = {
        "row_count": len(rows),
        "counts_by_group": counts,
        "android_strings_xml_files": strings_files,
        "rows_with_em_dash_in_wording": EM_DASH_IDS,
        "rows_missing_arabic": [r["id"] for r in rows if not r["arabic"]],
        "rows_missing_english": [r["id"] for r in rows if not r["english"]],
        "coverage": COVERAGE,
    }
    summary_path = out.with_name("native_summary.json")
    summary_blob = json.dumps(summary, ensure_ascii=False, indent=2)
    if EM_DASH in summary_blob:
        summary_blob = summary_blob.replace(EM_DASH, EM_TOKEN)
    summary_path.write_text(summary_blob + "\n", encoding="utf-8")

    print(f"wrote {len(rows)} rows to {out}")
    for g, n in counts.items():
        print(f"  {g}: {n}")
    print(f"summary: {summary_path}")


if __name__ == "__main__":
    main()

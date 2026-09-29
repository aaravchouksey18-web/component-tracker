#!/bin/bash
# Static layout + theme lint. Runs as part of ./test.sh.
#
# This exists because a layout bug shipped through a clean test run and a clean
# render log. SectionLabel had become `HStack { Text; Rectangle }`, and because
# Rectangle is maximally greedy its rule competed with a Spacer in the card
# footer that embedded it — so the "IN STOCK" and "VALUE" captions drifted out
# of alignment with the numbers under them. Nothing failed: the tests asserted
# on data, and the render harness rasterises ScrollView content as empty, so the
# three views that contained the bug were blank images by construction.
#
# These four rules are the ones whose violations produce that class of failure.
# It is a lint, not a type checker: it reads text, so it can miss things and it
# can be over-broad. Where it is over-broad the escape hatch is an explicit
# `// lint:allow <rule>` on the offending line, so a suppression is always a
# visible decision rather than a quiet one.
set -uo pipefail
cd "$(dirname "$0")"

python3 - <<'PY'
import re, sys, pathlib, collections

SRC = pathlib.Path("Sources")
files = sorted(SRC.glob("*.swift"))
if not files:
    print("lint: no sources found"); sys.exit(1)

text = {f: f.read_text() for f in files}
# The one file allowed to hold literal colours: it defines the palettes.
PALETTE_FILE = "Design.swift"
# Transparency is theme-neutral, so `.clear` is not a theme violation.
# Semantic/system fonts would sidestep the monospace policy and the type scale.
# Anchored on `font(` so a property named `title` (`self.title = title`) is not
# mistaken for the `.title` font style — the exact false positive the first
# version of this rule produced.
SEMANTIC_FONT = re.compile(r'font\(\s*\.(?:title2?|headline|subheadline|body|caption|caption2|footnote)\b')

errors = []
def err(f, line_no, rule, msg):
    errors.append(f"{f.name}:{line_no}  [{rule}]  {msg}")

# ---------------------------------------------------------------- helpers

def strip_strings(src):
    """Blank out string literal contents, keeping offsets identical.

    Necessary before any brace matching: this codebase embeds paths and format
    strings containing `(` and `}` that would otherwise desynchronise the scan
    and make the whole layout check silently useless.
    """
    out = list(src)
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c == '\\' and i + 1 < n:
            if out[i] != '\n': out[i] = ' '
            if out[i+1] != '\n': out[i+1] = ' '
            i += 2
            continue
        if c == '"':
            # Count leading hashes: """...""" and #"..."# are both legal Swift.
            j = i - 1
            hashes = 0
            while j >= 0 and src[j] == '#':
                hashes += 1; j -= 1
            if hashes:
                closer = '"' + '#' * hashes
            else:
                closer = '"'
            out[i] = ' '
            i += 1
            while i < n:
                if src[i] == '\\':
                    out[i] = ' '; i += 1
                    if i < n: out[i] = ' '; i += 1
                    continue
                if src.startswith(closer, i):
                    for k in range(i, min(i + len(closer), n)):
                        if out[k] != '\n': out[k] = ' '
                    i += len(closer)
                    break
                if out[i] != '\n': out[i] = ' '
                i += 1
            continue
        i += 1
    return ''.join(out)

def match_forward(s, start, opens, closes):
    """Index of the closer matching the opener at `start`, or len(s)."""
    depth = 0
    for i in range(start, len(s)):
        if s[i] in opens:
            depth += 1
        elif s[i] in closes:
            depth -= 1
            if depth == 0:
                return i
    return len(s)

def stack_bodies(body):
    """Yield (kind, start, end) for the *content* of every HStack/VStack.

    The subtlety this had to get right: `HStack(spacing: 6) { ... }` puts its
    children in the trailing closure, not inside the parentheses. Scanning the
    parens sees only `spacing: 6` and finds nothing — which is exactly how the
    first version of this lint reported the SectionLabel regression as clean.
    """
    out = []
    for m in re.finditer(r'\b(HStack|VStack)\s*\(', body):
        close_paren = match_forward(body, m.end() - 1, '(', ')')
        j = close_paren + 1
        while j < len(body) and body[j] in ' \t\r\n':
            j += 1
        if j < len(body) and body[j] == '{':
            close_brace = match_forward(body, j, '{', '}')
            out.append((m.group(1), j + 1, close_brace))
    return out

# ---------------------------------------------------------------- rules

def check_theme(f, lines):
    """No literal colours outside Design.swift.

    This is the rule that keeps the light/dark toggle honest. A hardcoded
    colour in a leaf view compiles fine, looks right in whichever scheme it was
    written for, and then silently refuses to change — which is how half a
    window ends up dark-on-dark after a toggle.
    """
    if f.name == PALETTE_FILE:
        return
    for i, ln in enumerate(lines, 1):
        if "lint:allow theme" in ln:
            continue
        code = ln.split("//", 1)[0]
        for pat, msg in [
            (r'Color\s*\(\s*(?:\.sRGB|hex:|red:|\.white|\.black)',
             "literal colour — use Palette.* so it follows the light/dark toggle"),
            (r'#[0-9A-Fa-f]{6}\b',
             "hex literal — use Palette.*"),
            (r'\.(?:foregroundStyle|foregroundColor|background|fill|tint|stroke)\(\s*Color\s*\(',
             "literal colour in a paint modifier — use Palette.*"),
        ]:
            if re.search(pat, code):
                err(f, i, "theme", msg)

def check_fonts(f, lines):
    """Everything monospaced, everything on the explicit type scale."""
    for i, ln in enumerate(lines, 1):
        if "lint:allow font" in ln:
            continue
        code = ln.split("//", 1)[0]
        if "Font.system(" in code:
            # The call can wrap, so look at a small window rather than the line.
            chunk = "\n".join(lines[i-1:i+3])
            call = chunk.split(")")[0]
            if "design:" not in call:
                err(f, i, "font", "Font.system without `design: .monospaced` — columns of "
                                 "figures do not line up in a proportional face")
        if SEMANTIC_FONT.search(code):
            err(f, i, "font", f"`{SEMANTIC_FONT.search(code).group(0)}` — semantic sizes do "
                             "not scale here; use .ui()/.mono()/.field()")
        if "Font.custom(" in code or re.search(r'Font\s*\(\s*(?:name|size)\s*:', code):
            err(f, i, "font", "named font — an unresolvable .custom() falls back silently "
                             "with no error; use .system(design: .monospaced)")

def check_shapes(f, lines):
    """No curves, no depth, no fill. This aesthetic has none of the three."""
    banned = [
        (r'\bRoundedRectangle\b', "rounded rectangle"),
        (r'\bCapsule\s*\(', "capsule"),
        (r'\bCircle\s*\(', "circle"),
        (r'\bEllipse\s*\(', "ellipse"),
        (r'\.cornerRadius\s*\(', "corner radius"),
        (r'\.shadow\s*\(', "shadow"),
        (r'\b(?:Linear|Radial|Angular)Gradient\b', "gradient"),
    ]
    for i, ln in enumerate(lines, 1):
        if "lint:allow shape" in ln:
            continue
        code = ln.split("//", 1)[0]
        for pat, what in banned:
            if re.search(pat, code):
                err(f, i, "shape", f"{what} — this design has no curves, depth or fill")

# ------------------------------------------------- the layout contract

# Which structs count as "shared" is derived, not hand-listed: a `View` struct
# is shared if two or more *other* files construct it. GhostButton( is built in
# several views, so a flexible child inside it changes the width negotiation of
# all of them and the defect surfaces in whichever negotiates hardest. A struct
# only one file uses cannot do that.
DECL = re.compile(r'^\s*(?:public\s+|private\s+|fileprivate\s+)?struct\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*([^{]+)\{?')

structs = {}
for f, src in text.items():
    lines = src.splitlines()
    starts = []
    for i, ln in enumerate(lines):
        m = DECL.match(ln)
        if m and re.search(r'\bView\b', m.group(2)):
            starts.append((i, m.group(1)))
    for idx, (i, name) in enumerate(starts):
        end = starts[idx + 1][0] if idx + 1 < len(starts) else len(lines)
        structs[name] = (f, i, end)

usage = collections.defaultdict(set)
for f, src in text.items():
    for name in structs:
        built = len(re.findall(r'\b' + re.escape(name) + r'\s*[({]', src)) - \
               len(re.findall(r'struct\s+' + re.escape(name) + r'\b', src))
        if built > 0:
            usage[name].add(f.name)

shared = {n for n, fs in usage.items() if len(fs) >= 2}

# The flexible things. `maxWidth: .infinity` counts because that is how a
# greedy child is usually spelled; a bare `Spacer()` and `Divider()` are greedy
# by construction.
FLEX = [
    (re.compile(r'\bSpacer\s*\('),                 "Spacer()"),
    (re.compile(r'\bDivider\s*\('),                "Divider()"),
    (re.compile(r'maxWidth\s*:\s*\.infinity'),     ".frame(maxWidth: .infinity)"),
    (re.compile(r'maxHeight\s*:\s*\.infinity'),    ".frame(maxHeight: .infinity)"),
]

# A shape with only one dimension pinned is flexible on the other axis, which is
# what made `Rectangle().frame(height: 1)` swallow a card footer's width.
SHAPE = re.compile(r'\b(Rectangle|Color)\s*\(')
BOTH_DIMS = re.compile(r'\.frame\s*\([^)]*width[^)]*height', re.S)

def check_contract(name, body, file, base_line, user_by):
    for kind, s, e in stack_bodies(body):
        inner = body[s:e]
        if "lint:allow greedy" in inner:
            continue
        line = base_line + body.count("\n", 0, s) + 1
        for pat, label in FLEX:
            if pat.search(inner):
                err(file, line, "layout",
                    f"`{name}` is shared by {len(user_by[name])} files and holds {label} "
                    f"inside a {kind}. A flexible child here changes width negotiation in "
                    "every view that embeds it. Give it an explicit frame, or mark the line "
                    "`// lint:allow greedy` if the fill is genuinely intended.")
        for m in SHAPE.finditer(inner):
            tail = inner[m.end(): m.end() + 200]
            # Walk to the end of this modifier chain and see whether both
            # dimensions get pinned before anything else intervenes.
            nxt = re.search(r'\.(?!frame\b)', tail)
            chain = tail[:nxt.start()] if nxt else tail
            if "Rectangle" in m.group(0) and not BOTH_DIMS.search(chain):
                err(file, line, "layout",
                    f"`{name}` is shared by {len(user_by[name])} files and holds a Rectangle "
                    f"with only one axis pinned. In a {kind} it expands to fill the axis you "
                    "did not set. Pin both, or mark the line `// lint:allow greedy`.")

# ---------------------------------------------------------------- run

for f, src in text.items():
    lines = src.splitlines()
    check_theme(f, lines)
    check_fonts(f, lines)
    check_shapes(f, lines)

for name in sorted(shared):
    f, i, end = structs[name]
    raw = "\n".join(text[f].splitlines()[i:end])
    check_contract(name, strip_strings(raw), f, i + 1, usage)

unused = [n for n in sorted(structs) if n not in shared]
print(f"lint: {len(structs)} view structs, {len(shared)} shared "
      f"({', '.join(sorted(shared))})")
if unused:
    print(f"lint: {len(unused)} single-file ({', '.join(unused)})")

if errors:
    print(f"\n{len(errors)} lint error(s):\n")
    for e in errors:
        print("  " + e)
    sys.exit(1)
print("lint: clean")
PY

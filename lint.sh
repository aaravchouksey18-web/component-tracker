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
# These rules target the class of failure a passing test run cannot see.
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

# A font constructor and its first argument, so the rule can inspect the size
# without having to parse the whole call. Balanced parens are not attempted: a
# font call in this codebase is short, and the window below stops at the first
# close paren, which is the size argument in every form used.
FONT_CALL = re.compile(r'\.(?:ui|mono|field)\(\s*([^),]*(?:\([^)]*\))?[^),]*)')

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
                err(f, i, "font", "Font.system without an explicit `design:` — the default "
                                 "flips with the system setting rather than the skin")
        if SEMANTIC_FONT.search(code):
            err(f, i, "font", f"`{SEMANTIC_FONT.search(code).group(0)}` — semantic sizes do "
                             "not scale here; use .ui()/.mono()/.field()")
        if "Font.custom(" in code or re.search(r'Font\s*\(\s*(?:name|size)\s*:', code):
            err(f, i, "font", "named font — an unresolvable .custom() falls back silently "
                             "with no error; use .system(design: .monospaced)")
        # A font size must be a named role, never a number and never a skin
        # anchor read directly.
        #
        # The numeric-literal form of this rule was in place for the whole type
        # refactor and did not fire once, because there was nothing left to
        # catch: the 117 literals had already been replaced. It then missed the
        # four sites that read `SkinController.skin.bodySize` inside a font
        # constructor, which are equally outside the role system and equally
        # invisible to a grep for digits. A rule that only knows one spelling of
        # the thing it forbids is not a rule; both spellings are here now.
        if FONT_CALL.search(code):
            arg = FONT_CALL.search(code).group(1)
            if re.fullmatch(r'\s*SkinController\.skin\.[A-Za-z]+(\s*[+\-]\s*[0-9.]+)?\s*'
                            r'(,\s*[^)]*)?', arg):
                err(f, i, "font", "font size reads a skin anchor directly (`"
                                 + arg.strip() + "`) — use a Type.Role so the size is "
                                 "named and every skin moves together")
            elif re.match(r'\s*[0-9]', arg):
                err(f, i, "font", f"literal font size `{arg.strip()}` — use a Type.Role "
                                 "so the skin's type scale actually reaches this view")

# ------------------------------------------------- the layout contract

# Which structs count as "shared" is derived, not hand-listed: a `View` struct
# is shared if two or more *other* files construct it. GhostButton( is built in
# several views, so a flexible child inside it changes the width negotiation of
# all of them and the defect surfaces in whichever negotiates hardest.
#
# The `<...>` clause is load-bearing and was missing. `CardChrome` is declared
# `struct CardChrome<Content: View>: View {`, and the pattern that only allowed
# whitespace between the name and the colon did not match it — so the most
# structurally invasive view in the app, the one that owns a card's entire
# chrome, was invisible to this rule. The bug it missed was live for a full
# round of verification: transparent cards in Blueprint, 12 vertical grid lines
# running through the text, found by eye rather than by the linter that exists
# to find exactly that.
#
# Any regex-based linter has this shape of hole — a declaration form it does not
# anticipate is not reported, it is *absent*, and absence reads as clean. The
# count line below prints every struct it found, so a view silently dropping out
# of the list is at least visible.
DECL = re.compile(r'^\s*(?:public\s+|private\s+|fileprivate\s+)?struct\s+'
                  r'([A-Za-z_][A-Za-z0-9_]*)\s*(?:<[^>{]*>)?\s*:\s*([^{]+)\{?')

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
        built = 0
        for m in re.finditer(r'\b' + re.escape(name) + r'\s*[({]', src):
            line_start = src.rfind("\n", 0, m.start()) + 1
            if re.search(r'struct\s+$', src[line_start:m.start()]):
                continue          # the declaration, not a call
            built += 1
        if built > 0:
            usage[name].add(f.name)

shared = {n for n, fs in usage.items() if len(fs) >= 2}

# Which views get the layout contract, derived rather than hand-listed.
#
# The original rule checked only views constructed from two or more *files*, and
# that is the wrong boundary in both directions.
#
# Too narrow: `CardChrome` is declared `struct CardChrome<Content: View>: View`
# and used only from `ComponentListViews.swift`, so it failed the 2-file test and
# was never checked at all — the declaration form also defeated the struct
# regex, so it was invisible twice over. It is the view that owns a card's entire
# chrome, and the bug it shipped (transparent cards, so Blueprint's 24pt field
# grid ran through the text) was live through a full round of verification.
#
# Too broad: checking every view struct produced 58 errors, nearly all of them
# `Spacer()` inside a root view like `HistoryView` or `ExportSheet`. A root view
# negotiates its own width and has no parent to negotiate against; a `Spacer` in
# one is the ordinary way to push two things apart. 58 suppressions would be 58
# comments nobody reads, which is worse than no rule because it trains you to
# skip the output.
#
# The property that decides the rule is not "is it constructed" but "is it a
# composable component" — a view whose width is negotiated by a parent that is
# not visible in its own file. Two ways to be one, both derivable:
#
#   - built from two or more files, so no single reader can see every
#     constraint applied to it, or
#   - generic over its content, which is a declaration of intent to be
#     embedded: `struct CardChrome<Content: View>` exists to wrap somebody
#     else's layout.
#
# Everything else — a card, a list, a screen — is a root of its own sub-layout
# even when a parent technically constructs it. `Spacer()` inside a card's
# `HStack` is how you push a quantity away from a label; that is the idiom, not
# a defect. Applying the rule to those produced 58 findings, of which the
# overwhelming majority were correct code, and 58 suppressions is worse than no
# rule because it teaches you to skip the output.
#
# The generic clause is the actual bug fix. `CardChrome` — the view that owns a
# card's entire chrome, and the one that shipped transparent cards so the
# 24pt field grid showed through the text — is generic and built from one file,
# so it failed both halves of the old test and was never checked. It is now
# checked, and it is clean.
constructors = collections.defaultdict(set)   # view name -> files that build it
for name in structs:
    for f, src in text.items():
        for m in re.finditer(r'\b' + re.escape(name) + r'\s*[({]', src):
            line_start = src.rfind("\n", 0, m.start()) + 1
            if re.search(r'struct\s+$', src[line_start:m.start()]):
                continue          # the declaration, not a call
            # `struct Foo: View` also has to be excluded when the name is a
            # prefix of another declaration: `ComponentCard` matched
            # `struct ComponentCardGrid` under a plain `\b`, counted as declared
            # twice, and was reported as never constructed.
            constructors[name].add(f)
            break

def is_generic(name):
    f, _, _ = structs[name]
    return re.search(r'struct\s+' + re.escape(name) + r'\s*<', text[f]) is not None

def embedded(name):
    """True if some other view builds this one — anywhere, in any file."""
    return bool(constructors.get(name))

checked = shared | {n for n in structs if is_generic(n)}
roots = sorted(n for n in structs if n not in checked)

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

def blast(name, user_by):
    """How this view's internals can hurt, in terms the message can use."""
    n = len(user_by.get(name, ()))
    if n >= 2: return f"is built by {n} files"
    if n == 1: return "is built by one file"
    return "is a view struct"

def check_contract(name, body, file, base_line, user_by):
    for kind, s, e in stack_bodies(body):
        inner = body[s:e]
        if "lint:allow greedy" in inner:
            continue
        line = base_line + body.count("\n", 0, s) + 1
        for pat, label in FLEX:
            if pat.search(inner):
                err(file, line, "layout",
                    f"`{name}` {blast(name, user_by)} and holds {label} "
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
                    f"`{name}` {blast(name, user_by)} and holds a Rectangle "
                    f"with only one axis pinned. In a {kind} it expands to fill the axis you "
                    "did not set. Pin both, or mark the line `// lint:allow greedy`.")

def check_radius(f, lines):
    """Corner radius must come from the skin.

    Hardcoding one reintroduces exactly the bug `Skin.radius` was added to
    remove: a view that looks right in the skin you built it in and wrong in the
    other two, and only in that one view, which is the hardest kind to notice.
    """
    for i, ln in enumerate(lines, 1):
        if "lint:allow radius" in ln or f.name == PALETTE_FILE:
            continue
        code = ln.split("//", 1)[0]
        if re.search(r'cornerRadius\s*:\s*[0-9]', code):
            err(f, i, "radius", "literal corner radius — use Metrics.corner so the skin "
                                "controls it")
        if re.search(r'cornerRadius\s*:\s*SkinController', code):
            continue

# ---------------------------------------------------------------- run

for f, src in text.items():
    lines = src.splitlines()
    check_theme(f, lines)
    check_fonts(f, lines)
    check_radius(f, lines)

for name in sorted(checked):
    f, i, end = structs[name]
    raw = "\n".join(text[f].splitlines()[i:end])
    check_contract(name, strip_strings(raw), f, i + 1, usage)

# Print the full list, not just the shared subset. A view that quietly drops out
# of the checked set — because its declaration form changed, or because a
# rename broke a lookup — is indistinguishable from a view with nothing to
# complain about, and that is precisely how `CardChrome` went unchecked.
print(f"lint: {len(structs)} view structs; layout contract on {len(checked)} "
      f"composable, skipped {len(roots)}")
print(f"lint: composable ({', '.join(sorted(checked))})")
if roots:
    print(f"lint: self-contained, width negotiated in-tree ({', '.join(roots)})")
generic = sorted(n for n in structs if is_generic(n))
if generic:
    print(f"lint: generic ({', '.join(generic)})")

if errors:
    print(f"\n{len(errors)} lint error(s):\n")
    for e in errors:
        print("  " + e)
    sys.exit(1)
print("lint: clean")
PY

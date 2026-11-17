#!/usr/bin/env python3
"""Import upstream ink's compiler/runtime test suite as an InkSwift conformance corpus.

Reads `tests/Tests.cs` from a checkout of https://github.com/inkle/ink and writes:

* `Tests/SwiftInkRuntimeTests/Fixtures/Conformance/upstream-<Test>-<n>.ink` — every
  inline story, verbatim;
* `….ink.json` — the story compiled by inklecate (when inklecate accepts it);
* `….diagnostics.txt` — inklecate's errors/warnings/author messages (when any);
* `Tests/SwiftInkRuntimeTests/Conformance/Upstream*Tests.swift` — one Swift test per
  upstream test and mode, translated from the C# where the API maps.

Each upstream test runs in two modes, mirroring upstream's own `Normal` and
`JsonRoundTrip` fixtures: `native` (InkSwift compiler + runtime) and `runtime`
(inklecate compiler + InkSwift runtime). A test whose C# does not translate is
emitted `.disabled("conformance: not ported — …")` with the C# kept as a comment.

Known failures live in `known-failures.json` next to this script, as
`{"<Test>": {"native": "<reason>", "runtime": "<reason>"}}`; each becomes a
`.disabled(if: Conformance.skipsBacklog, "conformance: <reason>")` trait. Hand ports live in `overrides/<Test>.swift`
(the Swift body, using `c` and the same helpers as generated bodies).

This is a bootstrap: run it to (re)import upstream, then commit the output. Usage:

    scripts/conformance/import_upstream_tests.py <ink-checkout> <inklecate>
"""
import json
import os
import re
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
FIXTURES = os.path.join(ROOT, "Tests/SwiftInkRuntimeTests/Fixtures/Conformance")
SWIFT_DIR = os.path.join(ROOT, "Tests/SwiftInkRuntimeTests/Conformance")
HERE = os.path.dirname(os.path.abspath(__file__))
TESTS_PER_FILE = 30


# ---------------------------------------------------------------- C# scanning

def scan_string(src, i):
    """Return (end_index, kind, raw_value) for the string literal starting at i."""
    if src.startswith('@"', i):
        j, out = i + 2, []
        while True:
            if src[j] == '"':
                if src.startswith('""', j):
                    out.append('"')
                    j += 2
                    continue
                return j + 1, "verbatim", "".join(out)
            out.append(src[j])
            j += 1
    assert src[i] == '"'
    j, out = i + 1, []
    escapes = {"n": "\n", "t": "\t", "r": "\r", '"': '"', "\\": "\\", "'": "'", "0": "\0"}
    while src[j] != '"':
        if src[j] == "\\":
            nxt = src[j + 1]
            if nxt == "u":
                out.append(chr(int(src[j + 2:j + 6], 16)))
                j += 6
                continue
            out.append(escapes.get(nxt, nxt))
            j += 2
            continue
        out.append(src[j])
        j += 1
    return j + 1, "regular", "".join(out)


def method_bodies(src):
    """Yield (name, line, body_text) for each `public void TestX()` method."""
    for m in re.finditer(r"public void (Test\w*)\s*\(\s*\)\s*\{", src):
        depth, i = 1, m.end()
        while depth:
            c = src[i]
            if c == '"' or src.startswith('@"', i):
                i, _, _ = scan_string(src, i)
                continue
            if c == "'":
                i = src.index("'", i + 2) + 1 if src[i + 1] == "\\" else i + 3
                continue
            if src.startswith("//", i):
                i = src.index("\n", i)
                continue
            depth += {"{": 1, "}": -1}.get(c, 0)
            i += 1
        yield m.group(1), src.count("\n", 0, m.start()) + 1, src[m.end():i - 1]


def tokenize_strings(body):
    """Replace string literals with placeholders; return (text, literals)."""
    out, lits, i = [], [], 0
    while i < len(body):
        if body[i] == '"' or body.startswith('@"', i):
            end, kind, value = scan_string(body, i)
            out.append(f"__S{len(lits)}__")
            lits.append({"kind": kind, "value": value})
            i = end
            continue
        if body.startswith("//", i):
            end = body.find("\n", i)
            i = len(body) if end < 0 else end
            continue
        if body.startswith("/*", i):
            i = body.index("*/", i) + 2
            continue
        out.append(body[i])
        i += 1
    return "".join(out), lits


def statements(text):
    """Split placeholder text into top-level statements on `;`. A C# block
    (`if (…) { … }`, a lambda) stays inside one statement and is rejected later."""
    stmts, buf, depth = [], [], 0
    for c in text:
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        if depth == 0 and c == ";":
            s = "".join(buf).strip()
            if s:
                stmts.append(s)
            buf = []
            continue
        buf.append(c)
    s = "".join(buf).strip()
    if s:
        stmts.append(s)
    return stmts


def split_args(s):
    args, depth, buf = [], 0, []
    for c in s:
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        if c == "," and depth == 0:
            args.append("".join(buf).strip())
            buf = []
            continue
        buf.append(c)
    if "".join(buf).strip():
        args.append("".join(buf).strip())
    return args


def call_spans(text, name):
    """Yield (start, args_start, end) for each `name(...)` call in text."""
    for m in re.finditer(r"\b" + re.escape(name) + r"\s*\(", text):
        depth, i = 1, m.end()
        while depth:
            depth += {"(": 1, ")": -1}.get(text[i], 0)
            i += 1
        yield m.start(), m.end(), i


# ---------------------------------------------------------------- translation

UNPORTABLE = [
    (r"\bforeach\b|\bfor\s*\(|\bwhile\s*\(", "loops"),
    (r"=>|\bdelegate\b", "lambdas"),
    (r"BindExternalFunction|allowExternalFunctionFallbacks", "external functions"),
    (r"ObserveVariable|RemoveVariableObserver", "variable observers"),
    (r"EvaluateFunction|HasFunction", "EvaluateFunction"),
    (r"SwitchFlow|RemoveFlow|aliveFlowNames|currentFlowName", "flows"),
    (r"ToJson|LoadJson|CopyStateForBackgroundThreadSave|BackgroundSaveComplete", "state JSON save/load"),
    (r"\bInkList\b|ListValue|listDefinitions|\bnew InkListItem", "list API"),
    (r"storySeed|ResetState|ResetCallstack|ResetErrors", "state reset/seed"),
    (r"onError|onDidContinue|onMakeChoice|onEvaluateFunction|onChoosePathString", "story callbacks"),
    (r"TagsForContentAtPath|ContentAtPath|KnotContainerWithName|\.mainContentContainer", "content-by-path API"),
    (r"FindAll|\bparsedStory\b|Parsed\.|Runtime\.|\.content\b|\.ToString\(", "parsed hierarchy / runtime object model"),
    (r"string\.Format|StringParser|InkParser|CharacterRange|ListAllCharacterRanges", "compiler internals"),
    (r"VisitCountAtPathString|TurnsSince|currentTurnIndex|\.state\.", "story state API"),
    (r"ContinueAsync|asyncContinueComplete|\.Continue\s*\(\s*\w", "async continue"),
    (r"\bout\b|\bref\b|typeof|\bis\b|\bas\b|\(int\)|\(float\)|\(string\)|\bobject\b", "C# casts/type tests"),
    (r"\bif\s*\(|\btry\b|\bcatch\b|\busing\b|\bthrow\b", "C# control flow"),
    (r"\bnew\b(?!\s*List<string>)", "object construction"),
]


def swift_string(value):
    v = (value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
         .replace("\t", "\\t").replace("\r", "\\r").replace("\0", "\\0"))
    return '"' + v + '"'


class Port(Exception):
    pass


def translate(name, body):
    """Translate a C# test body. Returns (stories, compile_flags, swift_lines)."""
    text, lits = tokenize_strings(body)
    stmts = statements(text)

    # Which literals are stories: passed (directly or via a variable) to
    # CompileString*. Variables are followed in order, as a test may reassign
    # its story string between compiles.
    var_assign = re.compile(r"^(?:var|string)?\s*(\w+)\s*=\s*__S(\d+)__$")
    current, story_lits, story_vars = {}, [], set()
    for s in stmts:
        m = var_assign.match(s)
        if m:
            current[m.group(1)] = int(m.group(2))
            continue
        for fn in ("CompileStringWithoutRuntime", "CompileString"):
            for _, a0, end in call_spans(s, fn):
                arg = split_args(s[a0:end - 1])[0]
                lit = re.fullmatch(r"__S(\d+)__", arg)
                if lit:
                    idx = int(lit.group(1))
                elif arg in current:
                    idx = current[arg]
                    story_vars.add(arg)
                else:
                    raise Port("story built at runtime")
                if idx not in story_lits:
                    story_lits.append(idx)
    stories = [lits[i]["value"] for i in story_lits]
    flags = {}
    var_lit = {}

    def compile_call(m_text, fn):
        args = split_args(m_text)
        arg0 = args[0]
        idx = int(arg0[3:-2]) if arg0.startswith("__S") else var_lit[arg0]
        n = story_lits.index(idx)
        named = []
        for a in args[1:]:
            k, _, v = a.partition(":")
            k, v = k.strip(), v.strip()
            if k == "testingErrors" and v == "true":
                named.append("testingErrors: true")
            elif k == "countAllVisits" and v == "true":
                named.append("countAllVisits: true")
                flags[n] = "countAllVisits"
            elif v in ("true", "false") and not k:
                raise Port("positional compile flags")
        helper = "compileWithoutRuntime" if fn == "CompileStringWithoutRuntime" else "compile"
        return f"c.{helper}({', '.join([str(n)] + named)})"

    def rewrite_calls(s, fn, make):
        while True:
            spans = list(call_spans(s, fn))
            if not spans:
                return s
            start, a0, end = spans[0]
            s = s[:start] + make(s[a0:end - 1]) + s[end:]

    assigned = {}
    out = []
    for s in stmts:
        m = var_assign.match(s)
        if m and m.group(1) in story_vars:
            var_lit[m.group(1)] = int(m.group(2))
            continue
        for pattern, why in UNPORTABLE:
            if re.search(pattern, s):
                raise Port(why)
        s = rewrite_calls(s, "CompileStringWithoutRuntime", lambda a: compile_call(a, "CompileStringWithoutRuntime"))
        s = rewrite_calls(s, "CompileString", lambda a: compile_call(a, "CompileString"))
        s = rewrite_calls(s, "Assert.AreEqual", lambda a: "c.equal(" + ", ".join(split_args(a)[:2]) + ")")
        s = rewrite_calls(s, "Assert.AreNotEqual", lambda a: "c.notEqual(" + ", ".join(split_args(a)[:2]) + ")")
        s = rewrite_calls(s, "Assert.IsTrue", lambda a: "c.isTrue(" + split_args(a)[0] + ")")
        s = rewrite_calls(s, "Assert.IsFalse", lambda a: "c.isFalse(" + split_args(a)[0] + ")")
        s = rewrite_calls(s, "Assert.IsNull", lambda a: "c.isNil(" + split_args(a)[0] + ")")
        s = rewrite_calls(s, "Assert.IsNotNull", lambda a: "c.isNotNil(" + split_args(a)[0] + ")")
        s = rewrite_calls(s, "Assert.Fail", lambda a: "c.fail(" + (split_args(a) or ['""'])[0] + ")")
        s = re.sub(r"new\s+List<string>\s*\{([^}]*)\}", r"[\1]", s)
        s = re.sub(r"new\s+List<string>\s*\(\s*\)", "[String]()", s)
        s = re.sub(r"\b_(error|warning|author)Messages\b", r"c.\1Messages", s)
        s = re.sub(r"\bHadError\s*\(", "c.hadError(", s)
        s = re.sub(r"\bHadWarning\s*\(", "c.hadWarning(", s)
        s = re.sub(r"\.ContinueMaximally\s*\(\s*\)", ".continueMaximally()", s)
        s = re.sub(r"\.Continue\s*\(\s*\)", ".continue()", s)
        s = re.sub(r"\.ChooseChoiceIndex\s*\(", ".chooseChoice(at: ", s)
        s = re.sub(r"(\w+)\.currentChoices\s*\[([^\]]+)\]\.", r"c.choice(\1, \2)?.", s)
        s = re.sub(r"\.(currentTags|globalTags)\s*\[([^\]]+)\]", r".\1[safe: \2]", s)
        s = re.sub(r"\bc\.(error|warning|author)Messages\s*\[([^\]]+)\]", r"c.\1Messages[safe: \2]", s)
        s = re.sub(r"\.Count\b(?!\s*\()", ".count", s)
        s = re.sub(r"\.Contains\s*\(", ".contains(", s)
        s = re.sub(r"\.StartsWith\s*\(", ".hasPrefix(", s)
        s = re.sub(r"\.EndsWith\s*\(", ".hasSuffix(", s)
        s = re.sub(r"\.hasError\b", ".currentErrors.isEmpty == false", s)
        s = re.sub(r"\.variablesState\s*\[\s*(__S\d+__)\s*\]\s*=\s*(.+)$", r".setVariable(\1, to: \2)", s)
        s = re.sub(r"\.variablesState\s*\[\s*(__S\d+__)\s*\]", r".getVariable(\1)", s)
        s = re.sub(r"\.ChoosePathString\s*\(\s*(__S\d+__)\s*\)", r".choosePath(\1)", s)
        s = re.sub(r"System\.Globalization\.NumberFormatInfo\.CurrentInfo\.NumberDecimalSeparator", '"."', s)
        s = re.sub(r"\bstring\.Empty\b", '""', s)
        s = re.sub(r"(\d+\.\d+)f\b", r"\1", s)
        s = re.sub(r"\bnull\b", "nil", s)
        leftover = re.findall(r"\b[A-Z]\w*\s*\(|\bvariablesState\b|\.state\b|\b[A-Z]\w*\.[A-Za-z]", s)
        if leftover:
            raise Port("unmapped API " + leftover[0].rstrip("( "))

        m = re.match(r"^(?:var|Story|Ink\.Runtime\.Story|string|int|bool|float)\s+(\w+)\s*=\s*(.+)$", s, re.S)
        if m:
            assigned[m.group(1)] = assigned.get(m.group(1), 0) + 1
            s = f"let {m.group(1)} = {m.group(2)}"
        else:
            m = re.match(r"^(\w+)\s*=\s*(.+)$", s, re.S)
            if m and m.group(1) in assigned:
                assigned[m.group(1)] += 1
        if re.search(r"c\.compile|chooseChoice|choosePath", s):
            s = re.sub(r"^(let \w+ = |\w+ = )?", lambda mm: (mm.group(1) or "") + "try ", s, count=1)
        s = re.sub(r"(?<![+=])\s*\+\s*(?![+=])", " + ", s)
        s = re.sub(r"__S(\d+)__", lambda mm: swift_string(lits[int(mm.group(1))]["value"]), s)
        s = re.sub(r"\s*\n\s*", " ", s)
        out.append(s)

    reassigned = {k for k, v in assigned.items() if v > 1}
    lines = [re.sub(r"^let (\w+) =", lambda mm: ("var " if mm.group(1) in reassigned else "let ") + mm.group(1) + " =", l)
             for l in out]
    return stories, flags, lines


def stories_only(body):
    """Story literals for an untranslatable test (best effort, for fixtures only)."""
    text, lits = tokenize_strings(body)
    found = []
    var_lit = {m.group(1): int(m.group(2)) for m in re.finditer(r"(?:var|string)\s+(\w+)\s*=\s*__S(\d+)__", text)}
    for fn in ("CompileStringWithoutRuntime", "CompileString"):
        for _, a0, end in call_spans(text, fn):
            arg = split_args(text[a0:end - 1])[0]
            lit = re.fullmatch(r"__S(\d+)__", arg)
            idx = int(lit.group(1)) if lit else var_lit.get(arg)
            if idx is not None and idx not in found:
                found.append(idx)
    return [lits[i]["value"] for i in sorted(found)]


# ---------------------------------------------------------------- output

def compile_fixture(inklecate, base, count_all_visits):
    cmd = [inklecate] + (["-c"] if count_all_visits else []) + ["-o", base + ".ink.json", base + ".ink"]
    env = dict(os.environ, LC_ALL="en_US.UTF-8", DOTNET_SYSTEM_GLOBALIZATION_INVARIANT="1")
    proc = subprocess.run(cmd, cwd=FIXTURES, capture_output=True, text=True, env=env, timeout=60)
    diagnostics = [l for l in (proc.stdout + proc.stderr).splitlines()
                   if re.match(r"^(ERROR|WARNING|TODO|RUNTIME ERROR|RUNTIME WARNING):", l)]
    diag_path = os.path.join(FIXTURES, base + ".diagnostics.txt")
    if diagnostics:
        open(diag_path, "w").write("\n".join(diagnostics) + "\n")
    elif os.path.exists(diag_path):
        os.remove(diag_path)
    return os.path.exists(os.path.join(FIXTURES, base + ".ink.json"))


def swift_name(test):
    return test[0].lower() + test[1:]


def emit_test(t, known):
    name = t["name"]
    reasons = known.get(name, {})
    lines = [f"    // MARK: {name} — Tests.cs:{t['line']}", ""]
    if t["body"] is None:
        lines.append(f"    /*  Upstream C# (not ported — {t['why']}):")
        lines += ["        " + l.rstrip() for l in t["csharp"].strip("\n").splitlines()]
        lines.append("    */")
        lines.append(f"    @Sendable private static func {swift_name(name)}(_ c: Conformance) throws {{")
        lines.append(f"        c.fail(\"not ported: {t['why']}\")")
    else:
        lines.append(f"    @Sendable private static func {swift_name(name)}(_ c: Conformance) throws {{")
        lines += ["        " + l for l in t["body"]]
    lines.append("    }")
    for mode in t["modes"]:
        reason = reasons.get(mode) or (f"not ported — {t['why']}" if t["body"] is None else None)
        trait = f"(.disabled(if: Conformance.skipsBacklog, \"conformance: {reason}\"))" if reason else ""
        label = "native compiler and runtime" if mode == "native" else "inklecate JSON on the runtime"
        lines.append("")
        lines.append(f"    @Test{trait}")
        lines.append(f"    func `{name} — {label}`() {{")
        lines.append(f"        Conformance.run(\"{name}\", .{mode}, Self.{swift_name(name)})")
        lines.append("    }")
    lines.append("")
    return lines


HEADER = """// GENERATED by scripts/conformance/import_upstream_tests.py from upstream ink
// (inkle/ink {rev}, tests/Tests.cs, MIT — see Fixtures/Conformance/UPSTREAM-LICENSE.txt).
// Each upstream test runs in two modes: `native` (InkSwift compiler + runtime) and
// `runtime` (inklecate's compiled JSON on the InkSwift runtime). `.disabled` here
// marks a BACKLOG item — a known gap, named in the reason — not unfinished work;
// see CLAUDE.md "Upstream conformance suite". Re-enable a test when its gap closes.

import Testing
@testable import SwiftInkRuntime

@Suite("Upstream ink conformance — {first} … {last}")
struct {struct_name} {{
"""


def main():
    ink, inklecate = sys.argv[1], sys.argv[2]
    rev = subprocess.run(["git", "-C", ink, "rev-parse", "--short", "HEAD"], capture_output=True, text=True).stdout.strip()
    src = open(os.path.join(ink, "tests", "Tests.cs"), encoding="utf-8").read()
    known = json.load(open(os.path.join(HERE, "known-failures.json")))
    os.makedirs(FIXTURES, exist_ok=True)
    os.makedirs(SWIFT_DIR, exist_ok=True)
    for f in os.listdir(FIXTURES):
        if f.startswith("upstream-"):
            os.remove(os.path.join(FIXTURES, f))
    for inc in ("test_included_file.ink", "test_included_file2.ink", "test_included_file3.ink", "test_included_file4.ink"):
        data = open(os.path.join(ink, "tests", inc), encoding="utf-8").read()
        open(os.path.join(FIXTURES, inc), "w").write(data)

    tests = []
    for name, line, body in method_bodies(src):
        override = os.path.join(HERE, "overrides", name + ".swift")
        try:
            stories, flags, swift = translate(name, body)
            why = None
        except Port as port:
            stories, flags, swift, why = stories_only(body), {}, None, str(port)
        if os.path.exists(override):
            swift = [l.rstrip("\n") for l in open(override).read().strip("\n").splitlines()]
            why = None
        accepted = True
        for n, story in enumerate(stories):
            base = f"upstream-{name}-{n}"
            open(os.path.join(FIXTURES, base + ".ink"), "w").write(story)
            accepted &= compile_fixture(inklecate, base, flags.get(n) == "countAllVisits")
        modes = ["native"] + (["runtime"] if accepted and stories else [])
        tests.append(dict(name=name, line=line, body=swift, why=why, csharp=body, modes=modes))

    for f in os.listdir(SWIFT_DIR):
        if f.startswith("Upstream") and f.endswith("Tests.swift"):
            os.remove(os.path.join(SWIFT_DIR, f))
    for i in range(0, len(tests), TESTS_PER_FILE):
        chunk = tests[i:i + TESTS_PER_FILE]
        struct_name = f"UpstreamConformance{i // TESTS_PER_FILE + 1:02d}Tests"
        text = HEADER.format(rev=rev, first=chunk[0]["name"], last=chunk[-1]["name"], struct_name=struct_name)
        for t in chunk:
            text += "\n".join(emit_test(t, known)) + "\n"
        text = text.rstrip("\n") + "\n}\n"
        open(os.path.join(SWIFT_DIR, struct_name + ".swift"), "w").write(text)

    ported = sum(t["body"] is not None for t in tests)
    print(f"{len(tests)} tests: {ported} ported, {len(tests) - ported} not ported; "
          f"{sum(len(t['modes']) for t in tests)} Swift tests")


if __name__ == "__main__":
    main()

# Diffing two builds and classifying the result

The reliable way to judge compatibility between two versions of a binary is a
**type-aware diff** of the built artifacts. Scripts `diff-abi.sh` and
`check-abi-verdict.sh` automate this file's procedure; read this to interpret
their output or run the tools manually.

## Prerequisites that decide result quality

- **Debug info.** libabigail and abi-dumper read DWARF. Build both versions
  with `-g` (optimization level does not matter for the comparison). Without
  DWARF the tools degrade to **symbol-level** comparison — removals are
  still caught, but **type/layout changes become invisible**. A verdict from
  a symbol-only diff must be downgraded: "no symbol breaks; layout not
  verified" — that is `INCONCLUSIVE` for compatible-claims, still `BREAKING`
  if removals showed up.
  - Debug info may also live in split files
    (`/usr/lib/debug/.build-id/...`, `-dbgsym` packages) — libabigail flags:
    `--d1 <dir> --d2 <dir>`.
  - **debuginfod pitfall:** when DWARF is absent, libabigail queries the
    servers in `DEBUGINFOD_URLS` (set by default on Ubuntu/Fedora) and can
    **hang indefinitely** on a restricted network. Run diffs with
    `DEBUGINFOD_URLS=""` unless remote debug fetch is deliberately wanted
    (the skill's scripts do this). Verified on libabigail 2.4.0.
- **Same architecture** for both inputs; cross-arch diffs are meaningless.
- Compare **installed-equivalent artifacts** (the real `.so`), not `.a`
  archives or intermediate objects.

## Primary engine: libabigail

```bash
abidiff old/libfoo.so new/libfoo.so                    # human report
abidiff --stat old/libfoo.so new/libfoo.so             # summary counts only
abidiff --harmless old/libfoo.so new/libfoo.so         # include harmless diffs
abidiff --no-added-syms ...                            # hide additions (focus on damage)
abidiff --suppressions supp.ini ...                    # filter known-internal types
abidiff --d1 old/debug --d2 new/debug old.so new.so    # split debug info
```

**Exit code is a bitmask** — this is what scripts must test, not the text:

| Bit | Meaning |
|---|---|
| 0 (value 0) | no ABI change at all → COMPATIBLE |
| 1 (`ABIDIFF_ERROR`) | tool error — result is void, do not conclude anything |
| 2 (`ABIDIFF_USAGE_ERROR`) | bad invocation — void |
| 4 (`ABIDIFF_ABI_CHANGE`) | some ABI change detected (may be additions or reviewable changes) |
| 8 (`ABIDIFF_ABI_INCOMPATIBLE_CHANGE`) | change libabigail *proves* incompatible → BREAKING |

So: `0` → compatible; `4` → read the report and classify; `12` → breaking;
odd values → invalid run. `4` without `8` is **not automatically safe**.
Verified against libabigail 2.4.0: bit 8 fires for provable cases such as
removed symbols and **vtable changes**, but a struct field insertion that
shifts existing member offsets returns bit 4 only — the layout damage is in
the **report text** (`'int y' offset changed from 32 to 64`), not the exit
code. Therefore on exit 4, grep the report: an `offset changed` line for a
type crossing the interface is BREAKING by the classification rules of
`c-abi.md`; added symbols are fine; other sub-type changes (changed enum
values etc.) need human review. `check-abi-verdict.sh` encodes exactly this.

Reading the report:

- `Removed function symbols` / `Removed variable symbols` → BREAKING, always.
- `Added ...` → additions; compatible by themselves.
- `... changed type` sections: libabigail prints the exact field, old/new
  offset and size — an offset/size change in a public type is BREAKING;
  a change inside a type never exposed to consumers may be suppressible
  (see below).
- vtable changes are called out explicitly for C++ — BREAKING.

**Baselining** (compare against a stored reference instead of an old build):

```bash
abidw --out-file libfoo.abi new/libfoo.so     # XML corpus of the ABI
abidiff libfoo.abi newer/libfoo.so            # later: diff against the corpus
```

**Suppression files** keep verdicts honest by silencing only *known-private*
types (never public ones):

```ini
[suppress_type]
  name_regexp = ^internal_.*
[suppress_function]
  name_regexp = ^_priv_
```

Record in the report that suppressions were used and why.

## Secondary engine: abi-compliance-checker (ACC)

Independent implementation; useful as a second opinion on breaking verdicts
and for its HTML report artifact.

```bash
abi-dumper old/libfoo.so -o old.dump -lver 1.0    # needs -g builds
abi-dumper new/libfoo.so -o new.dump -lver 2.0
abi-compliance-checker -l libfoo -old old.dump -new new.dump
# report lands in compat_reports/libfoo/1.0_to_2.0/compat_report.html
```

Exit code 0 = compatible, non-zero = problems found (coarser than abidiff's
bitmask — read the report for the classification; it separates "Binary
Compatibility" from "Source Compatibility", which maps exactly onto this
skill's ABI-vs-API distinction).

**Verified blind spot (ACC 2.3 + ABI Dumper 1.2 + Vtable-Dumper 1.2):** in
this dump-based workflow ACC reported a class gaining a **virtual function**
as "Binary compatibility: 100%" with the new method listed only under Added
Symbols — no vtable-layout problem — while abidiff 2.4.0 proved the same
pair incompatible (exit 12). It did correctly flag a struct-layout change
(50%, data-type problem). Consequence: **never accept an ACC-clean result as
the verdict for C++ interfaces**; ACC is corroboration only, and abidiff (or
manual vtable analysis) decides.

When the engines disagree, arbitrate with ground truth (below) and say in
the verdict which engine claimed what.

## Ground truth / fallback: symbol tables and layout by hand

Always available (binutils only), catches the loud breaks:

```bash
nm -D --defined-only --with-symbol-versions old.so | awk '{print $3}' | sort > /tmp/o
nm -D --defined-only --with-symbol-versions new.so | awk '{print $3}' | sort > /tmp/n
comm -23 /tmp/o /tmp/n        # symbols REMOVED  → any output = BREAKING
comm -13 /tmp/o /tmp/n        # symbols ADDED    → additions
readelf -d old.so | grep SONAME ; readelf -d new.so | grep SONAME   # SONAME delta?
```

Layout spot-checks for specific public types (needs DWARF or BTF):

```bash
pahole -C crossing_struct old.so > /tmp/po
pahole -C crossing_struct new.so > /tmp/pn
diff -u /tmp/po /tmp/pn       # any offset/size delta = BREAKING
```

Limits of the fallback — state them in any verdict built on it: no type
changes, no vtable analysis, no parameter-type checks for C (names don't
encode types), no semantic checks. Symbol-clean + layout-unverified =
`INCONCLUSIVE` at best.

## End-to-end confirmation with a real consumer

When an existing consumer binary is available, close the loop:

```bash
LD_LIBRARY_PATH=/path/to/new LD_BIND_NOW=1 ldd -r ./old-consumer
#   pass: no undefined symbols / version errors
LD_LIBRARY_PATH=/path/to/new ./old-consumer --selftest   # or its real workload
```

This proves link-level compatibility and exercises semantics that no static
diff can see. It does **not** replace the diff (it only covers the symbols
this one consumer uses).

## Classification decision (mirrors `check-abi-verdict.sh`)

1. abidiff ran with DWARF, exit 0 → **COMPATIBLE**.
2. abidiff exit has bit 8, or removals in any engine/fallback, or the report
   shows `offset changed` for a crossing type → **BREAKING**.
3. abidiff exit 4 only, report shows additions + only suppressible/private
   changes → **COMPATIBLE_WITH_ADDITIONS** (list what was reviewed).
4. Only symbol-level evidence available and it is clean → **INCONCLUSIVE**
   ("no symbol breaks; type layout unverified — build with -g or install
   libabigail for a definitive verdict").
5. Tool errors, missing files, arch mismatch → **INCONCLUSIVE** with the
   reason. Never convert absence of evidence into a pass.

Write the result into `templates/abi-report.md`. The verdict is the
deliverable; wiring it into CI/release gates is out of scope.

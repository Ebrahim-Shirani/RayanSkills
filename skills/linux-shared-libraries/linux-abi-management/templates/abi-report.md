# ABI comparison report

<!-- Fill every field; write "none" or "not checked (reason)" rather than
     deleting a row. This report is the deliverable of Workflows 3/4. -->

## Summary

| | |
|---|---|
| **Verdict** | COMPATIBLE / COMPATIBLE_WITH_ADDITIONS / BREAKING / INCONCLUSIVE |
| Old artifact | `<path / package / version>` |
| New artifact | `<path / package / version>` |
| Architecture(s) judged | `<e.g. x86-64; note if others remain unjudged>` |
| Date / judged by | `<date> / <person or agent>` |

**One-paragraph rationale:** _why this verdict, naming the decisive
evidence._

## Environment

| | Old | New |
|---|---|---|
| Compiler & version | | |
| libc & version | | |
| Debug info (DWARF) present | yes/no | yes/no |

**ABI-relevant flag deltas between the builds:** _none, or list them
(`_FILE_OFFSET_BITS`, `_TIME_BITS`, visibility, dual-ABI macro, LTO,
pack/enum flags, sanitizers)._

## Evidence

### SONAME

- Old: `<soname or none>` — New: `<soname or none>` — `<unchanged | CHANGED (declared break)>`

### Engines run

| Engine | Ran? | Result |
|---|---|---|
| `abidiff` | yes/no (why not) | exit code + one-line summary |
| `abidiff --no-added-syms` | yes/no | exit code |
| `abi-compliance-checker` | yes/no (why not) | report path + one-line summary |
| `nm -D` symbol diff | yes/no | removed: N, added: M |
| `pahole` on crossing types | yes/no | types checked, deltas found |
| Consumer smoke test (`LD_BIND_NOW=1 ldd -r`, workload) | yes/no | consumer used + result |

### Findings (one row per individual change)

| # | Change | Layer (symbols/versions/layout/convention/linkage/semantics) | Classification | Mechanism / evidence |
|---|---|---|---|---|
| 1 | | | | |

### Suppressions / exclusions applied

_None, or: suppression file contents + justification (private types only)._

## Caveats and unverified areas

- _e.g. "semantic contracts not machine-checkable; judged from changelog"_
- _e.g. "aarch64 build not available; HFA-sensitive struct X unjudged there"_
- _e.g. "dlsym/interposition consumers cannot be enumerated statically"_

## If BREAKING: required decisions

- Owner approval: `<obtained from … on … / PENDING — do not ship>`
- SONAME bump: `<required: old → new / not required because (proof)>`
- Migration notes: `<per reference/migration.md, or link>`

## Reproduction

```bash
# exact commands to reproduce every evidence row, e.g.:
abidiff --harmless old/libX.so new/libX.so
nm -D --defined-only old/libX.so | sort > /tmp/o   # …
```

<!-- End of report. Wiring this verdict into release/CI processes is out of
     scope for the ABI judgment — hand the report to the release owner. -->

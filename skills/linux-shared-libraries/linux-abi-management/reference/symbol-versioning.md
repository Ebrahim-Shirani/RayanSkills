# Symbol versioning — judging compatibility of versioned interfaces

This file covers **how to read versioned symbols and judge whether a change
breaks consumers**. Designing or authoring a versioning scheme (writing
version scripts, choosing node names) is out of scope for this skill.

## The model

With GNU symbol versioning, a symbol's identity is the pair
**(name, version node)**, e.g. `pthread_create@GLIBC_2.34`.

- In the **provider**: `readelf -V lib.so` shows `.gnu.version_d` — the
  version nodes defined, and `readelf --dyn-syms` shows each symbol's node:
  - `foo@@V2` — the **default** version: what *new* links against this
    library bind to. Exactly one default per name.
  - `foo@V1` — a **non-default (compat)** version: kept only so *old*
    binaries keep resolving; new links can't get it (except via
    `dlvsym`/`.symver` tricks).
- In the **consumer**: `readelf -V consumer` shows `.gnu.version_r` — for
  each NEEDED library, exactly which version nodes it requires. This is the
  ground truth for "what does this binary need."

## Judgment rules

| Observation (old → new provider) | Verdict | Why |
|---|---|---|
| New symbols under a **new** version node; all old (name, version) pairs still defined | ADDITIONS | old consumers' `version_r` entries all still resolve |
| A (name, version) pair present in old is **absent** in new | BREAKING | any consumer that captured it fails at load: `version 'V1' not found` |
| Same name moved to a new default (`foo@@V2`) **and** old kept as `foo@V1` | ADDITIONS | the classic compatible-evolution pattern: old binaries bind V1, new bind V2 |
| Same name, same version, but the *behavior/signature behind* the node changed | BREAKING (semantic) | the pair is the promise; changing what it does breaks it invisibly to the loader |
| A **version node** disappears entirely (`version_d` entry gone) | BREAKING | all consumers requiring that node fail at load, even if same-named symbols exist unversioned |
| Library goes from unversioned → versioned, old bare names kept as default | usually ADDITIONS | unversioned references bind the default; **verify** with an old consumer (`ldd -r`) |
| Library goes from versioned → unversioned | BREAKING | consumers' `version_r` requirements cannot be satisfied |

## Verification commands

```bash
# Provider side: full (symbol, version) inventory, old vs new
nm -D --defined-only --with-symbol-versions old/libfoo.so | sort > /tmp/old.sym
nm -D --defined-only --with-symbol-versions new/libfoo.so | sort > /tmp/new.sym
diff -u /tmp/old.sym /tmp/new.sym
# Any line deleted (not merely moved) that is a (name@VER) pair = BREAKING.

# Consumer side: what does an existing binary actually require?
readelf -V ./consumer | sed -n '/.gnu.version_r/,$p'

# Prove an old consumer still resolves against the new provider:
LD_LIBRARY_PATH=/path/to/new LD_BIND_NOW=1 ldd -r ./consumer
# Pass: no 'undefined symbol' and no 'version ... not found' lines.
```

`abidiff` also understands versions and will report removed versioned symbols
— see `regression-and-diffing.md`.

## glibc versions as a consumer-side ABI constraint

The most common versioning question is not about your library but about
glibc: a binary built on a newer distro carries e.g.
`memcpy@GLIBC_2.14` / `GLIBC_2.34` requirements and fails on older systems
with `version 'GLIBC_2.34' not found`.

Judgment method:

```bash
# Max glibc version a binary demands:
readelf -V ./binary | grep -o 'GLIBC_[0-9.]*' | sort -uV | tail -1
# Compare against the *oldest* target system's glibc:
ldd --version   # on the target
```

Verdict: the binary is compatible with every system whose glibc ≥ that
maximum node. This is a *deployment floor* judgment, not a defect in either
binary. (Choosing build baselines to lower the floor is a build/packaging
concern — out of scope; report the floor and stop.)

## kernel Module.symvers versioning

Kernel symbol CRCs (`CONFIG_MODVERSIONS`) are a different mechanism with the
same shape — (symbol, checksum) pairs that must match. Covered in
`kernel-abi.md`.

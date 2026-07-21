---
name: "Linux Shared Library Release"
description: >
  Run the complete release process for a Linux shared library (.so): judge
  ABI compatibility against the previous release's committed baseline
  (abidiff), compute the next MAJOR.MINOR.PATCH+BUILD, bump SOVERSION and
  SONAME only on a proven ABI break, wire VERSION/SOVERSION/SONAME and the
  symlink chain through the project's native build system (CMake, Meson,
  Autotools, Make, Bazel), run the pre-ship release gate, and produce the
  git tag, CHANGELOG, release note, dependency.md manifest, and new ABI
  baseline. Works for native builds, cross-compilation with a sysroot
  (e.g. Yocto/poky, aarch64), and remote builds over SSH. Use this skill
  whenever the user wants to release, version, bump, tag, or set up
  versioning for a shared library — including "cut a release", "what
  should the next version be", "did we break ABI since the last
  tag/release", "do I need to bump the SOVERSION", "generate release
  notes/changelog" for a library, adopting or continuing a repo that
  contains dependency.md or abi-baselines/, or fixing a library that
  shipped an ABI break without a SONAME bump. Do NOT use it for releasing
  executables or applications (no shared library involved), for building
  distro packages (-dev/runtime split), or for judging a patch's ABI
  impact when no release is intended.
---

# Linux Shared Library Release

This skill owns the release of a **shared library** end to end. The single
idea underneath: for a library, the version is not an opinion — the ABI diff
against the previous release is *evidence*, and the version is computed from
it. Everything else (build wiring, tag, changelog, manifest, baseline) exists
to make that computation repeatable at the next release.

## Version format and invariants

```
MAJOR.MINOR.PATCH+BUILD        e.g. 1.5.0+412.gc21b4e0
```

- **BUILD** = `<commit-count>.g<short-hash>` from `scripts/build_meta.sh` —
  always generated, never asked from the user, recorded in the manifest and
  changelog but **never in the .so filename** (the realname stays
  `libNAME.so.MAJOR.MINOR.PATCH`).
- **Zero-reset:** a bump resets everything to its right (BUILD recomputed).
- **Leftmost wins:** the largest single change decides the whole bump.
- **Source of truth** for the current version: the last `vX.Y.Z` git tag;
  line 1 of `dependency.md` mirrors it.
- **SOVERSION** normally equals MAJOR and changes **only** on a proven ABI
  break. Never silently: a SONAME change abandons every existing consumer.

## The bump rule (ABI verdict → version)

Get the verdict in phase 3, then apply — leftmost wins against any
code-level classification from phase 4:

| Evidence | Bump |
|---|---|
| Verdict **BREAKING** (proven by abidiff) | MAJOR, **and** SOVERSION bump |
| Behavioral/semantic break, ABI unchanged (old callers would misbehave) | MAJOR; SOVERSION bump is a judgment call — ask the owner (see `references/soname-concepts.md`) |
| Verdict **COMPATIBLE_WITH_ADDITIONS** | at least MINOR |
| Verdict **COMPATIBLE**, code changed (fixes, internals, deps) | at least PATCH |
| Verdict **INCONCLUSIVE** | **stop** — fix the evidence (usually: rebuild with `-g`), never release on a guess |

The judgment is about the library's own contract, not any particular
application. For classifying the non-ABI changes (commit log, dependency
diff, toolchain diff), use the table in `references/bump-rules.md` — it
applies unchanged; the ABI verdict simply adds a floor to the result.

## The release workflow

Phases 0–3 gather facts, phase 4 judges, phases 5–7 write results.

### Phase 0 — Discover state (bootstrap if needed)

Check in the repo root: `dependency.md`? `v*` tag (`git tag --list 'v*'`)?
SONAME wiring in the build files (`SOVERSION`, `soversion:`,
`-version-info`, `-Wl,-soname`)? An `abi-baselines/` directory?

**All present** → normal release, continue to phase 1.

**First run** → bootstrap, in this order:

1. Ask the user for the current version as MAJOR.MINOR.PATCH only (suggest
   `0.1.0` for a brand-new library). Never ask for BUILD.
2. If SONAME wiring is absent or wrong, wire it now through the native build
   system — detect the system by marker file and follow the matching
   `references/build-systems/*.md` (CMake / Meson / Autotools / Make /
   Bazel). Principles: use native facilities, single version source of
   truth, idempotent edits, SOVERSION = MAJOR (or `0` pre-1.0). Present the
   plan before editing build files. If wiring already exists, verify it
   instead (`references/validation.md`) — do not churn what is correct.
3. Determine the build mode (phase 1), build, and collect the snapshot
   (phase 2).
4. Save the first ABI baseline (`scripts/abi_baseline.sh save`), write
   `dependency.md` (`references/release-manifest.md`), generate
   `VERSIONING.md` from `templates/VERSIONING.md.template`, commit, tag
   `v<version>`. No bump on first run — there is nothing to compare against;
   tell the user the baseline is recorded.

**Partial state** (tag without manifest, baseline without tag, …) is
inconsistent: show what was found, let the user pick the authority.

### Phase 1 — Determine the build mode

Dependency and ABI facts are only real where the library is built for. Three
modes — **native**, **cross-sysroot**, **remote** (SSH) — with detection,
protocol, and abort rules in `references/target-detection.md`. Read the mode
from `dependency.md` (`target.mode`) when recorded; detect only on first
run; in remote mode without working SSH, follow the abort protocol — never
invent facts. One mode nuance for libraries: ABI tools (`abidw`, `abidiff`,
`readelf`) are execution-free, so in cross-sysroot mode *and* for artifacts
fetched from a remote target, all judgment runs on the host. The rule is: move
artifacts to the engine, never install tooling on targets — libabigail is
required on the machine running this skill, and in remote mode the built
library is fetched over SSH **unstripped** (or with its split `.debug`
file) before analysis (`references/abi-baselines.md`, "Where the engine
runs").

### Phase 2 — Build and collect the snapshot

Build the library **with `-g`** (DWARF is what makes the ABI verdict
type-aware; stripping happens after the baseline is saved). Then collect:

- **Toolchain:** compiler + version, language standard.
- **Declared dependencies** from the build files, ≤2 levels deep; classify
  in-house / third-party / standard.
- **Actual dependencies:** `scripts/extract_deps.py <lib> [--sysroot DIR]`
  reads DT_NEEDED and resolves versions. Binary truth beats build files;
  merge both.
- **Versions** per dependency, preferring SONAME/realname, then pkg-config,
  package manager, headers — record `version_source` each time.

Diff against the manifest snapshot: changed / added / removed.

### Phase 3 — ABI verdict against the committed baseline

```bash
scripts/abi_baseline.sh check build/libexample.so.1.4.2
```

Diffs the fresh build against the newest corpus in `abi-baselines/` and
prints exactly one `VERDICT:` line (COMPATIBLE /
COMPATIBLE_WITH_ADDITIONS / BREAKING / INCONCLUSIVE). Lifecycle, storage
policy, cross-arch rules, and why INCONCLUSIVE stops the release:
`references/abi-baselines.md`. To read a surprising abidiff report, open
`references/abi-diffing.md`. On BREAKING, show the user the removed/changed
items — an unintended break is a bug to fix, not a MAJOR to rubber-stamp;
only a *deliberate* break proceeds (and pairs with the SOVERSION bump).

### Phase 4 — Classify the rest and compute the version

Gather `git log <last-tag>..HEAD`, the dependency diff, the toolchain diff.
Classify each change with `references/bump-rules.md` (Conventional Commits
map directly when present; otherwise read the diffs; ask one precise
question when a change stays ambiguous). Combine with the ABI floor from
the table above: max bump wins, zero-reset, append BUILD from
`scripts/build_meta.sh`. **Show the user the computed version with the
per-change reasoning before writing anything** — this is the cheap moment to
catch a misclassification.

### Phase 5 — Apply the version to the build

Update the single version source of truth to the new MAJOR.MINOR.PATCH; on a
BREAKING release also raise SOVERSION (per the build-system reference in
use). Rebuild and confirm the artifacts: SONAME, symlink chain, consumer
DT_NEEDED (`references/validation.md`).

### Phase 6 — Release gate

```bash
scripts/release_gate.sh build/libexample.so.1.5.0 [--pc example.pc] [--consumer demo]
```

Execution-free pre-ship checks — SONAME convention, chain, DT_NEEDED
hygiene, RPATH, strip/debug split, TEXTREL, pkg-config agreement. Any FAIL
blocks the release; diagnose with `references/release-gate.md`. Strip order
matters: baseline first, then `--only-keep-debug`, `strip`,
`--add-gnu-debuglink` (the gate reference shows the sequence).

### Phase 7 — Write the release artifacts

1. **`abi-baselines/<version>/`** — `scripts/abi_baseline.sh save <lib>
   <version>` on the final (pre-strip) artifact.
2. **`dependency.md`** — rewrite per `references/release-manifest.md`: new
   version line 1, new snapshot, `library:` block (SONAME, SOVERSION,
   verdict, baseline path, libabigail version).
3. **`CHANGELOG.md`** (committed) and **`release_note_<version>.md`**
   (uncommitted — ensure `release_note_*.md` is gitignored): one entry per
   change — what, why, impact; note the ABI verdict.
4. Commit manifest + baseline + changelog together; **tag**
   `v<MAJOR.MINOR.PATCH>` on that commit.
5. Keep `VERSIONING.md` truthful — if the SOVERSION policy or version source
   moved, update it.

Do not push or open merge requests unless asked.

## Bundled resources

- `references/build-systems/{cmake,meson,autotools,make,bazel}.md` — native
  VERSION/SOVERSION wiring; open only the detected system's file.
- `references/soname-concepts.md` — VERSION vs SOVERSION vs SONAME, chain,
  when SOVERSION moves; read when explaining or deciding edge cases.
- `references/validation.md` — reading readelf/objdump/ldd output.
- `references/target-detection.md` — build-mode detection, SSH protocol,
  abort rules (phase 1).
- `references/bump-rules.md` — change classification beyond the ABI table
  (phase 4).
- `references/abi-baselines.md` — baseline lifecycle and policy (phase 3/7).
- `references/abi-diffing.md` — interpreting abidiff/ACC reports.
- `references/release-manifest.md` — dependency.md format (phase 0/7).
- `references/release-gate.md` — gate rationale and strip sequence (phase 6).
- `scripts/build_meta.sh <repo>` — BUILD component.
- `scripts/extract_deps.py <lib> [--sysroot DIR]` — ELF dependency JSON.
- `scripts/abi_baseline.sh save|check` — baseline lifecycle + verdict.
- `scripts/check-abi-verdict.sh <old> <new>` — direct two-binary verdict
  (adoption: compare two existing builds when no baseline exists yet).
- `scripts/release_gate.sh <lib>` — pre-ship checks.
- `templates/VERSIONING.md.template` — the policy document deliverable.

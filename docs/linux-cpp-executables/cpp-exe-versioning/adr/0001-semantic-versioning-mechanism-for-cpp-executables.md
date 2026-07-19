# ADR 0001 — Semantic versioning mechanism for C/C++ executables

- **Status:** Accepted
- **Date:** 2026-07-19
- **Skill:** `cpp-exe-versioning` (group `linux-cpp-executables`)

## Context

We need a repeatable mechanism that computes a release version for C/C++
applications whose final artifact is an **executable**, across three build
situations: native builds, cross-compilation with a sysroot on the host, and
projects whose build/test happens only on a remote target machine. The
mechanism must account for changes in the application's own code, in
libraries produced by the development team, in third-party/standard
libraries, and in the toolchain, and must produce auditable artifacts
(dependency manifest, release note, changelog, git tag).

A survey found no existing skill or dominant off-the-shelf tool for this in
the C/C++ ecosystem (`semantic-release` and `GitVersion` target other
ecosystems and do not handle sysroots/remote targets), so a custom skill was
designed.

## Decisions

### D1 — Version format `MAJOR.MINOR.PATCH+BUILD`

SemVer semantics: MAJOR = backward-incompatible behavior (configs, data,
CLI, workflows break), MINOR = backward-compatible new capability,
PATCH = fixes/invisible changes. Two invariants: **zero-reset** (a bump
zeroes all parts to its right, BUILD excepted) and **leftmost-wins** (one
release gets exactly one bump, decided by its most significant change).

### D2 — BUILD is generated, never asked

`<commit-count>.g<short-hash>` (e.g. `1.4.2+345.g7a3f9c1`). Commit count
alone is not unique across branches; the hash disambiguates. This is SemVer
build metadata (after `+`) and never participates in version comparison.

### D3 — Git tags are the source of truth

The current version is the last `vMAJOR.MINOR.PATCH` tag. Line 1 of
`dependency.md` mirrors it so a program can read its version with a one-line
file read.

### D4 — `dependency.md` is a committed, semi-machine-readable manifest

Line 1: bare version string. Then a YAML snapshot: target block (build mode,
triple, sysroot/ssh host, automation flag), toolchain (compiler, language
standard), and per-dependency records (name, kind: in-house/third-party/
standard, version, SONAME, `version_source`). Its git history is the
project's dependency history. Recording `version_source` guarantees each
release diffs like-for-like numbers.

### D5 — Three build modes with an explicit remote protocol

Detected from the build tool (toolchain file + `CMAKE_SYSROOT` ⇒
cross-sysroot; everything local ⇒ native; unresolvable paths ⇒ remote or
inconclusive). Inconclusive ⇒ ask the user once and persist the answer.
Remote mode: facts are collected over SSH; if the user provides access it is
recorded (`automated: true`) and reused on every activation; if access is
unavailable and not provided, the release **aborts** — host-machine library
versions must never be substituted for target facts.

### D6 — Executable-only scope; libraries via standard conventions only

This skill versions executables. It makes **no assumptions and requires no
custom interface** regarding how dependency libraries are versioned; the
only accepted assumption is standard shared-library convention (SONAME /
realname versions, pkg-config, package-manager metadata, ELF inspection).
Rationale: libraries have a different contract (API/ABI vs. behavior) and
different machinery (SOVERSION, abidiff); mixing both in one skill degrades
both. Library versioning will be a separate skill in a shared-libraries
group.

### D7 — Bump classification rules

- Language standard change (e.g. C++11→17): MAJOR.
- App code: fix ⇒ PATCH; compatible new capability ⇒ MINOR; breaks old
  configs/data/behavior ⇒ MAJOR.
- Dependency changed with zero app-code impact ⇒ PATCH (regardless of how
  big the dependency's own bump was — only the effect on this program
  counts). SONAME shortcut: same SONAME + realname minor/patch moved ⇒
  ABI-compatible by convention ⇒ PATCH without investigation.
- Dependency change adopted compatibly (new API used) ⇒ MINOR; propagated
  breakage to the app's own contract ⇒ MAJOR.
- Dependency added: MINOR if powering new user-visible capability, PATCH if
  internal; removed: PATCH if behavior unchanged, MAJOR if capability lost.
- Conventional Commits (`fix:`/`feat:`/`feat!:`+`BREAKING CHANGE`) map
  mechanically when present; otherwise diff reading, with precisely scoped
  user questions only for genuinely ambiguous cases.

### D8 — Dependency truth comes from the binary, not only the build tool

Declared dependencies are read from the build tool (≤2 levels), but the
built ELF's `DT_NEEDED` list (via bundled `extract_deps.py`, sysroot-aware,
pure file inspection so it works on cross-compiled artifacts) is
authoritative where available; the two are merged.

### D9 — Release artifacts

Per release: `dependency.md` rewritten and committed;
`release_note_<version>.md` generated but **not** committed (gitignored);
the same entries appended to a committed `CHANGELOG.md` (so history is not
lost); tag `v<MAJOR.MINOR.PATCH>`; optional `version.h.in` +
`configure_file` so the binary self-reports its version.

### D10 — Bootstrap for previously-versioned projects

On first run the skill asks only for the current **MAJOR.MINOR.PATCH**
(BUILD is generated), snapshots dependencies, commits `dependency.md`, and
tags — with no bump, since there is no previous snapshot to diff.

## Consequences

- Every later release is computable with at most a handful of targeted
  questions; fully automatic when Conventional Commits are used and target
  access is available.
- The committed `dependency.md` makes the convention self-documenting —
  benchmarks showed even a skill-less agent largely follows it once the file
  exists; the skill's value concentrates in bootstrap, mode handling, and
  edge-case correctness (e.g. total-commit-count BUILD, zero-reset).
- Aborting instead of guessing in unreachable-remote scenarios trades
  convenience for snapshot integrity.

## Test evidence

See `../tests/`: 3 eval scenarios × (with skill / baseline). With skill:
15/15 assertions, ~2× faster, low variance. Baseline: 11/15, and 1/5 on the
bootstrap scenario. Details in `tests/iteration-1/benchmark.md` and the
browsable `tests/iteration-1/review.html`.

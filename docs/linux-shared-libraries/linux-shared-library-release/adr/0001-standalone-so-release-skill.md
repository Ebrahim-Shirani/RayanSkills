# ADR 0001 — One standalone skill for the entire .so release process

- **Status:** Accepted (2026-07-20)
- **Owner decision, design review of 2026-07-20.** Supersedes group
  decisions D-A (composition-only architecture) and D-B (separate
  orchestrator); carries D-C and D-D forward unchanged.

## Context

The group originally planned single-responsibility tool skills
(`linux-shared-library-versioning`, `linux-abi-management`, plus reserved
`linux-library-validation` / `linux-library-packaging`) composed by a
release orchestrator. The 2026-07-20 review raised: no skill owned the
release *process*; cross-development was judged but not operationalized;
the validation skill overlapped its neighbors; and a large orchestrator
risked accuracy loss from resident context.

`cpp-exe-versioning` (202-line SKILL.md, on-demand references, non-loading
scripts, benchmarked well) demonstrates that one skill can own a full
release process across build systems while keeping resident context lean.
Total skill size is a disk cost; only resident context affects accuracy.

## Decision

Build **`linux-shared-library-release`** as a single, self-contained skill
owning the complete `.so` release process:

1. **Mechanism** — SONAME / SOVERSION / realname / symlink chain wired
   through the project's native build system (CMake, Meson, autotools,
   plain make). Salvaged from `linux-shared-library-versioning`.
2. **Judgment** — ABI comparison against the previous release baseline via
   libabigail; verdict ∈ {compatible, compatible-with-additions, breaking}.
   Methodology salvaged from `linux-abi-management`.
3. **Process** — next MAJOR.MINOR.PATCH from verdict (D-D: breaking ⇒
   MAJOR + SOVERSION bump; additions ⇒ MINOR; compatible ⇒ PATCH;
   leftmost-wins, zero-reset), baseline lifecycle, git tag `vX.Y.Z`,
   CHANGELOG (committed), release note (uncommitted), release manifest
   with `MAJOR.MINOR.PATCH+<commit-count>.g<short-hash>` (D-C — never in
   the `.so` filename).
4. **Gate** — pre-ship checklist (SONAME, symlink chain, DT_NEEDED, symbol
   visibility, RPATH hygiene, strip/debug split, pkg-config) as
   `references/release-gate.md` + `scripts/` check, loaded only in the
   gate phase.
5. **Target modes** — native / cross-sysroot / remote+SSH, mirroring
   `cpp-exe-versioning` Phase 1; libabigail tools are execution-free and
   safe on foreign-arch binaries.
6. **Engine placement (added 2026-07-20):** libabigail is required on the
   *analysis host* (where the skill runs), never on targets — artifacts
   move to the engine, not the engine to the target. Remote mode fetches
   the unstripped artifact (or its split `.debug`) over SSH before
   analysis. If the host cannot have libabigail, the portable `.abi` XML
   allows running the check on any reachable machine that does; the
   binutils-only fallback can prove BREAKING but never COMPATIBLE, so it
   may block but never green-light a release.

Structure: lean SKILL.md (~200 lines; workflow skeleton + decision rules
only), per-phase `references/*.md` loaded on demand, mechanical steps in
`scripts/` that execute without loading prose.

## Resolved questions

- **Q1 (granularity):** single skill with progressive disclosure; split
  only if skill-creator benchmarks (pass rate, tokens, time vs.
  `cpp-exe-versioning` iteration-1) show degradation.
- **Q2 (validation skill):** removed. A release gate is a phase of one
  process, not a reusable competency; a skill with a single caller is
  interface cost without reuse benefit.
- **Q3 (cross/remote helpers):** duplicated inside this skill to preserve
  self-containment. `cpp-exe-versioning`'s copy is the reference
  implementation. **Amended 2026-07-20:** shipped files must contain no
  cross-skill references whatsoever — the skill's users may have no access
  to or awareness of the rest of this repo, and runtime files must not
  point the executing agent at paths that don't exist for them. Provenance
  and sync tracking live in `docs/.../provenance.md` (development-only).
  Extraction into a shared skill is reconsidered only when a third
  consumer appears.
- **Q4 (baselines):** commit the `abidw` corpus per release under
  `abi-baselines/<version>/lib<name>.abi` (optionally xz); record the
  libabigail version in the manifest for reproducible verdicts.
  Regeneration from tagged builds is fallback only — rebuild-identical
  toolchains cannot be assumed, especially cross.

## Consequences

- If benchmarks pass (skill T003), `linux-shared-library-versioning` is
  removed (content absorbed). **`linux-abi-management` is kept** as a
  standalone CI/diagnostic utility (ABI checks on PRs need no release);
  this skill does not depend on it.
- Packaging (-dev/runtime split, deb/rpm) is out of scope; a future
  separate concern.
- Risk accepted: duplicated target-access helpers may drift from
  `cpp-exe-versioning`; mitigated by origin headers and a group-level
  sync check.

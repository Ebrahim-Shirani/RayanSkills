# TASKS — linux-shared-libraries (group-level)

Group-level design backlog for the **Linux shared-library release mechanism**.
Per-skill implementation backlogs stay in `docs/linux-shared-libraries/<skill>/TASKS.md`;
this file tracks work that spans the group.
Statuses: `TODO` · `IN_PROGRESS` · `DONE` · `BLOCKED` · `CANCELLED`.

---

## T001 — Design the .so release-mechanism architecture (group composition)

- **Status:** DONE — resolved 2026-07-20; superseded by the consolidation
  decision recorded below and in
  `linux-shared-library-release/adr/0001`. See "Resolution (2026-07-20)"
  at the end of this task.
- **ADR:** to be written (group-level ADR, see Deliverable 1)
- **Depends on:** —
- **Related:** `docs/linux-cpp-executables/cpp-exe-versioning/adr/0001` (the
  executable release mechanism whose conventions this group shares),
  `linux-shared-library-versioning` ADR 001, `linux-abi-management` ADR 001.

### Goal

Make the release process for Linux `.so` libraries **fully operational** as a
composition of single-responsibility skills, and record the architecture in a
group-level ADR before implementing anything further.

### Current state (as of 2026-07-20)

Implemented:

- **`linux-shared-library-versioning`** — wires the SONAME-level mechanism
  (VERSION / SOVERSION / SONAME / symlink chain) through the project's native
  build system; validates built artifacts; documents policy in
  `VERSIONING.md`. Deliberately does not decide versions.
- **`linux-abi-management`** — inspects/diffs binaries and delivers a verified
  ABI verdict (*compatible* / *compatible-with-additions* / *breaking*).
  Explicitly stops at the verdict; excludes release processes.

Planned (names reserved, not yet designed):

- **`linux-library-validation`** — necessity under question (see Open
  Questions).
- **`linux-library-packaging`** — -dev/runtime split, distro conventions.
  Uncontested; genuinely separate concern.

### Review findings to incorporate (from the 2026-07-20 architecture review)

1. **Missing orchestrator.** No skill owns the release *process*: computing
   the next MAJOR.MINOR.PATCH, owning the `abidw` baseline lifecycle (commit
   an `.abi` corpus per release, diff against it at the next), mapping the
   ABI verdict to VERSION/SOVERSION bumps, git tags, CHANGELOG, release
   notes, or a dependency manifest. `abidw --out-file` appears once in
   `linux-abi-management/reference/regression-and-diffing.md` as a technique,
   but no skill operationalizes baselines. Without this, the group is a
   toolbox, not a release process.
2. **Cross-compilation gap in `linux-abi-management`.** The skill is
   architecture-*aware* in judgment (psABI references for x86-64/AArch64,
   "state target architectures" checklist item, cross-arch-diff warning,
   `diff-abi.sh` reads the ELF Machine field) but not cross-development-
   *operational*: it never states its tools are execution-free and therefore
   safe on cross-compiled artifacts on the host; no sysroot handling for
   locating libraries and split debug files in a target rootfs; no remote
   mode (SSH fetch of artifacts, persisted target record, abort-instead-of-
   guess); no cross-toolchain debug-info guidance (`-g`, separate `.debug`
   files). Proposed resolution: solve once at the process level — the
   orchestrator owns the target-mode model (native / cross-sysroot /
   remote+SSH), mirroring `cpp-exe-versioning`'s Phase 1 design — rather
   than patching each tool skill.
3. **`linux-library-validation` overlap.** As named it overlaps
   `linux-shared-library-versioning` §4 Validate (SONAME, symlink chain,
   DT_NEEDED) and `linux-abi-management` (compatibility). Either recharter
   as a *release gate* — an aggregator running the full pre-ship checklist
   (SONAME, chain, DT_NEEDED, symbol-visibility surface, RPATH hygiene,
   strip/debug split, pkg-config sanity) with a pass/fail report — or fold
   that role into the orchestrator and remove the skill. Owner is inclined
   to remove it if not actually necessary.

### Design decisions accepted so far (to be ratified in the group ADR)

- **D-A: Single-responsibility skills that compose; no custom interfaces.**
  Skills exchange only standard artifacts and well-defined files; the
  exchanged *file formats are the architecture* and must be documented in
  the group ADR (`.abi` corpus, `VERSIONING.md`, verdict report, release
  manifest).
- **D-B: A release orchestrator is required** (working name
  `linux-shared-library-release`). It computes the version, owns baselines,
  maps verdict→bump, drives the tool skills, produces tag + CHANGELOG +
  release note + manifest, and owns the target-mode model.
- **D-C: Conventions shared with `cpp-exe-versioning`** (by convention, not
  by interface): git tags `vX.Y.Z` as source of truth;
  `MAJOR.MINOR.PATCH+BUILD` with BUILD = `<commit-count>.g<short-hash>`
  recorded in the manifest/changelog — never in the `.so` filename (realname
  stays `X.Y.Z`); leftmost-wins and zero-reset bump rules; release note
  generated but uncommitted, CHANGELOG committed; bootstrap asks the user
  only for MAJOR.MINOR.PATCH.
- **D-D: SOVERSION decisions are ABI-verdict-driven.** *breaking* ⇒ MAJOR +
  SOVERSION bump (via `linux-shared-library-versioning`);
  *compatible-with-additions* ⇒ MINOR; *compatible* ⇒ PATCH; app-agnostic —
  the library's own contract is what's judged.

### Open questions (must be answered before finalizing)

- **Q1 — Orchestrator size vs. accuracy trade-off (owner's concern,
  2026-07-20).** A large orchestrator skill means a large always-loaded
  context during execution, which may reduce model accuracy. Analyze before
  committing to a single orchestrator. Options to evaluate:
  1. One orchestrator with aggressive progressive disclosure — lean SKILL.md
     (workflow skeleton only), per-phase `references/*.md` loaded on demand,
     mechanical steps pushed into `scripts/` that execute without loading
     prose into context (the `cpp-exe-versioning` pattern; its SKILL.md is
     ~220 lines and benchmarked well).
  2. Split the orchestrator: e.g. `…-release-versioning` (compute the bump)
     and `…-release-artifacts` (baselines, tag, changelog, manifest) — at
     the cost of one more inter-skill contract and a coordination burden on
     the invoking agent.
  3. Orchestrator as a thin "conductor" that delegates whole phases to the
     tool skills via the Skill mechanism and keeps only sequencing +
     decision rules resident.
  Evaluation method: draft option 1 first; measure SKILL.md size and
  benchmark with skill-creator evals (pass rate, tokens, time) as was done
  for `cpp-exe-versioning`; split only if the data shows degradation.
- **Q2 — Fate of `linux-library-validation`:** remove, or recharter as the
  release gate (possibly a *reference/checklist inside the orchestrator*
  instead of a standalone skill)? Decide together with Q1, since folding it
  in grows the orchestrator.
- **Q3 — Where do the cross/remote helpers live?** The framework requires
  everything a skill needs to ship inside it; `cpp-exe-versioning` already
  contains target-detection prose and an `extract_deps.py`. Duplicating in
  this group risks drift; a shared "target-access" skill adds an interface.
  Decide deliberately and record the reasoning.
- **Q4 — Baseline storage policy:** commit `.abi` corpora to the library
  repo per release (self-contained, grows the repo) vs. regenerate from
  tagged builds on demand (lean repo, requires rebuildability). Default
  leaning: commit, like `dependency.md`.

### Deliverables / next steps (in order)

1. Group-level ADR `docs/linux-shared-libraries/adr/001` — composition
   architecture, artifact-flow contracts, ratified decisions D-A…D-D,
   resolved Q1–Q4.
2. Decision record for `linux-library-validation` (remove / recharter),
   reflected in this file and in the group ADR.
3. Scaffold + author the orchestrator skill per the Q1 outcome (own
   `docs/<group>/<skill>/` mirror with ADR + TASKS.md).
4. Cross-mode note in `linux-abi-management` (small): state execution-free
   tool safety on foreign-arch binaries and point to the orchestrator for
   sysroot/remote acquisition.
5. Eval/benchmark the orchestrator with skill-creator (fixtures analogous to
   the `cpp-exe-versioning` iteration-1 set, plus an ABI-break scenario).
6. Design `linux-library-packaging` last; it consumes the release outputs.

### Acceptance criteria

- Group ADR exists and answers Q1–Q4 with reasoning.
- Every inter-skill artifact (producer, consumer, format, location) is
  documented in the ADR.
- The release pipeline table (mechanism / judgment / process / gate /
  packaging) has an owner for every row, with no orphan steps.
- Benchmarked evidence supports the chosen orchestrator granularity.

### Resolution (2026-07-20)

Owner decision after design review: **consolidate into one standalone skill,
`linux-shared-library-release`**, that owns the entire `.so` release process
(mechanism + judgment + process + gate) across all build systems — the
`cpp-exe-versioning` pattern, not an orchestrator over tool skills.

- **Q1** → single skill with aggressive progressive disclosure (lean
  SKILL.md, per-phase references, non-loading scripts); split only if
  skill-creator benchmarks show degradation.
- **Q2** → `linux-library-validation` removed; release gate is a reference +
  script inside the new skill.
- **Q3** → target-access helpers duplicated inside the new skill;
  `cpp-exe-versioning` is the named reference implementation. Amended
  2026-07-20: shipped files carry NO cross-skill references (the skill must
  be standalone at runtime); provenance/sync tracking lives in
  `docs/linux-shared-libraries/linux-shared-library-release/provenance.md`.
  Rule-of-three trigger for future extraction.
- **Q4** → commit `.abi` corpora per release
  (`abi-baselines/<version>/`, libabigail version recorded in the manifest);
  regeneration from tagged builds is the documented fallback only.

Consequences:

- D-A/D-B (composition + orchestrator) are **superseded**; D-C/D-D
  (shared conventions; verdict→bump mapping) are **carried into** the new
  skill unchanged.
- If benchmarks (new skill's T003) pass: remove
  `linux-shared-library-versioning` (content absorbed). **Keep
  `linux-abi-management`** as a standalone CI/diagnostic utility.
- Empty scaffolds `linux-library-validation` and `linux-library-packaging`
  slated for deletion (sandbox blocked it on 2026-07-20). Packaging stays a
  future, separate concern outside the new skill's scope.

## T002 — Deliver linux-shared-library-release

- **Status:** DONE (2026-07-20) — skill authored, benchmarked (100% vs 76%
  baseline, iteration 1), and consolidation executed: group now contains
  exactly `linux-shared-library-release` (the release process) and
  `linux-abi-management` (standalone CI/diagnostic utility).
  `linux-shared-library-versioning` and the empty validation/packaging
  scaffolds removed; removed skill's docs retained as history.
- **Backlog:** `docs/linux-shared-libraries/linux-shared-library-release/TASKS.md`

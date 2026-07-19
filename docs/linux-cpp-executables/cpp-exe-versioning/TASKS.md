# TASKS — cpp-exe-versioning

Development task backlog for the `cpp-exe-versioning` skill
(group `linux-cpp-executables`). Statuses: `TODO` · `IN_PROGRESS` · `DONE` ·
`BLOCKED` · `CANCELLED`.

## T001 — Design the versioning mechanism

- **Status:** DONE
- **ADR:** 0001
- **Depends on:** —
- **Acceptance:** Version format, bump rules, build modes, artifact set, and
  executable-only scope agreed and recorded in ADR 0001.
- **Summary:** Iterated design discussion covering SemVer format with
  generated BUILD metadata, git tags as source of truth, `dependency.md`
  manifest, native/cross-sysroot/remote build modes with SSH protocol and
  abort rules, bump classification (incl. leftmost-wins and zero-reset),
  Conventional Commits as the change signal, and the decision to keep
  library versioning out of scope (standard .so conventions only).

## T002 — Author the skill

- **Status:** DONE
- **ADR:** 0001
- **Depends on:** T001
- **Acceptance:** SKILL.md (5-phase workflow) plus references
  (`bump-rules.md`, `target-detection.md`, `dependency-file.md`) and tested
  scripts (`build_meta.sh`, `extract_deps.py`) exist under
  `skills/linux-cpp-executables/cpp-exe-versioning/`.
- **Summary:** Written with the skill-creator methodology; scripts verified
  in a sandbox (ELF `DT_NEEDED` parsing incl. sysroot resolution and
  pkg-config fallback; git-derived BUILD string).

## T003 — Build eval fixtures and run benchmarks

- **Status:** DONE
- **ADR:** 0001
- **Depends on:** T002
- **Acceptance:** ≥3 realistic scenarios run with-skill vs. baseline, graded
  by objective assertions, aggregated into a benchmark, reviewable in a
  static viewer.
- **Summary:** Three fixture repos (cross-sysroot bootstrap; mixed fix+feat
  release expecting 1.3.0; dependency-only update expecting PATCH 0.9.2).
  Result: with skill 15/15 assertions, baseline 11/15 (bootstrap 1/5),
  with-skill runs ~2× faster with far lower variance. Artifacts in
  `tests/` (`evals.json`, `iteration-1/` incl. `benchmark.md`,
  `review.html`).

## T004 — Migrate into the RayanSkills framework

- **Status:** DONE
- **ADR:** 0001
- **Depends on:** T002, T003
- **Acceptance:** Skill under `skills/linux-cpp-executables/cpp-exe-versioning/`,
  docs mirror with `adr/`, `specs/`, `tests/`, this TASKS.md; frontmatter in
  two-field Title-Case form; `state.json` updated; committed and pushed.
- **Summary:** Group name normalized to kebab-case
  (`linux-cpp-executables`) per CLAUDE.md §2.

## T005 — Iterate on user review feedback (viewer)

- **Status:** TODO
- **ADR:** 0001
- **Depends on:** T003
- **Acceptance:** User feedback from `review.html` (feedback.json) processed;
  skill revised if needed; iteration-2 benchmark run if changes are made.

## T006 — Optimize skill description triggering

- **Status:** TODO
- **ADR:** 0001
- **Depends on:** T005
- **Acceptance:** Trigger eval set (~20 queries) reviewed by user;
  description optimization loop run; best description applied.

## T007 — Companion skill: shared-library versioning

- **Status:** TODO
- **ADR:** 0001 (D6)
- **Depends on:** —
- **Acceptance:** Separate skill (different group) covering SONAME/SOVERSION
  management and ABI-diff-driven bumps (`abidw`/`abidiff` baselines);
  shares the version format and BUILD conventions; no custom interface
  between the two skills.

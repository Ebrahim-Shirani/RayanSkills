# TASKS — linux-shared-library-release

Development backlog for the standalone `.so` release skill.
Statuses: `TODO` · `IN_PROGRESS` · `DONE` · `BLOCKED` · `CANCELLED`.

---

## T001 — Ratify architecture in ADR 0001

- **Status:** DONE (2026-07-20)
- **ADR:** `adr/0001-standalone-so-release-skill.md`
- **Depends on:** group-level T001 (design review of 2026-07-20)
- **Acceptance:** ADR records the consolidation pivot, Q1–Q4 resolutions,
  scope (all build systems, target modes), and the benchmark-gated removal
  plan for the superseded skills.

## T002 — Author SKILL.md + references + scripts

- **Status:** DONE (2026-07-20) — draft 1: SKILL.md 206 lines; 13 references
  (10 salvaged with origin headers, 3 new); 5 scripts (3 salvaged, 2 new:
  abi_baseline.sh, release_gate.sh — smoke-tested, honesty paths verified).
  Update (same day): libabigail 2.0 obtained root-free in the sandbox
  (apt-get download + dpkg -x to ~/local; recipe recorded in
  references/abi-baselines.md), so T003 can run fully type-aware here.
  Live testing exposed and fixed a classifier gap: abidiff reports
  signature changes (param added/retyped, return type changed) with only
  exit bit 4, so they scored INCONCLUSIVE instead of BREAKING. Fixed in
  abi_baseline.sh, in the origin linux-abi-management/check-abi-verdict.sh,
  and re-synced to the copy. All verdict paths verified: COMPATIBLE,
  COMPATIBLE_WITH_ADDITIONS, BREAKING (signature), honesty paths.
- **ADR:** 0001
- **Depends on:** T001
- **Acceptance:**
  - SKILL.md ≤ ~220 lines: workflow skeleton + decision rules only
    (`cpp-exe-versioning` pattern).
  - Per-phase `references/*.md`, loaded on demand; salvaged/adapted from
    `linux-shared-library-versioning` (SONAME wiring per build system) and
    `linux-abi-management` (verdict methodology), with origin headers.
  - Mechanical steps in `scripts/` (version computation, baseline diff,
    release gate, manifest generation) — executable without loading prose.
  - Build systems: CMake, Meson, autotools, plain make.
  - Target modes: native / cross-sysroot / remote+SSH.

## T003 — Define benchmark fixtures & run skill-creator evals

- **Status:** DONE — iteration 1 run and accepted by owner 2026-07-20
  (100% with-skill pass rate met the acceptance gate). Iteration 2
  (cmake/meson + cross-sysroot fixtures) remains optional future work.
- **Depends on:** T002
- **Acceptance:** fixtures cover: bootstrap new library; PATCH (compatible);
  MINOR (additions); MAJOR + SOVERSION bump (breaking); cross-sysroot mode;
  missing-baseline fallback. Pass rate / tokens / time comparable to
  `cpp-exe-versioning` iteration-1 results.
- **Iteration 1 results (2026-07-20):** 4 fixtures (bootstrap, MINOR,
  MAJOR+SOVERSION, missing-baseline honesty; plain Make — sandbox lacks
  cmake/meson; cross-sysroot fixture deferred to iteration 2).
  With skill **100% (20/20)** vs baseline **76% (15/20)**; cost
  +81 s / +16.5k tokens per run. Baseline failures: bootstrap layout
  conventions (3), verdict vocabulary not recorded in manifest (1),
  no manifest/baseline committed on release (1). Artifacts in the session
  workspace (fixtures + evals.json + review.html); evals.json preserved
  alongside benchmark outputs.

## T004 — Benchmark-gated cleanup of superseded skills

- **Status:** DONE (2026-07-20)
- **Executed:** removed `skills/linux-shared-libraries/linux-shared-library-versioning/`
  (content absorbed; its `docs/` mirror retained as historical record — the
  copies in this skill are now canonical, see `provenance.md`), plus the
  empty `linux-library-validation` and `linux-library-packaging` scaffolds.
  `linux-abi-management` KEPT as a standalone CI/diagnostic utility.
  Packaging remains a future, separate concern.

## T005 — Description triggering optimization

- **Status:** DONE (2026-07-22)
- **Method:** the automated skill-creator loop (`run_loop.py`) requires a
  logged-in `claude` CLI, unavailable in the Cowork sandbox. First pass
  (2026-07-20): trigger eval set authored and stored in
  `artifacts/description-trigger-eval.json`; manual description revision
  against it.
- **Automated run from Claude Code (2026-07-21/22):** the loop was executed
  end-to-end against the owner-reviewed eval set (`description-trigger-eval.json`,
  20 queries, stratified 12-train / 8-test split), model `claude-opus-4-8`,
  `--max-iterations 5`. The **evaluation** phase ran successfully every time;
  the **description-improvement** phase (`improve_description.py`'s `claude -p`
  call) failed reproducibly mid-run (`exit 1`, empty stderr), so no completed
  run produced a `best_description`/`results.json`.
- **Diagnosis (recorded so it isn't re-litigated):**
  - It is **not** usage credits/quota — credits are enabled, and the exact
    improve call replayed **standalone succeeds 4/4** with the real 19 KB prompt.
  - The improve call fails **only mid-run**, as the ~21st–61st `claude -p`
    invocation fired within a couple of minutes. Lowering eval concurrency
    10→4 did **not** help (per-iteration call *volume* is unchanged). The
    signature — works cold, fails after a volley, independent of credits —
    is most consistent with **short-window request/token rate throttling**.
  - The untried lever, if revisited, is to cut per-iteration call volume
    (`--runs-per-query 1`, `--num-workers 2`) to keep the volley small.
- **Outcome / decision:** across **all** partial iterations the **original
  (current) description was never beaten** on held-out test score — every
  auto-proposed rewrite tied or regressed (recall stayed low across variants).
  Therefore **no change is applied** to `SKILL.md`; the 2026-07-20 manually
  revised description stands. T005 is closed on the owner's instruction
  (2026-07-22): the automated loop was run from Claude Code, validated that the
  shipped description is not beaten by the optimizer, and surfaced an
  environmental blocker on the improve step. No best/final train/test score is
  recorded because no run completed; the representative partial signal was
  train recall ~0–17 % and the original description holding the top test score.
  Run scaffolding (retry wrapper, logs) was ephemeral in the session scratchpad
  and is git-ignored per artifacts policy.

# TASKS — Linux ABI Management Skill

Task backlog for this project. Tasks are completed **in order**. Each task has a status:
`TODO`, `IN_PROGRESS`, `DONE`, `BLOCKED`, or `CANCELLED`.

A task is **not** started merely because it exists — it is started only after review/approval.

| Field | Meaning |
|---|---|
| ID | Unique, ordered task identifier (`T001`, `T002`, …) |
| Status | Current state |
| ADR | Driving ADR, if any |

---

## T001 — Implement ADR 001 (skill architecture)

- **Status:** DONE
- **Approved:** 2026-07-18 — ADR 001 accepted; user approved starting this task.
- **Completed:** 2026-07-18 — full package implemented and verified (see Results below).
- **ADR:** `docs/linux-shared-libraries/linux-abi-management/adr/001_linux_abi_management_skill_architecture.md`
- **Depends on:** ADR 001 (Accepted)

**Description.** Implement the `linux-abi-management` skill exactly as defined in ADR 001 —
the complete progressive-disclosure package under
`skills/linux-shared-libraries/linux-abi-management/`, using the `skill-builder` skill as the
authoring reference. Build `SKILL.md` (lean router + dispatch table) first, then `reference/`,
`scripts/`, `templates/`, and `examples/` file by file, writing directly to disk.

**Acceptance criteria.**

1. `SKILL.md` present and conformant: two-field frontmatter exactly as fixed in ADR §6;
   under ~400 lines; contains mission, in-scope vs out-of-scope **capabilities** (no sibling
   skill named anywhere in shipped content — ADR §5.2), when-to-use, the core decision flow,
   and a dispatch table mapping every task/subtopic to the exact `reference/` file or
   `scripts/` entry to open. No deep explanations inlined.
2. `reference/` contains the twelve subtopic files of ADR §6 (merging/splitting is allowed if
   justified, but each file stays focused, self-contained, and independently loadable):
   `api-vs-abi`, `elf-and-linking`, `symbol-versioning` (ABI-judgment angle only), `c-abi`,
   `cpp-abi`, `compiler-linker-loader`, `kernel-abi`, `syscall-and-interfaces`,
   `regression-and-diffing`, `migration`, `tooling` (index: one line per tool — libabigail
   `abidiff`/`abidw`, `abi-compliance-checker`, `abi-dumper`, `pahole`, `readelf`, `objdump`,
   `nm`, `ldd`, `patchelf`, `objcopy`, `modinfo`, `depmod`, `bpftool`, `gdb`, `perf`,
   `strace`, `ltrace`), and `troubleshooting` (failure signature → cause → fix).
3. `scripts/` contains three runnable, documented scripts per ADR §5.4/§6:
   - `inspect-abi.sh` — SONAME, dynamic symbols, symbol versions for one binary;
   - `diff-abi.sh` — libabigail-primary / ACC-secondary comparison of two builds;
   - `check-abi-verdict.sh` — runs the checks and emits a compatible/breaking verdict only
     (no pipeline wiring).
   Each script degrades gracefully: reports missing engines explicitly and never silently
   passes when a required tool is absent (ADR §5.5).
4. `templates/` contains `abi-review-checklist.md` (every item actionable) and
   `abi-report.md` (fill-in diff-result report).
5. `examples/` contains 2–4 concrete worked cases, including at least one compatible change
   (e.g. added symbol) and one breaking change (e.g. struct layout change), each ending at a
   verified verdict.
6. The five workflows of ADR §4 are covered end to end (inspect one binary; review a proposed
   change; diff two versions; ABI verdict for a shared-library or kernel update; handle a
   required ABI break) — real commands, clear pass/fail criteria, every workflow stopping at
   the verdict.
7. The skill encodes the standing rules: prefer ABI stability; breaking changes always
   flagged and gated on explicit approval plus a SONAME-bump decision; API vs ABI separated
   in every judgment; arch/compiler/linker/loader/runtime implications stated when relevant;
   concrete verification commands for every recommendation; out-of-scope requests
   (packaging, pipeline wiring, authoring versioning schemes, generic admin, kernel
   development, language teaching) stated as out of scope without naming any other skill.
8. Kernel-side content confined to interface level, isolated in `kernel-abi.md` and
   `syscall-and-interfaces.md` so the future split of ADR §5.6 stays cheap.
9. Quality bar (ADR §6): no placeholders, no TODOs, no empty sections; every script actually
   runs; verified against the `skill-builder` validation checklist.

**Note.** Do not start until ADR 001 is reviewed and this task is approved.

### Results (2026-07-18)

Package shipped at `skills/linux-shared-libraries/linux-abi-management/`:
`SKILL.md` (187 lines — router with decision flow + dispatch table), 12
`reference/` files, 3 `scripts/`, 2 `templates/`, 3 `examples/` (compatible C
addition; silent C struct break; C++ vtable break).

**Quality gates (all pass):** frontmatter valid (name 20/64, description
264/1024 chars); no `TODO`/placeholder markers; **no sibling skill named
anywhere in shipped content** (ADR §5.2 verified by grep); every
dispatch-table target exists; SKILL.md under the ~400-line budget.

**Script verification (19 tests, this machine: binutils+gcc present;
libabigail/ACC absent — fallback paths tested for real, abidiff engine paths
tested via a stub reproducing libabigail's documented exit bitmask
0/4/8/12/1):**

| Test | Expectation | Result |
|---|---|---|
| `inspect-abi.sh` on fixture `.so`, `/bin/ls` (version_r branch), usage & non-ELF errors | full surface dump; exits 0/2/3 | ✅ |
| `diff-abi.sh` addition pair / identical-symbols pair | engines-unavailable stated loudly; correct add/remove lists | ✅ |
| verdict: additions, no engine | INCONCLUSIVE (exit 2), never a pass | ✅ |
| verdict: silent struct change, no engine | INCONCLUSIVE (exit 2) — the honesty rule | ✅ |
| verdict: removed symbol / SONAME bump | BREAKING (exit 1) | ✅ |
| verdict: unreadable input / usage | INCONCLUSIVE (2) / usage (2) | ✅ |
| verdict via abidiff exits 0 / 4-adds / 4-review / 12 / 1 | COMPATIBLE / COMPATIBLE_WITH_ADDITIONS / INCONCLUSIVE / BREAKING / INCONCLUSIVE | ✅ |
| verdict: abidiff clean but inputs stripped (no DWARF) | INCONCLUSIVE, "rebuild with -g" | ✅ |
| End-to-end consumers (examples 01/02): old consumer vs new compatible lib; struct-break demo | clean resolution; `sum=3` → garbage with **no loader error** | ✅ |

**Defects found during verification:** loader test initially failed because
fixtures lacked SONAME-named symlinks — a fixture setup issue, not a skill
defect; examples already use `-Wl,-soname` correctly. One malformed table row
fixed in `templates/abi-report.md` before ship.

**Deferred:** filed as T002.

---

## T002 — Validate against real diff engines

- **Status:** DONE
- **Approved:** 2026-07-18 — user made abidiff available and asked to proceed.
- **Completed:** 2026-07-18 — abidiff portion first (see below), then ACC 2.3
  + ABI Dumper 1.2 + Vtable-Dumper 1.2 + pahole v1.25 after the user
  installed them (criteria 3–4; results in the second section below).
- **ADR:** `docs/linux-shared-libraries/linux-abi-management/adr/001_linux_abi_management_skill_architecture.md`
- **Depends on:** T001 (DONE)

**Description.** T001 verified the abidiff code paths of `diff-abi.sh` and
`check-abi-verdict.sh` with a stub reproducing libabigail's documented exit
bitmask, because libabigail/ACC/pahole were not installable in the build
environment. Re-run the verification with the real tools.

**Acceptance criteria.**

1. On a machine with `abigail-tools` (abidiff/abidw), `abi-compliance-checker`
   + `abi-dumper`, and `dwarves` (pahole) installed, rebuild the three example
   fixture pairs (examples 01–03) and run both scripts on each.
2. Confirm real abidiff exit codes match the stub assumptions (0 clean; 4
   additions with `--no-added-syms` → 0; 4-only for review cases; 12 for the
   struct and vtable breaks) and that the verdicts come out
   COMPATIBLE_WITH_ADDITIONS / BREAKING / BREAKING respectively.
3. Confirm the ACC secondary-engine block in `diff-abi.sh` produces a report
   on at least one pair.
4. Confirm `pahole -C point` output matches the layout shown in example 02.
5. File any divergence as new tasks and correct the affected reference/
   example content.

**Note.** Do not start until approved.

### Results — abidiff portion (2026-07-18, libabigail 2.4.0)

Criteria 1, 2, and 5 completed; 3 and 4 remain blocked (tools not installed).
All three example fixture pairs rebuilt (incl. the C++ `libshape` pair) and
both scripts run against the real engine — 10/10 regression checks pass.

**Real exit codes vs stub assumptions:**

| Case | Stub assumed | Real 2.4.0 | Match |
|---|---|---|---|
| identical pair | 0 | 0 | ✅ |
| addition (greet) | 4; `--no-added-syms` → 0 | 4; `--no-added-syms` → 0 | ✅ |
| C++ vtable break (shape) | bit 8 set | 12, report names the new vtable entry (`voffset 3/3`) | ✅ |
| struct layout break (point) | 12 | **4** — bit 8 not set; evidence only in report text | ❌ divergence |

**Divergence 1 (verdict logic):** abidiff 2.4.0 reserves bit 8 for changes it
can prove incompatible (removals, vtable changes); a field insertion that
shifts existing member offsets returns bit 4 with the proof in the report
body. Fixed per criterion 5: `check-abi-verdict.sh` now greps the bit-4
report for `offset changed` → BREAKING (the point pair now yields
`VERDICT: BREAKING ... (exit 4)`); `reference/regression-and-diffing.md`
bitmask notes and classification rules corrected; example 02 updated with the
real report and exit code; example 03 refreshed with real 2.4.0 output.

**Divergence 2 (new defect found, only reproducible with the real engine):**
on DWARF-less inputs abidiff **hung indefinitely** — libabigail's debuginfod
client blocking on Ubuntu's default `DEBUGINFOD_URLS` under a restricted
network. Fixed: both `diff-abi.sh` and `check-abi-verdict.sh` now
`export DEBUGINFOD_URLS=""`; pitfall documented in
`reference/regression-and-diffing.md`. Stripped-pair runs now complete
instantly and still yield the honest INCONCLUSIVE.

**Also verified:** `abidw --out-file` baseline corpus + later `abidiff
corpus.abi new.so` works as `regression-and-diffing.md` describes; stub-mode
paths (reviewme/error) unchanged after the fixes.

### Results — ACC & pahole portion (2026-07-18, ACC 2.3 / ABI Dumper 1.2 / Vtable-Dumper 1.2 / pahole v1.25)

**Criterion 4 (pahole):** `pahole -C point` matches example 02's layout
claims exactly (offsets 0/4 → 0/4/8, size 8 → 12); example 02 updated to the
verbatim v1.25 output format.

**Criterion 3 (ACC block in `diff-abi.sh`):** ran end to end on all three
pairs, producing `compat_reports/<lib>/old_to_new/compat_report.html` each
time:

| Pair | ACC binary compat | Correct? |
|---|---|---|
| greet (addition) | 100%, 0 problems | ✅ |
| point (struct break) | **50%**, 1 binary problem; source 100% — independently confirms the "compiles fine, breaks binaries" point | ✅ |
| shape (C++ vtable break) | **100%, 0 problems** — added virtual listed only as an Added Symbol | ❌ missed |

**Divergence 3 (ACC blind spot, criterion 5):** ACC 2.3's dump-based
workflow does not flag a vtable-layout change from an added virtual function
even with vtable-dumper installed, while abidiff 2.4.0 proves the same pair
incompatible (exit 12). Documented in `reference/regression-and-diffing.md`
(ACC section: "never accept an ACC-clean result as the verdict for C++")
and in example 03. This confirms ADR §5.5's engine ordering (libabigail
primary, ACC corroboration only) with hard evidence. No script change
needed — `check-abi-verdict.sh` never consults ACC for its verdict.

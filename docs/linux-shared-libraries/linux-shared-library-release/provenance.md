# Provenance & sync map (development-only)

The shipped skill is fully standalone: no file under
`skills/linux-shared-libraries/linux-shared-library-release/` references any
other skill, at runtime or otherwise (owner decision, 2026-07-20 — a user of
this skill may have no access to or awareness of the rest of this repo).
Drift tracking for salvaged content therefore lives HERE, not in the shipped
files. When editing a file below in either location, port the change to the
other side (ADR 0001, Q3).

**Update 2026-07-20 (T004):** `linux-shared-library-versioning` has been
REMOVED from the repo (benchmark-gated consolidation; its docs/ mirror is
retained as historical record). The copies in this skill marked (†) below
are now the CANONICAL versions — there is no other side to sync with.
`cpp-exe-versioning` and `linux-abi-management` still exist; sync discipline
still applies to files copied from them.

| File in this skill | Origin (reference implementation) | Copied | Notes |
|---|---|---|---|
| references/build-systems/cmake.md | (†) skills/linux-shared-libraries/linux-shared-library-versioning/reference/cmake.md | 2026-07-20 | verbatim |
| references/build-systems/meson.md | (†) …/linux-shared-library-versioning/reference/meson.md | 2026-07-20 | verbatim |
| references/build-systems/autotools.md | (†) …/linux-shared-library-versioning/reference/autotools.md | 2026-07-20 | verbatim |
| references/build-systems/make.md | (†) …/linux-shared-library-versioning/reference/make.md | 2026-07-20 | verbatim |
| references/build-systems/bazel.md | (†) …/linux-shared-library-versioning/reference/bazel.md | 2026-07-20 | verbatim |
| references/soname-concepts.md | (†) …/linux-shared-library-versioning/reference/concepts.md | 2026-07-20 | "scope boundary" blockquote reworded: judgment is in-skill (phase 3) |
| references/validation.md | (†) …/linux-shared-library-versioning/reference/validation.md | 2026-07-20 | verbatim |
| references/target-detection.md | skills/linux-cpp-executables/cpp-exe-versioning/references/target-detection.md | 2026-07-20 | verbatim |
| references/bump-rules.md | …/cpp-exe-versioning/references/bump-rules.md | 2026-07-20 | verbatim |
| references/release-manifest.md | …/cpp-exe-versioning/references/dependency-file.md | 2026-07-20 | adapted: library: block added, cross-skill wording removed |
| references/abi-diffing.md | skills/linux-shared-libraries/linux-abi-management/reference/regression-and-diffing.md | 2026-07-20 | verbatim |
| scripts/build_meta.sh | …/cpp-exe-versioning/scripts/build_meta.sh | 2026-07-20 | verbatim |
| scripts/extract_deps.py | …/cpp-exe-versioning/scripts/extract_deps.py | 2026-07-20 | verbatim |
| scripts/check-abi-verdict.sh | …/linux-abi-management/scripts/check-abi-verdict.sh | 2026-07-20 | in sync incl. signature-change fix (2026-07-20, applied to origin first) |
| templates/VERSIONING.md.template | (†) …/linux-shared-library-versioning/templates/VERSIONING.md.template | 2026-07-20 | verbatim |

New (no origin): SKILL.md, references/abi-baselines.md,
references/release-gate.md, scripts/abi_baseline.sh, scripts/release_gate.sh.

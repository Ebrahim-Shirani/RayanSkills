# Tests & benchmarks — cpp-exe-versioning

Authoring-time evaluation artifacts (not shipped with the skill).

## Layout

- `evals.json` — the 3 eval scenarios with prompts and expected outputs.
- `iteration-1/` — first benchmark iteration:
  - `eval-*/{with_skill,without_skill}/outputs/` — artifacts each run
    produced (dependency.md, release notes, CHANGELOG, `git_state.txt`).
  - `eval-*/*/grading.json` / `timing.json` — assertion results and
    token/time cost per run.
  - `benchmark.json` / `benchmark.md` — aggregate comparison and analyst
    notes.
  - `review.html` — standalone browsable viewer (open in a browser).

## Scenarios

1. **bootstrap-cross-sysroot** — adopt versioning on a cross-compiled
   aarch64 CMake project (toolchain file + in-repo sysroot), previous
   version 2.1.0 supplied by the user.
2. **mixed-fix-feat-release** — release with one `fix:` and one `feat:`
   commit since `v1.2.3`; expected MINOR → `1.3.0` (leftmost-wins,
   zero-reset).
3. **dep-only-update-release** — vendored `libfoo` 1.2.0→1.4.0, same SONAME,
   zero source changes; expected PATCH → `0.9.2`.

## Fixture reconstruction

Fixtures were disposable git repos built in a sandbox (small CMake projects;
sysroot faked with SONAME symlink chains; `libfoo` actually compiled twice
with `-Wl,-soname,libfoo.so.1`; binaries built natively where needed). The
exact expected states are captured in each eval's `eval_metadata.json` and
`evals.json`; rebuild equivalents from those descriptions if a new iteration
needs fresh fixtures.

## Iteration-1 result

With skill 15/15 assertions (100%), baseline 11/15 (73%) — baseline scored
1/5 on bootstrap and used commits-since-tag instead of total commit count
for BUILD. With-skill runs were ~2× faster (111s ± 10 vs 198s ± 79) at
+6.4k tokens.

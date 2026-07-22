# Test & benchmark artifacts (development-only)

Policy (owner, 2026-07-20): anything generated for testing, benchmarking, or
evaluation — and not part of the shipped skill — lives under this
`docs/<group>/<skill>/artifacts/` directory, so future maintainers can find
it, understand it, and delete it safely. Nothing in here is read by the
skill at runtime.

Git policy (owner, 2026-07-21): generated payloads in `artifacts/` are
**git-ignored** — only this README and the hand-authored eval definitions
(`evals.json`, `description-trigger-eval.json`) are committed. The payloads
described below exist on machines where the runs were made; everything is
regenerable from the committed definitions (fixture-creation steps are
encoded in the eval prompts/assertions; `grade.py` logic is described per
assertion).

Note on locations: `skill-creator` by default writes its eval workspace to a
`<skill>-workspace/` directory *next to the skill* — that would pollute
`skills/`, so runs are executed in a scratch directory
(`/tmp/lslr-workspace/` in the session sandbox, ephemeral) and the durable
results are archived here afterwards. If you rerun evals, do the same.

## benchmark-iteration-1/ (2026-07-20)

| File | What it is |
|---|---|
| `evals.json` | The 4 eval definitions: prompts, expected outputs, assertions (bootstrap, MINOR, MAJOR+SOVERSION, missing-baseline honesty). |
| `fixtures.tar.gz` | The 4 fixture git repos (libcalc, libtemp, libtemp_brk, libjson) in their pristine pre-run state. Unpack and copy per run; agents mutate them. |
| `grade.py` | Programmatic grader: checks every assertion against a run's repo (tags, SONAME via rebuild-at-tag, manifest lines, committed baselines) and writes `grading.json` per run. |
| `run-results.tar.gz` | Full iteration-1 outputs minus the mutated repos: per-run `summary.md`, `grading.json`, `timing.json`, `eval_metadata.json`. |
| `benchmark.json` / `benchmark.md` | Aggregated results: with skill 100% (20/20) vs baseline 76% (15/20); +81 s, +16.5k tokens per run. |
| `review.html` | Static skill-creator eval viewer (Outputs + Benchmark tabs). Open in a browser. |

Result summary: with-skill runs followed all 7 phases, produced correct
verdict-driven bumps (COMPATIBLE_WITH_ADDITIONS→1.5.0, BREAKING→2.0.0 with
SOVERSION 2), and handled the missing-baseline case honestly (regenerated
from the tag, disclosed provenance). Baseline failures: nonstandard baseline
layout, verdict not recorded in a manifest, no manifest/baseline committed.
Known gaps for iteration 2: fixtures are plain-Make only (sandbox had no
cmake/meson); no cross-sysroot fixture yet.

## description-trigger-eval.json

Trigger eval set (20 queries, should/should-not) for optimizing the SKILL.md
`description`. The automated loop needs a logged-in `claude` CLI, which the
Cowork sandbox does not have; run it from Claude Code in this repo:

```bash
cd <skill-creator-dir>
python -m scripts.run_loop \
  --eval-set <this-dir>/description-trigger-eval.json \
  --skill-path <repo>/skills/linux-shared-libraries/linux-shared-library-release \
  --model <current-model> --max-iterations 5 --verbose
```

The 2026-07-20 description revision was done manually against this eval set
(reasoning in `../TASKS.md` T005).

**Automated run (2026-07-21/22).** The loop was run end-to-end from Claude Code
with `--model claude-opus-4-8 --max-iterations 5`. The evaluation phase ran, but
the description-improvement `claude -p` call failed reproducibly mid-run
(`exit 1`, empty stderr) — not usage credits (the exact call succeeds 4/4
standalone with the real prompt), most consistent with short-window rate
throttling after the eval phase's burst of calls; lowering concurrency did not
help. No completed run produced a `best_description`, and across all partial
iterations the current (shipped) description was never beaten on held-out test
score, so no description change was applied. See `../TASKS.md` T005 for the full
diagnosis and decision. The retry-wrapper/run logs were ephemeral scratchpad
files (git-ignored per the policy above) and are not archived here.

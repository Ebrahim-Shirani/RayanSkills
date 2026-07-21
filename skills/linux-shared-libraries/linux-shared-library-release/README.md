# Linux Shared Library Release

A single, self-contained Claude skill that runs the **entire release process
for a Linux shared library (`.so`)** — from ABI evidence to git tag.

## What it is designed for

For a shared library, the next version number is not an opinion: the ABI
diff against the previous release is *evidence*, and the version is computed
from it. This skill operationalizes that idea end to end:

1. Diffs the freshly built library against the previous release's committed
   ABI baseline (`abidiff`/`abidw`, type-aware via DWARF).
2. Maps the verdict to the bump — *breaking* ⇒ MAJOR + SOVERSION/SONAME
   bump; *compatible-with-additions* ⇒ MINOR; *compatible* ⇒ PATCH;
   *inconclusive* ⇒ the release stops rather than guessing.
3. Wires `VERSION`/`SOVERSION`/`SONAME` and the symlink chain through the
   project's **native build system** (CMake, Meson, Autotools, plain Make,
   Bazel), with a single version source of truth.
4. Runs an execution-free pre-ship gate (SONAME convention, symlink chain,
   `DT_NEEDED` hygiene, RPATH, strip/debug split, TEXTREL, pkg-config).
5. Produces the release artifacts: git tag `vX.Y.Z`, committed `CHANGELOG.md`
   and `dependency.md` manifest, uncommitted release note, and the new ABI
   baseline under `abi-baselines/<version>/`.

Build modes: **native**, **cross-compilation with a sysroot** (e.g.
Yocto/poky), and **remote builds over SSH**. ABI tooling never runs on the
target — artifacts are fetched to the analysis host, which is the only
machine that needs libabigail.

## When it triggers

Ask Claude things like: "cut a release of libfoo", "what should the next
version be?", "did we break ABI since the last tag?", "do I need to bump the
SOVERSION?", "set up versioned releases for this library", "generate release
notes and a changelog", or continue any repo that already contains
`dependency.md` or `abi-baselines/`.

## Use it for

- First-time adoption: unversioned `.so` projects (wires SONAME, records the
  first baseline, tags the starting version — no invented bump).
- Routine releases where the MAJOR/MINOR/PATCH decision should be
  evidence-driven and repeatable.
- Repos that shipped an ABI break without a SONAME bump and need the process
  fixed so it cannot recur.
- Cross-compiled or remotely built libraries (embedded targets need no
  tooling installed).

## Do NOT use it for

- Releasing **executables or applications** — nothing here applies without a
  shared library contract.
- **Distro packaging** (`-dev`/runtime split, deb/rpm) — deliberately out of
  scope; run it after the release.
- **Reviewing a patch's ABI impact with no release intent** (e.g. a CI check
  on a merge request) — that is a judgment task, not a release.
- Non-ELF platforms (macOS dylibs, Windows DLLs) or non-C/C++ ecosystems.

## Requirements

`git`, `gcc`/toolchain, binutils (`readelf`, `nm`) — and **libabigail**
(`abidw`, `abidiff`) on the machine running the release. Without libabigail
the skill degrades honestly: it can prove a break, but will never green-light
a release it cannot verify. Build release candidates with `-g`; the skill
saves the baseline before stripping.

## Layout

`SKILL.md` (agent workflow + decision rules) · `references/` (per-build-system
wiring, baseline policy, gate rationale, target modes — loaded on demand) ·
`scripts/` (baseline lifecycle, release gate, dependency extraction, build
metadata) · `templates/` (VERSIONING.md policy document).

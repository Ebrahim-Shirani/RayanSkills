---
name: "Cpp Exe Versioning"
description: >
  Compute and apply a semantic version (MAJOR.MINOR.PATCH+BUILD) for a C/C++
  application whose final artifact is an executable, at release time. Handles
  native builds, cross-compilation with a sysroot on the host, and projects
  where the build happens on a remote target machine (over SSH). Maintains a
  dependency.md manifest in the repo, classifies changes since the last
  release (app code, in-house libraries, third-party libraries, toolchain),
  generates a release note, and tags the repository. Use this skill whenever
  the user wants to version, bump, or release a C/C++ executable project —
  including phrases like "create a release", "what should the next version
  be", "bump the version", "generate release notes", "set up versioning for
  this project", or any mention of dependency.md in a C/C++ repo. Also use it
  when adopting versioning for a project that was previously versioned by
  another mechanism.
---

# C/C++ Executable Versioning

This skill produces a release version for a C/C++ **executable** and the
artifacts that go with it. It is not for versioning shared libraries — for the
libraries an application *depends on*, it relies only on standard, widely
accepted conventions (SONAME/realname version numbers, pkg-config, package
manager metadata, ELF inspection). It never assumes a dependency uses any
custom versioning scheme.

## Version format

```
MAJOR.MINOR.PATCH+BUILD
```

- **MAJOR** — breaking change: the new executable no longer works with the
  configs, data, or workflows that the previous release worked with.
- **MINOR** — new backward-compatible functionality.
- **PATCH** — bug fixes or invisible changes (e.g. a dependency was rebuilt
  at a new version without any code impact).
- **BUILD** — generated, never asked from the user:
  `<commit-count>.g<short-hash>` from `scripts/build_meta.sh`
  (e.g. `1.4.2+345.g7a3f9c1`). Commit count alone is not unique across
  branches; the hash makes the build identifiable.

Two invariants apply to every bump:

1. **Zero-reset:** when a part increases, all parts to its right reset to 0
   (BUILD excepted — it is always recomputed, never reset).
2. **Leftmost wins:** when one release contains several changes, only the
   change affecting the leftmost part determines the bump. A release with
   five PATCH-level changes and one MAJOR-level change is a MAJOR bump,
   nothing else.

The **source of truth** for the current version is the last git tag of the
form `vMAJOR.MINOR.PATCH`. The first line of `dependency.md` mirrors it so
programs and users can read the version with a one-line read.

## The release workflow

Work through these phases in order. Phases 1–2 gather facts, phase 3 judges
them, phases 4–5 write the results.

### Phase 0 — Discover state (and bootstrap if needed)

Check, in the repo root:

- Does `dependency.md` exist?
- Does a `vX.Y.Z` tag exist? (`git tag --list 'v*'`)

If **both** exist, this is a normal release: continue to Phase 1.

If **neither** exists, this is the first run — bootstrap:

1. Ask the user for the current version as **MAJOR.MINOR.PATCH only**. Never
   ask for BUILD; it is always generated. If the project was versioned by a
   different mechanism before, whatever the user gives becomes the starting
   point. If the project is brand new, suggest `0.1.0`.
2. Determine the build mode (Phase 1) and collect the full dependency
   snapshot (Phase 2).
3. Write `dependency.md` (see `references/dependency-file.md`), commit it,
   and tag the current commit `v<MAJOR.MINOR.PATCH>`.
4. Bootstrap ends here — there is no bump on the first run, because there is
   no previous snapshot to compare against. Tell the user the baseline is
   recorded and the next release will be computed automatically.

If only one of the two exists, something is inconsistent (e.g. tag deleted,
or dependency.md added by hand). Show the user what you found and let them
decide which one is authoritative before continuing.

### Phase 1 — Determine the build mode

The mechanism must know where the final executable runs, because that is
where dependency versions are real. Three modes exist; detection and the
exact steps for each are in `references/target-detection.md`. In short:

- **native** — built and run on this machine. Everything resolves locally.
- **cross-sysroot** — cross-compiled here with a toolchain file + sysroot.
  Everything still resolves locally, *inside the sysroot*.
- **remote** — only sources live here; build/test happen on another machine.
  Facts must come over SSH, or from the user.

Read the mode from `dependency.md` (`target.mode`) if it was recorded on a
previous run — do not re-detect and silently disagree with it. On first run,
detect it from the build tool; if detection is inconclusive, ask the user and
record the answer. In remote mode without working SSH access, follow the
abort protocol in the reference file: offer the user the chance to provide
access, and if they cannot, stop the release cleanly — never invent
dependency versions.

### Phase 2 — Collect the current snapshot

Collect these facts (in remote mode, via SSH; otherwise locally / in the
sysroot):

- **Toolchain:** compiler and its version, and the language standard
  (`CMAKE_CXX_STANDARD`, `-std=` flags).
- **Declared dependencies:** from the build tool (e.g. `CMakeLists.txt`
  `target_link_libraries`, `find_package`), followed **at most 2 levels**
  deep. Classify each as `in-house`, `third-party`, or `standard`
  (libc/libstdc++/libm...).
- **Actual dependencies:** if a built executable is available, run
  `scripts/extract_deps.py` on it. It reads `DT_NEEDED` SONAMEs from the ELF
  and resolves each to its real file and version. Binary truth beats build
  files — parsing CMake alone misses transitive links and finds links that
  are declared but unused. Use both and merge.
- **Versions:** per dependency, in order of preference: SONAME/realname
  version (`libfoo.so.1.4.2`), `pkg-config --modversion`, package manager
  (`dpkg -s` / `rpm -q`), version macros in headers. Record which source was
  used — next release must compare like with like.

Compare against the snapshot in `dependency.md`. Also check for
**added or removed** dependencies — a new library appearing is itself a
change to classify in Phase 3.

### Phase 3 — Classify every change since the last release

Gather the change set: `git log <last-tag>..HEAD`, the dependency diff from
Phase 2, and the toolchain diff. Then classify each change using the table
below. The full rationale and edge cases are in `references/bump-rules.md`.

| Change | Bump |
|---|---|
| Language standard changed (e.g. C++11 → C++17) | MAJOR |
| App code: bug fix only, no new capability | PATCH |
| App code: new capability, old behavior preserved | MINOR |
| App code: old configs/data/workflows no longer work | MAJOR |
| Dependency version changed, app code untouched by it | PATCH |
| Dependency changed and app code adapted, backward-compatibly (e.g. uses a new API) | MINOR |
| Dependency changed and app is no longer compatible with its own previous behavior | MAJOR |
| Dependency added or removed, no user-visible behavior change | PATCH |
| Dependency added to provide a new capability | MINOR |

These rules apply identically to in-house and third-party libraries: judge
them by their standard version metadata and by what actually changed in the
app's code, never by any custom protocol.

**How to judge "did the app code change because of the dependency":** check
whether commits touching the dependency's usage sites landed in the same
range. If commit messages follow Conventional Commits (`fix:`, `feat:`,
`feat!:`/`BREAKING CHANGE`), map them directly: fix→PATCH, feat→MINOR,
breaking→MAJOR. If they don't, read the diffs; when a change's compatibility
impact is still ambiguous after reading the code, ask the user about that
specific change — one precise question ("commit abc123 changes the config
parser; can old config files still load?") rather than a generic one.

### Phase 4 — Compute the new version

Take the maximum bump from Phase 3 (leftmost wins), apply zero-reset, then
append BUILD from `scripts/build_meta.sh`. Show the user the computed version
**with the per-change reasoning** before writing anything — this is the one
moment a human can catch a misclassification cheaply.

### Phase 5 — Write the release artifacts

1. **`dependency.md`** — rewrite with the new version on line 1 and the new
   snapshot (format: `references/dependency-file.md`). Commit it. This file
   lives in the repo so its history *is* the dependency history.
2. **`release_note_<version>.md`** — one entry per change: what changed, why,
   and what it fixes/improves/adds. `<version>` is exactly the released
   version. This file is **not** committed; ensure `release_note_*.md` is in
   `.gitignore`. Because release notes leave no trace in the repo, also
   append the same entries to a committed `CHANGELOG.md` — otherwise the
   project's change history exists nowhere.
3. **Tag** the release commit `v<MAJOR.MINOR.PATCH>`.
4. **`version.h`** (recommended, once per project): offer to add a
   `version.h.in` + CMake `configure_file` so the executable can report its
   own version (`--version`) and the version string is embedded in the
   binary (recoverable with `strings`). Commit the `.in` template, not the
   generated header.

Do not push or create merge requests unless the user asks.

## Bundled resources

- `references/target-detection.md` — read in Phase 1: detection heuristics,
  the SSH/remote protocol, and the abort rules.
- `references/bump-rules.md` — read in Phase 3 when a change doesn't map
  cleanly onto the table above.
- `references/dependency-file.md` — read before writing `dependency.md`:
  exact format and a full example.
- `scripts/build_meta.sh <repo-dir>` — prints the BUILD component.
- `scripts/extract_deps.py <binary> [--sysroot DIR]` — prints the ELF
  dependency list with resolved versions as JSON.

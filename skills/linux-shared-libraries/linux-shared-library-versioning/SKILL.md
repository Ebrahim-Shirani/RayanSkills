---
name: "Linux Shared Library Versioning"
description: "Implement and verify standard Linux ELF shared-library (.so) versioning in any project. Sets VERSION, SOVERSION, SONAME and the symlink chain using the project's native build system (CMake, Meson, Autotools/libtool, Make, Bazel). Use when a project builds .so libraries and needs correct SONAME/soname versioning, when validating existing versioning with readelf/objdump/ldd/file, when consolidating a single version source of truth, or when the user asks about SONAME, SOVERSION, ABI-safe library versioning, or 'libfoo.so.X' symlinks."
---

# Linux Shared Library Versioning

## Single Responsibility

This skill does **one thing**: implement and verify standard Linux ELF shared-library
versioning — `VERSION`, `SOVERSION`, `SONAME`, and the symbolic-link chain — using the
project's **native build system**.

Explicitly **out of scope** (handled by sibling skills, do not do them here):

- Symbol versioning / linker version scripts (`.map`, `VERSION { ... }`)
- ABI compatibility *checking* (`abidiff`, `abi-compliance-checker`)
- Distro packaging / `-dev` vs runtime package split
- Symbol visibility (`-fvisibility=hidden`, export maps)

If the user needs those, name the concern and defer it — do not expand this skill's scope.

## The Workflow (always in this order)

1. **Analyze** the project (read-only). → `## 1. Analyze`
2. **Present a plan** and the design decisions. Wait for confirmation. → `## 2. Plan`
3. **Implement** using native build-system facilities. → `## 3. Implement`
4. **Validate** the built artifacts with standard tools. → `## 4. Validate`
5. **Document** the adopted strategy. → `## 5. Document`

Never skip step 2. This skill modifies build files; the user sees and approves the plan first.

---

## Core Concepts (know these before acting)

Read `reference/concepts.md` for the full explanation. The one-paragraph version:

- **VERSION** — the full library version, `MAJOR.MINOR.PATCH` (e.g. `1.4.2`). Encodes the
  release-level identity of the library binary.
- **SOVERSION** — the ABI generation, normally just `MAJOR` (e.g. `1`). It becomes part of
  the SONAME.
- **SONAME** — the name the dynamic linker records in the ELF (`DT_SONAME`), e.g.
  `libexample.so.1`. Executables depend on the **SONAME**, not the full filename.
- **Symlink chain**:
  ```
  libexample.so            -> libexample.so.1        (dev/link-time, ships in -dev)
  libexample.so.1          -> libexample.so.1.4.2    (runtime, == SONAME)
  libexample.so.1.4.2                                 (the real file)
  ```

**The rule that matters most:** `SOVERSION` is **not** the release version. Bump `SOVERSION`
**only when the public ABI becomes incompatible** (removed/changed symbols, changed struct
layout, changed signatures). A library can go `1.4.2 → 1.5.0` — new features, backward
compatible — with the **same** `SOVERSION` of `1`. Deciding *whether* an ABI break occurred
is a judgement call (and a separate ABI-checking skill); this skill wires up the mechanism
and states the policy.

---

## 1. Analyze

Determine, read-only, before proposing anything:

**a. Which shared libraries are produced.** Grep the build files for shared-library targets:

```bash
# Build-system detection
ls CMakeLists.txt meson.build configure.ac Makefile.am Makefile BUILD BUILD.bazel WORKSPACE 2>/dev/null

# Shared-library target hints
grep -rnE 'add_library\([^)]*SHARED|shared_library\(|_LTLIBRARIES|-shared|linkshared|cc_(binary|library).*\.so' \
  --include=CMakeLists.txt --include=*.cmake --include=meson.build \
  --include=Makefile* --include=configure.ac --include=BUILD* . 2>/dev/null
```

**b. Which build system** owns those targets (see the matching `reference/*.md`):

| Marker file(s) | Build system | Reference |
|---|---|---|
| `CMakeLists.txt` | CMake | `reference/cmake.md` |
| `meson.build` | Meson | `reference/meson.md` |
| `configure.ac` + `Makefile.am` | Autotools / libtool | `reference/autotools.md` |
| `Makefile` (hand-written) | Make | `reference/make.md` |
| `BUILD`/`BUILD.bazel`/`WORKSPACE` | Bazel | `reference/bazel.md` |

**c. Whether versioning already exists.** Look for `VERSION`/`SOVERSION` properties,
`-version-info`, `soversion:`, `-Wl,-soname`. If found, switch to **verify** mode (see
`## Existing Projects`) — do not blindly rewrite it.

**d. How version info is currently managed** — and whether it is **duplicated**. Check every
plausible source: `project(... VERSION ...)`, `project(version:)`, a top-level `VERSION`
file, `#define *_VERSION` in headers, `AC_INIT`, `.pc.in` pkg-config files, packaging specs.
Duplication is the most common real defect. Note each location for the plan.

---

## 2. Plan

Present, concisely, before editing anything:

- The libraries found and their current state (versioned / unversioned / inconsistent).
- The chosen **single source of truth** for the version, and any duplicates to be redirected
  to it.
- The proposed `VERSION` and `SOVERSION` values, **with the reasoning** — especially why
  `SOVERSION` is what it is (existing ABI generation, or `1` for a first versioned release).
- The exact native-facility edits (per `reference/<build-system>.md`).
- What symlinks the build will generate.

Only proceed once the user confirms. If invoked non-interactively, still print the plan, then
proceed with the conservative defaults below.

**Conservative defaults when unspecified:**
- First-time versioning of an unversioned lib: `SOVERSION = 0` if pre-1.0, else `MAJOR` of the
  existing release version.
- Never *raise* an existing SOVERSION unless the user states an ABI break occurred.

---

## 3. Implement

Follow the reference file for the detected build system. Core principles:

- **Use native facilities. Do not hand-roll `ln -s` / `-Wl,-soname` when the build system
  provides versioning** (CMake, Meson, libtool all do). Hand-rolled symlinks are only the
  documented fallback for plain Make and Bazel (`reference/make.md`, `reference/bazel.md`).
- **Single source of truth.** Define the version once; derive `SOVERSION` from it
  (`MAJOR`). Redirect duplicates (headers, `.pc.in`) to that source via the build system's
  configure/substitution mechanism rather than leaving parallel literals.
- **Idempotent.** Re-running must not duplicate or conflict. Match on the property/flag and
  update in place; check a symlink exists and points correctly before creating it
  (`ln -sf`, or a guard). Never append a second `set_target_properties`/`-version-info`.

Quick reference of the native knob per system (details in the reference files):

| Build system | Native mechanism |
|---|---|
| CMake | `set_target_properties(t PROPERTIES VERSION x.y.z SOVERSION x)` — install generates symlinks |
| Meson | `library('t', …, version : 'x.y.z', soversion : 'x')` |
| Autotools | `libt_la_LDFLAGS = -version-info C:R:A` (**not** x.y.z — see reference) |
| Make | `-Wl,-soname,libt.so.X` + `ln -sf` install rules (fallback) |
| Bazel | `linkopts = ["-Wl,-soname,libt.so.X"]` + genrule symlinks (fallback) |

---

## 4. Validate

Build first, then verify the produced artifacts. Never trust the source edit alone.

```bash
# 1. SONAME recorded in the ELF (must be libNAME.so.SOVERSION)
readelf -d path/to/libexample.so.1.4.2 | grep SONAME
objdump -p path/to/libexample.so.1.4.2 | grep SONAME     # equivalent

# 2. Files are real ELF shared objects, symlinks resolve
file path/to/libexample.so*                              # symlink chain + 'ELF ... shared object'
ls -l  path/to/libexample.so*                            # inspect the chain visually

# 3. A consumer depends on the SONAME, not the full filename
ldd path/to/consumer_binary | grep example               # should show libexample.so.1
readelf -d path/to/consumer_binary | grep NEEDED         # DT_NEEDED == SONAME
```

Confirm all three:

- **SONAME correct:** `DT_SONAME == libexample.so.<SOVERSION>`.
- **Symlink chain correct:** `libexample.so → …so.<SOVERSION> → …so.<VERSION>` (real file).
- **Consumers reference the SONAME**, not `libexample.so.1.4.2`. A `DT_NEEDED` of the full
  version string is a defect (usually a missing SONAME at link time).

See `reference/validation.md` for interpreting each field and common failure signatures.

---

## 5. Document

Generate `VERSIONING.md` (in the project's docs location, or root) from
`templates/VERSIONING.md.template`. It must state:

- the adopted versioning strategy and the single source of truth (with file path),
- the meaning of VERSION and of SOVERSION **in this project**,
- the version-numbering policy, and the explicit **when-to-bump-SOVERSION** rule,
- maintenance guidelines for future developers (how to cut a compatible vs breaking release).

Keep it factual to what was implemented; do not restate general theory beyond what a
maintainer needs.

---

## Existing Projects (verify mode)

When step 1 finds versioning already present:

1. **Verify** it follows convention: SONAME `= libNAME.so.MAJOR`, symlink chain intact,
   `SOVERSION` matches the SONAME's numeric part, VERSION is `MAJOR.MINOR.PATCH`.
2. **Detect inconsistencies:** VERSION source duplicated; `SOVERSION` set to the full release
   version (a classic mistake); SONAME not matching SOVERSION; symlinks missing; libtool
   `-version-info` that doesn't map to the intended SONAME.
3. **Recommend** the minimal fix, and explain the impact (changing an existing SONAME breaks
   already-linked consumers — flag this loudly; it is rarely what you want).
4. **Avoid unnecessary modifications.** If it is already correct, say so and stop. Do not
   churn style or re-order for its own sake.

---

## Reference Files

- `reference/concepts.md` — VERSION / SOVERSION / SONAME / symlinks / ABI, in depth.
- `reference/cmake.md`, `reference/meson.md`, `reference/autotools.md`,
  `reference/make.md`, `reference/bazel.md` — native per-build-system implementation.
- `reference/validation.md` — reading `readelf`/`objdump`/`ldd`/`file` output.
- `templates/VERSIONING.md.template` — the documentation deliverable.

# ADR 001 — Linux Shared Library Versioning Skill: Architecture

**Status:** Accepted
**Date:** 2026-07-16
**Supersedes:** —
**Superseded by:** —

---

## 1. Context

Linux ELF shared libraries (`*.so`) require correct versioning to remain safe to distribute
and link against. A misversioned library breaks the runtime contract between a library and its
consumers: the dynamic linker cannot tell compatible builds apart, and executables may bind to
an incompatible ABI. Correct versioning rests on four coupled concepts — `VERSION`,
`SOVERSION`, `SONAME`, and a standard symbolic-link chain — implemented, ideally, through the
project's own build system.

In practice this is done inconsistently. Common real-world defects:

- version numbers duplicated across `project()`, headers, and pkg-config files;
- `SOVERSION` set equal to the release version (bumped on every release rather than only on
  ABI breaks);
- hand-rolled `ln -s` symlinks instead of native build-system facilities;
- missing or incorrect `DT_SONAME`, so consumers depend on a fully qualified filename.

We are building a **reusable AI skill** that any future agent can invoke, against an arbitrary
target project, to implement or verify standard shared-library versioning. This ADR defines
the skill's architecture: its scope, responsibilities, design decisions, and implementation
approach.

This skill is one member of a family of single-responsibility skills for Linux shared
libraries (siblings: `linux-abi-management`, `linux-library-packaging`,
`linux-library-validation`). The family is designed to **compose**, not overlap.

## 2. Decision (Summary)

Build a project-agnostic, progressive-disclosure Claude skill that:

1. explains the purpose and relationships of VERSION / SOVERSION / SONAME / symlinks and their
   tie to ABI compatibility;
2. analyzes a target project to detect its shared libraries, build system, existing
   versioning, and version source(s);
3. presents a design plan for user approval before mutating anything;
4. implements standard versioning using the project's **native build system** whenever
   available, consolidating version information into a single source of truth;
5. validates the built artifacts with standard tools (`readelf`, `objdump`, `ldd`, `file`);
6. generates maintainer-facing documentation of the adopted strategy.

The skill is packaged as a lean `SKILL.md` plus on-demand `reference/` files (one per build
system, plus concepts and validation) and a documentation `templates/` file. The
`skill-builder` skill is the authoring reference for structure and frontmatter.

## 3. Scope

### 3.1 In Scope

- The **SONAME-level versioning mechanism**: `VERSION`, `SOVERSION`, `SONAME` (`DT_SONAME`),
  and the standard three-link symlink chain
  (`libX.so → libX.so.<SOVERSION> → libX.so.<VERSION>`).
- **Project analysis**: which `.so` libraries are produced; which build system
  (CMake, Meson, Autotools/libtool, Make, Bazel) owns them; whether versioning already
  exists; how (and how redundantly) version info is managed.
- **Native implementation** per build system, encoding each system's specific mechanism
  (not treating them as interchangeable).
- **Single source of truth** consolidation for version information.
- **Verification of existing versioning** with minimal, justified changes.
- **Validation** of built artifacts with `readelf`/`objdump`/`ldd`/`file`.
- **Documentation** of the adopted strategy, including the when-to-bump-SOVERSION policy.

### 3.2 Out of Scope (delegated to sibling skills)

- **Symbol versioning** — linker version scripts / `.map` files, versioned symbol nodes.
- **ABI compatibility checking** — `abidiff` (libabigail), `abi-compliance-checker`, and the
  automated decision of whether an ABI break occurred.
- **Packaging conventions** — `-dev` vs runtime package split, distro shlibs.
- **Symbol visibility** — `-fvisibility=hidden`, export control.

When a request touches these, the skill names the concern and defers to the appropriate
sibling skill rather than expanding its own responsibility. This boundary is a deliberate
architectural constraint (see §5.1).

## 4. Responsibilities & Workflow

The skill enforces a fixed five-phase workflow; the plan phase is a mandatory gate.

1. **Analyze (read-only).** Detect build system, shared-library targets, existing versioning,
   and all version sources (including duplicates).
2. **Plan (approval gate).** Present findings, the chosen single source of truth, proposed
   `VERSION`/`SOVERSION` **with rationale**, exact native edits, and resulting symlinks. Wait
   for confirmation. Never skip.
3. **Implement.** Apply native-facility edits; consolidate version sources; keep changes
   idempotent.
4. **Validate.** Build, then verify `DT_SONAME`, the symlink chain, and that consumers depend
   on the SONAME rather than the full filename.
5. **Document.** Emit `VERSIONING.md` describing the strategy and maintenance policy.

## 5. Design Decisions

### 5.1 Strict single responsibility

**Decision.** The skill is limited to SONAME-level versioning. Symbol versioning, ABI
checking, packaging, and visibility are excluded and delegated to named sibling skills.

**Rationale.** Focused skills are easier to maintain, reuse, and compose. A future agent can
chain this skill with an ABI-checking skill without either duplicating logic. Scope creep would
make the skill fragile and its triggering ambiguous.

### 5.2 Native build-system facilities first

**Decision.** Always prefer the build system's own versioning support. Hand-rolled
`-Wl,-soname` + `ln -s` is a documented fallback only where no native facility exists
(plain Make, Bazel).

**Rationale.** Native facilities (CMake `VERSION`/`SOVERSION`, Meson `version`/`soversion`,
libtool `-version-info`) generate the SONAME and symlinks correctly and portably, and survive
build reconfiguration. Custom scripts drift and are error-prone. Honesty about the fallback
(rather than pretending a native path always exists) is preferable to forcing a broken
abstraction.

### 5.3 Per-build-system encoding, not a unified abstraction

**Decision.** Provide one reference file per build system encoding its exact mechanism, rather
than a single generic recipe.

**Rationale.** The mechanisms are genuinely different. Most importantly, libtool's
`-version-info current:revision:age` is **not** `major.minor.patch`; the SONAME major is
`current − age`. Treating systems as equivalent produces silently wrong SONAMEs. Explicit
per-system encoding prevents this class of error.

### 5.4 SOVERSION is decoupled from the release version

**Decision.** The skill teaches and enforces that `SOVERSION` (ABI generation, normally
`MAJOR`) changes **only on an incompatible ABI change**, independent of the release `VERSION`.
Conservative defaults never raise an existing SOVERSION without an explicit stated ABI break.

**Rationale.** Setting `SOVERSION` to the full release version — bumping it every release — is
the single most common real-world mistake and needlessly breaks consumers. Making the
distinction explicit in concepts, plan rationale, and generated documentation directly targets
this defect. (The automated *detection* of an ABI break is out of scope, §3.2.)

### 5.5 Single source of truth for version information

**Decision.** Consolidate duplicated version literals into one authoritative source and derive
the rest (e.g. `SOVERSION` = `MAJOR`; header/pkg-config values via build substitution).

**Rationale.** Duplication causes divergence between the declared and actual version. A single
source removes a whole category of maintenance bugs.

### 5.6 Plan-before-mutate and idempotency

**Decision.** No build-file modification occurs before the user approves a plan. All edits are
idempotent: match-and-update in place, guard symlink creation, never append duplicate
property/flag declarations.

**Rationale.** The skill mutates a foreign project's build system; surprising changes are
costly. Idempotency lets the skill be re-run safely (e.g. after partial application) without
producing duplicate or conflicting configuration.

### 5.7 Validation on artifacts, not source

**Decision.** Correctness is confirmed by inspecting built binaries with standard tools, not
by trusting the source edit.

**Rationale.** The recorded `DT_SONAME`, the on-disk symlink chain, and consumers' `DT_NEEDED`
are the actual contract. Only artifact inspection proves the mechanism worked end to end.

### 5.8 Progressive-disclosure packaging

**Decision.** Lean `SKILL.md` (workflow + core concepts + native-knob summary) with details in
on-demand `reference/*.md`; use `skill-builder` as the authoring reference.

**Rationale.** Keeps always-loaded context small while allowing deep, build-system-specific
guidance to load only when relevant.

## 6. Implementation Approach

**Package structure.**

```
linux-shared-library-versioning/
├── SKILL.md                     # workflow, concepts summary, native-knob table
├── CLAUDE.md                    # project guidelines, ADR & task rules
├── reference/
│   ├── concepts.md              # VERSION/SOVERSION/SONAME/symlinks/ABI in depth
│   ├── cmake.md                 # set_target_properties VERSION/SOVERSION; install symlinks
│   ├── meson.md                 # library(version:, soversion:)
│   ├── autotools.md             # -version-info C:R:A ↔ SONAME mapping
│   ├── make.md                  # -Wl,-soname + ln -sf fallback (idempotent)
│   ├── bazel.md                 # linkopts soname + genrule symlinks (fallback)
│   └── validation.md            # interpreting readelf/objdump/ldd/file
├── templates/
│   └── VERSIONING.md.template   # documentation deliverable
└── docs/
    ├── adr/                     # this ADR and successors
    └── TASKS.md
```

**Per-build-system mechanism (to be encoded in the reference files):**

| Build system | Native mechanism | SONAME source |
|---|---|---|
| CMake | `set_target_properties(t PROPERTIES VERSION x.y.z SOVERSION x)`; `install(TARGETS)` generates symlinks | `SOVERSION` |
| Meson | `library('t', …, version : 'x.y.z', soversion : 'x')` | `soversion` |
| Autotools/libtool | `libt_la_LDFLAGS = -version-info current:revision:age` | `current − age` |
| Make (fallback) | `-Wl,-soname,libt.so.X` at link; `ln -sf` install rules | explicit `X` |
| Bazel (fallback) | `linkopts = ["-Wl,-soname,libt.so.X"]`; genrule for symlinks | explicit `X` |

**Validation commands (encoded in `reference/validation.md`):**

- `readelf -d <lib> | grep SONAME` / `objdump -p <lib> | grep SONAME` → `DT_SONAME == libX.so.<SOVERSION>`.
- `file <lib>*`, `ls -l <lib>*` → symlink chain resolves to a real ELF shared object.
- `ldd <consumer>` / `readelf -d <consumer> | grep NEEDED` → `DT_NEEDED == SONAME`, not the full filename.

**Documentation deliverable.** `VERSIONING.md` generated from the template, stating the
adopted strategy, the single source of truth (with path), the meaning of VERSION and SOVERSION
in the project, the numbering policy, the explicit when-to-bump-SOVERSION rule, and maintenance
guidance.

## 7. Consequences

**Positive.**

- Reusable, project-agnostic, composable with sibling skills.
- Prevents the most common versioning defects (SOVERSION misuse, duplicated versions,
  hand-rolled symlinks, missing SONAME).
- Safe to re-run (idempotent) and safe to apply (plan-gated).
- Honest about fallbacks where native support is absent.

**Negative / trade-offs.**

- Excluding ABI checking means the skill wires the mechanism but cannot, by itself, decide
  whether an ABI break occurred — it relies on user input or a sibling skill for that
  judgement.
- Per-build-system encoding means new build systems require new reference files rather than
  configuration of a generic engine.
- The mandatory plan gate makes fully non-interactive runs slightly heavier (plan is still
  printed before conservative-default execution).

## 8. Alternatives Considered

1. **One monolithic "shared library management" skill** covering versioning, symbol
   versioning, ABI checking, packaging, and visibility. *Rejected* — violates single
   responsibility; hard to maintain, reuse, and trigger unambiguously (§5.1).
2. **A generic build-system abstraction** with a single recipe. *Rejected* — the mechanisms
   differ materially (esp. libtool `-version-info`), so a unified recipe produces wrong
   SONAMEs (§5.3).
3. **Custom versioning scripts** applied uniformly regardless of build system. *Rejected* —
   ignores robust native facilities, drifts, and is error-prone; used only as a documented
   fallback (§5.2).
4. **Coupling SOVERSION to the release version** for simplicity. *Rejected* — this is the
   defect the skill exists to prevent (§5.4).
5. **Trusting source edits without artifact validation.** *Rejected* — the ELF contract must
   be verified on the built binary (§5.7).

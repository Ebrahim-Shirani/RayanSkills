# ADR 001 — Linux ABI Management Skill: Architecture

**Status:** Accepted
**Date:** 2026-07-18 (accepted 2026-07-18)
**Supersedes:** —
**Superseded by:** —

---

## 1. Context

Linux binaries — shared objects, executables, and kernel modules — expose a
**binary interface (ABI)**: the concrete contract of symbols, calling
conventions, data layouts, and versioned interfaces that already-compiled
consumers depend on. Unlike the API (a source-level contract), the ABI can break
without any source change: a reordered struct field, a changed compiler flag, a
different libstdc++ — and previously working binaries fail at load or, worse,
corrupt state silently at run time.

Engineers routinely face questions this skill must answer well:

- "Does this change break the ABI, or only the API?"
- "Are these two builds of `libfoo.so` binary-compatible?"
- "Can this kernel module still load after the update?"
- "We must break the ABI — how do we do it safely?"

Answering these correctly requires ELF/dynamic-linking literacy, C and C++
(Itanium) ABI knowledge, awareness of compiler/linker/loader effects, and
fluency with the analysis toolchain (libabigail, `abi-compliance-checker`,
`readelf`, `pahole`, …). Done ad hoc, the analysis is error-prone and the
verdict is often an unverified "it should be fine."

We are building a **reusable AI skill**, `linux-abi-management`, whose center of
gravity is **analysis and decision-making about binary compatibility of
already-built binaries** — inspecting, diffing, judging, and preserving ABI.
It is *not* a skill for building, versioning, or shipping libraries.

This skill is one member of a family of single-responsibility skills for Linux
shared libraries (siblings in this repo: `linux-shared-library-versioning`,
`linux-library-packaging`, `linux-library-validation`). The family composes; it
does not overlap. **Unlike earlier siblings, this skill's shipped `SKILL.md`
must not name or route to the others** (see §5.2) — the split is recorded here,
in the design docs, only.

## 2. Decision (Summary)

Build a project-agnostic, progressive-disclosure Claude skill that:

1. explains and applies the **API vs ABI** distinction, classifying any proposed
   or observed change as *compatible*, *backward-compatible additions*, or
   *breaking*;
2. **inspects** a single binary's ABI surface: ELF structure, dynamic symbols,
   symbol versions, SONAME, relocations, GOT/PLT, visibility, weak symbols,
   DWARF/BTF type information;
3. **diffs two versions** of a binary/library with libabigail and
   `abi-compliance-checker` and classifies every reported difference;
4. reasons about **C ABI and C++ (Itanium) ABI** and about compiler-, linker-,
   loader-, architecture-, and runtime-specific effects;
5. covers **kernel-side ABI at the interface level** — kABI,
   `Module.symvers`, `CONFIG_MODVERSIONS`, exported symbols,
   syscall/ioctl/netlink/sysfs/procfs stability, tracepoints, eBPF ABI — without
   entering kernel development;
6. ends every workflow at a **verified verdict**: a compatible/breaking result
   plus the exact commands and methodology that establish it.

The skill is packaged as a lean router `SKILL.md` plus on-demand `reference/`
files, runnable `scripts/`, review/report `templates/`, and worked `examples/`.
The `skill-builder` skill is the authoring reference for structure and
frontmatter.

## 3. Scope

### 3.1 In Scope (capabilities)

- **Inspecting a binary's ABI**: dumping and interpreting SONAME, dynamic
  symbol table, symbol versions, visibility, weak symbols, relocations,
  GOT/PLT, and type info (DWARF/BTF) for one build.
- **Diffing two versions** of a shared object, executable, or kernel symbol
  interface, and classifying each difference.
- **Judging a proposed change** (source diff, patch, or described change) for
  ABI impact *before* it lands — including C and C++ (Itanium) specifics:
  name mangling, vtable layout, RTTI, inline functions, templates, struct
  layout, calling conventions, and architecture differences.
- **Toolchain effects**: how compiler versions and flags, glibc vs musl, LTO,
  and loader behavior change the effective ABI.
- **Kernel interface behavior**: whether a module/userspace consumer keeps
  working across a kernel update, judged via kABI, symvers/modversions,
  exported symbols, and the stability rules of
  syscalls/ioctl/netlink/sysfs/procfs/tracepoints/eBPF.
- **Migration judgment for a required ABI break**: flagging the break,
  requiring explicit approval, and framing the SONAME bump *as a compatibility
  decision*, with a safe-transition method.
- **Verification methodology**: every judgment ships with concrete commands and
  a repeatable validation method.
- Symbol-versioning and version-script questions **only from the ABI-judgment
  angle** ("does this change break the ABI?").

### 3.2 Out of Scope (capabilities, stated without naming owners)

Per the source prompt, the shipped `SKILL.md` states these plainly as
out-of-scope capabilities and stops — it does **not** name, route to, or assume
the existence of any other skill (the runtime selects skills by description):

- Building, packaging, or distributing libraries.
- Defining release processes or wiring verdicts into CI/CD pipelines
  (every workflow ends at the verdict).
- *Authoring* a SONAME / version-script / symbol-versioning scheme as a how-to.
- Generic Linux administration.
- Kernel feature development (kernel ABI is covered at the interface level
  only).
- Teaching C or C++ as languages.

## 4. Responsibilities & Workflows

`SKILL.md` carries the decision flow; details live in `reference/`. The skill
covers at least these workflows, each executable (real commands, clear
pass/fail criteria) and each terminating at the verdict:

1. **Inspect one binary** — dump and interpret its ABI surface
   (`scripts/inspect-abi.sh`).
2. **Review a proposed change** — classify the ABI impact of a source-level
   change before it is built/released.
3. **Diff two versions** — compare builds with
   `abidiff`/`abi-compliance-checker` (`scripts/diff-abi.sh`) and classify
   every difference.
4. **Produce an ABI verdict** for a shared-library update or a kernel update
   (`scripts/check-abi-verdict.sh` emits compatible/breaking, verdict only —
   no pipeline wiring).
5. **Handle a required ABI break** — migration approach with the SONAME bump
   treated as a compatibility decision requiring explicit approval.

Rules every workflow encodes:

- **Prefer ABI stability.** Never recommend an ABI-breaking change without
  flagging it as breaking and requiring explicit approval (and a SONAME-bump
  decision).
- **Separate API from ABI** in every judgment.
- **State architecture/compiler/linker/loader/runtime implications** when they
  matter.
- **Concrete verification commands, always.** No "it should be fine."
- When the real task is packaging, pipeline wiring, or authoring a versioning
  scheme: state that it is out of scope and stop.

## 5. Design Decisions

### 5.1 Analysis-and-judgment single responsibility

**Decision.** The skill judges and preserves binary compatibility of
already-built binaries. It does not build, package, version, or ship anything,
and it does not wire its verdicts into pipelines.

**Rationale.** A focused skill triggers unambiguously and composes with the
rest of the family. "Center of gravity: the verdict" gives every workflow a
crisp, testable termination point.

### 5.2 Scope boundary defined by capability, not by sibling names

**Decision.** The shipped `SKILL.md` describes its boundary purely as in-scope
vs out-of-scope *capabilities*. It never names, references paths of, or hands
off to sibling skills. The repo-wide split (packaging / validation / versioning
as separate skills) is recorded **only in this ADR** as design rationale.

**Rationale.** The runtime selects whichever skill is relevant from its
description; a skill that routes by name couples itself to the repo's current
inventory and breaks when skills are renamed, split, or absent (e.g. when a
user installs only this one). This deliberately diverges from the older
sibling ADR 001 (versioning), which names its siblings in shipped content —
the capability-based boundary is the pattern going forward.

### 5.3 Progressive disclosure: lean router + per-subtopic references

**Decision.** `SKILL.md` is a lean router targeting under ~400 lines: mission,
scope, when-to-use, core decision flow, and a **dispatch table** mapping
tasks/subtopics to the exact reference file or script to open. All heavy
knowledge lives in `reference/`, one focused, independently loadable,
self-contained file per subtopic. No flat pile of top-level `.md` files.

**Rationale.** Only the frontmatter `description` is always in context, and
`SKILL.md` loads on every trigger — it must stay cheap. Deep content
(e.g. Itanium mangling rules, kernel symvers) loads only when the dispatch
table sends the agent there. This is a hard requirement of the source prompt.

### 5.4 Runnable scripts over prose for mechanical tasks

**Decision.** Mechanical operations ship as small, well-documented scripts —
`inspect-abi.sh` (SONAME/dynamic symbols/versions for one binary),
`diff-abi.sh` (abidiff / abi-compliance-checker wrapper for two builds),
`check-abi-verdict.sh` (runs the checks, emits a compatible/breaking verdict
only) — instead of paragraphs the agent must read and re-derive.

**Rationale.** A script is cheaper to load than the prose describing it,
executes identically every time, and gives the verdict workflows their
pass/fail mechanics for free.

### 5.5 Tool choices: libabigail primary, ACC secondary, binutils for ground truth

**Decision.** `reference/tooling.md` is an index (one line per tool: what it
reveals about ABI, when to reach for it), not a manual. The diffing scripts
prefer **libabigail** (`abidiff`, `abidw`) as the primary engine, with
**`abi-compliance-checker`** (+ `abi-dumper`) as the secondary/corroborating
engine. Ground-truth inspection uses `readelf`, `objdump`, `nm`, `pahole`,
`ldd`; ancillary tools covered: `patchelf`, `objcopy`, `modinfo`, `depmod`,
`bpftool`, `gdb`, `perf`, `strace`, `ltrace`.

**Rationale.** libabigail operates on DWARF+ELF, understands C/C++ type-level
changes, and classifies harmless vs harmful diffs — the closest fit to
"classify this change." ACC provides an independent second opinion and
report format. Raw binutils output is the arbiter when higher-level tools
disagree or are unavailable. Scripts must degrade gracefully (report which
engines are installed; never silently pass when a tool is missing).

### 5.6 Kernel-side ABI included at interface level, flagged as a future split

**Decision.** Kernel content (kABI, `Module.symvers`, `CONFIG_MODVERSIONS`,
exported symbols, syscall/ioctl/netlink/sysfs/procfs stability, tracepoints,
eBPF ABI) is included, confined to **interface behavior** in two reference
files (`kernel-abi.md`, `syscall-and-interfaces.md`). **Design note:** if this
content grows, kernel-side ABI is a natural candidate to split into its own
skill later; the userspace/kernel seam in the reference layout is kept clean
to make that split cheap.

**Rationale.** "Will this module still load?" is a genuine ABI-verdict
question and belongs here today. But kernel ABI has its own toolchain and
audience; pre-drawing the seam avoids a costly disentanglement later.

### 5.7 Group placement: `linux-shared-libraries`

**Decision.** The skill lives at
`skills/linux-shared-libraries/linux-abi-management/` (docs mirrored at
`docs/linux-shared-libraries/linux-abi-management/`).

**Rationale.** The source prompt proposed a new group `linux-abi`, but the
skill's siblings — and the family ADR describing the composition — already live
in `linux-shared-libraries`, and the user confirmed placement there. One group
per family keeps the tree navigable. (Recorded as a deliberate deviation from
the source prompt.)

### 5.8 Source prompt is authoring input, not a shipped or committed artifact

**Decision.** The authoring prompt (`linux-abi-management.prompt.md`) is not
committed to the repository (ignored via `.gitignore` `*.prompt.md`). This ADR
captures its requirements; the ADR — not the prompt — is the durable design
record.

**Rationale.** User requirement; also keeps the repo's rule intact that only
skill artifacts ship under `skills/` and only durable design records live
under `docs/`.

## 6. Implementation Approach

**Package structure** (merge/split reference files sensibly during
implementation, but keep each focused and independently loadable):

```
skills/linux-shared-libraries/linux-abi-management/
├── SKILL.md                      # lean router: mission, scope, decision flow, dispatch table
├── reference/
│   ├── api-vs-abi.md             # the core distinction + how to classify a change
│   ├── elf-and-linking.md        # ELF, dynamic linking, SONAME, GOT/PLT, relocations, visibility, weak syms
│   ├── symbol-versioning.md      # version scripts & symvers from the ABI-judgment angle only
│   ├── c-abi.md                  # System V / C ABI, calling conventions, struct layout, arch differences
│   ├── cpp-abi.md                # Itanium C++ ABI: mangling, vtables, RTTI, inline, template pitfalls
│   ├── compiler-linker-loader.md # toolchain effects on ABI (glibc/musl, flags, LTO)
│   ├── kernel-abi.md             # kABI, Module.symvers, CONFIG_MODVERSIONS, exports, BTF (interface level)
│   ├── syscall-and-interfaces.md # syscall/ioctl/netlink/sysfs/procfs/tracepoint/eBPF stability
│   ├── regression-and-diffing.md # diffing versions & classifying results (libabigail/abidiff/ACC)
│   ├── migration.md              # handling a required ABI break safely; soname bump as a decision
│   ├── tooling.md                # tool index: what each reveals, when to reach for it
│   └── troubleshooting.md        # failure signature → cause → fix
├── scripts/
│   ├── inspect-abi.sh            # dump SONAME, dynamic symbols, versions for one binary
│   ├── diff-abi.sh               # abidiff / abi-compliance-checker wrapper: compare two builds
│   └── check-abi-verdict.sh      # run checks, emit compatible/breaking verdict (verdict only)
├── templates/
│   ├── abi-review-checklist.md   # actionable checklist for an ABI review
│   └── abi-report.md             # fill-in report template for a diff result
└── examples/
    └── (2–4 worked cases, e.g. compatible symbol addition vs breaking struct change)
```

**Frontmatter** (fixed by the source prompt; the description is the always-in-
context trigger):

```
---
name: "Linux ABI Management"
description: "Inspect, diff, and judge the binary compatibility (ABI) of Linux shared objects, executables, and kernel symbol interfaces. Use when checking if a change breaks ABI, comparing two library versions, or verifying whether a change is binary-compatible before release."
---
```

**Build order.** `SKILL.md` (router + dispatch table) first; then `reference/`,
`scripts/`, `templates/`, `examples/` file by file, each self-contained. Files
are written directly to disk, iteratively — never emitted as one dump.

**Quality bar.** No placeholders, no TODOs, no empty sections in shipped
files. Every checklist item actionable; every script runs; every
recommendation technically justified. Depth over volume — no padding.

## 7. Consequences

**Positive.**

- A single, well-triggered home for "is this binary-compatible?" questions,
  with verified verdicts instead of guesses.
- Cheap to load: router + on-demand references + scripts.
- Capability-based boundary survives repo refactors and partial installs.
- Kernel seam pre-drawn; a future split is a file move, not a rewrite.

**Negative / trade-offs.**

- The skill can declare a SONAME bump *required* but cannot implement the
  versioning mechanics or the packaging/pipeline follow-through — users must
  carry the verdict onward themselves (by design).
- Two diff engines (libabigail + ACC) mean environment-dependent availability;
  scripts must handle absence explicitly, which adds script complexity.
- Breadth (userspace + kernel + C + C++) risks reference-file sprawl; the
  dispatch-table discipline and per-file self-containment are the mitigation,
  and §5.6 defines the escape valve.
- Diverging from the sibling ADR's name-the-siblings style (§5.2) leaves the
  older skill inconsistent with the new pattern until it is revised.

## 8. Alternatives Considered

1. **One monolithic "Linux shared libraries" skill** (versioning + ABI +
   packaging + validation). *Rejected* — ambiguous triggering, unmaintainable,
   violates the family's single-responsibility composition (§5.1).
2. **Naming sibling skills in `SKILL.md` for routing**, as the versioning
   skill does. *Rejected* — couples the skill to repo inventory; the runtime
   routes by description; the source prompt forbids it (§5.2).
3. **A separate `linux-abi` group**, per the source prompt's layout.
   *Rejected* by user decision — the family lives together in
   `linux-shared-libraries` (§5.7).
4. **Prose-only skill without scripts.** *Rejected* — mechanical steps
   (dump/diff/verdict) are cheaper, more reliable, and more testable as
   runnable scripts (§5.4).
5. **Single diff engine (libabigail only).** *Rejected* — ACC as a second
   engine catches engine-specific blind spots and provides corroboration for
   breaking verdicts; binutils remains the ground truth (§5.5).
6. **Excluding kernel-side ABI entirely** (defer to a future kernel skill).
   *Rejected for now* — kernel-update verdicts are in the skill's core
   mission; instead the content is confined to interface level and the split
   is pre-planned (§5.6).
7. **Committing the authoring prompt** under `docs/` for provenance.
   *Rejected* — user requirement; the ADR itself is the durable record (§5.8).

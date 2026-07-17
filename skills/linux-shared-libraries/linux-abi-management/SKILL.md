---
name: "Linux ABI Management"
description: "Inspect, diff, and judge the binary compatibility (ABI) of Linux shared objects, executables, and kernel symbol interfaces. Use when checking if a change breaks ABI, comparing two library versions, or verifying whether a change is binary-compatible before release."
---

# Linux ABI Management

## Mission

Judge and preserve the **binary interface (ABI)** of already-built Linux
binaries: shared objects, executables, and kernel/module symbol interfaces.
Every task here ends at a **verified verdict** — *compatible*,
*compatible-with-additions*, or *breaking* — backed by the exact commands that
establish it. Never conclude "it should be fine"; run the verification.

## Scope

**In scope (what this skill does):**

- Inspect a binary's ABI surface: ELF structure, dynamic symbols, symbol
  versions, SONAME, relocations, GOT/PLT, visibility, weak symbols, DWARF/BTF.
- Diff two versions of a binary/library and classify every difference.
- Judge a proposed source change for ABI impact before it ships — C ABI and
  C++ (Itanium) ABI, with compiler/linker/loader and architecture effects.
- Kernel interfaces at the behavior level: kABI, `Module.symvers`,
  `CONFIG_MODVERSIONS`, exported symbols, syscall/ioctl/netlink/sysfs/procfs
  stability, tracepoints, eBPF ABI.
- Frame a required ABI break as a migration decision (including whether a
  SONAME bump is needed) and verify the outcome.
- Symbol-versioning questions **only** from the judgment angle: "does this
  change break the ABI?"

**Out of scope (state it plainly, then stop):**

- Building, packaging, or distributing libraries.
- Release processes and CI/CD wiring — every workflow here stops at the
  verdict.
- Authoring a SONAME / version-script / symbol-versioning scheme as a how-to.
- Generic Linux administration.
- Kernel feature development (kernel ABI is covered at the interface level
  only).
- Teaching C or C++ as languages.

When a request is really one of these, say it is out of scope for this skill
and stop. Do not attempt it here.

## Core decision flow

```
What is the input?
│
├─ One binary, "what does it expose?"          → Workflow 1 (inspect)
├─ A source change / patch, "will it break?"   → Workflow 2 (review a change)
├─ Two builds, "are they compatible?"          → Workflow 3 (diff) → Workflow 4 (verdict)
├─ A kernel or library update, "safe to take?" → Workflow 4 (verdict)
└─ "We must break the ABI"                     → Workflow 5 (migration)

While judging, always:
1. Separate API impact from ABI impact (they are different contracts).
2. Identify which ABI layer changed: symbols? types/layout? calling
   convention? versions? semantics?
3. State arch/compiler/linker/loader/runtime caveats when they apply.
4. End with the verdict + the commands that verify it.
```

## Dispatch table

Open **exactly** the file needed for the sub-topic at hand; each is
self-contained.

| Task / sub-topic | Open |
|---|---|
| Is this an API or an ABI change? Classify a change | `reference/api-vs-abi.md` |
| ELF anatomy: dynamic symbols, SONAME, GOT/PLT, relocations, visibility, weak symbols | `reference/elf-and-linking.md` |
| Versioned symbols (`foo@VER`): what a version change means for compatibility | `reference/symbol-versioning.md` |
| C struct layout, alignment, calling conventions, arch differences | `reference/c-abi.md` |
| C++: mangling, vtables, RTTI, inline, templates, dual ABI | `reference/cpp-abi.md` |
| Compiler flags, glibc vs musl, LTO, loader effects on ABI | `reference/compiler-linker-loader.md` |
| Kernel modules: kABI, `Module.symvers`, MODVERSIONS, exports, BTF | `reference/kernel-abi.md` |
| Syscall / ioctl / netlink / sysfs / procfs / tracepoint / eBPF stability | `reference/syscall-and-interfaces.md` |
| How to diff two builds and read abidiff / ACC output | `reference/regression-and-diffing.md` |
| A break is unavoidable — migrate safely, SONAME-bump decision | `reference/migration.md` |
| Which tool reveals what (index) | `reference/tooling.md` |
| Runtime failure signature → cause → fix | `reference/troubleshooting.md` |
| Dump one binary's ABI surface | `scripts/inspect-abi.sh` |
| Compare two builds (libabigail primary, ACC secondary) | `scripts/diff-abi.sh` |
| Emit a compatible/breaking verdict | `scripts/check-abi-verdict.sh` |
| Structured ABI review | `templates/abi-review-checklist.md` |
| Report a diff result | `templates/abi-report.md` |
| Worked cases (compatible add, struct break, C++ vtable break) | `examples/` |

## Workflows

### 1. Inspect one binary

```bash
scripts/inspect-abi.sh <binary>
```

Prints ELF type, SONAME, NEEDED entries, exported dynamic symbols, symbol
versions, and visibility notes. Interpret the output with
`reference/elf-and-linking.md`; for versioned symbols use
`reference/symbol-versioning.md`. **Pass:** the surface matches what the
library intends to export. **Fail:** unintended exports, missing SONAME, or
unversioned symbols where versions are expected — report each finding.

### 2. Review a proposed change (no second binary yet)

1. Classify the change with the tables in `reference/api-vs-abi.md`; for C++
   constructs use `reference/cpp-abi.md`, for struct/layout questions use
   `reference/c-abi.md` (and `pahole` on the built object when available).
2. State the judgment per change: compatible / compatible-with-additions /
   breaking, **with the mechanism** (e.g. "inserts a field into a
   caller-allocated struct → layout break").
3. Give the verification method: the exact `abidiff`/`pahole`/`readelf`
   commands that will prove the judgment once both builds exist (Workflow 3).
4. If any item is breaking: flag it explicitly; it requires the owner's
   explicit approval and a SONAME-bump decision (`reference/migration.md`).

### 3. Diff two versions

```bash
scripts/diff-abi.sh <old-binary> <new-binary>
```

Runs libabigail (`abidiff`) and, when installed, `abi-compliance-checker` as
a second opinion; falls back to a symbol-table diff (with a stated confidence
downgrade) when neither engine is available. Debug info (DWARF) makes the
comparison type-aware — build both versions with `-g` when possible. Read the
output with `reference/regression-and-diffing.md`. Record results with
`templates/abi-report.md`.

### 4. Produce the verdict (library or kernel update)

```bash
scripts/check-abi-verdict.sh <old-binary> <new-binary>
```

Emits exactly one verdict line — `COMPATIBLE`, `COMPATIBLE_WITH_ADDITIONS`,
`BREAKING`, or `INCONCLUSIVE` — plus the evidence, and exits nonzero for
`BREAKING`/`INCONCLUSIVE`. `INCONCLUSIVE` is a real outcome: without a
type-aware engine or debug info, silent layout changes cannot be excluded and
the script says so rather than passing. For kernel-module compatibility the
inputs differ (symbol CRCs, not ELF diffs) — follow the judgment procedure in
`reference/kernel-abi.md`; for userspace-visible kernel interfaces use
`reference/syscall-and-interfaces.md`.

**This workflow ends at the verdict.** Wiring the verdict into a release
gate or pipeline is out of scope — hand over "here is the result and how it
was verified" and stop.

### 5. Handle a required ABI break

Only after Workflow 3/4 proves the break is real:

1. Re-check whether a compatible alternative exists (additive path —
   `reference/migration.md` §"Avoiding the break").
2. If the break stands: require explicit approval from the owner. Never
   proceed on an unflagged break.
3. Decide the SONAME bump as a **compatibility decision** (old and new must
   be co-installable for unrebuilt consumers) and plan the migration steps
   per `reference/migration.md`.
4. Verify after the break ships: old consumers keep loading the old ABI, new
   consumers bind the new one (commands in `reference/migration.md`).

## Standing rules (apply to every judgment)

- **Prefer ABI stability.** Never recommend a breaking change without
  flagging it as breaking, requiring explicit approval, and raising the
  SONAME-bump decision.
- **API ≠ ABI.** State both impacts separately every time.
- **Name the caveats** — architecture, compiler, linker, loader, runtime —
  whenever they change the answer.
- **Verify, always.** Every recommendation ships with concrete commands and a
  repeatable method. An unverifiable judgment is reported as such.
- **Stop at the edge.** Packaging, pipelines, versioning-scheme authoring:
  declare out of scope and end there.

## Prerequisites

Core tools: `readelf`, `nm`, `objdump`, `ldd` (binutils/glibc — near-always
present). Type-aware diffing: `abidiff`/`abidw` (libabigail package), ideally
with both builds compiled with `-g`. Secondary engine:
`abi-compliance-checker` + `abi-dumper`. Struct layout: `pahole`. Kernel:
`modinfo`, `modprobe`, `bpftool`. The scripts detect what is installed and
state what is missing — they never silently pass. See `reference/tooling.md`
for the full index.

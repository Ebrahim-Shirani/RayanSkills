# Concepts: VERSION, SOVERSION, SONAME, symlinks, and ABI

This file is the theory behind the skill. Read it when you need to explain a decision or
justify a value. The mechanism it describes is the same on every Linux/glibc system regardless
of build system; only the *knobs* differ (see the per-build-system reference files).

## The three names of a shared library

A single shared library exists under **three** names on disk, connected by symlinks:

```
libexample.so           # 1. linker name   (dev symlink)
libexample.so.1         # 2. soname        (runtime symlink)  == DT_SONAME in the ELF
libexample.so.1.4.2     # 3. real name     (the actual file)
```

1. **Linker name** — `libexample.so`. Used only at **link time**: when you compile a program
   with `-lexample`, the linker (`ld`) searches for `libexample.so`. It is a symlink, normally
   shipped in a `-dev` package, and never referenced at runtime.

2. **soname** — `libexample.so.1`. This is the value recorded **inside** the ELF file as the
   dynamic tag `DT_SONAME`. When you link a program against the library, `ld` copies the
   library's `DT_SONAME` into the program as a `DT_NEEDED` entry. At runtime the dynamic linker
   (`ld.so`) looks for exactly this name. This symlink is what runtime consumers depend on.

3. **Real name** — `libexample.so.1.4.2`. The actual shared object file. Its precise name is a
   convention; what makes the machinery work is the `DT_SONAME` it carries, not its filename.

The key insight: **executables are bound to the soname, not the filename.** You can replace
`libexample.so.1.4.2` with `libexample.so.1.4.3` (bump the real file, repoint the
`libexample.so.1` symlink) and every existing program keeps working — because they all asked
`ld.so` for `libexample.so.1`, and that soname still resolves.

## VERSION

`VERSION` is the **full version of the library binary**, conventionally `MAJOR.MINOR.PATCH`
(e.g. `1.4.2`). It names the real file (`libexample.so.1.4.2`) and identifies the exact build.
It is a release-level identity: two builds with different features/fixes get different
VERSIONs.

## SOVERSION

`SOVERSION` is the **ABI generation number** — normally just the `MAJOR` component (e.g. `1`).
It is the number that appears in the soname (`libexample.so.<SOVERSION>`) and therefore in
`DT_SONAME`.

The distinction between VERSION and SOVERSION is the whole point:

- **VERSION** changes on **every release** (any new build).
- **SOVERSION** changes **only when the ABI becomes incompatible.**

So a library may progress:

```
release 1.4.2   VERSION=1.4.2   SOVERSION=1   soname=libexample.so.1
release 1.5.0   VERSION=1.5.0   SOVERSION=1   soname=libexample.so.1   # new features, still compatible
release 2.0.0   VERSION=2.0.0   SOVERSION=2   soname=libexample.so.2   # ABI break
```

Between 1.4.2 and 1.5.0 the soname is unchanged, so programs linked against 1.4.2 keep running
against 1.5.0. At 2.0.0 the soname changes to `libexample.so.2`; old programs continue to load
`libexample.so.1` (which can be installed side by side), new programs load `libexample.so.2`.
That parallel installability is exactly what SOVERSION buys you.

### The most common mistake

Setting `SOVERSION` equal to the full release version — i.e. bumping the soname on every
release. This forces every consumer to relink on every release and defeats the entire purpose
of sonames. **SOVERSION is not the release version.** Bump it only on an ABI break.

## SONAME

`SONAME` (the `DT_SONAME` dynamic tag) is `libexample.so.<SOVERSION>`. It is generated for you
when you set VERSION/SOVERSION through a native build system; you rarely write it by hand
(except in the plain-Make/Bazel fallbacks, where it is passed as `-Wl,-soname,libexample.so.1`).

Verify it on the built artifact:

```bash
readelf -d libexample.so.1.4.2 | grep SONAME
# 0x...  (SONAME)  Library soname: [libexample.so.1]
```

## The symlink chain

Installation lays down the chain so all three names resolve:

```
libexample.so         -> libexample.so.1        # linker name  -> soname
libexample.so.1       -> libexample.so.1.4.2    # soname       -> real file
libexample.so.1.4.2                              # real file
```

Native build systems (CMake, Meson, libtool) generate these symlinks at `install` time. Only
in the fallback cases do you create them explicitly (idempotently, with `ln -sf`).

## What "ABI compatibility" means here

The **ABI** (Application Binary Interface) is the binary-level contract a compiled consumer
relies on: exported symbol names, function signatures/calling conventions, struct and class
layouts, sizes and offsets of public types, enum values, vtable layouts (C++), and global data.

An ABI change is **incompatible** (requires a SOVERSION bump) when an already-compiled consumer
could misbehave or fail to load against the new library. Typical breakers:

- removing or renaming an exported symbol;
- changing a function's signature or calling convention;
- changing the layout/size of a public struct/class (adding a field in the middle, reordering,
  changing a member type);
- changing the meaning or value of public constants/enums;
- (C++) changing a class with virtual functions, inheritance, or inline-visible members.

Backward-compatible changes (no SOVERSION bump) include: adding a **new** exported function,
appending to an opaque/handle-based API, bug fixes that don't change signatures or layouts.

> **Where the decision comes from.** *Deciding* whether a given change is ABI-incompatible
> is not done by eyeballing this list — it is done in phase 3 of the release workflow, by
> diffing the built artifact against the committed baseline (`scripts/abi_baseline.sh check`).
> This file explains the mechanism (VERSION/SOVERSION/SONAME/symlinks) and the policy; the
> verdict that drives the SOVERSION decision always comes from that type-aware diff.

## Note on non-Linux platforms

This skill targets Linux/ELF. The same source-level knobs behave differently elsewhere: on
macOS (Mach-O) CMake's `VERSION`/`SOVERSION` map to dylib `compatibility_version`/
`current_version`, and Windows PE DLLs have no soname concept at all. Apply this skill on Linux
targets; do not assume the produced symlink chain is meaningful on other platforms.

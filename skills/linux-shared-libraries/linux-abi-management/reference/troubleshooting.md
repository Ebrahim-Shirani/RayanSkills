# Troubleshooting — failure signature → cause → fix

Runtime/load-time failures that are ABI problems in disguise. For each: the
exact message shape, the mechanism, the diagnosis commands, and what a *fix*
means at the judgment level (rebuild, provide the right file, or escalate a
breaking verdict — never patch around a break silently).

## `error while loading shared libraries: libfoo.so.1: cannot open shared object file`

**Cause:** the loader can't find any file with SONAME `libfoo.so.1` — not
installed, not in the search path, or the library moved to SONAME `.2`
(i.e. an ABI break already happened and the old stream was removed).
**Diagnose:** `ldd ./app | grep libfoo`; `ldconfig -p | grep libfoo`;
`LD_DEBUG=libs ./app 2>&1 | grep libfoo`.
**Fix:** install/point to the file carrying the *old* SONAME; if it no longer
exists, the consumer must be rebuilt against the new ABI — record it as a
consumer of the break.

## `symbol lookup error: ./app: undefined symbol: foo` (or mangled `_ZN3...`)

**Cause:** the library present at run time lacks a symbol the consumer
captured at link time — older library than the one linked against, or the
symbol was removed (a break). Note lazy binding: this can surface mid-run at
first call, not at startup.
**Diagnose:** `nm -D --defined-only $(ldd ./app | awk '/libfoo/{print $3}') | grep foo`;
find which version introduced/removed it by diffing candidate libraries;
`LD_BIND_NOW=1 ldd -r ./app` to surface *all* such problems at once.
**Fix:** supply a library version that defines the symbol; if it was removed
deliberately, that is a BREAKING verdict to report, and the consumer needs a
rebuild/port.

## `version 'GLIBC_2.34' not found (required by ./app)` — or any `version 'X' not found`

**Cause:** consumer requires a version node the runtime library doesn't
define. With glibc: binary built on a newer distro than it runs on
(deployment floor). With other libraries: the provider dropped/renamed a
version node — a break.
**Diagnose:** `readelf -V ./app | grep -o "GLIBC_[0-9.]*" | sort -uV | tail -1`
vs the target's `ldd --version`; for non-glibc, `readelf -V` both sides
(`symbol-versioning.md`).
**Fix:** run on a system meeting the floor / provide the library version
defining the node. Rebuilding on an older baseline is a build-environment
decision — out of scope; report the floor.

## Crashes or garbage *without* any loader error, after a library/compiler update

**Cause profile:** the silent ABI break — layout change of a crossing type,
changed return type (C++, same mangling), semantic change in an inlined
function, `_FILE_OFFSET_BITS`/`_TIME_BITS`/dual-ABI mismatch. The loader is
satisfied (names all resolve); the data contract is not.
**Diagnose:** `abidiff previous-working.so current.so` (with debug info);
`pahole -C suspicious_struct` both versions; in `gdb`, `ptype /o struct X` in
the consumer vs the library's DWARF — offset disagreement is the proof.
Check build-flag deltas (`compiler-linker-loader.md` checklist).
**Fix:** rebuild the consumer against the new ABI *or* restore the old ABI;
then escalate: this was an unflagged BREAKING change — record it and the
SONAME-bump decision it should have triggered (`migration.md`).

## `undefined symbol: _ZNSt7__cxx1112basic_string...` (or link errors mentioning `__cxx11`)

**Cause:** libstdc++ dual-ABI mismatch — objects built with different
`_GLIBCXX_USE_CXX11_ABI` values linked/loaded together (`cpp-abi.md`).
**Diagnose:** `nm -DC each_object | grep -c __cxx11` across the objects —
mixed 0/nonzero counts across a `std::string`-crossing interface = mismatch.
**Fix:** all parties on one setting (a rebuild decision for the owners);
verdict: the two artifacts were never ABI-compatible.

## `dlopen` fails: `cannot allocate memory in static TLS block`

**Cause:** the loaded library (or its deps) uses initial-exec TLS and the
static TLS pool is exhausted — often after a library update grew TLS usage.
**Diagnose:** `readelf -d lib.so | grep FLAGS` (`STATIC_TLS`);
compare `readelf -l old.so new.so | grep TLS` sizes.
**Fix:** load earlier / reduce IE-TLS usage (owner decision); flag the TLS
growth as the ABI-relevant regression it is (`elf-and-linking.md`, TLS).

## Module: `Unknown symbol in module` (dmesg) / `insmod: ERROR: could not insert module`

**Cause:** the kernel doesn't export a symbol the module imports — different
kernel config/version than the module was built for.
**Diagnose:** `dmesg | tail`; `modprobe --dump-modversions mod.ko` vs the
running kernel's `Module.symvers` or `/proc/kallsyms` (`kernel-abi.md`).
**Fix:** module rebuilt for this kernel, or run the matching kernel. Note a
missing-because-GPL case: `license` in `modinfo` vs `EXPORT_SYMBOL_GPL`.

## Module: `disagrees about version of symbol foo` / `version magic '...' should be '...'`

**Cause:** MODVERSIONS CRC mismatch (symbol's type signature changed) or
vermagic mismatch (different kernel release/config).
**Diagnose:** the CRC join procedure in `kernel-abi.md`.
**Fix:** rebuild per target kernel. Forcing (`modprobe --force`) discards the
safety check and risks silent corruption — do not recommend it; report the
incompatibility.

## `Exec format error`

**Cause:** wrong architecture/class (running x86-64 binary on ARM, 32-bit
module on 64-bit kernel), or corrupted/truncated file.
**Diagnose:** `file thebinary` vs `uname -m`; for modules also kernel
bitness.
**Fix:** correct-arch artifact; not an ABI evolution issue — different ABI
entirely.

## "Worked with LD_LIBRARY_PATH, breaks when installed" (or vice versa)

**Cause:** different files satisfy the SONAME in the two configurations —
RPATH/RUNPATH/cache precedence (`compiler-linker-loader.md`).
**Diagnose:** `LD_DEBUG=libs ./app 2>&1 | grep 'trying file'` in both setups;
`readelf -d ./app | grep -E 'RPATH|RUNPATH'`.
**Fix:** identify which file carries the intended ABI and why the paths
diverge; the verdict names the file that must win. Changing install layout /
packaging is out of scope.

## General rule

Every entry above ends in one of three outcomes: (a) supply the artifact
that carries the promised ABI, (b) rebuild the consumer against the new ABI,
or (c) surface an unflagged breaking change to its owner with evidence
(`templates/abi-report.md`). "Make the error go away" tricks that erase the
safety signal (force-loading modules, stripping version requirements with
patchelf in production) are not fixes and are not recommended.

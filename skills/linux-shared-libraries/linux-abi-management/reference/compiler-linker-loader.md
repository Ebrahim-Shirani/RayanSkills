# Compiler, linker, and loader effects on ABI

Two builds of **identical source** can have different ABIs. When diffing
versions or judging an update, always ask: *did the toolchain or build flags
change, independently of the code?*

## Compiler flags that change the ABI of the same source

| Flag / macro | Effect on ABI |
|---|---|
| `-D_FILE_OFFSET_BITS=64` | `off_t` & friends become 64-bit → every crossing type using them changes layout. Mixed settings between library and consumer = classic silent break |
| `-D_TIME_BITS=64` (glibc ≥2.34, 32-bit archs) | 64-bit `time_t`; same class of break as above |
| `-fshort-enums` | enum size follows value range instead of `int` — layout change in every struct holding an enum |
| `-fpack-struct[=n]`, changed `#pragma pack` defaults | global layout change |
| `-fvisibility=hidden` (added/removed) | changes the exported symbol set wholesale |
| `_GLIBCXX_USE_CXX11_ABI=0/1` | libstdc++ dual ABI — see `cpp-abi.md` |
| `-fabi-version` / `-fabi-compat-version` | C++ mangling/layout corner cases; `-Wabi` warns |
| `-ffast-math` in a **library** | links `crtfastmath.o`, historically set FTZ/DAZ flags process-wide from a `dlopen`'d object — semantic ABI change for the whole process |
| `-fno-exceptions` / `-fno-rtti` on a C++ interface | removes unwind tables / type_info that consumers may need through the boundary |
| Sanitizer/instrumented builds (`-fsanitize=address`) | different runtime deps and interceptors — not interchangeable with production builds |

**Not** ABI-changing by themselves (common false alarms): `-O` levels, `-g`,
`-march`/`-mtune` for the *exported interface* (they change instruction
selection, not the psABI contract — but a library built with `-march=x86-64-v3`
simply crashes (SIGILL) on older CPUs: a *deployment* constraint to report,
not an interface change).

## LTO and symbol effects

LTO does not alter the psABI, but build-system changes that accompany it
often alter the **exported set** (internalization of symbols that were
accidentally exported before). After any LTO on/off transition, diff the
dynamic symbol tables — disappeared accidental exports are still breaks for
whoever used them:

```bash
nm -D --defined-only old.so | sort >/tmp/o; nm -D --defined-only new.so | sort >/tmp/n
diff -u /tmp/o /tmp/n
```

## C runtime: glibc vs musl

- glibc and musl are **different ABIs**, not versions of one: different
  symbol versioning (musl has none), different `FILE`/locale/regex layouts,
  different loader paths (`/lib/ld-linux-x86-64.so.2` vs
  `/lib/ld-musl-x86_64.so.1`). A glibc-built binary on musl (or vice versa)
  is out of contract even when it appears to start.
- Detection: `readelf -l bin | grep interpreter`.
- glibc itself evolves by symbol versioning — the deployment-floor judgment
  (`version 'GLIBC_2.34' not found`) is covered in `symbol-versioning.md`.
- Static linking removes the libc dependency but freezes libc behavior into
  the binary and breaks NSS/dlopen expectations — flag when a static/dynamic
  switch happened between the compared versions.

## Linker effects

- `--as-needed` (default on modern distros): drops unused NEEDED entries —
  a library update can change consumers' dependency closure without any
  code change.
- `--no-undefined` / `-z defs` absent: a library can ship with undefined
  symbols it expects the *executable* to provide — its effective ABI then
  includes requirements on the host process. `nm -D --undefined-only lib.so`
  reveals them.
- `-z now` vs lazy binding: changes *when* a missing-symbol break surfaces
  (load time vs first call) — affects how you must test, not the verdict:
  always verify with `LD_BIND_NOW=1 ldd -r`.
- Version scripts / `--default-symbol-version`: change the (name, version)
  pairs — judge with `symbol-versioning.md`.

## Loader (ld.so) effects — which ABI you actually get

The loader picks the file that provides the contract; the *selection* is part
of the effective ABI environment:

1. Search order: `DT_RPATH` (unless `RUNPATH` present) → `LD_LIBRARY_PATH` →
   `DT_RUNPATH` → `/etc/ld.so.cache` → default dirs. `RPATH` vs `RUNPATH`
   differ in whether they apply to transitive deps (`RPATH` does,
   `RUNPATH` doesn't) — an update that switches them can change *which*
   transitive library is loaded.
2. Diagnosis commands:

```bash
ldd ./consumer                          # what would be loaded (uses the cache)
LD_DEBUG=libs ./consumer 2>&1 | head    # exact search trace
LD_DEBUG=bindings ./consumer 2>&1 | grep 'symbol_name'   # who resolved what
ldconfig -p | grep libfoo               # cache contents
```

3. `LD_PRELOAD` and multiple providers of a symbol: first definition in
   search order wins (interposition). A judgment of "removing this symbol is
   safe" must mention that interposers/`dlsym("...")` users are invisible to
   static analysis.
4. `dlopen` specifics: `RTLD_LOCAL` (default) vs `RTLD_GLOBAL` changes
   whether a plugin's symbols join the global scope; `RTLD_DEEPBIND` inverts
   lookup priority. Plugin-system ABI questions usually hinge on these, plus
   unique `type_info` for C++ (`cpp-abi.md`).
5. Static TLS: libraries with initial-exec TLS consume a fixed pool when
   `dlopen`'d — a growth between versions can make `dlopen` fail on the same
   host ("cannot allocate memory in static TLS block").

## Checklist when toolchain differences are in play

For any two-version comparison, record alongside the verdict:

- compiler & version, and libc & version, for both builds
  (`readelf -p .comment lib.so` often shows the compiler);
- relevant flag deltas from the build system (visibility, `_FILE_OFFSET_BITS`,
  `_TIME_BITS`, dual-ABI macro, pack/enum flags, LTO, sanitizers);
- loader interpreter path (`readelf -l | grep interpreter`);
- whether the comparison covered one architecture or all shipped ones.

A verdict that ignored a changed toolchain is incomplete — say which of these
were checked.

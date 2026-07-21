# Validation: reading readelf / objdump / ldd / file

Validate the **built artifacts**, never just the source edit. There are three things to prove:

1. the library's recorded soname (`DT_SONAME`) is `libNAME.so.<SOVERSION>`;
2. the on-disk symlink chain resolves to a real ELF shared object;
3. a consumer depends on the **soname**, not the fully qualified filename.

Assume `libexample`, `VERSION=1.4.2`, `SOVERSION=1` in the examples.

## 1. SONAME recorded in the library

```bash
readelf -d libexample.so.1.4.2 | grep SONAME
#  0x000000000000000e (SONAME)   Library soname: [libexample.so.1]

objdump -p libexample.so.1.4.2 | grep SONAME
#  SONAME               libexample.so.1
```

- **Pass:** `libexample.so.1` — matches `libNAME.so.<SOVERSION>`.
- **Fail — soname is the full version** (`libexample.so.1.4.2`): the build set `VERSION`
  without `SOVERSION` (CMake/Meson), or `-Wl,-soname` used the wrong string. Consumers will be
  pinned to the exact file. Fix the versioning knob.
- **Fail — no `SONAME` line at all:** the library was linked without a soname (common in the
  plain-Make path when `-Wl,-soname` is missing). Consumers will record the filename. Add the
  soname at link time.
- **Fail — soname number ≠ SOVERSION** (autotools): `-version-info C:R:A` is inconsistent; the
  soname is `C − A`. Recompute per `autotools.md`.

## 2. The symlink chain and file types

```bash
ls -l libexample.so*
# libexample.so       -> libexample.so.1
# libexample.so.1     -> libexample.so.1.4.2
# libexample.so.1.4.2

file libexample.so*
# libexample.so:       symbolic link to libexample.so.1
# libexample.so.1:     symbolic link to libexample.so.1.4.2
# libexample.so.1.4.2: ELF 64-bit LSB shared object, x86-64, ... , not stripped
```

- **Pass:** two symlinks resolving down to one real `ELF ... shared object`.
- **Fail — a link is missing:** e.g. no `libexample.so` → link-time `-lexample` fails (dev
  symlink absent); no `libexample.so.1` → runtime resolution of the soname fails. Ensure the
  install step generates the full chain (native install rules, or `ln -sf` in the fallback).
- **Fail — a "link" is a real file / dangling:** `file` shows an ELF where a symlink is
  expected, or "broken symbolic link". The install copied instead of linking, or ordering is
  wrong. Rebuild the chain.
- **Fail — `file` says the library is stripped and empty of a soname:** re-check step 1.

## 3. Consumers depend on the soname, not the filename

Link a program against the library, then inspect what it records:

```bash
readelf -d ./consumer | grep NEEDED
#  0x0000000000000001 (NEEDED)   Shared library: [libexample.so.1]

ldd ./consumer | grep example
#  libexample.so.1 => /usr/local/lib/libexample.so.1 (0x00007f...)
```

- **Pass:** `DT_NEEDED` / `ldd` show `libexample.so.1` (the soname).
- **Fail — the full filename appears** (`libexample.so.1.4.2`): the library had no correct
  soname when the consumer was linked (see step 1). The consumer is now pinned to that exact
  file and will break on any real-file rename. Fix the library's soname and **relink** the
  consumer.
- **`ldd` shows "not found":** the soname is correct but not on the loader path — an install
  location / `ld.so` cache / `RPATH` issue, not a versioning defect. `ldconfig` or
  `LD_LIBRARY_PATH` as appropriate.

> `ldd` runs the dynamic loader; only run it on binaries you trust. `readelf -d` is a safe
> static alternative and is preferred for untrusted artifacts.

## Quick one-shot check

```bash
lib=libexample.so.1.4.2
echo "== soname =="       ; readelf -d "$lib" | grep SONAME
echo "== chain =="        ; ls -l libexample.so* ; file libexample.so*
echo "== a consumer =="   ; readelf -d ./consumer | grep NEEDED
```

All three green ⇒ versioning is correct: soname is `libNAME.so.<SOVERSION>`, the chain
resolves, and consumers bind to the soname.

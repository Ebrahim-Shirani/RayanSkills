# Autotools / libtool: shared library versioning

Autotools builds shared libraries through **libtool**, which has its own versioning scheme:
`-version-info current:revision:age`. **This is not `major.minor.patch`.** Treating it as such
is the classic error and produces the wrong soname. Encode the mapping deliberately.

## The knob

In `Makefile.am`, on a `_LTLIBRARIES` target:

```makefile
lib_LTLIBRARIES = libexample.la
libexample_la_SOURCES = example.c
libexample_la_LDFLAGS = -version-info $(EXAMPLE_LT_CURRENT):$(EXAMPLE_LT_REVISION):$(EXAMPLE_LT_AGE)
```

libtool passes the right `-Wl,-soname` and generates the symlink chain at `make install`.

## The mapping (memorize this)

Given `-version-info current:revision:age` (call them `C:R:A`), on Linux/ELF libtool emits:

```
soname     = libexample.so.(C - A)                     # DT_SONAME  -> (C - A) is the SOVERSION
real file  = libexample.so.(C - A).A.R
symlinks   = libexample.so -> libexample.so.(C-A) -> libexample.so.(C-A).A.R
```

So for `-version-info 3:2:1`:

```
SOVERSION  = C - A = 2       -> soname   libexample.so.2
real file  = libexample.so.2.1.2
```

**Consequence:** the libtool "current" is *not* the soname number. The soname/SOVERSION is
`current − age`. When mapping an intended `SOVERSION` onto libtool, the simplest correct choice
is `age = 0`, giving `soname = current`. (Nonzero `age` exists so one binary can advertise
compatibility with a range of older sonames; only use it deliberately.)

## The update rules (how maintainers bump C:R:A)

Apply these **in order**, starting from the current `C:R:A`, per release that changes the
installed library:

1. If the source code changed at all since the last release: **R += 1** (`revision`).
2. If any interface was **added, removed, or changed**: **C += 1**, then **R = 0**.
3. If interfaces were **added** (and none removed/changed — i.e. backward compatible): **A += 1**.
4. If any interface was **removed or changed** (incompatible): **A = 0**.

Reading the effect through the mapping `soversion = C − A`:

- Backward-compatible addition → `C += 1, A += 1` → `C − A` **unchanged** → same soname. ✅
- Incompatible change → `C += 1, A = 0` → `C − A` **increases** → new soname. ✅
- Bugfix only → `R += 1` → soname unchanged, real file's trailing number changes. ✅

This is libtool's way of expressing exactly the VERSION/SOVERSION rule: the soname
(`C − A`) moves **only on an ABI break**.

## Do not confuse `-version-info` with `-release`

libtool also has `-release X.Y`, which bakes the string into the filename
(`libexample-X.Y.so`) and makes **every** release incompatible (each gets a distinct name).
That is a different, coarser policy; do not mix it with `-version-info`. For standard ABI-based
versioning, use `-version-info` only.

## Single source of truth

Keep `C:R:A` in `configure.ac` as substituted variables, driven from one place, so `Makefile.am`
carries no literals:

```m4
# configure.ac
AC_INIT([example], [1.4.2])
EXAMPLE_LT_CURRENT=3
EXAMPLE_LT_REVISION=2
EXAMPLE_LT_AGE=1
AC_SUBST([EXAMPLE_LT_CURRENT])
AC_SUBST([EXAMPLE_LT_REVISION])
AC_SUBST([EXAMPLE_LT_AGE])
```

Note the **release** version (`AC_INIT` `1.4.2`) and the **libtool** `C:R:A` are intentionally
separate axes — the release version is human-facing; `C:R:A` drives the ABI soname. Document
both in `VERSIONING.md` and, if you need the soname's numeric SOVERSION elsewhere, compute
`C − A` rather than duplicating it.

## Idempotency notes

- Edit the existing `_la_LDFLAGS` `-version-info` in place; never add a second `-version-info`.
- Keep `C:R:A` in the `AC_SUBST` variables so a bump is a one-place change.
- A re-run should find `-version-info` present and, if the values are already consistent with
  the intended soname, make no change.

## Verify (after `./configure && make && make install`)

```bash
readelf -d <prefix>/lib/libexample.so.2.1.2 | grep SONAME   # -> libexample.so.2  (== C - A)
ls -l <prefix>/lib/libexample.so*
```

If the soname's number is not `C − A`, the `-version-info` values are inconsistent with intent
— recompute from the update rules above. See `validation.md`.

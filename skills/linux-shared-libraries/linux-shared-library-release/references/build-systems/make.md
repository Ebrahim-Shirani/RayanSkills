# Plain Make: shared library versioning (fallback)

Hand-written Makefiles have **no native versioning facility**. This is a documented fallback:
you set the soname explicitly at link time with `-Wl,-soname` and create the symlink chain
yourself with `ln -sf`. Be honest that this is manual, and keep it idempotent.

> Prefer a real build system (CMake/Meson/Autotools) if the project is willing. Use this only
> when plain Make is a hard constraint.

## Single source of truth

Define the version once, at the top of the Makefile (or in an included `version.mk`, or read
from a `VERSION` file), and derive the soname number:

```makefile
# --- version: single source of truth ---
VERSION   := 1.4.2
SOVERSION := $(word 1,$(subst ., ,$(VERSION)))   # -> 1  (MAJOR)

LIBNAME   := libexample
REALNAME  := $(LIBNAME).so.$(VERSION)            # libexample.so.1.4.2
SONAME    := $(LIBNAME).so.$(SOVERSION)          # libexample.so.1
LINKERNAME:= $(LIBNAME).so                       # libexample.so
```

Reading `VERSION` from a file keeps it out of the Makefile entirely:
`VERSION := $(shell cat VERSION)`.

## Link with an explicit soname

The soname must be embedded in the ELF via `-Wl,-soname`, and the output file is the **real
name**:

```makefile
$(REALNAME): $(OBJS)
	$(CC) -shared -Wl,-soname,$(SONAME) -o $@ $^ $(LDFLAGS)
	ln -sf $(REALNAME) $(SONAME)       # build-tree convenience links
	ln -sf $(SONAME)   $(LINKERNAME)
```

`-fPIC` must be in `CFLAGS` for the objects. The `-Wl,-soname,$(SONAME)` is what makes
`DT_SONAME = libexample.so.1`; without it, consumers would record the full filename as
`DT_NEEDED` — a defect.

## Install the chain (idempotently)

`ln -sf` (`-s` symlink, `-f` replace-if-exists) is inherently idempotent — re-running install
re-points the links without error or duplication:

```makefile
DESTDIR ?=
PREFIX  ?= /usr/local
LIBDIR  ?= $(PREFIX)/lib

install: $(REALNAME)
	install -d $(DESTDIR)$(LIBDIR)
	install -m 0755 $(REALNAME) $(DESTDIR)$(LIBDIR)/$(REALNAME)
	ln -sf $(REALNAME) $(DESTDIR)$(LIBDIR)/$(SONAME)      # soname   -> real
	ln -sf $(SONAME)   $(DESTDIR)$(LIBDIR)/$(LINKERNAME)  # linker   -> soname
```

Result:

```
libexample.so         -> libexample.so.1
libexample.so.1       -> libexample.so.1.4.2     # DT_SONAME
libexample.so.1.4.2
```

(If you split packages, `libexample.so` — the linker name — is the `-dev` artifact.)

## Bumping

- New release, compatible: change `VERSION` only (e.g. `1.4.2 → 1.5.0`); `SOVERSION` derived
  as `MAJOR` stays `1`; soname unchanged. ✅
- ABI break: bump `MAJOR` (`1.x → 2.0.0`); `SOVERSION` becomes `2`; soname becomes
  `libexample.so.2`. ✅

Because `SOVERSION` is derived from `VERSION`'s MAJOR here, a compatible minor release that you
mistakenly numbered as a MAJOR bump would move the soname — so keep the numbering policy
(`VERSIONING.md`) explicit: MAJOR bumps mean ABI breaks.

## Idempotency notes

- Use `ln -sf` everywhere (never plain `ln -s`, which errors if the link exists).
- Derive `SOVERSION`, `SONAME`, `REALNAME` from `VERSION`; don't scatter literals.
- Re-running this skill on an already-correct Makefile should detect `-Wl,-soname` and the
  `ln -sf` install rules and make no change.

## Verify

```bash
readelf -d libexample.so.1.4.2 | grep SONAME    # -> libexample.so.1
ls -l libexample.so*
```

See `validation.md`. The most important check for the hand-rolled path: confirm a **consumer**
records the soname, not the filename — `readelf -d ./consumer | grep NEEDED` should show
`libexample.so.1`. If it shows `libexample.so.1.4.2`, the `-Wl,-soname` was missing when the
library was linked.

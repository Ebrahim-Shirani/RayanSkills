# Bazel: shared library versioning (fallback)

Bazel's `cc_binary(linkshared = True)` / `cc_library` produce a `.so` but have **no native
soname/symlink-chain facility** equivalent to CMake's `SOVERSION`. This is a documented
fallback: set the soname explicitly via `linkopts`, and produce the versioned name + symlink
chain with a `genrule` (or a small custom/Starlark rule). Be honest that this is manual.

> If the project can use `rules_foreign_cc` to drive an underlying CMake/Meson/Autotools build,
> prefer that and follow the corresponding reference file instead.

## Set the soname on the shared object

The soname must be embedded in the ELF. Pass it through `linkopts`:

```python
# BUILD.bazel
SOVERSION = "1"
VERSION   = "1.4.2"

cc_binary(
    name = "libexample.so.%s.%s.%s" % tuple(VERSION.split(".")),  # libexample.so.1.4.2
    srcs = ["example.c"],
    linkshared = True,
    linkopts = ["-Wl,-soname,libexample.so.%s" % SOVERSION],       # DT_SONAME = libexample.so.1
)
```

`-Wl,-soname,libexample.so.1` is what makes consumers record `libexample.so.1` as `DT_NEEDED`
rather than the full filename. Keep `SOVERSION` at MAJOR and bump **only on an ABI break**.

Keep `VERSION`/`SOVERSION` as top-of-file constants (or load them from a shared `.bzl` via
`load(...)`) so there is a single source of truth.

## Generate the symlink chain

Bazel won't create the `.so.1` and `.so` symlinks for you; emit them with a `genrule`:

```python
genrule(
    name = "libexample_symlinks",
    srcs = [":libexample.so.1.4.2"],
    outs = ["libexample.so.1", "libexample.so"],
    cmd = """
        real=$(location :libexample.so.1.4.2)
        ln -sf $$(basename $$real) $(RULEDIR)/libexample.so.1
        ln -sf libexample.so.1     $(RULEDIR)/libexample.so
    """,
)
```

(Use `ln -sf` for idempotency.) Package all three names together (e.g. in the `pkg_tar` /
install step) so the deployed layout is:

```
libexample.so         -> libexample.so.1
libexample.so.1       -> libexample.so.1.4.2     # DT_SONAME
libexample.so.1.4.2
```

## A cleaner alternative

Wrap the two steps above in a small Starlark macro (`shared_library_versioned(name, version,
soversion, srcs, ...)`) in a `.bzl` file so each library is one call and the soname/symlink
logic lives in one place. This keeps `BUILD` files idempotent and DRY. Encoding that macro is
optional; the `genrule` approach above is sufficient and explicit.

## Bumping

- Compatible release: change `VERSION` only; `SOVERSION` stays; soname unchanged.
- ABI break: bump `SOVERSION` (and `VERSION` MAJOR); soname becomes `libexample.so.2`.

## Idempotency notes

- `ln -sf` in the genrule is idempotent by construction.
- Keep `VERSION`/`SOVERSION` as single constants; derive names from them.
- A re-run should find `-Wl,-soname` in `linkopts` and the symlink genrule already present, and
  make no change.

## Verify

```bash
readelf -d bazel-bin/.../libexample.so.1.4.2 | grep SONAME   # -> libexample.so.1
readelf -d bazel-bin/.../consumer | grep NEEDED              # -> libexample.so.1 (not the filename)
```

See `validation.md`.

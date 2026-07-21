# Meson: shared library versioning

Meson has native support via the `version` and `soversion` keyword arguments of
`shared_library()` / `library()`. It generates the soname and the install-time symlink chain.
**Do not** hand-roll symlinks.

## Single source of truth

Declare the version once on `project()` and reference it:

```meson
project('example', 'c', version : '1.4.2')

# project version is available as meson.project_version()
ver   = meson.project_version()          # '1.4.2'
sover = ver.split('.')[0]                # '1'  -> ABI generation (MAJOR)
```

## The versioning knob

```meson
libexample = shared_library('example',
    'src/example.c',
    version   : ver,        # 1.4.2  -> real file libexample.so.1.4.2
    soversion : sover,      # 1      -> soname    libexample.so.1  (DT_SONAME)
    install   : true)
```

Produces after `meson install`:

```
libexample.so         -> libexample.so.1
libexample.so.1       -> libexample.so.1.4.2     # DT_SONAME = libexample.so.1
libexample.so.1.4.2
```

Semantics:

- `soversion` is the soname / `DT_SONAME`. Keep it at `MAJOR`; bump **only on an ABI break**.
- `version` names the real file; must be `MAJOR.MINOR.PATCH`.
- If you give `version` but omit `soversion`, Meson derives `soversion` from the **first**
  component of `version`. This is convenient but implicit — prefer setting `soversion`
  explicitly so the ABI generation is stated, not inferred.
- Use `shared_library(...)` (or `library(...)` with `default_library=shared`); `soversion` is
  ignored for static builds.

## Consolidating duplicates

Generate a header from the project version instead of a second literal:

```meson
conf = configuration_data()
conf.set('EXAMPLE_VERSION',       ver)
conf.set('EXAMPLE_VERSION_MAJOR', sover)
configure_file(input : 'version.h.in',
               output : 'version.h',
               configuration : conf)
```

For pkg-config, use the `pkgconfig` module, which takes the version from the target/project:

```meson
import('pkgconfig').generate(libexample,
    description : 'Example library',
    version : ver)
```

Now `project(version : …)` is the sole source.

## Idempotency notes

- Edit the **existing** `shared_library()` call's keyword args in place; don't duplicate the
  target.
- Reference `meson.project_version()` rather than pasting the version, so a bump touches one
  line.
- A re-run should find `version`/`soversion` already present and correct, and make no change.

## Verify (after `meson compile` + `meson install`)

```bash
readelf -d <prefix>/lib/libexample.so.1.4.2 | grep SONAME   # -> libexample.so.1
ls -l <prefix>/lib/libexample.so*
```

See `validation.md`.

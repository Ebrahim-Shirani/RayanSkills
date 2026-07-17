# CMake: shared library versioning

CMake has first-class, native support. Use the `VERSION` and `SOVERSION` target properties;
`install(TARGETS)` generates the symlink chain automatically. **Do not** hand-roll symlinks.

## Single source of truth

Declare the version once, on `project()`, and let CMake expose the components:

```cmake
project(example VERSION 1.4.2 LANGUAGES C CXX)
# CMake now defines:
#   PROJECT_VERSION            = 1.4.2
#   PROJECT_VERSION_MAJOR      = 1
#   PROJECT_VERSION_MINOR      = 4
#   PROJECT_VERSION_PATCH      = 2
#   (and <PROJECT-NAME>_VERSION* equivalents)
```

If a header or pkg-config file also needs the version, **derive** it from here via
`configure_file()` rather than writing a second literal (see "Consolidating duplicates").

## The versioning knob

```cmake
add_library(example SHARED src/example.c)

set_target_properties(example PROPERTIES
    VERSION   ${PROJECT_VERSION}          # 1.4.2  -> real file libexample.so.1.4.2
    SOVERSION ${PROJECT_VERSION_MAJOR})   # 1      -> soname    libexample.so.1
```

This produces, after build + install:

```
libexample.so         -> libexample.so.1
libexample.so.1       -> libexample.so.1.4.2   # DT_SONAME = libexample.so.1
libexample.so.1.4.2
```

- `SOVERSION` becomes the soname (`DT_SONAME`). Keep it at `MAJOR` and bump **only on an ABI
  break** — not every release.
- `VERSION` names the real file. It must be `MAJOR[.MINOR[.PATCH]]`.
- Setting `SOVERSION` without `VERSION` is valid: soname = `SOVERSION`, real file =
  `libexample.so.<SOVERSION>` (no third level). Setting `VERSION` without `SOVERSION` makes the
  soname equal to the full `VERSION` — usually **not** what you want; set both.

## Install rules (generate the symlinks)

The symlink chain is created by `install(TARGETS)`, not by the build tree:

```cmake
include(GNUInstallDirs)
install(TARGETS example
    LIBRARY  DESTINATION ${CMAKE_INSTALL_LIBDIR}     # .so / .so.1 / .so.1.4.2 (ELF)
    RUNTIME  DESTINATION ${CMAKE_INSTALL_BINDIR}     # .dll on Windows
    ARCHIVE  DESTINATION ${CMAKE_INSTALL_LIBDIR})
```

CMake installs the real file and the two symlinks. The `libexample.so` (linker-name) symlink is
the dev artifact; if you split packages, it belongs in `-dev`.

## Consolidating duplicates

If the version is also hard-coded in a header, replace the literal with a generated file:

```cmake
configure_file(include/example/version.h.in
               ${CMAKE_CURRENT_BINARY_DIR}/include/example/version.h @ONLY)
target_include_directories(example PUBLIC ${CMAKE_CURRENT_BINARY_DIR}/include)
```

```c
/* include/example/version.h.in */
#define EXAMPLE_VERSION       "@PROJECT_VERSION@"
#define EXAMPLE_VERSION_MAJOR  @PROJECT_VERSION_MAJOR@
```

Same approach for `example.pc.in` (pkg-config): substitute `@PROJECT_VERSION@` /
`@PROJECT_VERSION_MAJOR@`. Now `project(VERSION …)` is the sole source of truth.

## Idempotency notes

- Modify the **existing** `set_target_properties` in place; do not add a second call — CMake
  would honor only the last, silently masking the earlier one.
- Prefer referencing `${PROJECT_VERSION}` / `${PROJECT_VERSION_MAJOR}` over pasting literals, so
  a version bump touches exactly one line (`project()`).
- Re-running this skill should find the properties already set and make no change.

## Verify (after `cmake --build` + `cmake --install`)

```bash
readelf -d <prefix>/lib/libexample.so.1.4.2 | grep SONAME   # -> libexample.so.1
ls -l <prefix>/lib/libexample.so*                           # chain: .so -> .so.1 -> .so.1.4.2
```

See `validation.md` for full interpretation.

## Gotcha: macOS

On macOS `VERSION`/`SOVERSION` map to Mach-O `current_version`/`compatibility_version`, not an
ELF soname. This skill targets Linux; don't rely on the symlink chain semantics off-ELF.

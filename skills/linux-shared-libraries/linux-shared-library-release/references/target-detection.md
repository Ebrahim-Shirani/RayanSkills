# Build-mode detection and the remote protocol

The executable's dependency versions are only meaningful on the machine (or
in the filesystem image) where it will actually run. This file explains how
to figure out which situation you are in and what to do in each.

## Detection order

If `dependency.md` already records `target.mode`, use it. Re-detect only if
the build files have visibly changed (e.g. a toolchain file appeared), and if
your detection disagrees with the recorded mode, ask the user instead of
silently switching.

Otherwise inspect the build tool:

1. **Toolchain file present?** Look for `CMAKE_TOOLCHAIN_FILE`,
   `-DCMAKE_TOOLCHAIN_FILE` in build scripts/presets, or `toolchain*.cmake`
   in the repo. Inside it, `CMAKE_SYSROOT` / `CMAKE_FIND_ROOT_PATH` and
   `CMAKE_SYSTEM_PROCESSOR` identify a **cross-sysroot** build. Record the
   sysroot path and target triple.
2. **No toolchain file, compiler is native, libraries resolve on this
   machine?** → **native**.
3. **Dependency paths in the build files do not exist on this machine**
   (e.g. `CMakeLists.txt` references `/opt/nvidia/deepstream/...` or
   aarch64 library paths that aren't here), or the project docs/CLAUDE.md
   describe building on another machine → **remote**, or at least
   inconclusive.

If inconclusive, ask the user directly: "Where is this program built and
run?" Offer the three modes. Record the answer in `dependency.md` — the
question must not be asked again on later runs.

## Per-mode fact gathering

### native

Everything is local. `extract_deps.py <binary>` with no flags; `pkg-config`,
`dpkg`/`rpm`, compiler `--version` all run directly.

### cross-sysroot

The compiler and sysroot are on this machine; the target device is not
needed at all. Gather facts like this:

- Compiler: run the cross compiler from the toolchain file with `--version`.
- Libraries: `extract_deps.py <binary> --sysroot <path>` — SONAME resolution
  happens inside the sysroot.
- pkg-config: `PKG_CONFIG_SYSROOT_DIR=<sysroot>
  PKG_CONFIG_LIBDIR=<sysroot>/usr/lib/pkgconfig:<sysroot>/usr/share/pkgconfig
  pkg-config --modversion <pkg>`.
- libc/libstdc++ versions: from the sysroot's files, same as any library.

### remote

Only sources are here; the built executable and all libraries live on the
target machine. Facts must come from there.

1. Check `dependency.md` for a recorded `target.ssh_host`. If present, test
   it (`ssh <host> true`, short timeout). Working → proceed: run the same
   commands as native mode, prefixed with `ssh <host>`; copy
   `extract_deps.py` over (`scp`) or run its equivalent commands remotely
   (`readelf -d`, `ls -l` on the resolved libraries, `pkg-config`,
   `dpkg -s`).
2. No recorded host: ask the user. They may provide an SSH host/alias (with
   key-based access) or a build script that already reaches the target. If
   provided and it works, record in `dependency.md`:
   `target.mode: remote`, `target.ssh_host: <host>`,
   `target.automated: true`. From then on every activation of this mechanism
   uses it automatically.
3. Access not available: state plainly that the target machine is
   unreachable and that dependency facts cannot be collected. If the user
   wants to continue, they must provide the SSH connection now. If they
   cannot, **stop the release**. Do not substitute host-machine library
   versions, and do not guess — a dependency snapshot that describes the
   wrong machine is worse than none, because later releases will diff
   against it.

## What gets recorded

Whatever mode is determined, write it into the `target:` block of
`dependency.md` (see `dependency-file.md`): mode, triple, sysroot path or
ssh host, and whether automated collection is possible. This block is what
makes every later release run without re-asking.

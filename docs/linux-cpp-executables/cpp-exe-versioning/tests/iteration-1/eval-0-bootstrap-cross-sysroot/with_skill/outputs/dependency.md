2.1.0+2.gf8bae99

## Snapshot

```yaml
version: 2.1.0
build: 2.gf8bae99
released: 2026-07-19
target:
  mode: cross-sysroot     # native | cross-sysroot | remote
  triple: aarch64-linux-gnu
  ssh_host: null          # remote mode only
  sysroot: sysroot        # repo-relative; toolchain-aarch64.cmake sets CMAKE_SYSROOT
  automated: true         # facts collectable without asking the user
toolchain:
  compiler: aarch64-linux-gnu-g++ (version unknown - cross compiler not installed on this host)
  cxx_standard: 14
dependencies:
  - name: opencv_core
    kind: third-party
    version: 4.1.1
    soname: libopencv_core.so.4.1
    version_source: soname
  - name: spdlog
    kind: third-party
    version: 1.9.2
    soname: libspdlog.so.1
    version_source: soname
```

## Notes

- Bootstrap baseline: project was previously versioned manually (spreadsheet);
  2.1.0 was provided as the current version. No bump computed on this first run.
- Facts collected from the in-repo sysroot (`sysroot/usr/lib/aarch64-linux-gnu`)
  by SONAME/realname; no pkg-config metadata present in the sysroot.
- No built executable was available, so declared CMake dependencies
  (`target_link_libraries`: spdlog, opencv_core) were used; run
  `extract_deps.py <binary> --sysroot sysroot` on the next release once a
  binary exists.
- Record the cross compiler version on the next run if the toolchain becomes
  available on the host.

1.3.0+3.g2c82bfb

## Snapshot

```yaml
version: 1.3.0
build: 3.g2c82bfb
released: 2026-07-19
target:
  mode: native
  triple: x86_64-linux-gnu
  ssh_host: null
  sysroot: null
  automated: true
toolchain:
  compiler: g++ (Ubuntu 11.4.0-1ubuntu1~22.04.3) 11.4.0
  cxx_standard: 17
dependencies:
  - name: zlib
    kind: third-party
    version: 1.2.11
    soname: libz.so.1
    version_source: dpkg
  - name: libc
    kind: standard
    version: "6"
    soname: libc.so.6
    version_source: soname
```

## Notes

- Native build; all facts collected locally on x86_64-linux-gnu.
- ELF DT_NEEDED of `build/logtool`: `libz.so.1`, `libc.so.6`. `libstdc++.so.6`
  from the previous snapshot is no longer in DT_NEEDED (no C++ runtime
  symbols referenced); recorded set updated to match the binary.

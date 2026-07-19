0.9.2+2.g830daab

## Snapshot

```yaml
version: 0.9.2
build: 2.g830daab
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
  - name: foo
    kind: in-house
    version: 1.4.0
    soname: libfoo.so.1
    version_source: soname
  - name: libc
    kind: standard
    version: "6"
    soname: libc.so.6
    version_source: soname
```

## Notes

- Native build; facts collected locally from `build/fooapp` (ELF DT_NEEDED)
  and `libs/` realnames.
- libfoo updated 1.2.0 -> 1.4.0 with SONAME unchanged (`libfoo.so.1`);
  no app source changes in this release.
- The previous snapshot listed `libstdc++`; the current binary's DT_NEEDED
  contains only `libfoo.so.1` and `libc.so.6` (the app uses no C++ runtime
  symbols). Recorded what the binary actually needs. No behavior impact.
- BUILD computed at commit 830daab, the source state the released binary
  was built from.

0.9.2+1.g830daab

## Snapshot

```yaml
version: 0.9.2
build: 1.g830daab
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
  - name: libstdc++
    kind: standard
    version: "6"
    soname: libstdc++.so.6
    version_source: soname
```

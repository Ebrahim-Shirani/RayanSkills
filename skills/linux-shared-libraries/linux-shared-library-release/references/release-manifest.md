# dependency.md — release-manifest format for a shared library

`dependency.md` is committed to the repo and serves three purposes: (1) the
first line is the machine-readable current version, (2) the YAML block is the
snapshot the next release diffs against, (3) its git history is the release
and dependency history. The `library:` block records what makes a `.so`
release different from any other artifact; everything else is generic
release bookkeeping.

## Rules

- **Line 1 is exactly the full version string and nothing else** — no
  heading, no prose. One-line read gives the version.
- Everything needed to *re-run without asking questions* lives under
  `target:`.
- Every dependency records `version_source` so the next diff compares the
  same kind of number against itself.
- The `library:` block records the ABI-side outcome of the release: SONAME,
  SOVERSION, the verdict that produced this version, the baseline it was
  judged against, and the engine version that judged it.
- Human-readable notes go after the YAML block, never before line 2.

## Template / example

```markdown
1.5.0+412.gc21b4e0

## Snapshot

```yaml
version: 1.5.0
build: 412.gc21b4e0
released: 2026-07-20
library:
  name: libexample
  soname: libexample.so.1
  soversion: 1
  abi_verdict: COMPATIBLE_WITH_ADDITIONS   # vs baseline below
  abi_baseline: abi-baselines/1.4.2/libexample.so.1.abi
  libabigail: abidw 2.4
  headers_installed: include/example/*.h
target:
  mode: cross-sysroot       # native | cross-sysroot | remote
  triple: aarch64-linux-gnu
  ssh_host: null
  sysroot: /opt/poky/3.1/sysroots/aarch64-poky-linux
  automated: true
toolchain:
  compiler: aarch64-poky-linux-g++ 9.2.0
  cxx_standard: 17
dependencies:
  - name: zlib
    kind: third-party
    version: 1.2.11
    soname: libz.so.1
    version_source: soname
  - name: libstdc++
    kind: standard
    version: 6.0.28
    soname: libstdc++.so.6
    version_source: soname
```

## Notes

- ABI additions: example_frob_ex() added; existing surface untouched.
```

## Diffing on the next release

Parse the YAML block, collect a fresh snapshot the same way (same
`version_source` per dependency), and produce **changed / added / removed**
lists for classification. The `library.abi_baseline` path tells the check
step what the current build must be judged against. After the bump is
decided, rewrite the whole file with the new snapshot and commit it in the
release commit that gets tagged — together with the new baseline under
`abi-baselines/` (see `references/abi-baselines.md`).

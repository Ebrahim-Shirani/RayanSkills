# dependency.md — format specification

`dependency.md` is committed to the repo and serves three purposes: (1) the
first line is the machine-readable current version, (2) the YAML block is
the snapshot the next release diffs against, (3) its git history is the
project's dependency history.

## Rules

- **Line 1 is exactly the full version string and nothing else** — no
  heading, no prose. A program or script must be able to get the version by
  reading one line.
- Everything the mechanism needs to *re-run without asking questions* lives
  in the `target:` block.
- Every dependency records `version_source` so the next diff compares the
  same kind of number against itself (a SONAME-derived version and a
  pkg-config version for the same lib can legitimately differ).
- Human-readable notes go after the YAML block, never before line 2.

## Template / example

```markdown
1.4.2+345.g7a3f9c1

## Snapshot

```yaml
version: 1.4.2
build: 345.g7a3f9c1
released: 2026-07-19
target:
  mode: remote            # native | cross-sysroot | remote
  triple: aarch64-linux-gnu
  ssh_host: jetson        # remote mode only
  sysroot: null           # cross-sysroot mode only
  automated: true         # facts collectable without asking the user
toolchain:
  compiler: g++ (Ubuntu/Linaro 7.5.0) 7.5.0
  cxx_standard: 17
dependencies:
  - name: opencv
    kind: third-party
    version: 4.1.1
    soname: libopencv_core.so.4.1
    version_source: soname
  - name: spdlog
    kind: third-party
    version: 1.9.2
    version_source: pkg-config
  - name: kcf
    kind: in-house
    version: 2.3.0
    soname: libkcf.so.2
    version_source: soname
  - name: libstdc++
    kind: standard
    version: 6.0.25
    soname: libstdc++.so.6
    version_source: soname
```

## Notes

- Remote facts collected over `ssh jetson`.
```

## Diffing on the next release

Parse the YAML block from the committed `dependency.md`, collect a fresh
snapshot the same way (same `version_source` per dependency), and produce
three lists: **changed** (same name, different version), **added**,
**removed**. These feed Phase 3 classification. After the bump is decided,
rewrite the whole file with the new version and snapshot and commit it as
part of the release commit that gets tagged.

# logtool 1.3.0 — Release Notes

Released: 2026-07-19
Build: 1.3.0+2.g2c82bfb (2 commits since v1.2.3, base 2c82bfb)
Target: native x86_64-linux-gnu

## Why 1.3.0

Changes since v1.2.3 include one feature and one fix; per semantic
versioning the feature drives a minor bump (1.2.3 -> 1.3.0).

## Changes

### Features
- Add --json output mode for machine-readable logs (2c82bfb)

### Fixes
- Print correct zlib version string on startup (25646f5)

## Dependencies

- zlib 1.2.11 (libz.so.1, from dpkg) — unchanged
- libstdc++ 6 (libstdc++.so.6) — unchanged

Toolchain: g++ (Ubuntu 11.4.0-1ubuntu1~22.04.3) 11.4.0, C++17.
Verified: release binary rebuilt and smoke-tested (`logtool version 1.2.11`).

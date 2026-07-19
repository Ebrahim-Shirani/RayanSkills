# logtool 1.3.0+3.g2c82bfb — 2026-07-19

Minor release (1.2.3 -> 1.3.0): one new backward-compatible capability and
one bug fix. Existing configs, flags, and default output are unchanged.

## Changes

- **feat: add --json output mode for machine-readable logs** (`2c82bfb`)
  Adds a new `--json` flag that emits logs in a machine-readable JSON
  format, for consumption by scripts and log pipelines. The default
  human-readable output is untouched, so existing workflows keep working.
  Classified MINOR (new capability, old behavior preserved) — this sets the
  release bump.

- **fix: print correct zlib version string on startup** (`25646f5`)
  The startup banner previously reported a wrong zlib version; it now prints
  the version actually linked (via `zlibVersion()`). No interface change.
  Classified PATCH.

- **Dependency link set: libstdc++ no longer required** (build observation)
  The built executable's DT_NEEDED now lists only `libz.so.1` and
  `libc.so.6`; `libstdc++.so.6` is no longer needed. No user-visible
  behavior change. Classified PATCH.

## Dependencies

- zlib 1.2.11 (dpkg) — unchanged
- Toolchain: g++ 11.4.0, C++17 — unchanged

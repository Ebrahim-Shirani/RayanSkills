# fooapp 0.9.2+2.g830daab — Release Notes (2026-07-19)

## Changes since v0.9.1

- **Vendored libfoo updated 1.2.0 -> 1.4.0** (commit `830daab`).
  - What changed: the prebuilt in-house library `libs/libfoo.so.1.4.0`
    replaced `libs/libfoo.so.1.2.0`; the SONAME `libfoo.so.1` is unchanged,
    so the ABI remains compatible by convention.
  - Why: routine drop-in of an updated build of the vendored dependency.
  - Impact: no application source changes, no CLI/config/data/behavior
    contract changes for users. Classified as PATCH (dependency version
    changed, app code untouched).

## Version reasoning

- Bump: PATCH (leftmost and only change class) -> 0.9.1 -> 0.9.2
- BUILD: 2.g830daab (commit count + short hash of the built source state)

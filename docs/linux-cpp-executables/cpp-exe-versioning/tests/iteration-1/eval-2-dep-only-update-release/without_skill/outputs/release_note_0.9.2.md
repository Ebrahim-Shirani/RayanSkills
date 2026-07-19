# fooapp 0.9.2 — Release Notes

Released: 2026-07-19
Build: 0.9.2+1.g830daab

## Summary

Patch release. The only change since 0.9.1 is an updated build of the
vendored in-house dependency libfoo: 1.2.0 -> 1.4.0. There are no
application source changes, so the app's own behavior/API is unchanged
and this is a patch-level bump (0.9.1 -> 0.9.2).

## Changes

- Vendored libfoo updated from 1.2.0 to 1.4.0 (libs/libfoo.so.1.4.0).
- SONAME is unchanged (libfoo.so.1), i.e. the update is ABI-compatible;
  the existing fooapp binary (linked against libfoo.so.1 with runpath
  $ORIGIN/../libs) picks up the new library without a rebuild.
- Verified: build/fooapp runs against libfoo 1.4.0 (smoke test passes,
  resolves libs/libfoo.so.1 -> libfoo.so.1.4.0).

## Dependencies

| Name      | Kind     | Version | SONAME         |
|-----------|----------|---------|----------------|
| foo       | in-house | 1.4.0   | libfoo.so.1    |
| libstdc++ | standard | 6       | libstdc++.so.6 |

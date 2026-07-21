# Bump rules — full reasoning and edge cases

The executable's version contract is **behavior**: command-line interface,
config file format, data formats, outputs, and observable behavior. A change
is MAJOR when a user who upgrades in place — same configs, same data, same
scripts around the program — gets breakage. It is MINOR when they get new
capability and nothing breaks. It is PATCH when nothing about the contract
moved at all.

## Toolchain

- **Language standard changed** (C++11 → C++17, C99 → C11...): MAJOR. The
  build environment contract changed for everyone who builds this program.
  Detect from `CMAKE_CXX_STANDARD` / `-std=` diffs in the build tool.
- **Compiler version changed, same standard:** PATCH, unless it forced code
  changes — then classify those code changes on their own merits.

## App code

- Bug fixes only → PATCH.
- New capability, previous behavior intact → MINOR.
- Old configs/data no longer load, CLI flags removed or changed meaning,
  output format changed in a way consumers must adapt to → MAJOR.

With Conventional Commits (`fix:` / `feat:` / `feat!:` or a
`BREAKING CHANGE:` footer), the mapping is mechanical. Without them, read
the diff; concentrate on parsers, file formats, CLI handling, and defaults —
that is where silent breaking changes live.

## Dependencies (identical rules for in-house and third-party)

Judge a dependency only by its standard metadata: SONAME and realname
version (`libfoo.so.MAJOR` / `libfoo.so.X.Y.Z`), pkg-config version,
package manager version. Never assume it follows any custom scheme. If an
in-house library happens to publish a `X.Y.Z+BUILD` version, compare only
`X.Y.Z` — build metadata never participates in comparison (this is also the
SemVer rule).

- **Version changed, zero code impact** (no commits touch its usage sites;
  program just links the newer library): PATCH. Even if the *dependency's*
  own MAJOR changed — what matters is the effect on this program, and a
  rebuild against a new library is a real but invisible change.
  - The SONAME shortcut: if the library follows standard `.so` versioning
    and only the realname's minor/patch moved (same SONAME), the ABI is
    compatible by convention — PATCH with no further investigation needed.
    If the **SONAME itself** changed (`libfoo.so.1` → `libfoo.so.2`), the
    program was necessarily rebuilt against an incompatible ABI; check
    whether code had to change and classify accordingly (below).
- **Code adapted, backward-compatibly** — e.g. the app now calls a new API
  the library added, everything old still works: MINOR.
- **Code adapted such that the app itself broke compatibility** — the
  migration forced config/data/behavior changes visible to the app's users:
  MAJOR. Note the direction of reasoning: a dependency's breaking change
  does *not* automatically make the app's bump MAJOR; it is MAJOR only if
  the breakage propagated to the app's own contract.
- **Dependency added:** MINOR if it exists to power a new user-visible
  capability, PATCH if it is internal plumbing. **Removed:** PATCH if
  behavior is unchanged, MAJOR if capability was dropped.

## Combining

Collect every classified change, take the leftmost (most significant) bump,
apply it once, zero the parts to its right. Never apply two bumps in one
release. BUILD is recomputed from git regardless.

## When to ask the user

Ask only when the code genuinely does not answer the question, and ask about
the specific change: name the commit or the dependency and the concrete
doubt ("libfmt went 9→10 and formatting call sites changed in commit
`4f2c11a`; does the log output format change for existing users?"). The
user's answer resolves that change's class; everything mechanical stays
mechanical.

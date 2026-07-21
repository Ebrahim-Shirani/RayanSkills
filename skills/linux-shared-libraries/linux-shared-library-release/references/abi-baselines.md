# ABI baselines — lifecycle and storage policy

The release decision (which part of the version to bump, whether SOVERSION
moves) is driven by comparing the new build against the ABI of the *previous
release*. That previous ABI must exist somewhere trustworthy. This file
defines where it lives and how it flows through releases.

## The lifecycle

Every release does two baseline operations, in this order:

1. **Check (phase 3):** `scripts/abi_baseline.sh check <new-lib.so.X.Y.Z>`
   diffs the freshly built library against the newest committed baseline and
   emits the verdict that drives the bump.
2. **Save (phase 7):** after the new version is decided and the final artifact
   is built, `scripts/abi_baseline.sh save <lib.so.X.Y.Z> <new-version>`
   serializes the new ABI corpus. Commit `abi-baselines/` as part of the same
   release commit that gets tagged — the tag, the manifest, and the baseline
   must never drift apart.

Layout in the repo:

```
abi-baselines/
└── 1.4.2/
    ├── libexample.so.1.abi        # abidw corpus (XML)
    └── libexample.so.1.abi.meta   # soname, version, libabigail version, dwarf yes/no, date
```

## Why commit the corpus (not regenerate from tags)

Regenerating a baseline by rebuilding an old tag assumes the old toolchain is
still available and produces a bit-identical ABI corpus. In cross-development
that assumption routinely fails, and `abidw` output itself varies across
libabigail versions. A baseline you cannot reproduce is a verdict you cannot
trust. Committing costs repo size; it buys self-contained, review-diffable
ABI history. Regeneration from a tagged build is the documented *fallback*
when a baseline is missing (first adoption, corrupted file) — never the
primary path. When falling back, record in the manifest that the baseline was
regenerated and with which libabigail version.

Record the **libabigail version** in `.meta` and in the release manifest:
verdicts are only strictly reproducible with the same engine version.

If corpus size becomes a problem, store `xz`-compressed (`.abi.xz`) and
decompress before `abidiff`; do not sacrifice the committed history.

## Debug info is what makes verdicts real

`abidw`/`abidiff` are type-aware only when DWARF is present. Build release
candidates with `-g`; save the baseline **before** stripping; then
`objcopy --only-keep-debug` + `strip` for the shipped artifact. A baseline
saved from a stripped library condemns every future comparison to
INCONCLUSIVE for layout changes — the save script warns, listen to it.

## Where the engine runs

`abidw`/`abidiff` parse ELF+DWARF as data and never execute the binary, so
ABI analysis has no reason to happen where the artifact runs. The rule:
**move artifacts to the engine, never the engine to the target.**

- **Requirement:** libabigail on the *analysis host* — the machine where
  this skill executes. Targets need nothing installed, ever (embedded
  targets often have no package manager and no room for dev tooling).
  Install: `apt install abigail-tools` (Debian/Ubuntu),
  `dnf install libabigail` (Fedora/RHEL), `pacman -S libabigail` (Arch).
  Without root: `apt-get download abigail-tools libabigail0` (user-writable
  `-o Dir::State::lists=... -o Dir::Cache=...` if needed), then
  `dpkg -x <deb> ~/local` and run with `PATH=~/local/usr/bin:$PATH`
  `LD_LIBRARY_PATH=~/local/usr/lib/x86_64-linux-gnu` — the runtime deps
  (libelf, libdw, libxml2) are usually already present.
- **native / cross-sysroot:** the artifact is already local; analyze in
  place.
- **remote mode:** fetch the built library over SSH/scp into a host temp
  dir, then analyze locally. Fetch the **unstripped** artifact, or the
  stripped one *plus* its split `.debug` file — a DWARF-less fetch silently
  degrades every future verdict to INCONCLUSIVE. If the remote build only
  produces stripped binaries, fix that first (build with `-g`, strip at
  packaging).
- **Host cannot have libabigail:** the `.abi` corpus is portable XML, so
  the engine's location is flexible — copy baseline + artifact to any
  reachable machine that has libabigail (even the remote itself, if it
  happens to) and run the check there. Failing that, the degraded binutils
  ladder applies: a symbol diff can *prove* BREAKING but can never prove
  COMPATIBLE, so it may block a release but never green-light one — the
  scripts return INCONCLUSIVE and the release stops honestly.

## Cross-compilation

`abidw` and `abidiff` read ELF+DWARF and execute nothing, so both baseline
operations run on the build host against foreign-architecture artifacts.
Never compare corpora across architectures — the psABI differs and the
verdict is meaningless; the check script refuses via the meta/ELF machine
mismatch. One baseline set per target architecture if you ship several
(subdirectory per triple, e.g. `abi-baselines/aarch64-linux-gnu/1.4.2/`).

## INCONCLUSIVE is a stop, not a pass

The check script exits 2 for INCONCLUSIVE (missing DWARF, missing engine,
tool errors). Do not release on a guess: fix the cause (install libabigail,
rebuild with `-g`) and re-check. If the user insists on proceeding, record
the unverified status explicitly in the release note and manifest.

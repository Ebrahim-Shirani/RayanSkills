# The release gate — what is checked before shipping, and why

Run `scripts/release_gate.sh <libNAME.so.X.Y.Z> [--pc file.pc] [--consumer bin]`
on the built artifact in phase 6. Any FAIL blocks the release. The script is
execution-free (readelf/file only), so it works unchanged on cross-compiled
artifacts. This file explains each check so failures can be diagnosed, not
just reported.

**Realname is a regular ELF shared object.** The versioned file
`libNAME.so.X.Y.Z` must be the real object; if it is itself a symlink the
chain is inverted and installs break.

**SONAME present and conventional.** Without `DT_SONAME` the linker records
the *path or full filename* the consumer was linked against — every future
release then breaks every consumer. Convention is `libNAME.so.<SOVERSION>`
with SOVERSION = MAJOR; a deliberate deviation (e.g. libtool
current:revision:age arithmetic) is acceptable only if `VERSIONING.md`
documents it.

**Symlink chain.** `libNAME.so → libNAME.so.SOVER → realname`. The middle
link is what the loader resolves at runtime (it equals the SONAME); the dev
link is what `-lNAME` resolves at link time. A missing middle link means
nothing that depends on the library will load from this directory; a missing
dev link is only a warning because packaging often creates it at install.

**DT_NEEDED entries are plain SONAMEs.** A NEEDED entry containing a slash or
a full `x.y.z` version means some dependency was linked without a SONAME —
the defect propagates to this library's consumers.

**RPATH/RUNPATH hygiene.** A baked absolute path leaks the build layout,
overrides the system search order, and breaks relocation. `$ORIGIN`-relative
entries are legitimate for bundled layouts — verify they are intended.

**Strip / debug split.** Ship stripped; keep debug info. Order matters: save
the ABI baseline (needs DWARF) → `objcopy --only-keep-debug lib lib.debug` →
`strip --strip-unneeded lib` → `objcopy --add-gnu-debuglink=lib.debug lib`.
The gate warns rather than fails here because policies differ, but a shipped
`.debug_info` section is almost never intended.

**No TEXTREL.** Text relocations mean some object was built without `-fPIC`:
pages cannot be shared, and hardened loaders refuse the library outright.

**pkg-config agreement.** A `.pc` whose `Version:` disagrees with the
realname misleads every downstream `pkg-config --modversion` check —
consumers pin against a lie. Keep the `.pc` generated from the single version
source of truth (see the build-system references), never hand-edited.

**Consumer binds the SONAME.** Given `--consumer`, its `DT_NEEDED` must be
exactly the SONAME. A full-filename NEEDED means the consumer was linked
against a library that lacked its SONAME at link time.

Symbol-visibility surface is judged in phase 3 (the ABI diff shows exactly
what is exported); if the export list contains obviously internal symbols,
raise it with the user — the fix (`-fvisibility=hidden` + explicit exports)
is an ABI-affecting change to plan, not to slip into a release.

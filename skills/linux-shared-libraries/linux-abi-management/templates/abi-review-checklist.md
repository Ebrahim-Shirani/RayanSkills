# ABI review checklist

Use for Workflow 2 (judging a proposed change) or as the review scaffold for
a release diff. Every item is a concrete check — tick it only with evidence
(command output or an explicit reasoning note). Delete rows that genuinely
don't apply; never leave one unticked and unexplained.

## 1. Frame the change

- [ ] Listed every individual change (one verdict per change, worst-of wins).
- [ ] Identified the crossing types: every struct/class/enum/typedef that
      appears in exported signatures, public headers, or callback contracts.
- [ ] Stated target architectures for the judgment (x86-64 only? aarch64
      too?). Arch-sensitive constructs present (bitfields, `long double`,
      HFAs)? → judge per arch.
- [ ] Toolchain identical between the compared versions? If not, completed
      the flag checklist in `reference/compiler-linker-loader.md`
      (`_FILE_OFFSET_BITS`, `_TIME_BITS`, visibility, dual-ABI, LTO,
      pack/enum flags).

## 2. Symbol set

- [ ] No exported symbol removed or renamed
      (`nm -D --defined-only old | sort` vs `new`, `comm -23`).
- [ ] No symbol's binding demoted (GLOBAL→WEAK) or visibility tightened
      (DEFAULT→HIDDEN/PROTECTED) (`readelf --dyn-syms -W`, Bind/Vis columns).
- [ ] Exported **data** symbols: size unchanged (`readelf --dyn-syms`, Size
      column — copy relocations freeze the old size into consumers).
- [ ] Symbol versions: every old (name, version) pair still defined; no
      version node dropped (`readelf -V`; `reference/symbol-versioning.md`).
- [ ] Additions reviewed: intentional, and genuinely additive (no
      "addition" that shifts a vtable or grows a caller-allocated struct).

## 3. Types and layout

- [ ] For every crossing struct/class: size, alignment, and every field
      offset unchanged (`pahole -C <type>` old vs new, or abidiff report).
- [ ] No field inserted/reordered/retyped in caller-visible structs.
- [ ] Struct growth cases: proven library-allocated AND no `sizeof` leakage
      from public headers/macros.
- [ ] Enums: no renumbering of existing constants; additions don't change
      the enum's size on any target ABI.
- [ ] Function signatures: parameter/return types unchanged — including
      typedef indirection (`time_t`, `off_t` width!) and transitively
      included types.

## 4. C++ specifics (skip for pure C with `extern "C"` verified)

- [ ] No virtual function added/removed/reordered/re-signatured; vtable
      layout confirmed unchanged (abidiff vtable section).
- [ ] No data member added to consumer-allocated classes (private counts).
- [ ] No base-class or virtual-base change.
- [ ] Inline/template code in public headers: bodies unchanged, or the
      semantic skew (old copies inlined in consumers) explicitly judged.
- [ ] Return-type-only change anywhere? (same mangled name → silent break).
- [ ] `std::` types crossing the boundary: dual-ABI setting and standard
      library (libstdc++/libc++) unchanged between builds.

## 5. Semantics (tools cannot check these — reason explicitly)

- [ ] Behavior contracts kept: errno/return conventions, ownership/free
      rules, thread-safety, reentrancy, blocking behavior.
- [ ] No change to the meaning of existing enum values / flag bits /
      `#define` constants that are compiled into consumers.
- [ ] Callback invocation contracts (order, thread, lifetime) unchanged.

## 6. Linkage metadata

- [ ] SONAME unchanged (or: bump intended and approved — see §8).
- [ ] NEEDED closure changes reviewed (new runtime deps consumers must
      satisfy).
- [ ] TLS: no exported `__thread` growth / model change (`dlopen` static-TLS
      risk).

## 7. Verification actually run

- [ ] `abidiff old new` (DWARF builds) — exit code and report recorded.
- [ ] Fallbacks/corroboration as applicable: ACC, `pahole` per type,
      `nm -D` diff.
- [ ] If an existing consumer binary is available:
      `LD_LIBRARY_PATH=<new> LD_BIND_NOW=1 ldd -r <consumer>` clean, and a
      real workload exercised.
- [ ] Results recorded in `templates/abi-report.md`.

## 8. Verdict and gate

- [ ] Single verdict stated: COMPATIBLE / COMPATIBLE_WITH_ADDITIONS /
      BREAKING / INCONCLUSIVE — with the mechanism for every non-compatible
      item.
- [ ] If BREAKING: explicitly flagged to the owner; approval obtained
      **before** proceeding; SONAME-bump decision made and recorded
      (`reference/migration.md`).
- [ ] API impact stated separately from ABI impact.
- [ ] Out-of-scope follow-ups (packaging, CI wiring, versioning-scheme
      authoring) named as such and left to their owners.

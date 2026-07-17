# C ABI — layout, calling conventions, and architecture effects

The C ABI on Linux is defined per architecture by the **System V psABI**
supplements (x86-64, AArch64/AAPCS64, RISC-V, …) plus the platform's data
model (**LP64** on 64-bit Linux: `int`=4, `long`=`size_t`=pointer=8). A C ABI
judgment is always "same psABI, same data model, did the *types crossing the
boundary* change shape?"

## Struct and union layout rules (what "shape" means)

1. Fields are laid out **in declaration order** — the compiler never
   reorders.
2. Each field is aligned to its natural alignment; padding is inserted before
   fields as needed and after the last field to round the struct size up to
   its own alignment (max of field alignments).
3. Consequences for judgment:
   - **Appending** a field grows size, keeps existing offsets. Breaking iff
     any consumer allocates/embeds/arrays the struct or does `sizeof`
     arithmetic; compatible when the library allocates and consumers only
     hold pointers (the opaque/handle pattern).
   - **Inserting or reordering** fields shifts offsets → always BREAKING for
     any consumer that touches members directly.
   - **Changing a field's type** to one of different size/alignment shifts
     everything after it, and may change the whole struct's alignment.
4. Verify layout empirically, never by eye — padding is easy to mispredict:

```bash
pahole -C mystruct libfoo.so          # needs DWARF (-g) or BTF
# offsets, holes, total size per field — diff old vs new output
```

### Bitfields

Allocation order and unit packing are ABI-defined per psABI but subtle
(storage-unit sharing, ordering differs by endianness). Any change to a
bitfield sequence in a crossing struct: treat as BREAKING unless `pahole`
proves identical layout.

### Arrays, `flexible array member`, and `sizeof` leakage

A `[]` flexible array member at struct end keeps size stable when elements
grow — but any header macro that does `sizeof(struct s)` bakes today's size
into consumers. When judging "library-allocates" struct growth, grep the
public headers for `sizeof` of that type; a hit downgrades the verdict to
BREAKING.

## Enums and integer types

- Default: an enum is `int`-sized (values fitting in `int`). With
  `-fshort-enums` (some embedded ABIs) size follows the value range — adding
  a large value can change the enum's size. On mainstream Linux psABIs,
  adding constants keeps size; renumbering existing constants is BREAKING
  (old values are compiled into consumers).
- Width-changing typedefs in crossing types (`int` → `long`, `time_t` 32→64)
  are BREAKING: layout and register assignment both change. Note the feature
  -macro variants: `_FILE_OFFSET_BITS=64` and `_TIME_BITS=64` make *the same
  header* produce two different ABIs — see `compiler-linker-loader.md`.

## Calling conventions (per-arch essentials for judgment)

The psABI fixes how parameters and returns travel; a change to a *type* can
silently change its *passing class*:

- **x86-64 SysV**: first 6 integer/pointer args in `rdi,rsi,rdx,rcx,r8,r9`;
  floats in `xmm0-7`; small structs (≤16 bytes) may be split across
  registers by field class; larger structs go on the stack / via hidden
  pointer (return >16 bytes → caller-provided buffer in `rdi`). Judgment
  consequence: growing a struct parameter past 16 bytes, or changing a field
  from int to float, changes how it is passed — BREAKING even if offsets of
  other fields are unchanged.
- **AArch64 (AAPCS64)**: args in `x0-x7` / `v0-v7`; composites ≤16 bytes in
  registers; **HFA** (homogeneous float aggregates ≤4 members) in vector
  registers — adding one `int` to an all-float struct demotes it from HFA,
  changing passing. Return >16 bytes via `x8` indirect pointer.
- **32-bit ABIs** (i386, ARM EABI): everything on the stack / tighter rules;
  `long`/pointers are 4 bytes — a type "the same size on 64-bit" may differ
  here. State explicitly which architectures a verdict was evaluated for.

Variadic functions use distinct conventions on several ABIs (e.g. AArch64
Darwin differs; SysV requires `al` count for vector args on x86-64) —
changing fixed ↔ variadic is BREAKING.

## Other C-level ABI facts worth checking

- `long double`: 80-bit x87 on x86-64 Linux, 128-bit on AArch64. Crossing
  `long double` makes a verdict arch-specific by construction.
- `char` signedness differs (signed on x86, unsigned on ARM/AArch64) —
  semantic, not layout; flag when comparison/hashing behavior crosses the
  boundary.
- Attributes that alter ABI locally: `__attribute__((packed))`,
  `aligned(N)`, `regparm`, `ms_abi`, `vectorcall`. Any addition/removal on a
  crossing type/function is an ABI change by definition.
- Function pointers in public structs (callback tables / "ops" structs):
  the struct is a vtable in disguise — same rules as C++ vtables: append-only
  at best, and only if the library null-checks new slots and consumers
  zero-initialize (`calloc`/`= {0}`); otherwise BREAKING.

## Verification set for a C ABI judgment

```bash
# Type-aware diff (the real check — needs -g builds):
abidiff old/libfoo.so new/libfoo.so

# Struct-by-struct ground truth:
pahole -C the_struct old/libfoo.so > /tmp/o && pahole -C the_struct new/libfoo.so > /tmp/n
diff -u /tmp/o /tmp/n         # any offset/size difference in a crossing type = BREAKING

# Symbol-set sanity (catches removals/retypes at the name level only):
nm -D --defined-only old/libfoo.so | sort > /tmp/os
nm -D --defined-only new/libfoo.so | sort > /tmp/ns
diff -u /tmp/os /tmp/ns
```

State in the verdict which architectures were verified; a judgment made on
x86-64 does not automatically transfer to AArch64 when HFAs, `long double`,
or bitfields are involved.

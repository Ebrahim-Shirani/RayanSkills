# API vs ABI — the core distinction and how to classify a change

## Definitions

- **API** (Application Programming Interface): the **source-level** contract —
  names, types, and semantics a consumer compiles against. Breaking it forces
  consumers to **edit or fail to compile** their source.
- **ABI** (Application Binary Interface): the **binary-level** contract —
  everything an already-compiled consumer depends on at link and run time.
  Breaking it forces consumers to **rebuild** (or crash/misbehave if they
  don't).

The two are independent axes. All four combinations occur:

| | ABI kept | ABI broken |
|---|---|---|
| **API kept** | routine internal change | reorder struct fields; change type sizes; compiler/ABI flag change; add virtual method (C++) |
| **API broken** | rename via versioned alias while keeping old symbol; `#define`-level rename | remove a function; change a signature |

The right column is what this skill exists to catch: **source that still
compiles fine can still break every existing binary.**

## What the ABI of an ELF object consists of

A change is ABI-relevant iff it alters at least one of these layers:

1. **Exported symbol set** — names (mangled, for C++) in the dynamic symbol
   table (`.dynsym`), with binding (global/weak) and visibility.
2. **Symbol versions** — the version node attached to each symbol
   (`foo@@V1.2`), if the library uses versioning.
3. **Types and layout** — size, alignment, field offsets, enum values, and
   vtable layout of every type that crosses the boundary (parameters, return
   values, public structs, inline-accessed members).
4. **Calling convention** — how arguments/returns are passed; fixed by the
   psABI per architecture but changeable by attributes and some flags.
5. **Runtime linkage metadata** — SONAME, NEEDED, symbol resolution behavior
   (weak vs strong, interposition).
6. **Semantics** — behavior existing binaries rely on (errno contracts,
   ownership rules, thread-safety). Invisible to tools; judge by reasoning.

## The three verdict classes

- **COMPATIBLE** — no observable difference for any existing consumer binary.
  Old binaries run unchanged, byte-for-byte identical interface.
- **COMPATIBLE_WITH_ADDITIONS** (backward-compatible) — everything old
  consumers use is unchanged; new symbols/types were added. Old binaries run
  unchanged; binaries built against the *new* version won't run against the
  *old* one (forward-incompatible). This is the normal, healthy way libraries
  grow. No SONAME bump.
- **BREAKING** — at least one thing an existing consumer may depend on
  changed: removed/retyped symbol, changed layout of a crossing type, changed
  calling convention, changed semantics. Requires explicit approval and a
  SONAME-bump decision.

## Classification table — C

| Change | Verdict | Mechanism |
|---|---|---|
| Add a new exported function | ADDITIONS | new `.dynsym` entry; nothing existing moves |
| Remove / rename an exported function | BREAKING | consumer's `undefined symbol` at load |
| Change a function's parameter/return types | BREAKING | same symbol name, different contract — no load error, corruption at call time |
| Append a field to a struct that **only the library allocates** and consumers use via pointer | usually ADDITIONS | size change invisible to consumers who never allocate/embed/array it — verify no inline accessor leaked the size (`sizeof` in a macro/header) |
| Add/insert/reorder/remove fields in a struct consumers allocate, embed, or index | BREAKING | field offsets / size baked into consumer code at their compile time |
| Change a typedef'd integer's width (`int` → `long`) in a crossing type | BREAKING | layout + calling convention change |
| Add a new enum constant at the end | usually ADDITIONS | values stable; BREAKING if it changes the enum's size (`-fshort-enums` builds) or consumers exhaustively validate values |
| Reorder / renumber existing enum constants | BREAKING | old binaries carry old numeric values |
| Change a `#define` constant's value | BREAKING (semantic) | old value is compiled into consumers; both values now live simultaneously |
| Change behavior/ownership/errno contract, same signature | BREAKING (semantic) | tools cannot see it; must be judged from the change description |
| Make a public function `static` / hide it | BREAKING | symbol disappears from `.dynsym` |
| Change variadic ↔ fixed prototype | BREAKING | different calling convention on several ABIs |

## Classification table — C++ (details in `cpp-abi.md`)

| Change | Verdict | Mechanism |
|---|---|---|
| Add a non-virtual member function | ADDITIONS | new mangled symbol; object layout unchanged |
| Add a **virtual** function (any position) | BREAKING | vtable layout/size changes |
| Reorder virtual functions | BREAKING | consumers call through fixed vtable slots |
| Add a data member (even private) | BREAKING | object size / member offsets change |
| Change a default argument | API-visible only; ABI COMPATIBLE | defaults are substituted in the *caller* at its compile time — old callers keep the old default (flag the semantic skew) |
| Change inline function body | BREAKING (semantic) | old copies are inlined inside consumers; two behaviors coexist |
| Add an overload | ADDITIONS, usually | new mangled name; BREAKING for consumers taking the function's address through an ambiguous cast — rare, note it |
| Change template implementation | see `cpp-abi.md` | instantiations live in consumers |

## Classification procedure

For each individual change (never judge a batch as one unit):

1. **Locate the layer** (symbols / versions / layout / convention / linkage /
   semantics) the change touches.
2. **Look it up** in the tables above; if absent, reason from the mechanism
   column — the question is always *"what did an existing consumer binary
   capture at its compile/link time, and did that move?"*
3. **Confirm with tooling** once binaries exist: `abidiff old new` for
   symbols+types (needs DWARF for types), `pahole -C <struct>` for layout,
   `readelf --dyn-syms` for the symbol set. See
   `regression-and-diffing.md`.
4. **State both impacts**: "API: source still compiles / doesn't. ABI:
   verdict + mechanism."
5. The **batch verdict is the worst individual verdict**: one BREAKING item
   makes the release breaking regardless of how many additions surround it.

## Traps worth naming in any judgment

- "We only added things" — adding a virtual function or a struct field *is*
  an addition, and it breaks. Additive ≠ compatible; check the layer.
- "It still compiles" proves API compatibility only. ABI verdicts require
  binary-level evidence.
- "Tests pass" — tests were rebuilt; the population at risk is binaries that
  were **not** rebuilt. Test old binaries against the new library
  (`LD_LIBRARY_PATH` swap) or diff the ABI directly.
- Semantic breaks (layer 6) never show up in any tool output. Say so
  explicitly when the change description implies one.

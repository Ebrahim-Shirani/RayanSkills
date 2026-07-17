# ELF and dynamic linking — the ABI surface of a binary

What an ELF shared object actually promises to consumers, where each promise
is stored, and the command that reveals it. All commands are read-only.

## File-level identity

```bash
file libfoo.so.1.2.3          # ELF class, arch, linkage, stripped or not
readelf -h libfoo.so.1.2.3    # ELF header: class (32/64), machine, type (DYN/EXEC)
```

Architecture, ELF class, and endianness must match between consumer and
library — a mismatch is not an "ABI break", it is a different ABI entirely.

## The dynamic section — linkage metadata

```bash
readelf -d libfoo.so
```

ABI-relevant entries:

- **`SONAME`** — the name consumers record. Consumers store it as `NEEDED`;
  the loader searches for this string. A changed SONAME is a *declared* ABI
  break (that is its purpose); a missing SONAME makes consumers depend on the
  file path used at link time.
- **`NEEDED`** — this binary's own dependencies, by SONAME. A new NEEDED
  entry changes the runtime closure consumers must be able to satisfy.
- **`RPATH` / `RUNPATH`** — search-path hints; they select *which* file
  provides an ABI at run time (see `compiler-linker-loader.md`).
- **`FLAGS`/`FLAGS_1`** entries such as `BIND_NOW`, `NODELETE` — affect
  resolution timing, occasionally masking or exposing missing-symbol breaks
  (lazy binding hides an unused missing symbol until first call).

## Dynamic symbols — the primary contract

```bash
readelf --dyn-syms -W libfoo.so        # full dynamic symbol table
nm -D --defined-only libfoo.so         # exported (defined) symbols only
nm -D --undefined-only libfoo.so       # what it imports
```

Only `.dynsym` matters for the ABI. The static symbol table (`.symtab`,
plain `nm`, removed by `strip`) is debug-only — never judge ABI from it.

Per symbol, the contract includes:

- **Name** — for C++, the mangled name encodes the signature; demangle with
  `nm -D -C` or `c++filt` when reasoning, but compare *mangled* names.
- **Binding**: `GLOBAL` vs `WEAK`. A weak definition can be overridden by a
  global one elsewhere in the process; demoting global → weak changes
  resolution in multi-definition scenarios (interposition, plugins) — treat
  as a break unless proven unobserved. `UND` entries are imports.
- **Visibility** (`DEFAULT`, `HIDDEN`, `PROTECTED`): `HIDDEN` symbols never
  reach `.dynsym` — hiding a previously-default symbol removes it from the
  ABI (breaking). `PROTECTED` prevents interposition of the definition inside
  its own object — a resolution-semantics change if toggled.
- **Type and size**: `FUNC` vs `OBJECT`. For `OBJECT` symbols (exported
  variables) the **size is part of the ABI** — consumers may copy-relocate
  the object into their own BSS at its old size; growing it breaks them.
  This is why exported data is riskier than exported functions.
- **`IFUNC`** (`STT_GNU_IFUNC`): the implementation is chosen at load time;
  the *selected* behavior can differ per CPU — relevant when a "same binary"
  behaves differently across machines.

## Relocations, GOT and PLT — how binding happens

```bash
readelf -r libfoo.so                   # relocations
objdump -d -j .plt libfoo.so           # PLT stubs
```

- Function calls across objects go through the **PLT**, data references
  through the **GOT**; both are patched by the loader using `.dynsym`
  lookups. Consequence: *function* ABI is bound by name at load/first-call
  time — but *data* symbols may use **copy relocations** (`R_*_COPY`) in
  executables, freezing the object's size and initial layout into the
  consumer at its link time.
- **Lazy binding** (default without `BIND_NOW`): a removed symbol that is
  never called never faults. "It runs" therefore does not prove
  compatibility — enforce full resolution when testing:

```bash
LD_BIND_NOW=1 ldd -r ./consumer        # forces resolution of all symbols
ldd -d ./consumer                      # data relocations check
```

- Interposition: `LD_PRELOAD` and symbol search order mean a `DEFAULT`
  -visibility symbol can be overridden process-wide. Judgments about
  "nobody uses this symbol" must account for interposers and `dlsym` users,
  which no static scan can enumerate — say so when it matters.

## Weak symbols

`__attribute__((weak))` definitions and references:

- A **weak reference** may legitimately resolve to nothing (address NULL) —
  consumers feature-test with it. Removing a symbol that consumers weakly
  reference degrades gracefully; removing one they strongly reference breaks
  at load. Check the *consumer's* table: `nm -D --undefined-only consumer`
  marks weak references with `w`.

## Symbol versions

```bash
readelf -V libfoo.so                   # .gnu.version_d (definitions) / _r (needs)
```

Covered in depth in `symbol-versioning.md`. In one line: a versioned symbol's
contract is (name, version) — both must keep resolving.

## TLS

Thread-local exported variables (`STT_TLS`) add a TLS-model dimension:
initial-exec-model consumers reserve static TLS space at load; a library that
grows its TLS block or changes model can fail to `dlopen`
("cannot allocate memory in static TLS block"). Flag any change to exported
`__thread` data as ABI-relevant.

## Minimal inspection sequence (what `scripts/inspect-abi.sh` automates)

```bash
file "$BIN"
readelf -h "$BIN" | grep -E 'Class|Machine|Type'
readelf -d "$BIN" | grep -E 'SONAME|NEEDED|RPATH|RUNPATH|FLAGS'
nm -D --defined-only "$BIN"            # the exported set
readelf -V "$BIN"                      # version definitions/needs
readelf --dyn-syms -W "$BIN" | awk '$5=="WEAK" || $6!="DEFAULT"'  # oddities
```

Pass criterion: every exported symbol is intentional, SONAME is present and
correct, and versions (if used) are attached to every symbol.

# C++ ABI — Itanium rules for judging binary compatibility

Linux C++ uses the **Itanium C++ ABI** (all of GCC/Clang on Linux, every
architecture — "Itanium" is historical naming). It layers on the C psABI:
everything in `c-abi.md` still applies; this file adds what C++ changes.

## Name mangling — the signature is in the symbol

Every function's mangled name encodes namespace, class, name, cv-quals, and
**parameter types** (not the return type, except for templates/conversion
operators). Consequences:

- Changing any parameter type creates a **different symbol** → old consumers
  fail at load with `undefined symbol: _ZN...` — a *loud* break (better than
  C, where the name survives a signature change and corrupts silently).
- Changing only the **return type** of a normal function keeps the mangled
  name → *silent* break. Treat as BREAKING-silent; call it out.
- `extern "C"` functions opt out of mangling and behave per `c-abi.md`
  (silent breaks on any signature change).

Demangle for reasoning (`c++filt`, `nm -DC`), but always **compare mangled
names** — demangled text is lossy.

## Object layout

- Data members: laid out per the C rules within each access region; adding a
  data member — **including a private one** — changes object size and is
  BREAKING whenever consumers allocate the object (stack, `new` in their
  code, embedding, arrays, `sizeof`). The pImpl pattern exists precisely to
  make this compatible; a class without pImpl has its whole layout in the
  ABI.
- Adding a **first** virtual function to a class that had none inserts a
  vptr at offset 0 → shifts every member → BREAKING.
- Base-class changes (add/remove/reorder bases, single→multiple, adding a
  virtual base) reorganize the object and its vtables → BREAKING.
- Empty-base optimization and `[[no_unique_address]]` mean "adding an empty
  member/base is free" is *sometimes* true — verify with `pahole`, never
  assume.

## Vtables — the sharpest edge

Virtual calls compile to an **indexed load from the vtable**: slot numbers
are frozen into consumer binaries.

| Change | Verdict | Mechanism |
|---|---|---|
| Add a virtual function — even at the end of the class | BREAKING | shifts/extends vtable; derived classes in *consumers* laid out their own vtables assuming the old count; RTTI/thunk entries move. "Appending is safe" is a leaf-class-only, no-external-derivation special case — do not certify it without proving nobody derives |
| Reorder virtual functions | BREAKING | slot indices baked into every caller |
| Remove a virtual function | BREAKING | slots shift + mangled symbol disappears |
| Override an inherited virtual in a new release | usually ADDITIONS | slot already existed in the base; new code just fills it — verify vtable layout is unchanged (`abidiff` reports vtable changes) |
| Change a virtual's signature | BREAKING | new mangled name *and* the old slot's contract changes |

`abidiff` explicitly reports vtable layout changes when DWARF is present —
this is a primary reason to insist on `-g` builds for C++ judgment.

## Inline functions and templates — code that lives in the consumer

- An **inline function's body** (incl. anything in headers: inline methods,
  constexpr functions) is compiled **into each consumer**. Changing the body
  is not a link break — old copies keep running old code next to the
  library's new code. Verdict: BREAKING (semantic) whenever the old and new
  bodies must agree (locking protocol, data-format access, invariants).
- **Templates**: instantiations live in the consumers that instantiated
  them. Changing a template's implementation or a class template's layout →
  consumers hold stale instantiations → same semantic-skew verdict. Explicit
  instantiation definitions exported from the library (`extern template`)
  add normal symbol-level rules on top.
- Inline/template code also **touches members directly** — an "opaque" data
  change is not opaque if a header-inline accessor read the field.

## RTTI, exceptions, and operator new/delete

- `typeid`/`dynamic_cast` compare `type_info`; with `-fvisibility=hidden` or
  `dlopen(RTLD_LOCAL)` duplicate `type_info` objects can break
  `dynamic_cast` across boundaries — a *linkage* configuration issue, flag
  when visibility flags changed between versions.
- Exception types thrown across the boundary are crossing types — their
  layout and `type_info` follow all rules above.
- A class-specific `operator new`/`delete` added later changes who
  allocates/frees — semantic ABI, flag it.

## The libstdc++ dual ABI (`_GLIBCXX_USE_CXX11_ABI`)

GCC 5 introduced new `std::string`/`std::list` implementations, distinguished
by the inline namespace `std::__cxx11::` **in the mangled names**. Two builds
of the *same source* with different `_GLIBCXX_USE_CXX11_ABI` values export
different symbols and are link-incompatible wherever `std::string`/`list`
cross the interface.

Detection:

```bash
nm -DC libfoo.so | grep -c '__cxx11'   # >0 → new ABI in the interface
```

Judgment: a flip of this macro between two releases is BREAKING for C++
consumers (loud: undefined `_ZN...__cxx11...` symbols). Mixing libstdc++ and
libc++ across a C++ interface is likewise incompatible — the standard-library
types are different types. C interfaces (`extern "C"`, no std types) are
immune; that immunity is a property to *verify* (scan the public headers for
std types), not assume.

## Compiler-version effects specific to C++

Rare but real: historical mangling-scheme corrections and
`--fabi-version`/`-fabi-compat-version` differences can change mangled names
across compiler versions; GCC emits warnings under `-Wabi` for known cases.
When two builds used different major compiler versions, add a mangled-name
set diff (`nm -D` old vs new) to the evidence even when "nothing changed" in
source.

## Verification set for a C++ judgment

```bash
abidiff --harmless old/libfoo.so new/libfoo.so   # full report incl. vtable and
                                                 # mangled-symbol changes (DWARF builds)
nm -D --defined-only old/libfoo.so | sort > /tmp/o
nm -D --defined-only new/libfoo.so | sort > /tmp/n
diff -u /tmp/o /tmp/n                            # mangled-name adds/removes
pahole -C 'ClassName' new/libfoo.so              # object layout incl. vptr
```

State explicitly in the verdict: which classes are externally derivable,
which functions are inline/header-visible, and whether std:: types cross the
interface — these three facts decide most C++ verdicts.

# Worked case 3 — adding a virtual function (C++): BREAKING despite "only adding"

The classic C++ trap: an *addition* that rewrites the object's dispatch
layout. Companion to case 1 — same "we only added something" claim, opposite
verdict.

## The change

`libshape` v1 exports a polymorphic base class; v2 adds one virtual method
at the end of the class ("appending is safe, right?"):

```cpp
// shape.h (v1)                     // shape.h (v2)
class Shape {                       class Shape {
public:                             public:
    virtual ~Shape();                   virtual ~Shape();
    virtual double area() const;        virtual double area() const;
    void describe() const;              virtual double perimeter() const; // NEW
};                                      void describe() const;
Shape *make_square(double side);    };
                                    Shape *make_square(double side);
```

```bash
g++ -g -fPIC -shared -Wl,-soname,libshape.so.1 shape1.cpp -o old/libshape.so
g++ -g -fPIC -shared -Wl,-soname,libshape.so.1 shape2.cpp -o new/libshape.so
```

## Judgment before tooling (Workflow 2)

Per `reference/cpp-abi.md`, vtable table row "add a virtual function":

- The Itanium vtable for `Shape` gains a slot. Consumers compiled against v1
  built their calls — and, worse, any **derived classes of their own** —
  against the old slot count and layout.
- A consumer that merely *calls* `area()` through a v1-slot index may
  survive an append; a consumer that **derives from Shape** laid out its own
  vtable without the new slot — v2 code calling `perimeter()` on such an
  object jumps through a slot that doesn't exist in that vtable.
- External derivation cannot be ruled out for an exported polymorphic class.
- Expected verdict: **BREAKING**.

Note the contrast with a harmless C++ addition: a new **non-virtual** member
function would just be a new mangled symbol — genuine ADDITIONS.

## Evidence

The symbol diff shows *only an addition* — misleading if read alone:

```bash
$ scripts/diff-abi.sh old/libshape.so new/libshape.so
...
removed symbols: none
ADDED symbols (compatible additions at the symbol level):
  + _ZNK5Shape9perimeterEv        # Shape::perimeter() const
```

`abidiff` with DWARF sees the vtable change and condemns it — exit **12**
(4|8, proven incompatible). Output from libabigail 2.4.0:

```
1 Added function:

  [A] 'method virtual double Shape::perimeter() const'    {_ZNK5Shape9perimeterEv}
    note that this adds a new entry to the vtable of class Shape

1 function with some indirect sub-type change:

  [C] 'method virtual double Shape::area() const' at shape1.cpp:8:1 has some indirect sub-type changes:
    implicit parameter 0 of type 'const Shape*' has sub-type changes:
      in pointed to type 'const Shape':
        in unqualified underlying type 'class Shape' at shape2.cpp:1:1:
          type size hasn't changed
          1 member function insertion:
            'method virtual double Shape::perimeter() const' at shape2.cpp:10:1, virtual at voffset 3/3
```

```bash
$ scripts/check-abi-verdict.sh old/libshape.so new/libshape.so
VERDICT: BREAKING — abidiff proves an incompatible change ...
```

This case is the strongest argument for insisting on `-g` builds: without
DWARF, no tool sees anything but the innocent-looking added symbol, and the
verdict machinery correctly refuses to say COMPATIBLE
(`INCONCLUSIVE` from `check-abi-verdict.sh`) — but only a type-aware run
produces the *proof*.

It is also the case where the secondary engine fails outright: ACC 2.3's
dump-based workflow reported this exact pair as "Binary compatibility: 100%"
(the new virtual listed merely as an added symbol) — a verified blind spot
(`reference/regression-and-diffing.md`). An ACC-clean C++ result must never
be accepted as the verdict on its own.

## Runtime failure mode (why it matters)

A v1-compiled consumer with its own `class Circle : public Shape` passes a
`Circle*` into v2 library code; v2 calls `perimeter()` → jump through a
vtable slot the consumer's `Circle` vtable never allocated → arbitrary
function or crash. No loader diagnostic at any point.

## Verdict delivered

**BREAKING.** Mechanism: vtable layout change of an exported polymorphic
class with possible external derivation. API impact: additive
(source-compatible). Required decisions: owner approval + SONAME bump
(`reference/migration.md`). Compatible alternative to propose first: add
`perimeter()` as a **non-virtual** function this release (dispatching
internally), or introduce a new derived interface class — both keep
`Shape`'s vtable frozen.

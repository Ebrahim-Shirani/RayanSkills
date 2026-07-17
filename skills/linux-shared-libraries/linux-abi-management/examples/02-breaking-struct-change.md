# Worked case 2 — inserting a struct field (C): BREAKING, silently

The dangerous class: **every symbol still resolves**, the program loads and
runs, and reads garbage. This is why symbol-level evidence alone can never
produce a COMPATIBLE verdict.

## The change

`libpoint` v1 ships a caller-visible struct; v2 inserts a field in the
middle ("just adding a z coordinate"):

```c
/* point.h (v1) */              /* point.h (v2) */
struct point {                  struct point {
    int x;                          int x;
    int y;                          int z;      /* INSERTED */
};                                  int y;
int point_sum(struct point *p); };
                                int point_sum(struct point *p);
```

```bash
gcc -g -fPIC -shared -Wl,-soname,libpoint.so.1 point1.c -o old/libpoint.so
gcc -g -fPIC -shared -Wl,-soname,libpoint.so.1 point2.c -o new/libpoint.so
```

## Judgment before tooling (Workflow 2)

- Layer touched: **layout of a crossing type**. `struct point` is declared
  in the public header and consumers allocate it themselves.
- `y` moves from offset 4 to offset 8; size goes 8 → 12. A consumer compiled
  against v1 stores `y` at offset 4; v2's `point_sum` reads offset 8.
- The symbol set is **unchanged** — no loader error will ever fire.
- Expected verdict: **BREAKING (silent)**.

## Evidence

Symbol diff shows nothing — and says so honestly:

```bash
$ scripts/diff-abi.sh old/libpoint.so new/libpoint.so
...
removed symbols: none
added symbols: none
```

The layout check is decisive (either tool):

```bash
$ pahole -C point old/libpoint.so       # output from pahole v1.25
struct point {
	int                        x;                    /*     0     4 */
	int                        y;                    /*     4     4 */

	/* size: 8, cachelines: 1, members: 2 */
};

$ pahole -C point new/libpoint.so
struct point {
	int                        x;                    /*     0     4 */
	int                        z;                    /*     4     4 */
	int                        y;                    /*     8     4 */   # y moved: 4 -> 8

	/* size: 12, cachelines: 1, members: 3 */
};
```

`abidiff` (DWARF builds) reports it precisely (output from libabigail
2.4.0). Note the exit code: **4, not 12** — libabigail reserves the
"proven incompatible" bit 8 for cases like removals and vtable changes; for
struct layout damage the proof is in the report text:

```
1 function with some indirect sub-type change:
  [C] 'function int point_sum(point*)' at point1.c:2:1 has some indirect sub-type changes:
    parameter 1 of type 'point*' has sub-type changes:
      in pointed to type 'struct point' at point2.c:1:1:
        type size changed from 64 to 96 (in bits)
        1 data member insertion:
          'int z', at offset 32 (in bits) at point2.c:1:1
        1 data member change:
          'int y' offset changed from 32 to 64 (in bits) (by +32 bits)
```

The verdict script reads that `offset changed` line and concludes on its own:

```bash
$ scripts/check-abi-verdict.sh old/libpoint.so new/libpoint.so
VERDICT: BREAKING — abidiff reports member offset change(s) in a type crossing the interface (exit 4); ...
```

Demonstrating the silent corruption with a v1-built consumer:

```bash
gcc -g consumer.c -L old -lpoint -o consumer   # consumer sets {x=1,y=2}, expects sum 3
LD_LIBRARY_PATH=old ./consumer   # sum = 3   (correct)
LD_LIBRARY_PATH=new ./consumer   # sum = 1 + <garbage at offset 8> — no error, wrong data
```

## Verdict delivered

**BREAKING.** Mechanism: field insertion shifts `y`'s offset in a
caller-allocated public struct. API impact: source-compatible (it still
compiles!) — which is exactly why this must be caught at the ABI level.

Required decisions (`reference/migration.md`): explicit owner approval, and
a SONAME bump (`libpoint.so.1` → `libpoint.so.2`) so unrebuilt consumers can
never load v2. Compatible alternative to propose first: **append** `z` at
the end *if and only if* consumers could be shown not to embed/array the
struct — here they allocate it, so appending changes `sizeof` and is still
breaking; the honest paths are a new struct + new function, or the bump.

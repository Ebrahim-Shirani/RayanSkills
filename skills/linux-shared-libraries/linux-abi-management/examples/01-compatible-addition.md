# Worked case 1 — adding a function (C): COMPATIBLE_WITH_ADDITIONS

The healthy way a library grows, and what the evidence for it looks like.

## The change

`libgreet` v1.0 exports one function; v1.1 adds a second one. Nothing
existing is touched.

```c
/* greet.h (v1.0) */                 /* greet.h (v1.1) */
int greet(const char *name);         int greet(const char *name);
                                     int greet_count(void);       /* NEW */
```

Reproduce the two builds (both with `-g` so the diff is type-aware):

```bash
printf 'int greet(const char*n){(void)n;return 0;}\n' > greet1.c
printf 'int greet(const char*n){(void)n;return 0;}\nint greet_count(void){return 1;}\n' > greet2.c
gcc -g -fPIC -shared -Wl,-soname,libgreet.so.1 greet1.c -o old/libgreet.so
gcc -g -fPIC -shared -Wl,-soname,libgreet.so.1 greet2.c -o new/libgreet.so
```

## Judgment before tooling (Workflow 2)

- Layer touched: **exported symbol set** only — one new `FUNC` symbol.
- No crossing type changed, no existing signature changed, SONAME kept.
- Expected verdict: COMPATIBLE_WITH_ADDITIONS. Old binaries never look up
  `greet_count`, so nothing they captured has moved. Consumers built against
  v1.1 won't run on v1.0 (forward incompatibility — normal, worth stating).

## Evidence (Workflow 3/4)

```bash
$ scripts/diff-abi.sh old/libgreet.so new/libgreet.so
...
removed symbols: none
ADDED symbols (compatible additions at the symbol level):
  + greet_count
```

With libabigail installed, `abidiff old/libgreet.so new/libgreet.so` exits
with code 4 (`ABI_CHANGE` — the addition) and its report shows only:

```
1 Added function:
  [A] 'function int greet_count()'
```

`abidiff --no-added-syms` exits 0 — nothing besides additions. Therefore:

```bash
$ scripts/check-abi-verdict.sh old/libgreet.so new/libgreet.so
VERDICT: COMPATIBLE_WITH_ADDITIONS — only added symbols (1); everything pre-existing is unchanged (abidiff, DWARF present)
```

Without libabigail the same run honestly degrades:

```
VERDICT: INCONCLUSIVE — no removals, 1 addition(s) at symbol level, but no
type-aware engine available (install libabigail/abidiff) — layout of
existing types unverified
```

That downgrade is correct behavior: a symbol diff alone cannot exclude a
simultaneous struct-layout change.

## Closing the loop with a real consumer

```bash
gcc -g consumer.c -L old -lgreet -o consumer     # built against v1.0
LD_LIBRARY_PATH=new LD_BIND_NOW=1 ldd -r ./consumer   # → no unresolved symbols
LD_LIBRARY_PATH=new ./consumer                        # runs correctly
```

## Verdict delivered

**COMPATIBLE_WITH_ADDITIONS.** No SONAME bump. API impact: additive (old
source still compiles). Noted caveat: binaries linked against v1.1 require
v1.1+ at run time. End of task — shipping/packaging the release is someone
else's workflow.

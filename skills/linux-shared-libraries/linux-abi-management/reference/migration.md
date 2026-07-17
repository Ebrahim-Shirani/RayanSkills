# Handling a required ABI break

Enter this file only after a diff/review has **proven** a break
(`regression-and-diffing.md`). The skill's standing rule applies: a breaking
change ships only with the owner's explicit approval, and the SONAME question
must be decided — it is a compatibility decision, not a versioning-scheme
exercise.

## Step 0 — try to not break

Before accepting the break, check the additive alternatives:

- **Add, don't change**: new function (`foo2`, `foo_ex`) beside the old one;
  old symbol keeps its exact behavior. Verdict becomes ADDITIONS.
- **Grow opaquely**: if the struct is library-allocated and consumers hold
  pointers, append fields (verify no `sizeof` leakage — `api-vs-abi.md`).
  Caller-allocated structs can sometimes migrate to a size-tagged form
  (`size` as first member, new fields honored only when the caller declared
  a big-enough size) — that is an *additive* API for new callers.
- **Keep the old entry point as a compatibility shim** implemented on top of
  the new one. (If the project already uses symbol versioning, an
  old-version node can host the shim — evaluating that existing mechanism is
  in scope; authoring a new versioning scheme is not: if the project has
  none, the practical alternatives are the ones above or the SONAME bump.)
- **Deprecate first, remove later**: mark deprecated
  (`__attribute__((deprecated))`), keep the ABI intact this release, remove
  in the next planned break. Batching removals reduces the number of breaks.

If one of these fits, the task exits this file — verdict changes to
compatible/additions and no migration is needed.

## Step 1 — the SONAME decision

When the break stands, the question is: **may an unrebuilt consumer ever
load the new binary?** The answer must be no, and the SONAME is the mechanism
that enforces it.

- **Bump required** (the default for any BREAKING verdict on a shared
  library): the new library must carry a different SONAME
  (`libfoo.so.1` → `libfoo.so.2`) so the loader never satisfies an old
  consumer's `NEEDED: libfoo.so.1` with the incompatible file. Old and new
  can then be **installed side by side**, which is what keeps existing
  binaries working through the transition.
- **Bump genuinely not needed** only when it is *proven* that no consumer
  outside the same always-rebuilt-together unit exists (private/internal
  library, bundled plugin). Record that proof in the report; "we think
  nobody links it" is not proof.
- Deciding the bump is in scope. *Implementing* it (build-system edits,
  version-script authoring, packaging the two streams) is out of scope —
  state the requirement precisely ("new SONAME must differ; old N stays
  installed for existing consumers") and stop.

## Step 2 — plan the transition (judgment-level checklist)

- Enumerate known consumers (distro reverse-deps, internal build graph,
  `scanelf -N libfoo.so.1 -R /usr/lib /usr/bin` or
  `for b in ...; do readelf -d $b | grep -q 'libfoo\.so\.1' && echo $b; done`)
  — and state the caveat that `dlopen`/`dlsym` users cannot be enumerated
  statically.
- Classify each consumer: rebuilt-with-you vs independent. Independent
  consumers define how long the old ABI must stay available.
- Sequence: (1) new SONAME ships alongside old; (2) consumers rebuild
  against new at their own pace; (3) old library retired only when nothing
  `NEEDED`s it (re-run the enumeration to prove it).
- Communicate the break: changelog entry naming every removed/changed
  symbol/type, with the replacement for each. The diff report
  (`templates/abi-report.md`) is the source material.

## Step 3 — verify the executed migration

After the new version exists (and, where applicable, both are installed):

```bash
# The bump is real:
readelf -d old/libfoo.so | grep SONAME     # libfoo.so.1
readelf -d new/libfoo.so | grep SONAME     # libfoo.so.2  (must differ)

# Old consumers still bind the old ABI:
ldd ./old-consumer | grep libfoo           # resolves to libfoo.so.1
LD_BIND_NOW=1 ldd -r ./old-consumer        # no unresolved symbols

# New consumers bind the new ABI:
ldd ./new-consumer | grep libfoo           # resolves to libfoo.so.2

# The two ABIs are what we claimed (repeatable evidence):
abidiff old/libfoo.so new/libfoo.so        # documents the break precisely
```

Pass = all four observations hold. Deliver the verdict + this evidence;
release orchestration, package migration, and CI wiring are out of scope.

## Kernel-side note

For kernel interfaces there is no SONAME lever: a broken module ABI means
"rebuild the module per kernel" (or stay within a distro kABI stablelist —
`kernel-abi.md`); a broken userspace-facing interface is a kernel-policy
violation to *report upstream/distro-ward*, not something to migrate around
locally. Judge, document, and hand the finding to the owner of the kernel
update.

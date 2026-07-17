# Kernel↔userspace interfaces — stability rules and judgment

Each kernel/user interface has its own stability contract. A verdict about
"is it safe to depend on X" or "did the kernel update break us" starts by
identifying which interface class X belongs to.

## Stability ladder (strongest first)

| Interface | Contract | Judgment guidance |
|---|---|---|
| **Syscalls** | Never broken deliberately ("we don't break userspace"). Numbers are per-arch; new syscalls are additions | A program using only syscalls of kernel N runs on every kernel ≥ N. Depending on a *new* syscall sets a minimum-kernel floor — report the floor (`man 2 <call>` lists the introducing version). Check runtime fallback behavior: does the code handle `ENOSYS`? |
| **ioctl** | Stable per driver once shipped; the *struct* passed is part of the contract | Judge like a C ABI struct (`c-abi.md`): the ioctl number encodes direction+size (`_IOW(type,nr,size)`) — a struct size change changes the ioctl number itself, making old/new loudly incompatible (that is by design). Same-number-different-layout is the silent break to hunt for |
| **procfs** (`/proc`) | De-facto stable for established files; format changes do happen in rarely-parsed files | Parsing text formats is the risk: judge a consumer's parser against documented fields only; extra-columns-appended is the compatible evolution pattern (e.g. `/proc/stat`) |
| **sysfs** (`/sys`) | Governed by `Documentation/ABI/` in the kernel tree: `stable/`, `testing/` (most attributes; de-facto reliable), `obsolete/`, `removed/` | Look the attribute up in `Documentation/ABI/`; verdict = its documented class. One-value-per-file rule means format breaks are rare; *presence* is the thing that changes |
| **netlink** | Message formats are uAPI; attributes (TLVs) are append-only by design | Well-behaved consumers ignore unknown attributes and feature-test; a consumer that hard-rejects unknown TLVs breaks on additions — that is a consumer bug, report it as such |
| **Tracepoints** | **Not stable.** Explicitly subject to change between releases | Any tool parsing tracepoint fields must be judged "expected to break across kernel versions"; recommend feature-testing via the tracefs `format` files at runtime, not baking offsets |
| **kprobes / raw kernel symbols** | No contract at all | Anything attached to arbitrary kernel functions is per-kernel-build; the only honest verdict is BREAKING-by-default across updates |

## eBPF ABI

Three distinct contracts — identify which one a program relies on:

1. **The BPF syscall + verifier + helpers**: uAPI, stable. Helper IDs and
   signatures (`bpf_helpers` in uAPI headers) don't change once shipped.
   New helpers → minimum-kernel floor, judge like new syscalls.
2. **kfuncs** (BPF-callable kernel functions): explicitly **unstable** —
   kernel-version-specific, like kernel symbols. Programs using kfuncs are
   per-kernel unless the kfunc is one of the few documented as stable.
3. **Kernel data structures read by BPF programs** (tracing/`kprobe`
   programs): unstable layouts; the supported mitigation is **CO-RE**
   (Compile Once – Run Everywhere) — relocations resolved against the
   running kernel's BTF at load. Judgment for a CO-RE program: it survives
   *renames of nothing / moves of fields* (BTF relocation handles offset
   changes) but breaks on *removed/renamed* fields — check with:

```bash
bpftool btf dump file /sys/kernel/btf/vmlinux format c | grep -A20 'struct task_struct {'
# does the field the program reads still exist under that name?
```

Also verify feature floors: `bpftool feature probe` lists supported program
types/helpers on a target kernel.

## Judgment procedure for "did kernel update K1→K2 break our userspace?"

1. Inventory what the application actually uses: syscalls (`strace -c`),
   ioctls (`strace -e ioctl`), files under `/proc` and `/sys` (`strace -e
   openat` filtered), netlink (`strace -e socket,sendmsg` on AF_NETLINK),
   BPF/tracepoints (program sources or `bpftool prog list`).
2. Classify each dependency by the ladder above; only the unstable classes
   (tracepoints, kprobes, kfuncs, non-CO-RE struct reads) need per-version
   re-verification.
3. For each risky item, run the concrete check on K2 (attribute exists?
   tracepoint format same? BTF field present? feature probe passes?).
4. Verdict per item + overall worst-case, with the checks as evidence. As
   always: the verdict ends the task; adding the checks to CI is out of
   scope.

## Common misjudgments to avoid

- "It's in /sys so it's stable" — only `Documentation/ABI/stable` is
  promised; `testing` is likely-but-not-guaranteed. Cite the file's class.
- "The kernel never breaks userspace" — true for syscalls; **not** a promise
  about tracepoints, kfuncs, module ABI, or undocumented /proc parsing.
- Glibc wrappers vs raw syscalls: a "syscall works" verdict says nothing
  about the *libc* wrapper's availability on old glibc — that floor is
  judged separately (`symbol-versioning.md`, glibc section).

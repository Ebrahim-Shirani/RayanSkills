# Kernel ABI (kABI) — judging module compatibility at the interface level

Scope note: this file judges **whether a module and a kernel are
binary-compatible** and how to verify it. Kernel development, patching, and
build-system work are out of scope.

## The contract a kernel module depends on

An out-of-tree (or separately shipped) `.ko` depends on:

1. **Exported symbols** — functions/data the kernel exposes via
   `EXPORT_SYMBOL` / `EXPORT_SYMBOL_GPL` (GPL-only symbols additionally
   require a GPL-compatible module license).
2. **Symbol CRCs** (when `CONFIG_MODVERSIONS=y`) — a checksum of each
   exported symbol's type signature, recorded at kernel build time in
   `Module.symvers` (`CRC  symbol  module  export-type`) and embedded in
   modules at their build time.
3. **vermagic** — a string (kernel release + key config: SMP, preempt,
   module-unload, arch) that must match unless CRCs vouch for compatibility.
4. **Structure layouts** shared with the kernel (ops structs, everything
   reachable from the interfaces it uses) — *not* covered by CRCs of symbols
   the module doesn't import; this is why distro kABI guarantees exist.

The upstream kernel explicitly does **not** promise a stable in-kernel ABI
(`Documentation/process/stable-api-nonsense.rst`). Stability guarantees are a
**distro** product feature (RHEL kABI whitelists/stablelists, SUSE
kABI) — a judgment must say *which* guarantee it is relying on, if any.

## Judgment procedure: "will this module load on that kernel?"

```bash
# 1. What the module was built for and what it imports:
modinfo module.ko | grep -E 'vermagic|depends|license'
modprobe --dump-modversions module.ko    # (symbol, CRC) pairs the module expects

# 2. What the target kernel provides:
#    Module.symvers from the target kernel build, or /proc/kallsyms + symtypes.
#    Compare each imported symbol:
awk '{print $1, $2}' /path/to/target/Module.symvers | sort > /tmp/kernel.crc
modprobe --dump-modversions module.ko | awk '{print $1, $2}' | sort > /tmp/module.crc
join -j 2 /tmp/module.crc /tmp/kernel.crc | awk '$2 != $3 {print "CRC MISMATCH:", $1}'
comm -23 <(awk '{print $2}' /tmp/module.crc) <(awk '{print $2}' /tmp/kernel.crc) \
  | sed 's/^/MISSING SYMBOL: /'
```

Verdict rules:

| Evidence | Verdict |
|---|---|
| Every imported symbol present, every CRC equal | COMPATIBLE (symbol level — see the layout caveat below) |
| Any imported symbol missing from the target | BREAKING — module fails: `Unknown symbol in module` |
| Any CRC differs | BREAKING — `disagrees about version of symbol` at load |
| MODVERSIONS off and vermagic differs | BREAKING — refused at load (`version magic ... should be ...`); forcing the load is not a compatibility fix and is not recommended |
| Symbols/CRCs match but a shared struct the module uses changed layout (CRC only covers the symbols' own signatures reached by the checker) | BREAKING (silent) — the dangerous case; requires diffing the struct, see below |

Layout caveat: genksyms CRCs hash the type graph reachable from each
exported symbol's signature, which catches most struct changes — but
`void *` laundering, unions, and padding-only changes can slip through.
When the kernel update is more than a trivial patch, corroborate with a
type-level diff.

## Type-level diffing with BTF

Modern kernels (`CONFIG_DEBUG_INFO_BTF=y`) embed type info at
`/sys/kernel/btf/vmlinux`:

```bash
bpftool btf dump file /sys/kernel/btf/vmlinux format c > /tmp/kernel-types.h
# For two kernels, dump both and diff the structs the module touches:
diff <(grep -A30 '^struct net_device ' old-types.h) \
     <(grep -A30 '^struct net_device ' new-types.h)
```

`pahole` reads BTF too (`pahole -C tcp_sock /sys/kernel/btf/vmlinux`).
Offset or size differences in any struct the module dereferences = BREAKING
regardless of CRC agreement.

## Distro kABI stablelists

Enterprise distros freeze a subset of exported symbols per major release: a
module using **only** stablelisted symbols is supported across that distro's
minor updates. Judgment steps: obtain the distro's stablelist
(e.g. RHEL's `symvers` + kabi stablelist package), check the module's
imports are a subset, then still run the CRC comparison above against the
specific target kernel. Using any non-stablelisted symbol makes the module
per-kernel-build, and the verdict must say so.

## Userspace-facing kernel ABI

The kernel's promise to **userspace** ("don't break userspace") is a
different, much stronger contract — syscalls, ioctl, sysfs, etc. are covered
separately in `syscall-and-interfaces.md`. Do not mix the two in one verdict:
a kernel update can be perfectly safe for applications and still break every
out-of-tree module.

## What to hand over

The verdict plus: the list of imported symbols checked, the source of the
target kernel's symvers/BTF, whether a distro kABI guarantee applies, and the
exact commands above so the check is repeatable on the real target. Stop
there — wiring the check into build or update automation is out of scope.

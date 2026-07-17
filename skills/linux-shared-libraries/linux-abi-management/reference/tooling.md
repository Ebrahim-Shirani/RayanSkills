# Tooling index — what each tool reveals about ABI, and when to reach for it

An index, not a manual. One entry per tool: the ABI question it answers.
Detailed usage lives in the workflow-specific reference files.

## Diff engines

| Tool | Reveals | Reach for it when |
|---|---|---|
| `abidiff` (libabigail) | Type-aware ABI delta between two binaries: removed/added/changed symbols, struct offsets, vtables; exit bitmask encodes the verdict | Any two-version comparison — the primary engine (`regression-and-diffing.md`) |
| `abidw` (libabigail) | A binary's whole ABI serialized to XML | Storing a baseline to diff future builds against without keeping old binaries |
| `abi-compliance-checker` | Independent binary+source compatibility report (HTML) from two dumps | Second opinion on a breaking verdict; shareable report artifact |
| `abi-dumper` | The DWARF dump ACC consumes | Only as ACC's front end; needs `-g` builds |

## ELF ground truth (binutils & friends)

| Tool | Reveals | Reach for it when |
|---|---|---|
| `readelf -d` | SONAME, NEEDED, RPATH/RUNPATH, BIND_NOW | First look at any binary; SONAME/dependency questions |
| `readelf --dyn-syms -W` | The dynamic symbol table: binding, visibility, type, size per symbol | Exact exported-set questions; visibility/weak audits |
| `readelf -V` | Symbol-version definitions (`version_d`) and requirements (`version_r`) | Anything involving `foo@VER` or glibc version floors |
| `readelf -h` / `-l` | Arch/class/type; program headers incl. the interpreter path | Arch mismatch suspicion; glibc-vs-musl identification |
| `nm -D` | Quick exported/imported symbol lists (`--with-symbol-versions`, `-C` to demangle) | Fast symbol diffs between versions; scripting |
| `objdump -d`, `-T`, `-p` | Disassembly; dynamic symbols; private headers — overlaps readelf | Inspecting PLT stubs or when confirming what a call site actually does |
| `ldd` / `ldd -r` / `LD_BIND_NOW=1 ldd -r` | Which files satisfy NEEDED; unresolved symbols/data relocs | Proving an existing consumer resolves against a new library |
| `pahole` | Struct layout — offsets, holes, sizes — from DWARF or BTF | Layout verdicts on specific crossing types; kernel struct diffs via BTF |
| `c++filt` | Demangles Itanium names | Reading C++ symbol diffs |
| `file` | ELF class/arch/linkage/stripped at a glance | Triage of unknown binaries |

## Modifiers (use to *test* hypotheses, not to "fix" ABI)

| Tool | Reveals / does | Reach for it when |
|---|---|---|
| `patchelf` | Reads & rewrites SONAME, NEEDED, RPATH | Confirming a hypothesis in a sandbox (e.g. "would it load if the SONAME matched?"); never a compatibility fix for production judgment |
| `objcopy` | Extracts/strips sections, weakens symbols | Producing stripped/split-debug variants to test how the diff degrades |

## Kernel side

| Tool | Reveals | Reach for it when |
|---|---|---|
| `modinfo` | A module's vermagic, license, dependencies | First look at any `.ko` compatibility question |
| `modprobe --dump-modversions` | The (symbol, CRC) pairs a module was built against | CRC comparison against a target kernel's `Module.symvers` |
| `depmod` | Recomputes module dependency/symbol maps (`modules.dep`) | Verifying a module's deps resolve on a target kernel tree |
| `bpftool` | BTF dumps (`btf dump`), loaded programs, `feature probe` | Kernel struct layout diffs; eBPF feature floors; CO-RE field checks |

## Runtime observation (when static evidence is not enough)

| Tool | Reveals | Reach for it when |
|---|---|---|
| `gdb` | Actual struct layouts (`ptype /o`), vtable contents, where a corrupted call landed | Post-mortem of a suspected silent ABI break; layout inspection without pahole |
| `strace` | Syscalls/ioctls a process really uses | Inventorying kernel-interface dependencies (`syscall-and-interfaces.md`) |
| `ltrace` | Library calls a process makes | Inventorying which library symbols a consumer exercises at run time |
| `perf` | Where time/crashes concentrate, incl. JIT/PLT anomalies | Rarely for ABI; useful when a "compatible" update changed performance-relevant behavior |
| `LD_DEBUG=libs,bindings <prog>` | The loader's actual search and symbol-resolution decisions | "Which library/symbol actually got used?" disputes (`compiler-linker-loader.md`) |

## Selection rule

Start with the cheapest tool that can decide the question: `readelf`/`nm`
for symbol-level, `pahole` for one struct, `abidiff` for whole-binary
verdicts, ACC only to corroborate, runtime tools only when semantics or
loader behavior are in doubt. Every verdict cites which of these produced
its evidence.

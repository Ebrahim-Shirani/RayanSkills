#!/usr/bin/env bash
# inspect-abi.sh — dump the ABI surface of one ELF binary.
#
# Usage: inspect-abi.sh <binary>
#
# Prints: file identity, dynamic-section linkage metadata (SONAME/NEEDED/
# RPATH/RUNPATH), exported dynamic symbols (with versions when binutils
# supports it), imports, symbol-version nodes, and noteworthy oddities
# (weak bindings, non-default visibility, TLS, IFUNC, exported OBJECTs).
#
# Read-only. Exit codes: 0 ok, 2 usage error, 3 not ELF / missing tools.
set -euo pipefail

die() { echo "inspect-abi: error: $*" >&2; exit 3; }

[ $# -eq 1 ] || { echo "usage: $0 <binary>" >&2; exit 2; }
BIN=$1
[ -r "$BIN" ] || die "cannot read '$BIN'"

for t in readelf nm file; do
    command -v "$t" >/dev/null || die "required tool '$t' not found (install binutils/file)"
done

readelf -h "$BIN" >/dev/null 2>&1 || die "'$BIN' is not an ELF file"

section() { printf '\n== %s ==\n' "$1"; }

section "File identity"
file "$BIN"
readelf -h "$BIN" | grep -E 'Class|Machine|Type' | sed 's/^ *//'
readelf -l "$BIN" 2>/dev/null | grep -i 'interpreter' | sed 's/^ *//' || true

section "Dynamic section (linkage metadata)"
if readelf -d "$BIN" 2>/dev/null | grep -q '('; then
    readelf -d "$BIN" | grep -E '\((SONAME|NEEDED|RPATH|RUNPATH|FLAGS|FLAGS_1)\)' \
        | sed 's/^ *//' || true
    readelf -d "$BIN" | grep -q '(SONAME)' \
        || echo "NOTE: no SONAME — consumers will record the link-time path/filename"
else
    echo "no dynamic section (statically linked or relocatable object)"
fi

section "Exported dynamic symbols (the ABI symbol set)"
# --with-symbol-versions appends @VER; older binutils lack the flag.
if nm -D --defined-only --with-symbol-versions "$BIN" >/dev/null 2>&1; then
    NM_EXPORT=(nm -D --defined-only --with-symbol-versions)
else
    NM_EXPORT=(nm -D --defined-only)
fi
if "${NM_EXPORT[@]}" "$BIN" 2>/dev/null | grep -q .; then
    "${NM_EXPORT[@]}" "$BIN"
    printf 'total exported: %d\n' "$("${NM_EXPORT[@]}" "$BIN" | wc -l)"
else
    echo "none (nothing exported dynamically)"
fi

section "Imports (undefined dynamic symbols)"
COUNT_UND=$(nm -D --undefined-only "$BIN" 2>/dev/null | wc -l)
echo "count: $COUNT_UND  (list with: nm -D --undefined-only '$BIN')"

section "Symbol version nodes"
if readelf -V "$BIN" 2>/dev/null | grep -q 'Version'; then
    readelf -V "$BIN" | sed -n '/\.gnu\.version_d/,/^$/p' | grep -E 'Name:|Rev:' \
        | sed 's/^ *//' || echo "(no version definitions — library defines no nodes)"
    echo "-- required from dependencies (version_r): --"
    readelf -V "$BIN" | sed -n '/\.gnu\.version_r/,/^$/p' | grep -E 'File:|Name:' \
        | sed 's/^ *//' || true
else
    echo "no symbol versioning in use"
fi

section "Oddities worth judging (weak / hidden / protected / TLS / IFUNC / data)"
# Columns of `readelf --dyn-syms -W`: Num Value Size Type Bind Vis Ndx Name
readelf --dyn-syms -W "$BIN" 2>/dev/null | awk '
    NR>3 && $8 != "" && $7 != "UND" {
        if ($5=="WEAK")               print "WEAK binding      : " $8
        if ($6=="HIDDEN")             print "HIDDEN visibility : " $8
        if ($6=="PROTECTED")          print "PROTECTED vis     : " $8
        if ($4=="TLS")                print "TLS object        : " $8 "  (size " $3 ")"
        if ($4=="IFUNC")              print "GNU IFUNC         : " $8
        if ($4=="OBJECT")             print "exported DATA     : " $8 "  (size " $3 " — size is part of the ABI)"
    }' | sort -u
echo "(empty section above = no oddities found)"

printf '\nDone. Interpret with reference/elf-and-linking.md; versions with reference/symbol-versioning.md.\n'

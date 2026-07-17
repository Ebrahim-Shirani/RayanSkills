#!/usr/bin/env bash
# check-abi-verdict.sh — run the ABI checks on two builds and emit ONE verdict.
#
# Usage: check-abi-verdict.sh <old-binary> <new-binary>
#
# Verdicts (single line on stdout, prefixed 'VERDICT: '):
#   COMPATIBLE                 no ABI change (type-aware evidence)      exit 0
#   COMPATIBLE_WITH_ADDITIONS  only additions (type-aware evidence)    exit 0
#   BREAKING                   proven incompatible change              exit 1
#   INCONCLUSIVE               evidence insufficient — NOT a pass      exit 2
#
# Honesty rules: without a type-aware engine (abidiff + DWARF), silent layout
# changes cannot be excluded, so a clean symbol diff yields INCONCLUSIVE, not
# COMPATIBLE. Tool/usage errors also yield INCONCLUSIVE. This script judges
# compatibility only — it wires nothing into any pipeline.
set -uo pipefail

# Judgment must be local and deterministic: libabigail consults debuginfod
# when DWARF is missing, and the network fetch can block indefinitely
# (observed with Ubuntu's default DEBUGINFOD_URLS on a restricted network).
export DEBUGINFOD_URLS=""

usage() { echo "usage: $0 <old-binary> <new-binary>" >&2; exit 2; }
verdict() {  # $1=verdict $2=exitcode $3=reason
    echo "VERDICT: $1 — $3"
    exit "$2"
}
inconclusive() { verdict "INCONCLUSIVE" 2 "$1"; }

[ $# -eq 2 ] || usage
OLD=$1; NEW=$2
[ -r "$OLD" ] || inconclusive "cannot read '$OLD'"
[ -r "$NEW" ] || inconclusive "cannot read '$NEW'"
for t in readelf nm; do
    command -v "$t" >/dev/null || inconclusive "required tool '$t' missing (binutils)"
done
readelf -h "$OLD" >/dev/null 2>&1 || inconclusive "'$OLD' is not ELF"
readelf -h "$NEW" >/dev/null 2>&1 || inconclusive "'$NEW' is not ELF"

M_OLD=$(readelf -h "$OLD" | awk -F: '/Machine/{gsub(/^ +/,"",$2); print $2}')
M_NEW=$(readelf -h "$NEW" | awk -F: '/Machine/{gsub(/^ +/,"",$2); print $2}')
[ "$M_OLD" = "$M_NEW" ] || inconclusive "architecture mismatch ('$M_OLD' vs '$M_NEW')"

has_dwarf() { readelf -S "$1" 2>/dev/null | grep -q '\.debug_info'; }

# --- Evidence 1: SONAME ------------------------------------------------------
SON_OLD=$(readelf -d "$OLD" 2>/dev/null | awk -F'[][]' '/SONAME/{print $2}')
SON_NEW=$(readelf -d "$NEW" 2>/dev/null | awk -F'[][]' '/SONAME/{print $2}')
if [ -n "${SON_OLD}${SON_NEW}" ] && [ "$SON_OLD" != "$SON_NEW" ]; then
    verdict "BREAKING" 1 "SONAME changed ('${SON_OLD:-<none>}' -> '${SON_NEW:-<none>}') — a declared ABI break; old consumers will not bind the new file"
fi

# --- Evidence 2: symbol-table diff (always computed) -------------------------
if nm -D --defined-only --with-symbol-versions "$OLD" >/dev/null 2>&1; then
    NMCMD=(nm -D --defined-only --with-symbol-versions)
else
    NMCMD=(nm -D --defined-only)
fi
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
"${NMCMD[@]}" "$OLD" 2>/dev/null | awk '{print $3}' | sort -u > "$T/old"
"${NMCMD[@]}" "$NEW" 2>/dev/null | awk '{print $3}' | sort -u > "$T/new"
REMOVED=$(comm -23 "$T/old" "$T/new")
ADDED=$(comm -13 "$T/old" "$T/new")
if [ -n "$REMOVED" ]; then
    echo "evidence: removed symbols:" >&2
    echo "$REMOVED" | sed 's/^/  - /' >&2
    verdict "BREAKING" 1 "$(echo "$REMOVED" | wc -l) exported symbol(s) removed (first: $(echo "$REMOVED" | head -1))"
fi

# --- Evidence 3: abidiff (type-aware when DWARF present) ---------------------
if command -v abidiff >/dev/null; then
    DWARF_OK=yes
    { has_dwarf "$OLD" && has_dwarf "$NEW"; } || DWARF_OK=no

    abidiff "$OLD" "$NEW" > "$T/report" 2>&1
    RC=$?
    # bitmask: 1=error 2=usage 4=ABI change 8=incompatible change
    if [ $((RC & 3)) -ne 0 ]; then
        sed 's/^/  abidiff: /' "$T/report" >&2
        inconclusive "abidiff tool/usage error (exit $RC) — result void"
    fi
    if [ $((RC & 8)) -ne 0 ]; then
        grep -Ei 'removed|changed' "$T/report" | head -20 | sed 's/^/  abidiff: /' >&2
        verdict "BREAKING" 1 "abidiff proves an incompatible change (exit $RC); full report: abidiff '$OLD' '$NEW'"
    fi
    if [ "$RC" -eq 0 ]; then
        if [ "$DWARF_OK" = yes ]; then
            verdict "COMPATIBLE" 0 "abidiff (type-aware, DWARF present): no ABI change"
        else
            inconclusive "no symbol-level change, but DWARF is missing — type/layout changes cannot be excluded; rebuild both with -g for a definitive verdict"
        fi
    fi
    # RC has bit 4 only. libabigail (verified with 2.4.0) reserves bit 8 for
    # changes it can prove incompatible (removed symbols, vtable changes);
    # struct layout damage comes back as bit 4 with the evidence in the report
    # text. An existing member whose offset moved is decisively breaking.
    if grep -q 'offset changed' "$T/report"; then
        grep -E 'offset changed|size changed|data member' "$T/report" | head -10 | sed 's/^/  abidiff: /' >&2
        verdict "BREAKING" 1 "abidiff reports member offset change(s) in a type crossing the interface (exit $RC); full report: abidiff '$OLD' '$NEW'"
    fi
    # Otherwise: some change, not proven incompatible. Additions only?
    abidiff --no-added-syms "$OLD" "$NEW" > "$T/report2" 2>&1
    RC2=$?
    if [ $((RC2 & 3)) -ne 0 ]; then
        inconclusive "abidiff --no-added-syms errored (exit $RC2) — result void"
    fi
    if [ "$RC2" -eq 0 ] && [ -n "$ADDED" ]; then
        if [ "$DWARF_OK" = yes ]; then
            verdict "COMPATIBLE_WITH_ADDITIONS" 0 "only added symbols ($(echo "$ADDED" | wc -l)); everything pre-existing is unchanged (abidiff, DWARF present)"
        else
            inconclusive "additions only at symbol level, but DWARF is missing — layout of existing types unverified"
        fi
    fi
    sed 's/^/  abidiff: /' "$T/report" | head -40 >&2
    inconclusive "abidiff reports changes beyond pure additions (exit $RC) that it does not prove incompatible — human review of the report above required"
fi

# --- No type-aware engine: be honest -----------------------------------------
if [ -z "$ADDED" ]; then
    inconclusive "symbol tables identical, but no type-aware engine available (install libabigail/abidiff) — layout changes cannot be excluded"
else
    inconclusive "no removals, $(echo "$ADDED" | wc -l) addition(s) at symbol level, but no type-aware engine available (install libabigail/abidiff) — layout of existing types unverified"
fi

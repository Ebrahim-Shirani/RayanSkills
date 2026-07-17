#!/usr/bin/env bash
# diff-abi.sh — compare the ABI of two builds of the same binary/library.
#
# Usage: diff-abi.sh <old-binary> <new-binary>
#
# Engines, in order of preference:
#   1. abidiff (libabigail)      — type-aware when DWARF is present  [primary]
#   2. abi-compliance-checker    — second opinion, when installed    [secondary]
#   3. nm symbol-table diff      — always available fallback (symbol level ONLY)
# The script states plainly which engines ran and which were unavailable —
# it never silently passes. Interpretation guide: reference/regression-and-diffing.md
#
# Exit codes: 0 = ran, differences (if any) printed; 2 = usage; 3 = input error.
set -uo pipefail

# Keep the diff local and deterministic: with DWARF missing, libabigail's
# debuginfod client can block indefinitely fetching debug info over the
# network (Ubuntu sets DEBUGINFOD_URLS by default).
export DEBUGINFOD_URLS=""

die() { echo "diff-abi: error: $*" >&2; exit 3; }
[ $# -eq 2 ] || { echo "usage: $0 <old-binary> <new-binary>" >&2; exit 2; }
OLD=$1; NEW=$2
[ -r "$OLD" ] || die "cannot read '$OLD'"
[ -r "$NEW" ] || die "cannot read '$NEW'"
for t in readelf nm; do command -v "$t" >/dev/null || die "missing '$t' (binutils)"; done
readelf -h "$OLD" >/dev/null 2>&1 || die "'$OLD' is not ELF"
readelf -h "$NEW" >/dev/null 2>&1 || die "'$NEW' is not ELF"

M_OLD=$(readelf -h "$OLD" | awk -F: '/Machine/{print $2}')
M_NEW=$(readelf -h "$NEW" | awk -F: '/Machine/{print $2}')
[ "$M_OLD" = "$M_NEW" ] || die "architecture mismatch:${M_OLD} vs${M_NEW} — cross-arch diffs are meaningless"

has_dwarf() { readelf -S "$1" 2>/dev/null | grep -q '\.debug_info'; }

echo "=== ABI diff: $OLD -> $NEW ==="

# --- SONAME comparison -------------------------------------------------------
SON_OLD=$(readelf -d "$OLD" 2>/dev/null | awk -F'[][]' '/SONAME/{print $2}')
SON_NEW=$(readelf -d "$NEW" 2>/dev/null | awk -F'[][]' '/SONAME/{print $2}')
echo
echo "-- SONAME --"
echo "old: ${SON_OLD:-<none>}"
echo "new: ${SON_NEW:-<none>}"
if [ -n "${SON_OLD}${SON_NEW}" ] && [ "$SON_OLD" != "$SON_NEW" ]; then
    echo "NOTE: SONAME differs — a *declared* ABI break; old consumers will not bind the new file."
fi

# --- Engine 1: abidiff -------------------------------------------------------
echo
echo "-- engine: abidiff (libabigail) --"
if command -v abidiff >/dev/null; then
    has_dwarf "$OLD" && has_dwarf "$NEW" \
        || echo "WARNING: DWARF missing in one/both inputs — abidiff degrades to symbol level; type/layout changes will NOT be seen."
    abidiff "$OLD" "$NEW"
    RC=$?
    echo "abidiff exit code: $RC  (bitmask: 4=ABI change, 8=proven-incompatible change, odd=tool/usage error)"
else
    echo "UNAVAILABLE: abidiff not installed (package: libabigail / abigail-tools)."
    echo "Type and layout changes CANNOT be detected without it (or equivalent)."
fi

# --- Engine 2: abi-compliance-checker ---------------------------------------
echo
echo "-- engine: abi-compliance-checker (secondary) --"
if command -v abi-compliance-checker >/dev/null && command -v abi-dumper >/dev/null; then
    if has_dwarf "$OLD" && has_dwarf "$NEW"; then
        WORK=$(mktemp -d)
        LNAME=$(basename "${SON_OLD:-$(basename "$OLD")}" | sed 's/\.so.*//')
        if abi-dumper "$OLD" -o "$WORK/old.dump" -lver old >/dev/null 2>&1 \
           && abi-dumper "$NEW" -o "$WORK/new.dump" -lver new >/dev/null 2>&1; then
            abi-compliance-checker -l "$LNAME" -old "$WORK/old.dump" -new "$WORK/new.dump" \
                || echo "ACC reported problems (see its report above / compat_reports/)."
        else
            echo "abi-dumper failed on the inputs; skipping ACC."
        fi
        rm -rf "$WORK"
    else
        echo "SKIPPED: ACC needs DWARF (-g builds) in both inputs."
    fi
else
    echo "UNAVAILABLE: abi-compliance-checker and/or abi-dumper not installed."
fi

# --- Engine 3: symbol-table fallback (always runs; ground truth for symbols) --
echo
echo "-- symbol-table diff (nm; catches symbol adds/removes ONLY) --"
if nm -D --defined-only --with-symbol-versions "$OLD" >/dev/null 2>&1; then
    NMCMD=(nm -D --defined-only --with-symbol-versions)
else
    NMCMD=(nm -D --defined-only)
fi
T=$(mktemp -d)
"${NMCMD[@]}" "$OLD" 2>/dev/null | awk '{print $3}' | sort -u > "$T/old"
"${NMCMD[@]}" "$NEW" 2>/dev/null | awk '{print $3}' | sort -u > "$T/new"
REMOVED=$(comm -23 "$T/old" "$T/new")
ADDED=$(comm -13 "$T/old" "$T/new")
if [ -n "$REMOVED" ]; then
    echo "REMOVED symbols (BREAKING for any consumer that used them):"
    echo "$REMOVED" | sed 's/^/  - /'
else
    echo "removed symbols: none"
fi
if [ -n "$ADDED" ]; then
    echo "ADDED symbols (compatible additions at the symbol level):"
    echo "$ADDED" | sed 's/^/  + /'
else
    echo "added symbols: none"
fi
rm -rf "$T"

echo
echo "=== end of diff. Classify with reference/regression-and-diffing.md; ==="
echo "=== record the result with templates/abi-report.md.                 ==="
echo "For a single-line verdict run: scripts/check-abi-verdict.sh '$OLD' '$NEW'"

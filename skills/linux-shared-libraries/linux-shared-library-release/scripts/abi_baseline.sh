#!/usr/bin/env bash
# abi_baseline.sh — own the ABI-baseline lifecycle of a shared library.
#
# Usage:
#   abi_baseline.sh save  <lib.so.X.Y.Z> <version> [--dir DIR]
#   abi_baseline.sh check <lib.so.X.Y.Z> [--against VERSION] [--dir DIR]
#
#   save   Serialize the library's ABI corpus with abidw into
#          DIR/<version>/<soname>.abi (+ .meta with the libabigail version).
#          Run at release time, on the artifact being released; commit DIR.
#   check  Diff the library against the newest (or --against) committed
#          baseline with abidiff and emit ONE verdict line:
#            VERDICT: COMPATIBLE | COMPATIBLE_WITH_ADDITIONS   exit 0
#            VERDICT: BREAKING                                 exit 1
#            VERDICT: INCONCLUSIVE (NOT a pass)                exit 2
#
# DIR defaults to abi-baselines/ in the current directory (the repo root).
# Honesty rules (same as check-abi-verdict.sh): no type-aware evidence means
# INCONCLUSIVE, never COMPATIBLE — build with -g for definitive verdicts.
# abidw/abidiff only read ELF+DWARF; they execute nothing, so this is safe on
# cross-compiled foreign-architecture binaries on the host.
set -uo pipefail

# Keep judgment local and deterministic (debuginfod fetches can block forever).
export DEBUGINFOD_URLS=""

die()  { echo "error: $*" >&2; exit 2; }
verdict() { echo "VERDICT: $1 — $3"; exit "$2"; }
inconclusive() { verdict "INCONCLUSIVE" 2 "$1"; }

CMD=${1:-}; shift || true
LIB=${1:-}; shift || true
DIR=abi-baselines
AGAINST=""
VERSION=""
case "$CMD" in
  save)  VERSION=${1:-}; shift || true ;;
  check) ;;
  *) die "usage: $0 save|check <lib> ... (see header)" ;;
esac
while [ $# -gt 0 ]; do
  case "$1" in
    --dir)     DIR=$2; shift 2 ;;
    --against) AGAINST=$2; shift 2 ;;
    *) die "unknown argument '$1'" ;;
  esac
done

[ -r "$LIB" ] || die "cannot read '$LIB'"
readelf -h "$LIB" >/dev/null 2>&1 || die "'$LIB' is not ELF"
SONAME=$(readelf -d "$LIB" 2>/dev/null | awk -F'[][]' '/SONAME/{print $2}')
[ -n "$SONAME" ] || die "'$LIB' has no DT_SONAME — wire SONAME first (references/build-systems/)"
has_dwarf() { readelf -S "$1" 2>/dev/null | grep -q '\.debug_info'; }

if [ "$CMD" = save ]; then
  [ -n "$VERSION" ] || die "save needs the release version: save <lib> <version>"
  command -v abidw >/dev/null || die "abidw missing (install libabigail)"
  has_dwarf "$LIB" || echo "warning: '$LIB' has no DWARF (.debug_info); corpus will be symbol-level only — future verdicts against it will be INCONCLUSIVE for layout changes. Build with -g." >&2
  mkdir -p "$DIR/$VERSION"
  OUT="$DIR/$VERSION/$SONAME.abi"
  abidw --out-file "$OUT" "$LIB" || die "abidw failed"
  { echo "soname: $SONAME"
    echo "version: $VERSION"
    echo "libabigail: $(abidw --version 2>/dev/null | head -1)"
    echo "dwarf: $(has_dwarf "$LIB" && echo yes || echo no)"
    echo "date: $(date -u +%F)"
  } > "$OUT.meta"
  echo "baseline saved: $OUT (commit '$DIR/' as part of the release commit)"
  exit 0
fi

# ---- check -----------------------------------------------------------------
command -v abidiff >/dev/null || inconclusive "abidiff missing (install libabigail) — no type-aware engine, layout changes cannot be excluded"
[ -d "$DIR" ] || inconclusive "no baseline directory '$DIR' — first release? Use 'save' after this release; regeneration from the previous tag is the documented fallback (references/abi-baselines.md)"
if [ -n "$AGAINST" ]; then
  BASE_VER=$AGAINST
else
  BASE_VER=$(ls -1 "$DIR" 2>/dev/null | sort -V | tail -1)
fi
BASE="$DIR/$BASE_VER/$SONAME.abi"
if [ ! -r "$BASE" ]; then
  # SONAME may legitimately differ after a planned MAJOR bump; fall back to
  # any single .abi in the baseline dir, otherwise give up honestly.
  CANDIDATES=$(ls -1 "$DIR/$BASE_VER"/*.abi 2>/dev/null | wc -l)
  if [ "$CANDIDATES" -eq 1 ]; then
    BASE=$(ls -1 "$DIR/$BASE_VER"/*.abi)
    echo "note: SONAME changed since baseline ($(basename "$BASE" .abi) -> $SONAME); comparing across the rename" >&2
  else
    inconclusive "no baseline for '$SONAME' under '$DIR/$BASE_VER' — cannot judge"
  fi
fi

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
abidiff "$BASE" "$LIB" > "$T/report" 2>&1; RC=$?
# abidiff exit bitmask: 1=error 2=usage 4=ABI change 8=incompatible change
if [ $((RC & 3)) -ne 0 ]; then
  sed 's/^/  abidiff: /' "$T/report" >&2
  inconclusive "abidiff tool/usage error (exit $RC) — result void"
fi
# bit 8, member-offset moves, and signature changes of existing functions are
# all decisive breaks. abidiff (verified with 2.0) reports signature changes
# (parameter added/removed/retyped, return type changed) as "indirect
# sub-type changes" with only bit 4 — but a changed signature of an exported
# function breaks every existing caller at the calling-convention level.
if [ $((RC & 8)) -ne 0 ] || grep -Eq "offset changed|parameter [0-9]+ of type .* (changed|was added|was removed)|return type changed" "$T/report"; then
  grep -Ei 'removed|changed|offset|parameter' "$T/report" | head -20 | sed 's/^/  abidiff: /' >&2
  verdict "BREAKING" 1 "abidiff vs baseline $BASE_VER proves an incompatible change (exit $RC); full report: abidiff '$BASE' '$LIB'"
fi
DWARF_NOTE=""
grep -q 'dwarf: no' "$BASE.meta" 2>/dev/null && DWARF_NOTE="baseline"
has_dwarf "$LIB" || DWARF_NOTE="${DWARF_NOTE:+$DWARF_NOTE+}new binary"
if [ "$RC" -eq 0 ]; then
  [ -z "$DWARF_NOTE" ] && verdict "COMPATIBLE" 0 "abidiff vs baseline $BASE_VER: no ABI change (type-aware)"
  inconclusive "no reported change, but DWARF missing in $DWARF_NOTE — layout changes cannot be excluded; rebuild with -g"
fi
# RC bit 4 only: some change, not proven incompatible. Additions only?
abidiff --no-added-syms "$BASE" "$LIB" > "$T/report2" 2>&1; RC2=$?
if [ $((RC2 & 3)) -ne 0 ]; then inconclusive "abidiff --no-added-syms errored (exit $RC2)"; fi
if [ "$RC2" -eq 0 ]; then
  [ -z "$DWARF_NOTE" ] && verdict "COMPATIBLE_WITH_ADDITIONS" 0 "only additions vs baseline $BASE_VER; everything pre-existing unchanged (type-aware)"
  inconclusive "additions only at symbol level, but DWARF missing in $DWARF_NOTE — layout of existing types unverified"
fi
sed 's/^/  abidiff: /' "$T/report" | head -40 >&2
inconclusive "changes beyond pure additions that abidiff does not prove incompatible — human review of the report above required"

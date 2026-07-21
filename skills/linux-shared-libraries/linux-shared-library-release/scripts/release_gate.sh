#!/usr/bin/env bash
# release_gate.sh — pre-ship checks for a built shared library. Read-only,
# execution-free (readelf/file only — never runs the binary or the loader),
# therefore safe on cross-compiled foreign-arch artifacts on the host.
#
# Usage: release_gate.sh <libNAME.so.X.Y.Z> [--pc FILE.pc] [--consumer BIN]
#
# <libNAME.so.X.Y.Z> must be the REAL file (not a symlink), in the directory
# where the symlink chain was created (build or staged-install tree).
# Prints one PASS/FAIL/WARN line per check; exits nonzero if any check FAILs.
# Rationale for each check: references/release-gate.md.
set -uo pipefail

FAIL=0
pass() { echo "PASS  $*"; }
fail() { echo "FAIL  $*"; FAIL=1; }
warn() { echo "WARN  $*"; }

LIB=${1:-}; shift || { echo "usage: $0 <lib.so.X.Y.Z> [--pc FILE.pc] [--consumer BIN]" >&2; exit 2; }
PC=""; CONSUMER=""
while [ $# -gt 0 ]; do
  case "$1" in
    --pc) PC=$2; shift 2 ;;
    --consumer) CONSUMER=$2; shift 2 ;;
    *) echo "unknown argument '$1'" >&2; exit 2 ;;
  esac
done
[ -e "$LIB" ] || { echo "error: '$LIB' not found" >&2; exit 2; }

D=$(dirname "$LIB"); F=$(basename "$LIB")

# 1. Real ELF shared object, not a symlink
if [ -L "$LIB" ]; then fail "realname: '$F' is a symlink — pass the real file"; else pass "realname: '$F' is a regular file"; fi
file -b "$LIB" 2>/dev/null | grep -q 'shared object' && pass "ELF: shared object" || fail "ELF: not a shared object"

# 2. Filename encodes X.Y.Z; derive NAME, VERSION, MAJOR
case "$F" in
  lib*.so.*.*.*) NAME=${F%%.so.*}; VERSION=${F#*.so.}; MAJOR=${VERSION%%.*}
                 pass "filename: realname '$F' encodes VERSION $VERSION" ;;
  *) fail "filename: '$F' is not libNAME.so.X.Y.Z"; NAME=${F%%.so*}; VERSION=""; MAJOR="" ;;
esac

# 3. SONAME recorded and conventional (libNAME.so.MAJOR)
SONAME=$(readelf -d "$LIB" 2>/dev/null | awk -F'[][]' '/SONAME/{print $2}')
if [ -z "$SONAME" ]; then
  fail "SONAME: missing DT_SONAME — consumers would bind to the full filename"
else
  if [ -n "$MAJOR" ] && [ "$SONAME" = "$NAME.so.$MAJOR" ]; then
    pass "SONAME: '$SONAME' == $NAME.so.<SOVERSION> and SOVERSION==MAJOR"
  else
    warn "SONAME: '$SONAME' does not equal '$NAME.so.$MAJOR' — allowed only if SOVERSION deliberately differs from MAJOR (must be documented in VERSIONING.md)"
  fi
fi

# 4. Symlink chain: libNAME.so -> soname -> realname
if [ -n "$SONAME" ]; then
  if [ -L "$D/$SONAME" ] && [ "$(readlink "$D/$SONAME")" = "$F" ]; then
    pass "chain: $SONAME -> $F"
  else
    fail "chain: '$SONAME' symlink missing or not pointing at '$F'"
  fi
  if [ -L "$D/$NAME.so" ]; then
    TGT=$(readlink "$D/$NAME.so")
    case "$TGT" in "$SONAME"|"$F") pass "chain: $NAME.so -> $TGT" ;;
      *) fail "chain: $NAME.so points at '$TGT' (expected '$SONAME')" ;; esac
  else
    warn "chain: dev link '$NAME.so' absent here (fine if the -dev package creates it at install)"
  fi
fi

# 5. DT_NEEDED entries are SONAMEs, not full versioned filenames or paths
BAD=$(readelf -d "$LIB" 2>/dev/null | awk -F'[][]' '/NEEDED/{print $2}' | grep -E '/|\.so\.[0-9]+\.[0-9]+' || true)
if [ -n "$BAD" ]; then fail "DT_NEEDED: entries carry paths or full versions (missing SONAME in a dependency at link time): $(echo "$BAD" | tr '\n' ' ')"; else pass "DT_NEEDED: all entries are plain SONAMEs"; fi

# 6. RPATH/RUNPATH hygiene: no build-tree or non-\$ORIGIN absolute paths
RP=$(readelf -d "$LIB" 2>/dev/null | awk -F'[][]' '/RPATH|RUNPATH/{print $2}')
if [ -z "$RP" ]; then
  pass "RPATH: none embedded"
else
  case "$RP" in
    *'$ORIGIN'*) warn "RPATH: '$RP' uses \$ORIGIN — acceptable for relocatable layouts; verify intent" ;;
    *) fail "RPATH: '$RP' embeds a fixed path (leaks build layout; overrides system search)" ;;
  esac
fi

# 7. Debug info: shipped .so should be stripped, with debug split elsewhere
if readelf -S "$LIB" 2>/dev/null | grep -q '\.debug_info'; then
  warn "debug: .debug_info present in the shipped file — strip it after saving the ABI baseline (objcopy --only-keep-debug first)"
else
  if readelf -S "$LIB" 2>/dev/null | grep -q '\.gnu_debuglink'; then
    pass "debug: stripped, .gnu_debuglink present"
  else
    warn "debug: stripped with no .gnu_debuglink — keep a debug file for the baseline and for crash analysis"
  fi
fi

# 8. TEXTREL (breaks sharing, blocks hardened loaders)
readelf -d "$LIB" 2>/dev/null | grep -q 'TEXTREL' && fail "TEXTREL: present — library not compiled with -fPIC everywhere" || pass "TEXTREL: none"

# 9. pkg-config version agrees with the realname version
if [ -n "$PC" ]; then
  if [ -r "$PC" ]; then
    PCV=$(grep -E '^Version:' "$PC" | awk '{print $2}')
    [ "$PCV" = "$VERSION" ] && pass "pkg-config: Version $PCV matches realname" || fail "pkg-config: Version '$PCV' != realname version '$VERSION'"
  else
    fail "pkg-config: cannot read '$PC'"
  fi
fi

# 10. A consumer, if provided, must NEED the SONAME (not the full filename)
if [ -n "$CONSUMER" ] && [ -n "$SONAME" ]; then
  CN=$(readelf -d "$CONSUMER" 2>/dev/null | awk -F'[][]' '/NEEDED/{print $2}' | grep -F "$NAME.so" || true)
  if [ "$CN" = "$SONAME" ]; then pass "consumer: DT_NEEDED == '$SONAME'"; else fail "consumer: DT_NEEDED is '${CN:-<absent>}' (expected '$SONAME')"; fi
fi

exit $FAIL

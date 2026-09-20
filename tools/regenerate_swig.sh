#!/bin/sh
# Regenerate the checked-in Python bindings from the .i files.
#
# src/python/swig.sh alone is not enough: regeneration drops two things that the
# committed wrapper needs (see AGENTS.md, "Regenerating the SWIG bindings"), and
# doing them by hand is how they get forgotten. This script is the whole recipe,
# used both by a human and by .github/workflows/swig.yml.
#
# Use the same SWIG version as the committed wrapper -- a different one rewrites
# all 6MB and makes the diff unreviewable. The expected version is asserted below.
set -eu

EXPECTED_SWIG_VERSION=${EXPECTED_SWIG_VERSION:-4.2.1}
ROOT=$(cd "$(dirname "$0")/.." && pwd)

have=$(swig -version | sed -n 's/^SWIG Version //p')
if [ "$have" != "$EXPECTED_SWIG_VERSION" ]; then
  echo "swig $have found, but the committed wrapper was generated with $EXPECTED_SWIG_VERSION." >&2
  echo "Install that version, or set EXPECTED_SWIG_VERSION to override deliberately." >&2
  exit 1
fi

echo "== swig $have: regenerating from src/python/quickfix.i"
cd "$ROOT/src/python"
sh swig.sh

# 1. The MSVC ssize_t shim, which SWIG does not emit and the MSVC build needs.
if ! grep -q "_SSIZE_T_DEFINED" QuickfixPython.cpp; then
  echo "== re-applying the MSVC ssize_t shim"
  python3 - <<'PY'
path = "QuickfixPython.cpp"
text = open(path, encoding="utf-8", errors="surrogateescape").read()
anchor = """#if !defined(PY_SSIZE_T_CLEAN) && !defined(SWIG_NO_PY_SSIZE_T_CLEAN)
#define PY_SSIZE_T_CLEAN
#endif
"""
shim = """
#if defined(_MSC_VER)
#include <BaseTsd.h>
#ifndef _SSIZE_T_DEFINED
using ssize_t = SSIZE_T;
#define _SSIZE_T_DEFINED
#endif
#endif
"""
if anchor not in text:
    raise SystemExit("PY_SSIZE_T_CLEAN block not found; SWIG output changed shape")
open(path, "w", encoding="utf-8", errors="surrogateescape").write(
    text.replace(anchor, anchor + shim, 1))
PY
fi

# 2. The src/python3 copy, which is what the wheel packages.
echo "== copying quickfix.py to src/python3/"
cp quickfix.py "$ROOT/src/python3/quickfix.py"

echo "== done; review with: git diff --stat"

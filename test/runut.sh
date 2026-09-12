#!/bin/sh
#
# Run the C++ unit test suite.
#
# Usage: runut.sh [catch2 args...]
#
# Both --quickfix-config-file and --quickfix-spec-path are required: without the
# spec path TestSettings::specPath stays empty and every data dictionary lookup
# resolves to "/FIX4x.xml", failing ~16 cases for reasons that look unrelated.

SCRIPT=$(realpath "$0")
DIR=$(dirname "$SCRIPT")

# Autotools builds the real unit binary in src/C++/test and symlinks test/ut to
# src/ut, which is a STUB whose main() just returns 0 -- so src/C++/test must be
# checked FIRST or `make check` would silently pass without running anything.
# CMake does not build that stub: there, test/ut is a symlink into lib/.
if [ -x "$DIR/../src/C++/test/ut" ]; then
  WORKDIR="$DIR/../src/C++/test"
elif [ -x "$DIR/ut" ]; then
  WORKDIR="$DIR"
else
  echo "$0: no ut binary found in $DIR or $DIR/../src/C++/test; build first" >&2
  exit 1
fi

cd "$WORKDIR" || exit 1
exec ./ut --quickfix-config-file "$DIR/cfg/ut.cfg" --quickfix-spec-path "$DIR/../spec" "$@"

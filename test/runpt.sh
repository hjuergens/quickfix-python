#!/bin/sh
#
# Run the performance benchmark suite.
#
# Usage: runpt.sh [catch2 args...]

SCRIPT=$(realpath "$0")
DIR=$(dirname "$SCRIPT")

if [ -x "$DIR/pt" ]; then
  PT="./pt"
elif [ -x "$DIR/../src/pt" ]; then
  PT="../src/pt"
else
  echo "$0: no pt binary found in $DIR or $DIR/../src; build first" >&2
  exit 1
fi

cd "$DIR" || exit 1

# Report a failure from either pass: capturing only the second would hide a
# regression in the non-network benchmarks.
RESULT=0
$PT --quickfix-spec-path "$DIR/../spec" -# "~[network]" "$@" || RESULT=$?
$PT --quickfix-spec-path "$DIR/../spec" -# "[network]" "$@" || RESULT=$?
exit $RESULT

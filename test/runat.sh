#!/bin/sh
#
# Run the FIX acceptance suite against a freshly started `at` acceptor.
#
# Usage: runat.sh <port>
#
# Exits 0 only if every test group passed. Output from each group is buffered
# and printed at the end: nine concurrent writers on one descriptor would
# interleave and shred Runner.rb's multi-line failure reports.

SCRIPT=$(realpath "$0")
DIR=$(dirname "$SCRIPT")
cd "$DIR" || exit 1

RUBY="ruby -I."
PORT=$1

# Each group drives a distinct FIX session, so all of them can run at once.
GROUPS="fix40 fix41 fix42 fix43 fix44 fix50 fix50sp1 fix50sp2 validate"

AT_PID=''
RUNNER_PIDS=''
OUTDIR=''
DUMPED=''

usage() {
  echo "usage: $0 <port>" >&2
  exit 2
}

dump_output() {
  [ -n "$DUMPED" ] && return 0
  DUMPED=yes
  [ -n "$OUTDIR" ] || return 0
  for GROUP in $GROUPS; do
    [ -s "$OUTDIR/$GROUP.out" ] && cat "$OUTDIR/$GROUP.out"
  done
  return 0
}

# Kill only what we started. Signalling the whole process group -- as this
# script used to -- takes the shell down with it and replaces the real exit
# status with 143, so a passing run reports failure.
cleanup() {
  [ -n "$RUNNER_PIDS" ] && kill $RUNNER_PIDS 2>/dev/null
  [ -n "$AT_PID" ] && kill "$AT_PID" 2>/dev/null
  dump_output
  [ -n "$OUTDIR" ] && rm -rf "$OUTDIR"
  return 0
}

# The EXIT handler must never call exit: that would discard $RESULT.
trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

port_is_open() {
  ruby -rsocket -e 'TCPSocket.new(ARGV[0], ARGV[1].to_i).close' 127.0.0.1 "$1" 2>/dev/null
}

group_has_defs() {
  for DEF in "definitions/server/$1"/*.def; do
    [ -e "$DEF" ] && return 0
  done
  return 1
}

[ $# -eq 1 ] || usage
case $PORT in
'' | *[!0-9]*) usage ;;
esac
[ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ] || usage

# An unmatched glob is passed through literally and Runner.rb exits 0 on it, so
# without this check a renamed or missing group vanishes and the suite still
# reports success.
for GROUP in $GROUPS; do
  if ! group_has_defs "$GROUP"; then
    echo "$0: no .def files in definitions/server/$GROUP" >&2
    exit 1
  fi
done

# Refuse to run against a server we did not start: it would answer with foreign
# session state and every result would be meaningless.
if port_is_open "$PORT"; then
  echo "$0: port $PORT is already in use; refusing to start" >&2
  exit 1
fi

./setup.sh "$PORT" || exit 1

OUTDIR=$(mktemp -d) || exit 1

./at -f cfg/at.cfg >"$OUTDIR/at.log" 2>&1 &
AT_PID=$!

# Wait for the acceptor to bind before handing it the suite. Runner.rb retries
# for ~29s per .def file, so an unnoticed dead server costs hours, not seconds.
WAITED=0
while ! port_is_open "$PORT"; do
  if ! kill -0 "$AT_PID" 2>/dev/null; then
    echo "$0: acceptance server exited during startup:" >&2
    cat "$OUTDIR/at.log" >&2
    exit 1
  fi
  WAITED=$((WAITED + 1))
  if [ "$WAITED" -ge 30 ]; then
    echo "$0: acceptance server did not listen on port $PORT within ${WAITED}s:" >&2
    cat "$OUTDIR/at.log" >&2
    exit 1
  fi
  sleep 1
done

for GROUP in $GROUPS; do
  $RUBY Runner.rb 127.0.0.1 "$PORT" definitions/server/$GROUP/*.def \
    >"$OUTDIR/$GROUP.out" 2>&1 &
  eval "PID_$GROUP=$!"
  RUNNER_PIDS="$RUNNER_PIDS $!"
done

RESULT=0
for GROUP in $GROUPS; do
  eval "PID=\$PID_$GROUP"
  if wait "$PID"; then
    echo "$GROUP: ok"
  else
    RESULT=$?
    echo "$GROUP: FAILED (rc=$RESULT)"
  fi
done
# Reaped: clearing this keeps cleanup from signalling recycled PIDs.
RUNNER_PIDS=''

dump_output
exit $RESULT

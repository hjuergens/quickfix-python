#!/usr/bin/env bash
# CMAKE_CROSSCOMPILING_EMULATOR wrapper: run a cross-built .exe under Wine,
# translating Unix path arguments to Windows form first.
#
# Without the translation, CTest's absolute arguments arrive looking like
# "/home/you/repo/test/cfg/ut.cfg", and an argument parser on Windows reads a
# leading slash as an option introducer -- so the flag before it is reported as
# missing its value rather than the path being wrong. The failure names the
# flag, not the path, which makes it needlessly hard to read.
set -u

exe=$1; shift
args=()
for a in "$@"; do
  if [[ $a == /* && -e $a ]]; then
    args+=("$(winepath -w "$a" 2>/dev/null || echo "$a")")
  else
    args+=("$a")
  fi
done

exec wine "$exe" "${args[@]}"

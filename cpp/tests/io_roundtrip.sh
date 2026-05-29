#!/bin/sh
# I/O round-trip + read_int abort-code check for the C++ skeleton.
# Usage: io_roundtrip.sh <path-to-lo_io_probe>
set -u
probe="$1"

out=$(printf '7\n' | "$probe")
expected=$(printf '7\n42')
if [ "$out" != "$expected" ]; then
  echo "round-trip mismatch: got [$out], want [$expected]" >&2
  exit 1
fi

printf '' | "$probe" >/dev/null 2>&1
code=$?
if [ "$code" -ne 111 ]; then
  echo "read_int EOF: expected exit 111, got $code" >&2
  exit 1
fi

printf 'abc' | "$probe" >/dev/null 2>&1
code=$?
if [ "$code" -ne 110 ]; then
  echo "read_int malformed: expected exit 110, got $code" >&2
  exit 1
fi

echo "io round-trip + abort codes ok"

#!/usr/bin/env bash
#
# Cross-skeleton ABI link test (runbook WS-1 Phase 4.4).
#
# Links the pure-C harness (main.c) against each skeleton's static library and
# checks that all three print the same line ("42"). If a C program can link and
# run against a skeleton, that skeleton honors the C ABI — the actual promise the
# three make. Assumes each skeleton's static lib is already built; skips any that
# is missing.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

obj="$tmp/main.o"
cc -c "$root/tests/c_harness/main.c" -o "$obj"

expected=$'42'
cxx="${CXX:-c++}"
fail=0

run_check() {
  local name="$1" bin="$2" out
  out="$("$bin")"
  if [[ "$out" == "$expected" ]]; then
    echo "  $name: OK"
  else
    echo "  $name: FAIL (got [$out], want [42])" >&2
    fail=1
  fi
}

# Rust — link against the native libs rustc reports for the staticlib, so this
# works on Linux (needs -lpthread -ldl -lm …) as well as macOS.
rust_lib="$root/rust/target/debug/liblo_runtime.a"
if [[ -f "$rust_lib" ]]; then
  rust_libs="$(cd "$root/rust" \
    && cargo rustc -q --lib -- --print native-static-libs 2>&1 \
    | sed -n 's/.*native-static-libs: //p' | head -1 || true)"
  # shellcheck disable=SC2086
  cc "$obj" "$rust_lib" ${rust_libs:-} -o "$tmp/rust"
  run_check "rust" "$tmp/rust"
else
  echo "  rust: lib not built (cd rust && cargo build), skipped" >&2
fi

# Zig — std uses raw syscalls, no extra libs needed beyond what cc links.
zig_lib="$root/zig/zig-out/lib/liblo_runtime.a"
if [[ -f "$zig_lib" ]]; then
  cc "$obj" "$zig_lib" -o "$tmp/zig"
  run_check "zig" "$tmp/zig"
else
  echo "  zig: lib not built (cd zig && zig build), skipped" >&2
fi

# C++ — link with the C++ driver so the C++ standard library comes in.
cpp_lib="$root/cpp/build/liblo_runtime.a"
if [[ -f "$cpp_lib" ]]; then
  "$cxx" "$obj" "$cpp_lib" -o "$tmp/cpp"
  run_check "cpp" "$tmp/cpp"
else
  echo "  cpp: lib not built (cd cpp && cmake -B build -S . && cmake --build build), skipped" >&2
fi

if [[ "$fail" -ne 0 ]]; then
  echo "cross-skeleton harness: FAIL" >&2
  exit 1
fi
echo "cross-skeleton harness: all built skeletons link from C and agree (42)"

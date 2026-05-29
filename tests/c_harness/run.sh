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

# On Linux the default driver links PIE, but the Zig and C++ static libraries are
# built non-PIC, so their objects can't go into a PIE executable
# (R_X86_64_32S ... can not be used when making a PIE object). Link the harness
# binaries non-PIE there. macOS clang neither needs nor accepts -no-pie.
nopie=""
[[ "$(uname -s)" == "Linux" ]] && nopie="-no-pie"

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
# works on Linux (needs -lpthread -ldl -lm …) as well as macOS. We drop the -lc
# token: the C driver (`cc`) appends libc itself, and an explicit `-lc` fails to
# resolve on some Linux runners ("cannot find -lc").
#
# Color must be forced off: CI sets CARGO_TERM_COLOR=always, which makes cargo
# wrap the native-static-libs note in ANSI escapes — the trailing token then
# reads as "-lc"+escape, slips past the filter, and is handed to ld as a garbled
# lib name. `--color never` + stripping CR keeps the tokens clean.
rust_lib="$root/rust/target/debug/liblo_runtime.a"
if [[ -f "$rust_lib" ]]; then
  rust_note="$(cd "$root/rust" \
    && CARGO_TERM_COLOR=never cargo rustc -q --color never --lib -- \
       --print native-static-libs 2>&1 \
    | grep -m1 'native-static-libs:' | tr -d '\r' || true)"
  read -ra _rust_toks <<<"${rust_note##*native-static-libs: }"
  rust_libs=()
  for _t in "${_rust_toks[@]}"; do
    [[ -z "$_t" || "$_t" == "-lc" ]] || rust_libs+=("$_t")
  done
  # shellcheck disable=SC2086
  cc $nopie "$obj" "$rust_lib" "${rust_libs[@]}" -o "$tmp/rust"
  run_check "rust" "$tmp/rust"
else
  echo "  rust: lib not built (cd rust && cargo build), skipped" >&2
fi

# Zig — std uses raw syscalls, no extra libs needed beyond what cc links.
zig_lib="$root/zig/zig-out/lib/liblo_runtime.a"
if [[ -f "$zig_lib" ]]; then
  # shellcheck disable=SC2086
  cc $nopie "$obj" "$zig_lib" -o "$tmp/zig"
  run_check "zig" "$tmp/zig"
else
  echo "  zig: lib not built (cd zig && zig build), skipped" >&2
fi

# C++ — link with the C++ driver so the C++ standard library comes in.
cpp_lib="$root/cpp/build/liblo_runtime.a"
if [[ -f "$cpp_lib" ]]; then
  # shellcheck disable=SC2086
  "$cxx" $nopie "$obj" "$cpp_lib" -o "$tmp/cpp"
  run_check "cpp" "$tmp/cpp"
else
  echo "  cpp: lib not built (cd cpp && cmake -B build -S . && cmake --build build), skipped" >&2
fi

if [[ "$fail" -ne 0 ]]; then
  echo "cross-skeleton harness: FAIL" >&2
  exit 1
fi
echo "cross-skeleton harness: all built skeletons link from C and agree (42)"

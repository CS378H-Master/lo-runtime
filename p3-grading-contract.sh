#!/usr/bin/env bash
# =============================================================================
# CS 378H — P3 grading contract
# =============================================================================
# This file is the interface between your submission and the autograder.
# Every submission builds and runs differently, so instead of forcing a common
# starter layout, we ask you to fill in a few shell functions that tell the
# grader how to drive *your* toolchain.
#
# Submit this file, filled in, at the TOP LEVEL of your repository, keeping the
# name `p3-grading-contract.sh`.
#
# P3 keeps the six P2 functions UNCHANGED — lo-build, lo-check, lo-compile,
# lo-wasmrun, lo-emit-asm, lo-dump-ir — and the LO_ASSEMBLER variable, so you
# may paste your P2 fill-in verbatim. It adds two variables, LO_RUNTIME_NATIVE_LIB
# and LO_RUNTIME_WASM_LIB, that name the runtime archives your lo-build produces.
# In P3 the runtime under test is YOURS: the grader links your native assembly
# and its own ABI harness programs against these two archives.
#
# -----------------------------------------------------------------------------
# What the grader does — four stages
# -----------------------------------------------------------------------------
# Once per submission:
#
#     $ source p3-grading-contract.sh
#     $ lo-build                                       # build everything, once
#     $ lo-dump-ir prog.lo                             # 0 points, one program, diagnostic only
#
# Stage 1, WASM end-to-end: every Project-1 test (LO-3 and LO-4), via lo-check /
# lo-compile / lo-wasmrun, exactly as in P1 and P2. The module your lo-compile
# links contains your runtime, so these rows are scored.
#
#     $ lo-check   prog.lo                             # front-end only
#     $ lo-compile prog.lo /tmp/artifacts/prog.wasm    # front-end, and if good,
#                                                      # must emit .wasm at $2
#     $ lo-wasmrun /tmp/artifacts/prog.wasm            # run it
#
# Stage 2, native end-to-end: the same tests on the x86-64 back end. lo-check as
# before, and for run tests:
#
#     $ lo-emit-asm prog.lo /tmp/artifacts/prog.s      # YOUR compiler writes
#                                                      # Intel-syntax x86-64 asm to $2
#   then the GRADER, as you:
#     $ as --64 -o prog.o prog.s         (or: nasm -f elf64 -o prog.o prog.s
#                                              when LO_ASSEMBLER=nasm)
#     $ cc -no-pie -o prog prog.o "$LO_RUNTIME_NATIVE_LIB" -lpthread -ldl -lm
#     $ ./prog < input                                 # exit status and stdout graded
#
# Stage 3, GC stress: LO programs that allocate heavily (the public ones are in
# lo-testing's p3-gc-stress-tests/). Each is one row and must pass on WASM, natively, and
# natively again with LO_HEAP_SIZE set to the heap the program's header names
# (`// gc stress heap: <bytes>`), so your collector is exercised at a small heap.
#
# Stage 4, ABI harness: small C programs that call your runtime's entry points
# directly, with no compiler in between (the public ones, with instructions for
# running them yourself, are in lo-testing's p3-abi-harness/). The grader compiles
# them itself and, as you, links each against your archives and runs it:
#
#     $ cc -no-pie -o abi_03 abi_03.o "$LO_RUNTIME_NATIVE_LIB" -lpthread -ldl -lm && ./abi_03
#     $ wasm-ld --no-entry --export=lo_entry --allow-undefined abi_03.o "$LO_RUNTIME_WASM_LIB" -o abi_03.wasm
#     $ wasmrun abi_03.wasm
#
# Not every program runs every step: programs that are supposed to be REJECTED
# are only ever passed to `lo-check`.
#
# -----------------------------------------------------------------------------
# Rules that apply to this file as a whole
# -----------------------------------------------------------------------------
#  * It must be safe to `source`. Do NOT do any work at the top level: no
#    building, no `cd`, no output. Only variable assignments and function
#    definitions. The grader sources this file once and then calls the
#    functions many times.
#  * Do NOT print anything while being sourced. Anything your functions print
#    on stdout is compared byte-for-byte against expected program output, and a
#    stray banner will fail tests that would otherwise pass.
#  * Do NOT use `set -e` at the top level. A non-zero exit from `lo-check` is a
#    NORMAL, EXPECTED result (it means "this program has an error"), and `set -e`
#    would tear down the grader's shell. Use `set -e` inside a function body if
#    you want fail-fast there.
#  * Do not rename the functions or change their argument order.
#  * Paths given to you may be absolute and may contain no spaces, but quote
#    "$1" / "$2" anyway.
# =============================================================================

set -uo pipefail   # deliberately NOT -e; see above

# Absolute path to your repository root, so the functions work no matter what
# directory the grader happens to be in. Leave this as-is.
# To be safe, consider using $LO_ROOT in your commands to refer to your submission's
# root (review filled-in example at the end).
LO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"


# -----------------------------------------------------------------------------
# LO_ASSEMBLER
# -----------------------------------------------------------------------------
# Which assembler dialect lo-emit-asm writes:
#   gas   GNU as, Intel syntax (`.intel_syntax noprefix`) — the default
#   nasm  NASM syntax (`nasm -f elf64`)
# Leave it empty or set it to `gas` unless you emit NASM.
# -----------------------------------------------------------------------------
LO_ASSEMBLER=gas


# -----------------------------------------------------------------------------
# LO_RUNTIME_NATIVE_LIB, LO_RUNTIME_WASM_LIB                               (NEW)
# -----------------------------------------------------------------------------
# The two archives your runtime skeleton builds: the native static library the
# grader links your assembly and the native harness programs against, and the
# wasm32 static library the grader links the WASM harness programs against (the
# same archive your lo-compile already links). Both must exist, as non-empty
# regular files, after lo-build returns. Absolute paths built from $LO_ROOT;
# the defaults below are where the Rust skeleton's `cargo build --release` puts
# them. The grader never modifies them and never reads your runtime's sources.
#
# If either is missing or is not a file, every native row and every harness row
# fails with `runtime_lib_missing`; stage 1 is unaffected.
# -----------------------------------------------------------------------------
LO_RUNTIME_NATIVE_LIB="$LO_ROOT/rust/target/release/liblo_runtime.a"
LO_RUNTIME_WASM_LIB="$LO_ROOT/rust/target/wasm32-unknown-unknown/release/liblo_runtime.a"


# -----------------------------------------------------------------------------
# lo-build
# -----------------------------------------------------------------------------
# Build your compiler and anything it needs: your runtime for BOTH targets,
# libraries, ... Called ONCE, before any other function.
#
#   arguments : none
#   stdout    : ignored (build logs are fine here)
#   stderr    : ignored (shown to you if the build fails)
#   exit      : 0 on success, non-zero on failure.
#
# If this fails, the grader reports "your submission did not build", shows you
# the tail of this output, and skips every other test. Get this right first.
#
# The grading container has a network connection and a warm Cargo registry, but
# builds are on a slow, single-core machine — keep it under ~10 minutes.
# -----------------------------------------------------------------------------
lo-build() {
    cargo build --release --manifest-path "$LO_ROOT/compiler/Cargo.toml" || return 1
    cargo build --release --lib --manifest-path "$LO_ROOT/rust/Cargo.toml" || return 1
    # Emit WASM objects, not LLVM bitcode tied to rustc's LLVM version.
    cargo build --release --target wasm32-unknown-unknown --lib \
        --config profile.release.lto=false --manifest-path "$LO_ROOT/rust/Cargo.toml"
}


# -----------------------------------------------------------------------------
# lo-check  <source.lo>
# -----------------------------------------------------------------------------
# Run ONLY the front end: parse, resolve names, type check. Do not generate or
# write any output file.
#
#   $1        : path to a .lo source file
#   stdout    : ignored
#   stderr    : on rejection, must contain the error code for the problem you
#               found (see error-codes.md), e.g. E_UNKNOWN_VARIABLE. The grader
#               searches stderr for the code as a substring, so you are free to
#               word the surrounding message however you like.
#   exit      : 0  the program is well-formed and type-correct
#               1  the program has an error (and stderr names the code)
#
# Exit exactly 1 to reject. Any other non-zero status is treated as your
# compiler having crashed rather than having diagnosed the problem, and will
# not earn credit — this is deliberate, since a segfault on a malformed program
# is not the same as catching the error.
# -----------------------------------------------------------------------------
lo-check() {
    "$LO_ROOT/compiler/target/release/lo-compiler" --check "$1"
}


# -----------------------------------------------------------------------------
# lo-compile  <source.lo>  <output.wasm>
# -----------------------------------------------------------------------------
# Compile a program all the way to a linked WebAssembly module: run the front
# end, generate code, and link against YOUR runtime (the archive
# LO_RUNTIME_WASM_LIB names). UNCHANGED from P1 and P2.
#
#   $1        : path to a .lo source file
#   $2        : path where the finished .wasm MUST be written
#   stdout    : ignored
#   stderr    : shown to you on failure
#   exit      : 0 on success, non-zero on failure
#
# $2 is always of the form /tmp/artifacts/<name>.wasm. The grader creates and
# empties /tmp/artifacts before each program, so you may assume the directory
# exists and is writable, and you do not need to clean up after yourself.
#
# Write the module to EXACTLY $2 — not to a fixed path of your own choosing,
# and not next to the source file. Immediately after this function returns, the
# grader checks that $2 exists and is a non-empty regular file, and reports that
# check as its own test. If you exit 0 but write nothing, you will see
# "no .wasm produced" rather than a confusing failure later on.
#
# The finished module must export `lo_entry` (returning i32) and a `memory`,
# because that is what the `wasmrun` host harness looks for.
# -----------------------------------------------------------------------------
lo-compile() {
    LO_RUNTIME_ARCHIVE="$LO_RUNTIME_WASM_LIB" \
        "$LO_ROOT/compiler/target/release/lo-compiler" --compile "$1" "$2"
}


# -----------------------------------------------------------------------------
# lo-wasmrun  <module.wasm>
# -----------------------------------------------------------------------------
# Run a compiled module under the course's host harness.
#
# This one is already written, and you should NOT change it. `wasmrun` is
# installed in the course container and in the grading image; it supplies the
# `host` I/O imports your runtime is written against, calls `lo_entry`, and
# exits with whatever your program returned (or with a documented abort code
# such as 101 or 110 if your runtime trapped).
#
#   $1        : path to a linked .wasm module
#   stdin     : the grader may pipe a test's input in; wasmrun forwards it
#   stdout    : your program's output, compared byte-for-byte where a test
#               declares expected output
#   stderr    : searched for the expected message on abort tests
#   exit      : your program's exit status — must be passed through unchanged
#
# Do not wrap this in anything that swallows, renumbers, or remaps the exit
# status; the grader compares it against the value the test declares.
# -----------------------------------------------------------------------------
lo-wasmrun() {
    wasmrun "$1"
}


# -----------------------------------------------------------------------------
# lo-emit-asm  <source.lo>  <output.s>
# -----------------------------------------------------------------------------
# Compile a program to x86-64 assembly text: run the front end, lower to your
# IR, allocate registers, and write the assembly file. Do NOT assemble, link or
# run it — the grader does that, with the commands shown at the top of this
# file, against YOUR archive (LO_RUNTIME_NATIVE_LIB).
#
#   $1        : path to a .lo source file
#   $2        : path where the assembly MUST be written (/tmp/artifacts/<name>.s)
#   stdout    : ignored
#   stderr    : shown to you on failure
#   exit      : 0 on success, non-zero on failure
#
# What the grader's link step needs from your .s:
#   * a global `main` (`.globl main`) that calls `lo_runtime_init` first and
#     returns `Main.main`'s result as the process exit status;
#   * the dialect LO_ASSEMBLER names (GNU as Intel syntax by default);
#   * absolute `.quad` tables are fine — the link is `-no-pie`;
#   * end with `.section .note.GNU-stack,"",@progbits` (avoids a linker warning);
#   * runtime calls by their ABI names (lo_alloc, lo_print_int, lo_push_frame, …).
#
# Write to EXACTLY $2. The grader checks that $2 exists and is non-empty and
# reports that as its own test, then assembles it: an `as` error shows up as
# `assemble_failed` with the assembler's diagnostic, a link error as
# `link_failed` with the undefined symbols — in P3 an undefined `lo_*` symbol
# means your runtime archive does not export it.
# -----------------------------------------------------------------------------
lo-emit-asm() {
    "$LO_ROOT/compiler/target/release/lo-compiler" --emit-asm "$1" "$2"
}


# -----------------------------------------------------------------------------
# lo-dump-ir  <source.lo>
# -----------------------------------------------------------------------------
# Print your intermediate representation for the program to stdout. Worth 0
# points: the grader runs it once, on one LO-4 program, and records whether it
# exited 0 and printed something, as a diagnostic row. The format is yours; the
# grader does not parse it, and keeps the first few KB for the course staff.
#
#   $1        : path to a .lo source file
#   stdout    : your IR, any format, not empty
#   stderr    : shown to you on failure
#   exit      : 0 on success
# -----------------------------------------------------------------------------
lo-dump-ir() {
    "$LO_ROOT/compiler/target/release/lo-compiler" --dump-ir "$1"
}


# =============================================================================
# Worked example
# =============================================================================
# For reference, here is a complete fill-in for a Rust compiler named `loc`
# that emits a relocatable wasm object and links it against the runtime
# staticlib, and that writes GNU-as Intel-syntax assembly for the native back
# end, with the Rust runtime skeleton at runtime/. Yours will differ — this is
# only to show the shape. Pay special attention to the return codes of each
# function.
#
#   LO_ASSEMBLER=gas
#   LO_RUNTIME_NATIVE_LIB="$LO_ROOT/runtime/target/release/liblo_runtime.a"
#   LO_RUNTIME_WASM_LIB="$LO_ROOT/runtime/target/wasm32-unknown-unknown/release/liblo_runtime.a"
#
#   lo-build() {
#       ( cd "$LO_ROOT" && cargo build --release ) || return 1
#       ( cd "$LO_ROOT/runtime" &&
#         cargo build --release --target wasm32-unknown-unknown --lib ) || return 1
#       ( cd "$LO_ROOT/runtime" && cargo build --release --lib ) || return 1
#   }
#
#   lo-check() {
#       "$LO_ROOT/target/release/loc" --check "$1"
#   }
#
#   lo-compile() {
#       local obj; obj="$(mktemp)" || return 1
#       "$LO_ROOT/target/release/loc" --emit-obj "$obj" "$1" || { rm -f "$obj"; return 1; }
#       "$LO_ROOT/tools/wasm-ld" "$obj" "$LO_RUNTIME_WASM_LIB" -o "$2" \
#           --export=lo_entry --no-entry --allow-undefined
#       local rc=$?; rm -f "$obj"; return $rc
#   }
#
#   lo-emit-asm() {
#       "$LO_ROOT/target/release/loc" --emit-asm "$2" "$1"
#   }
#
#   lo-dump-ir() {
#       "$LO_ROOT/target/release/loc" --dump-ir "$1"
#   }
# =============================================================================

# LO Runtime — C++ skeleton

Modern C++20 implementation of the LO runtime ABI
([`../runtime-abi.md`](../runtime-abi.md)). The exported surface is `extern "C"`;
the implementation uses C++ freely. The provided entry points work out of the
box; the stubbed ones (`lo_gc_collect`, the `lo_string_*` ops, `lo_cast_check` /
`lo_instanceof`) `throw std::runtime_error` until your team fills them in for P3.

## Toolchain

- Clang 18+ or GCC 14+; CMake 3.28+. Built and tested against clang 19 + CMake
  4.3.
- `clang-format` for the pre-commit hook.

Catch2 v2 is vendored as a single header (`tests/catch.hpp`) — no package
manager or network needed to build the tests.

## Build & test

```sh
cmake -B build -S .
cmake --build build
ctest --test-dir build
clang-format --dry-run --Werror $(find src include -name '*.cpp' -o -name '*.h')
```

`ctest` runs the Catch2 ABI smoke suite (`lo_runtime_tests`: layout, alloc
zeroing, bump advance, shadow-stack push/pop, the `LO_EMPTY_STRING` singleton) and
the I/O round-trip + `read_int` abort-code checks (`io_round_trip`, driven via
`tests/lo_io_probe`).

## WASM

The C++/WASM build path (Emscripten vs direct `wasm-clang`) is an open course
decision and is not wired into CMake yet. The sources are WASM-ready: every
native/WASM split is an `#ifdef __wasm__` branch forwarding to host imports the
harness wires. Once the toolchain is chosen, add a WASM target (see the note in
`CMakeLists.txt`).

## Layout

```
CMakeLists.txt
include/lo_runtime/
├── lo_runtime.h      # umbrella header
├── object.h          # ABI types + offset helpers + static_assert layout locks
├── descriptors.h     # class descriptors + LO_EMPTY_STRING
├── alloc.h  shadow_stack.h  init.h  io.h  gc.h  string_ops.h  cast.h  abort.h
src/
├── abort.cpp alloc.cpp cast.cpp descriptors.cpp gc.cpp init.cpp io.cpp
└── shadow_stack.cpp string_ops.cpp
tests/
├── catch.hpp         # vendored Catch2 v2 single header
├── test_main.cpp     # CATCH_CONFIG_MAIN
├── abi_tests.cpp     # ABI smoke suite
├── lo_io_probe.cpp   # I/O test driver
└── io_roundtrip.sh   # round-trip + abort-code harness
```

## What to implement in P3

Start in `gc.cpp` (`lo_gc_collect` + the OOM-retry path in `alloc.cpp`), then the
`string_ops.cpp` and `cast.cpp` stubs. Build string results with the internal
`lo::bump_alloc_string`. The instructor's acceptance baseline is Cheney's
semispace with all shared tests passing (`../runtime-abi.md` §4.5).

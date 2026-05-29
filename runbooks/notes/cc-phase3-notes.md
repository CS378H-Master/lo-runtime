# Phase 3 notes — C++ skeleton

## What got done

Full modern-C++20 skeleton under `cpp/`, mirroring the Rust/Zig modules:
`object`/`descriptors`/`alloc`/`shadow_stack`/`init`/`io`/`gc`/`string_ops`/
`cast`/`abort`, headers in `include/lo_runtime/`, sources in `src/`, umbrella
`lo_runtime.h`. The exported surface is `extern "C"` (unmangled); the
implementation uses C++ freely. CMake builds a static library. Verified:
`cmake -B build -S .`, `cmake --build build`, `ctest --test-dir build` (2/2),
`clang-format --dry-run --Werror` (clean), and `clang-tidy` (clean, see caveat).
`nm` confirms all 23 `lo_*` functions + the 4 data symbols are exported,
unmangled, matching Rust and Zig.

## Layout agreement (Phase 4 audit)

`object.h` carries `static_assert` layout locks identical in value to the Rust
`const _` and Zig comptime ones: `Object` 16/12 bytes, string-data offset 20/16,
frame-roots offset 16/8 (64/32-bit), pointer-width gated via `#if UINTPTR_MAX`.

**Offset computation differs in spelling but not result.** Rust/Zig use a
zero-length marker field + `offset_of`/`@offsetOf`. C++ instead computes
`offsetof(StringObject, length) + sizeof(uint32_t)` (= 20) and, for roots, aligns
`offsetof(num_roots)+sizeof` up to `alignof(Object*)` (= 16). This avoids a
flexible-array-member / zero-length-array extension in standard C++20 while
producing the identical offsets. The structs are header-only (no inline tail
member); the inline bytes live at the computed offset. Documented in `object.h`.

## C++-specific decisions / deviations

- **Descriptors are `extern "C" const ClassDescriptor` defined in
  `descriptors.cpp`**, not the runbook's `inline constexpr`. Reason: codegen and
  the C harness need an emitted, unmangled external symbol (`LO_STRING_CLASS`
  etc.); `inline constexpr` is for C++ ODR-sharing across TUs and isn't the right
  tool for a C-ABI data export. Used C++20 designated initializers.

- **`name` field is `const char*`** (a C string) rather than `const uint8_t*`. The
  ABI's `*const u8` for `name` is "null-terminated UTF-8" — exactly a C string.
  Pointer-sized either way, so the byte layout is identical; `const char*` lets
  the descriptors be constant-initialized (rodata) with plain string literals.

- **Native I/O via `<cstdio>`** (C++ reaches `stdin`/`stdout` directly, unlike the
  Rust/Zig libc-`FILE*` problem that pushed them to stdlib I/O). `lo_eof` peeks
  with `getchar`+`ungetc`, not `feof` (which only reports EOF *after* a failed
  read — wrong for the ABI's "at EOF without consuming"). `read_int`/`read_bool`
  use the same getchar/ungetc peek-based parsing as Rust/Zig (I rewrote them off
  an initial `scanf` version — see clang-tidy below), so all three skeletons now
  parse input identically.

- **Stubs `throw std::runtime_error`** per the runbook. These are `extern "C"`
  functions that throw; a C caller invoking one would `std::terminate`, which is
  fine since passing programs never call stubs. (No `-Wexceptions` issue: extern
  "C" functions aren't implicitly `noexcept`.)

- **Heap is a `std::vector<std::uint8_t>`** per the runbook (its storage is
  `max_align_t`-aligned, so the `reinterpret_cast<Object*>` is well-aligned).

- **WASM is not wired into CMake.** The C++/WASM toolchain (Emscripten vs
  wasm-clang) is an open DC decision (runbook open items). The sources ARE
  WASM-ready — every native/WASM split is an `#ifdef __wasm__` branch forwarding
  to `host_*` imports — but no WASM target is built here, and those branches are
  therefore **untested** (compiled only under native, where `__wasm__` is unset).
  This is the one place the C++ skeleton is less complete than Rust/Zig (both of
  which build + symbol-verify their `.wasm`). Flagged for DC.

## Tooling caveats worth knowing (env, not code)

- **clang-tidy can't find the C++ sysroot headers on its own** here — the
  pip-installed `clang-tidy` (miniconda) reports spurious `'cstdint' file not
  found` errors because it doesn't know the macOS SDK path. Run it with
  `--extra-arg=-isysroot "$(xcrun --show-sdk-path)"` to get a real analysis; with
  that, the suite is **clean**. The `.clang-tidy` config disables checks at odds
  with this domain (`portability-avoid-pragma-once` — pragma once is the project
  idiom; `readability-implicit-bool-conversion` — the `assert(cond && "msg")`
  idiom) and the usual noise (magic-numbers, identifier-length). clang-tidy is NOT
  in the pre-commit hook or the runbook's Phase 3 verification commands, so this
  env quirk doesn't gate commits — but `cmake -B build -DCMAKE_EXPORT_COMPILE_COMMANDS=ON`
  + the `--extra-arg` invocation reproduces a clean run.

- **Genuine clang-tidy findings I fixed** (not suppressed): size_t multiplication
  for the default heap size (`bugprone-implicit-widening-of-multiplication-result`);
  designated initializers for the descriptors; rewrote `read_int`/`read_bool` off
  `scanf` to a checked `strtol` + getchar peek (`bugprone-unchecked-string-to-number-conversion`)
  — which also improved cross-skeleton parity. One justified `NOLINT`: the string
  `memcpy` (`bugprone-not-null-terminated-result`) — LO strings are
  length-prefixed by design, not null-terminated.

- **zsh vs bash word-splitting gotcha (cost me time).** The interactive shell here
  is zsh, which does NOT word-split unquoted `$(find ...)`/`$var`, so a manual
  `clang-format --dry-run $(find ...)` passes the whole list as one "filename"
  ("No such file or directory"). The **hook works correctly** because it has a
  `#!/usr/bin/env bash` shebang (bash word-splits) and pipes through `xargs`.
  When verifying clang-format manually, use `xargs` or `bash -c`, not a bare zsh
  command substitution.

## Testing approach

`ctest` runs two tests: the Catch2 `lo_runtime_tests` (vendored single-header
Catch2 v2.13.10 under `tests/catch.hpp` — no network/package-manager needed;
covers layout, alloc zeroing + header, bump advance, shadow push/pop,
`LO_EMPTY_STRING`), and `io_round_trip` (a `tests/io_roundtrip.sh` harness driving
`tests/lo_io_probe` for the print/read round-trip and the read_int abort codes
111/110). Strict warnings (`-Wall -Wextra -Werror`) apply only to the library
sources, not the vendored Catch2 header or the test TUs.

## Catch2 vs GoogleTest (runbook open item)

Went with **Catch2** (runbook default), vendored as the single header for
zero-setup builds. If DC prefers GoogleTest or FetchContent-based Catch2, easy to
swap — only `tests/` + the test stanza in `CMakeLists.txt` change.

## What Phase 4 should do / watch for

- The cross-skeleton layout audit can lean on the three sets of compile-time
  locks (Rust `const _`, Zig comptime, C++ `static_assert`) — they already encode
  the same numbers. The C harness should also runtime-check `sizeof`/offsets from
  C against all three `.a`s.
- The C harness links each `liblo_runtime.a`; all three export the identical 23
  functions + 4 data symbols (verified per skeleton). Note the C++ stubs **throw**
  — the harness must not call any stubbed entry point (it only uses provided ones:
  init, alloc, print, shutdown), same as it must avoid the Rust `unimplemented!`
  / Zig `@panic` stubs.
- C++ has no `.wasm` artifact yet (see above) — the WASM side of any cross-check
  covers Rust + Zig only until the C++/WASM toolchain is chosen.

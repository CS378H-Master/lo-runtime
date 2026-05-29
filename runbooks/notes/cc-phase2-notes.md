# Phase 2 notes — Zig skeleton

## What got done

Full Zig skeleton under `zig/`, mirroring the Rust reference module-for-module:
`object`, `descriptors`, `alloc`, `shadow_stack`, `init`, `io`, `gc`,
`string_ops`, `cast`, `abort`, with `lo_runtime.zig` as the root that re-exports
types and force-references every module so the `export fn` symbols land in the
artifacts. `build.zig` produces a native static library and a WASM reactor module.
Verified: `zig build`, `zig build -Dtarget=wasm32-freestanding`, `zig build test`
(7/7 steps), `zig fmt --check src` all pass. `nm` confirms all 23 `lo_*` functions
plus the 4 data symbols (`LO_STRING_CLASS`/`LO_INT_BOX_CLASS`/`LO_BOOL_BOX_CLASS`/
`LO_EMPTY_STRING`) are exported in both the native `.a` and the `.wasm`.

## Version pin

Zig **0.13.0** (per Phase 0). The `build.zig` API differs in 0.14+
(`addStaticLibrary`/`addExecutable` take a `root_module` there); if DC bumps the
toolchain, `build.zig` needs the 0.14 module API. Everything else is stable Zig.

## Layout agreement with Rust (the thing Phase 4 audits)

By construction the two agree: `object.zig` carries the same comptime layout locks
as the Rust `const _` asserts — `Object` = 16/12 bytes (64/32-bit), string data
offset = 20/16, frame roots offset = 16/8. Same rule as Rust: **use
`@offsetOf(StringObject, "data")`, never `@sizeOf`** (size includes trailing
padding → 24, which points past the inline bytes). `extern struct` gives the C
layout, so the field-by-field correspondence with Rust's `repr(C)` is exact.

## Zig-specific decisions / gotchas

- **I/O uses `std.io`, not `std.c`/libc** — same call as the Rust skeleton, same
  rationale (no libc linkage needed; `std.io` gives correct peek/EOF semantics
  that `feof` can't). Native input uses a one-byte pushback for peek; reads are
  one byte at a time (simple, correct, fine for tiny test inputs). The Zig and
  Rust skeletons therefore share an I/O backend strategy; only C++ (Phase 3) is
  planned to use libc `<cstdio>` directly, since C++ reaches `stdin` cleanly.

- **comptime target branching.** Every native/WASM split is
  `if (comptime is_wasm) { ... } else { ... }`, where `is_wasm` is a comptime
  const. The crucial part: the untaken branch is *not* analyzed, so the native
  branches' `std.io`/`std.process` references never reach the freestanding-WASM
  build, and the WASM `extern "host"` imports never become unresolved native
  symbols. **Gotcha learned:** a bare `if (comptime is_wasm) return X;` (no
  `else`) does NOT stop the following code from being analyzed — it just becomes
  unreachable-but-analyzed. Use a full `if/else` (or a comptime function-select)
  so the other branch is dropped. `readHeapSize` was rewritten this way.

- **"pointless discard" pitfall (cost me a build).** In `abort.zig`, the abort
  helpers use `msg`/`code` on native but ignore them on WASM. Writing
  `_ = msg;` in the WASM branch while the native branch uses `msg` triggers
  `error: pointless discard of function parameter` — Zig sees the param both
  discarded and used across branches. Fix: comptime-**select the whole function**
  (`const runtimeAbort = if (is_wasm) abortWasm else abortNative;`), so only one
  body is ever analyzed and the WASM body can legitimately discard. Same pattern
  for `lo_abort_null_receiver` via an internal selected `nullReceiver`. Worth
  remembering for any future per-target entry point whose params are
  target-conditionally used.

- **WASM reactor module.** `build.zig` builds the WASM target as an
  `addExecutable` with `entry = .disabled` + `rdynamic = true` (per the runbook),
  which keeps the `export fn`s as module exports with no `_start`. Native is
  `addStaticLibrary`. The build branches on `target.result.cpu.arch.isWasm()`.

- **Shadow frame / string flexible tails.** `roots: [0]?*Object` and
  `data: [0]u8` zero-length-array marker fields, same convention as Rust's
  `[u8; 0]`. `@offsetOf` on them gives the FAM start.

## Testing approach

`zig build test` wires three things into one `test` step: (1) `addTest` on the
root module (the unit tests live in `lo_runtime.zig` so the single-threaded test
runner picks them up; bracketing each with init/shutdown suffices — no mutex
needed, unlike Rust's parallel test threads); (2) a `Run` step driving
`lo_io_probe` with `setStdIn`/`expectStdOutEqual` for the round-trip; (3) two more
`Run` steps with `expectExitCode(111)` / `expectExitCode(110)` for the read_int
abort paths. The `Run`-step stdin/stdout/exit-code assertions are a nice Zig-build
feature that made the I/O round-trip cleaner than Rust's subprocess test.

## Ambiguities / open items (unchanged from Phase 1, still standing for DC/SC)

1. `ShadowFrame` inline-array layout (ABI §3.3) vs runbook step 1.3 wording —
   implemented to the ABI in both skeletons.
2. `lo_abort_null_receiver` as a provided entry point in every skeleton.
3. Per-language I/O backends differing (Rust + Zig on stdlib I/O; C++ planned on
   libc) under the soft consistency goal.

## What Phase 3 (C++) should re-read / watch for

- Same offset-of-not-size-of rule: `offsetof(StringObject, data)` for string data,
  `offsetof(ShadowFrame, roots)` for frame roots. Add `static_assert`s mirroring
  the Rust `const _` / Zig comptime locks (Object size 16, data offset 20, roots
  offset 16 on 64-bit).
- Identical `instance_size` values and descriptor names ("String"/"int"/"bool").
- Identical abort exit codes; only the provided paths are live (137/110/111/112/
  102).
- C++ can use `<cstdio>` for native I/O (stdin is reachable), but match the
  observable behavior and the `lo_eof` "peek without consuming" semantics — a raw
  `feof` is wrong; use `getc`+`ungetc` or an equivalent peek.
- Catch2 vs GoogleTest: runbook defaults to Catch2; I'll fetch Catch2 via CMake
  FetchContent unless DC signals otherwise.

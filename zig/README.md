# LO Runtime — Zig skeleton

Zig implementation of the LO runtime ABI ([`../runtime-abi.md`](../runtime-abi.md)).
The provided entry points work out of the box; the stubbed ones (`lo_gc_collect`,
the `lo_string_*` ops, `lo_cast_check` / `lo_instanceof`) `@panic` until your team
fills them in for P3.

## Toolchain

- Zig **0.13.0** (pinned — the `build.zig` API changed in 0.14+). Install from
  <https://ziglang.org/download/>.

No external dependencies.

## Build

```sh
zig build                                  # native static library (liblo_runtime.a)
zig build -Dtarget=wasm32-freestanding     # WASM module (lo_runtime.wasm)
zig build -Doptimize=ReleaseFast           # optimized native
```

Artifacts land under `zig-out/lib/` (native `.a`) and `zig-out/bin/` (the
`.wasm`). Every public entry point is an `export fn`, so symbols are unmangled and
C-linkable.

## Test

```sh
zig build test          # unit tests + I/O round-trip + abort-code checks
zig fmt --check src     # formatting (must be silent)
```

`zig build test` runs the comptime + runtime layout checks, the ABI smoke tests
(alloc zeroing, bump advance, shadow-stack push/pop, the `LO_EMPTY_STRING`
singleton), and drives `src/lo_io_probe.zig` to round-trip the print/read entry
points and confirm the `read_int` abort codes (111 EOF, 110 malformed).

## Layout

```
build.zig
src/
├── lo_runtime.zig    # root: re-exports + force-exports + unit tests
├── object.zig        # ABI-visible extern structs + comptime layout locks
├── descriptors.zig   # class descriptors + LO_EMPTY_STRING
├── alloc.zig         # bump allocator behind lo_alloc
├── shadow_stack.zig  # lo_push_frame / lo_pop_frame
├── init.zig          # lo_runtime_init / lo_runtime_shutdown
├── io.zig            # lo_print_* / lo_read_* / lo_println / lo_eof
├── gc.zig            # lo_gc_write_barrier (provided) + lo_gc_collect (stub)
├── string_ops.zig    # string op stubs
├── cast.zig          # cast/instanceof stubs
├── abort.zig         # runtime abort paths + lo_abort_null_receiver
└── lo_io_probe.zig   # I/O test driver (not part of the shipped runtime)
```

## What to implement in P3

Start in `gc.zig` (`lo_gc_collect` + the OOM-retry path in `alloc.zig`), then the
`string_ops.zig` and `cast.zig` stubs. Build string results with the internal
`alloc.bumpAllocString`. The instructor's acceptance baseline is Cheney's
semispace with all shared tests passing (`../runtime-abi.md` §4.5).

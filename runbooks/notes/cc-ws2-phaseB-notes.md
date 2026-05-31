# CC notes — WS-2 Phase B (Zig + C++ collectors)

**Date:** 2026-05-30. **Branch:** `ws2/phase-B-zig-cpp` (off merged `main` incl. Phase A).

## What got done

Replicated the Phase-A Rust reference Cheney collector into the Zig and C++
skeletons, byte-for-byte on the shared ABI:

- **Zig** — `zig/src/alloc.zig` restructured into two semispaces + OOM
  collect-and-retry; `zig/src/gc.zig` now has `objectSize` / `forward` / `collect`
  and the 5 A.4 tests. `zig build`, `zig build test` (12 tests incl. the 5 GC
  tests), `zig fmt --check src`, and the `wasm32-freestanding` build are green.
- **C++** — `cpp/src/alloc.cpp` (+`alloc.h` seam) restructured into two
  semispaces + OOM collect-and-retry; `cpp/src/gc.cpp` has `object_size` /
  `forward` / `lo_gc_collect` and the 5 A.4 tests (Catch2). `cmake --build`,
  `ctest`, and `clang-format --dry-run --Werror` are green.
- **Cross-skeleton** — `tests/c_harness/run.sh`: rust / zig / cpp all link from C
  with Cheney and agree (`42`).

The Phase-A `LO_EMPTY_STRING` `.rodata` flip for Zig/C++ was already merged in
Phase A; Phase B is purely the collector + its tests + the semispace heap.

## Byte-identical header / tombstone compat check (Phase B postcondition)

Confirmed the three skeletons agree on every collector-visible byte:

- **Object header.** `#[repr(C)]` (Rust) / `extern struct` (Zig) /
  standard-layout `struct` (C++), field order `{class_descriptor (ptr), gc_bits
  (u32), flags (u32)}` → 16 bytes on 64-bit. Pinned by each skeleton's own
  layout test **and** the C harness `_Static_assert`s (a fourth, C-side witness).
- **Forwarding flag (decision (C)): `gc_bits` bit 0** in all three —
  `GC_FORWARDED_BIT` (Rust `pub(crate)` / Zig `pub const`) and `kGcForwardedBit`
  (C++ anon-namespace). Same bit, same semantics.
- **Tombstone encoding.** All three overwrite the `class_descriptor` slot
  (pointer-sized) with the new to-space address and set bit 0 of `gc_bits`, in the
  same order (copy bytes → then clobber the original). A copy carries the intact
  descriptor with the flag clear.
- **Heap geometry (decision (B)).** All three: `semi = align_down(total/2, 16)`,
  two adjacent equal halves, from-space active with a bump cursor, `LO_HEAP_SIZE`
  floor `>= 2*16`. Identical `flip` (swap roles, install new free).
- **`object_size`.** All three use `align8(string_data_offset() + length)` for
  strings (offset-of, not size-of) and `align8(instance_size)` otherwise.

## Deliberate per-language divergences (behavior identical; flagged for SC)

- **Allocation-pressure test injection.** The Rust A.4 test (v) forces a small
  heap via the `LO_HEAP_SIZE` env var (exercising the real init path). Zig and C++
  instead call a non-ABI test hook (`heapInitWith` / `heap_init_with`) that takes
  an explicit total size, because setting the C environment before the runtime's
  `getenv`/`getEnvVarOwned` would require linking libc into the Zig test binary
  and is racy/fiddly across the Catch2/zig-test runners. The *env-reading logic
  itself* is identical across all three (read at init, halve, floor); only the
  test's injection differs. The env path is covered by the Rust reference.
- **Heap backing (pre-existing WS-1 soft-consistency item).** Rust uses
  `std::alloc::alloc_zeroed`, Zig `page_allocator.alignedAlloc`, C++
  `std::vector<std::uint8_t>`. Observable behavior is identical; the collector
  only ever sees a contiguous `[base, base+region)` region split in two.

## What WS-2 acceptance (§4) now needs

Both phases are implemented and green locally. The §4 gate is a clean checkout +
Cheney + the lo-testing conformance suite via `tests/c_harness/run.sh`, per
skeleton. **Still outstanding (not CC's), WS-1 delta #4:** the shared
`tests/lo_programs/*.lo` fixtures carry unverified LO-3 surface syntax
(`TODO(SC)`); only `expected/*.out` is the stable contract. WS-2 should not be
declared green on unverified fixtures until SC / lo-testing validates the `.lo`
bodies against `planning:lo-3-reference.md`. Re-surfaced in
`for-sc-ws2-spec-deltas.md`.

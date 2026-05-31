# CC notes — WS-2 Phase A (Rust reference Cheney collector)

**Date:** 2026-05-30. **Branch:** `ws2/phase-A-rust`.

## What got done

Implemented the reference Cheney two-space copying collector in the Rust
skeleton: `rust/src/alloc.rs` restructured into two equal semispaces with an
OOM-path collect-and-retry, and `rust/src/gc.rs` now carries `object_size`,
`forward`, and the flip + root-scan + Cheney-loop `collect` behind the existing
`lo_gc_collect` entry point. `LO_EMPTY_STRING` moved to a `.rodata` static object
(decision (A)). Five GC unit tests added in-crate. Rust is green: `cargo test`,
`cargo clippy --all-targets -- -D warnings`, `cargo fmt --check`, plus native +
`wasm32-unknown-unknown` builds.

Per a DC decision taken mid-phase (see "Scope deviation" below), the **minimal
`LO_EMPTY_STRING` symbol flip** was also applied to Zig and C++ and to the shared
C harness, so the whole repo (incl. the `cross_skeleton` CI job) stays green on
this branch. The Zig/C++ **collectors remain stubbed** — the real Cheney work in
those two skeletons is Phase B.

## Decisions to carry into Phase B (re-read before starting)

- **Forwarding-flag bit (decision (C)): `gc_bits` bit 0** — `GC_FORWARDED_BIT =
  0b1`. Documented in the `gc.rs` module header. Zig and C++ **must use the same
  bit** so the cross-skeleton header encoding stays byte-identical.
- **Tombstone encoding.** On evacuation, the from-space original's
  `class_descriptor` slot (pointer-sized) is overwritten with the new to-space
  address, and bit 0 of `gc_bits` is set. Order is load-bearing: read size + copy
  the bytes **before** clobbering `class_descriptor` (both reads need the intact
  descriptor); the to-space copy therefore carries the intact descriptor with the
  forwarding flag still clear. Only the original becomes a tombstone.
- **Heap geometry (decision (B)).** Total size from `LO_HEAP_SIZE` (16 MiB
  default) read at init; each semispace = `align_down(total/2, 16)`, the two
  halves exactly adjacent. The `LO_HEAP_SIZE` floor was raised from `>= 16` to
  `>= 2*16` so each semispace is non-degenerate. Zig/C++ must match this geometry
  exactly (same total→semi derivation) for cross-skeleton behavioral identity.
- **`object_size` offset-of trap.** Strings use
  `align8(offset_of(StringObject, data) + length)` (= `align8(20 + length)` on
  64-bit), **never** `size_of` (24). This is the single most common copy-loop
  bug; the Zig/C++ ports already have `stringDataOffset()` /
  `string_data_offset()` helpers — use them, not `@sizeOf`/`sizeof`.
- **Immortal range-check, no special case.** `forward` returns any pointer
  outside `[from_base, from_limit)` unchanged. That single check is what keeps
  `LO_EMPTY_STRING` (now `.rodata`, never *in* from-space) safe — there is no
  empty-string special case anywhere in the collector. Test (iv) below pins this.

## Rust-specific implementation patterns (for the Zig/C++ ports to mirror in spirit)

- **`.rodata` static via `unsafe impl Sync`.** `LO_EMPTY_STRING` is
  `pub static LO_EMPTY_STRING: StringObject = StringObject { header: Object {
  class_descriptor: &LO_STRING_CLASS as *const ClassDescriptor, gc_bits: 0,
  flags: 0 }, length: 0, data: [] };`. A non-`mut` `static` lands in read-only
  memory; because `StringObject` holds a raw pointer it is not `Sync` by default,
  so it needs `unsafe impl Sync for StringObject {}` (sound: immutable,
  single-threaded). Zig uses `export const` (→ `.rodata`); C++ uses a file-scope
  `const StringObject` with a designated initializer — both naturally read-only,
  no Sync analog needed.
- **Allocator/collector seam.** `alloc.rs` exposes three `pub(crate)` raw-pointer
  hooks to `gc.rs`: `from_space() -> (base, limit)`, `to_space_base()`, and
  `flip(new_free)`. The collector owns the Cheney walk; the allocator owns heap
  geometry and the flip commit. Mirror this split in Zig/C++ so neither file
  re-derives the other's state.
- **Test hook.** `heap_used()` (`FREE - FROM_BASE`) is a `#[doc(hidden)]`
  re-export used only by test (ii) to observe occupancy dropping after a collect.

## GC unit tests (A.4) — what each pins, to replicate per language

(i) live graph `root → A → B`: root slot and A's interior pointer are both
rewritten, objects move, contents preserved. (ii) unreachable object reclaimed:
`heap_used` drops from 48 → 24. (iii) variable-size String round-trips its bytes
through a collection. (iv) a moved object's field pointing at `LO_EMPTY_STRING`
still equals the immortal `.rodata` address after collect (range-check, no special
case). (v) allocation pressure: `LO_HEAP_SIZE=4096` (2 KiB semis), 600 dead allocs
with one rooted survivor — reaching the post-loop assertion proves GC reclaimed
and allocation continued (a missing trigger would exit 137 and kill the test).

The tests build a stack `TestFrame<N>` byte-compatible with `ShadowFrame`
(`{parent, num_roots, roots[N]}`) and a test `NODE_CLASS` (one pointer field at
offset 16, `instance_size 24`). Zig/C++ ports need the same two fixtures.

## Scope deviation (DC-approved) — flag for SC

The runbook stages Phase A as "Rust only." Decision (A) changes the **meaning of
a shared ABI symbol** (`LO_EMPTY_STRING`: pointer-variable → object), which the
shared `tests/c_harness/main.c` consumes and the `cross_skeleton` CI job runs
against all three skeletons. There is no C declaration that works for both the
old and new symbol model, so the flip is atomic across `main.c` + all three
skeletons — it cannot land in a Rust-only PR without turning the `cross_skeleton`
job red mid-transition.

DC chose (2026-05-30): pull the **trivial symbol flip** (`.rodata` object +
test/header updates) into Phase A for Zig and C++ as well, and flip `main.c`,
keeping all CI green; the **collectors** for Zig/C++ stay stubbed and are Phase B.
Recorded for SC in `for-sc-ws2-spec-deltas.md`. The runbook's Phase A/B split and
§4 ("cross-skeleton harness is the post-both-phases gate") could be sharpened to
acknowledge that shared-symbol ABI changes are atomic across skeletons + harness.

## What Phase B should re-read / watch for

- This file's "Decisions to carry into Phase B" — especially the bit, geometry,
  and offset-of points.
- `rust/src/gc.rs` is the reference; the algorithm and the alloc/gc seam are the
  shape to mirror. `rust/src/alloc.rs` for the semispace + OOM-retry structure.
- Zig/C++ already have the `.rodata` `LO_EMPTY_STRING` and the geometry-agnostic
  offset helpers; Phase B adds the two-semispace restructure + the collector +
  the A.4 tests in each native framework, and confirms byte-identical headers /
  tombstone encoding (Phase B notes should record that compat check).

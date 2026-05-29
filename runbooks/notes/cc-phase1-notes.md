# Phase 1 notes — Rust skeleton

## What got done

Full Rust skeleton under `rust/`: Cargo project (staticlib + cdylib + rlib),
all ABI-visible types, the three built-in class descriptors + `LO_EMPTY_STRING`,
the bump allocator behind `lo_alloc`, the shadow stack, runtime lifecycle, the
complete I/O surface, the bare-store write barrier, `lo_abort_null_receiver`, and
idiomatic `unimplemented!()` stubs for the GC / string / cast entry points.
Verified: `cargo build`, `cargo build --target wasm32-unknown-unknown`,
`cargo test` (11 tests), `cargo clippy --all-targets -- -D warnings`,
`cargo fmt --check` all pass.

## Decisions, and what tipped them

- **`static mut` over `OnceLock` for the mutable globals** (bump pointer, heap
  base/end/layout, `CURRENT_FRAME`, `LO_EMPTY_STRING`). The runbook explicitly
  sanctions `static mut` for the bump pointer and root list, and the runtime is
  single-threaded by spec (ABI §1), so the synchronization a `OnceLock`/`Mutex`
  buys is dead weight on the hot path. What made `static mut` painless under
  `cargo 1.87`: the `static_mut_refs` lint (warn-by-default, denied by our
  `-D warnings`) only fires on `&`/`&mut` of a static mut, **not** on by-value
  reads/writes. So every access reads the scalar out (`let b = BUMP_PTR;`) or
  writes it (`BUMP_PTR = …;`) and never forms a reference. This is the load-bearing
  idiom across `alloc.rs` / `shadow_stack.rs` / `descriptors.rs`; the Zig and C++
  skeletons have the equivalent globals but without this particular lint to dodge.

- **`unsafe impl Sync for ClassDescriptor`** so the descriptors can be `static`
  items (raw pointers make them `!Sync` by default). Sound because descriptors are
  immutable read-only data and the runtime is single-threaded. Commented at the
  impl.

- **Heap backed by `std::alloc::alloc_zeroed` + `Layout`, not `Vec<u8>`.** The
  runbook suggested `Vec<u8>` "for simplicity," but a `static mut Vec` can't be
  accessed without taking a reference to the static (→ `static_mut_refs`). Raw
  `alloc_zeroed`/`dealloc` storing a base pointer + `Layout` as scalar statics is
  cleaner here and frees correctly on shutdown. `LO_HEAP_SIZE` env override honored
  at init; default 16 MiB.

- **Native I/O via `std::io`, not libc.** This is the most significant deviation
  from the runbook (which named `printf`/`scanf`/`fgets`/`feof`). Reasons: the
  `libc` crate does not portably expose the `stdin`/`stdout` `FILE*` globals that
  `fgets`/`feof` require, and `feof`'s semantics ("true only after a failed read")
  don't match `lo_eof` ("at EOF *without consuming*"). `std::io::BufRead` gives the
  exact peek (`fill_buf`) / consume / `read_until` primitives the read semantics
  need, is portable, and drops the `libc` dependency entirely (so the crate has
  zero runtime deps). Observable behavior — stdout bytes, stdin tokens/lines, and
  every documented abort exit code — is identical. **Consistency note for Phases
  2–3:** Zig and C++ can use `std.c` / `<cstdio>` directly (they reach stdin
  easily), so the three skeletons will differ in I/O backend while matching in
  behavior. That's within the runbook's "soft" consistency goal.

- **WASM I/O** forwards to host imports under `#[link(wasm_import_module = "host")]`
  (`host_print_int`, `host_read_int`, …). `read_string` uses a two-call protocol
  (`host_read_line_len` then `host_read_line_into`) so the runtime sizes the heap
  allocation itself. The harness wires these; wasm isn't run here, only built.

## `repr(C)` / flexible-tail quirks (important for Phases 2 & 4)

- **`StringObject` data offset is `offset_of!(StringObject, data)` (= 20 on
  64-bit), NOT `size_of::<StringObject>()` (= 24).** The runbook said index off
  `base + size_of`, but `size_of` includes the 4 bytes of trailing padding after
  `length`, so it points *past* where the inline bytes begin. The
  flexible-array-member start is `offset_of`. **All three skeletons must use the
  offset-of of the `data`/`roots` marker field, not size-of, or the layouts
  diverge.** This is the single most likely cross-skeleton drift; Phase 4's audit
  should check it explicitly. Zig: `@offsetOf(StringObject, "data")`; C++:
  `offsetof(StringObject, data)`.

- **`ShadowFrame` uses the ABI's inline `roots: [*mut Object; N]` layout, not the
  runbook's `roots: *mut *mut Object`.** The runbook step 1.3 suggested a pointer
  field, but that is a *pointer*, not an inline array, and would not match the
  frames codegen stack-allocates (and the team's GC would scan the wrong memory).
  The ABI §3.3 inline-array layout is authoritative ("when in doubt, the ABI
  wins"). Represented as a fixed header `{ parent, num_roots, roots: [_; 0] }`
  with the tail starting at `offset_of(roots)` (= 16 on 64-bit; note the 4 bytes
  of padding between `num_roots` and the 8-aligned roots array). **Flagged for SC
  below.**

- Compile-time layout locks (`const _: () = { assert!(...) }`, pointer-width
  gated) pin `Object` = 16/12 bytes, string-data offset = 20/16, roots offset =
  16/8 for 64-/32-bit. These are the Rust analog of C++ `static_assert` /
  Zig `comptime` — Phase 4 should add the equivalents and confirm agreement.

## Provided vs stubbed — one addition

`lo_abort_null_receiver` (ABI §3.8) is in the **provided** set per ABI §4.4 but
was not in the Phase 1 numbered step list. Implemented it as provided (in
`abort.rs`), exit 102 / message per spec. Surfacing in the PR for DC sign-off
(also raised in Phase 0 notes).

## Testing approach

- `cargo test` covers: compile-time + runtime layout checks; alloc returns zeroed
  memory with a correct header; bump pointer advances by the rounded size; shadow
  push/pop maintains the linked list; `LO_EMPTY_STRING` is a valid length-0 string
  after init; and an I/O round-trip plus the `read_int` abort codes (111 EOF, 110
  malformed), driven through a child process (`src/bin/lo_io_probe.rs`) so stdio
  capture is clean and race-free.
- Runtime global state forced the `abi_smoke` tests to serialize through a mutex
  and bracket each with init/shutdown. The I/O tests sidestep that entirely by
  using a subprocess.
- **Bug caught during verification:** the first `read_int` keyed EOF-vs-malformed
  off "token empty," so a non-numeric token like `abc` wrongly reported EOF (111)
  instead of malformed (110). Fixed to key off "is a byte present after
  whitespace." Locked with a test.

## Ambiguities surfaced for DC / SC

1. **`ShadowFrame` representation** — confirm the ABI's inline-array layout is
   correct and the runbook's `roots: *mut *mut Object` wording in step 1.3 should
   be corrected (it conflicts with ABI §3.3). I went with the ABI.
2. **`lo_abort_null_receiver` as provided** — confirm it belongs in every
   skeleton's provided set (it's in ABI §4.4 but not the per-phase step lists).
3. **I/O backend** — confirm `std::io` for Rust native is acceptable given the
   libc-`FILE*` problem, and that per-language I/O backends differing (Rust
   `std::io` vs Zig/C++ libc) is fine under the soft consistency goal.
4. Runbook open items unchanged: heap default 16 MiB (kept), WASM trap uniformity
   (Rust stubs panic → wasm trap via `unimplemented!`; abort paths use
   `core::arch::wasm32::unreachable`).

## What Phase 2 (Zig) should re-read / watch for

- The offset-of-not-size-of rule for string data and frame roots (above) — get
  `@offsetOf` right or layouts drift.
- Match `instance_size` values exactly: String = `@sizeOf(StringObject)`,
  int/bool box = `@sizeOf(Object) + 4`.
- Boxed-primitive descriptor names: `"int"` / `"bool"` (len 3 / 4); String is
  `"String"` (len 6). Keep identical for error-message parity.
- Replicate the abort exit codes exactly (101/102/110/111/112/120/137); only the
  provided paths (137 OOM, 110/111 read_int, 112 read_bool, 102 null receiver) are
  live in the skeleton — the rest live in stubbed functions.
- Zig pinned to 0.13.0 (see Phase 0 notes) — the `build.zig` API differs in 0.14+.
